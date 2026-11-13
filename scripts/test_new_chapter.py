"""Runs scripts/new_chapter.py in a temporary copy of the repository and checks
what it leaves there:
- a cooperative chapter, a premium journey chapter and a later version of a
  journey chapter each create their files and add their shared lines;
- running any of them again, asking for a version the family cannot tell
  apart, or naming a stage id another chapter uses, writes nothing;
- every file that existed before only gains lines (a family catalog's KEYS
  line gains its key), and only the shared files that list chapters change;
- ci_shards.txt stays sorted;
- the placeholder thumbnail is the one test_chapter_descriptors.gd recognises;
- content/chapters/index.gd's development turn limits are the longest the
  rules and the server accept (scripts/chapter_tools/turn_limits.py).
With a Godot binary (--godot, or the GODOT environment variable) it then
imports the copy, writes the new chapters' fixtures, manifest rows and backend
copies with scripts/chapter_fixtures.py, checks that only the manifest golden
changed and only by the new chapters' rows, and runs the new suites with the
descriptor, registry, manifest, thumbnail, Home, shard, scrolling camera, fold
and Lighthouse release suites, which each read every registered chapter. Then
the journey chapter's own run becomes its routes (scripts/chapter_recording.py)
with every fixture unchanged, replays (scripts/chapter_recheck.py), and gets
turn limits of its own (scripts/chapter_turn_limits.py). Each Godot process
runs headless with its own user data folders.

The copy's game folder comes from --game (default: this repository's game/),
always with its service settings blanked; CI passes its imported offline copy.

Run: python3 scripts/test_new_chapter.py [--godot PATH] [--game PATH] [--keep]
"""
from __future__ import annotations

import argparse
from concurrent.futures import ThreadPoolExecutor
import difflib
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile

from chapter_tools.godot import copy_game as copy_offline_game, run as run_godot
from chapter_tools.chapters import Chapter
from chapter_tools.turn_limits import Rules, chapter_shape

ROOT = Path(__file__).resolve().parent.parent
SCRIPTS = Path(__file__).resolve().parent
SCAFFOLD = SCRIPTS / "new_chapter.py"
JOURNEY = "scaffold-test-journey@1"
RUNS = [
    ("scaffold-test-coop@1", ["--key", "scaffold-test-coop@1", "--family", "cooperative", "--title", "Scaffold Test Coop", "--shard", "1"]),
    ("scaffold-test-journey@1", ["--key", "scaffold-test-journey@1", "--family", "journey", "--title", "Scaffold Test Journey", "--shard", "2", "--premium"]),
    ("conservatory@2", ["--version-of", "conservatory@1", "--shard", "3"]),
]
REFUSED = [
    ["--version-of", "high-and-low@1", "--shard", "1"],
    ["--key", "conservatory@1", "--family", "journey", "--title", "Again", "--shard", "1"],
    # Stage ids that name another chapter's stage, so its suite would write over that chapter's fixtures.
    ["--key", "stage-clash@1", "--family", "journey", "--title", "Stage Clash", "--shard", "1", "--stages", "a-light-above,stage-clash-second"],
    ["--key", "stage-clash@1", "--family", "cooperative", "--title", "Stage Clash", "--shard", "1", "--stages", "stage-clash-first,upper-path"],
]
SHARED = {
    "game/content/chapters/index.gd", "game/core/cooperative/stage_catalog.gd", "game/core/journey/stage_catalog.gd",
    "game/presentation/player_copy.gd", "game/tests/ci_shards.txt",
    "backend/src/flags.ts",
}
EXISTING_SUITES = ["chapter_descriptors", "chapter_manifest", "chapter_registry", "registry_golden", "chapter_thumbnail_catalog", "ci_shards",
                   "home_keepsake_layer", "home_keepsake_states", "keepsake_props", "scrolling_camera", "fold_present", "lighthouse_v2_release"]
# The chapter unlock chain reads every offered chapter and its keepsake, so a
# new chapter must keep the chain whole (services/chapter_unlocks.gd).
EXISTING_SUITES += ["chapter_unlocks"]
IGNORED = shutil.ignore_patterns("android", "node_modules", ".wrangler", "__pycache__")

failures: list[str] = []


def check(ok: bool, message: str) -> bool:
    if not ok:
        failures.append(message)
        print("FAIL " + message)
    return ok


def snapshot(repo: Path) -> dict[str, bytes]:
    return {path.relative_to(repo).as_posix(): path.read_bytes() for path in repo.rglob("*") if path.is_file() and ".godot" not in path.parts}


def lines(data: bytes) -> list[str]:
    return data.decode("utf-8").replace("\r\n", "\n").split("\n")


def scaffold(repo: Path, args: list[str]) -> subprocess.CompletedProcess:
    return subprocess.run([sys.executable, str(SCAFFOLD), "--root", str(repo), *args], capture_output=True, text=True)


def check_scaffold(repo: Path, before: dict[str, bytes]) -> list[str]:
    """Runs each scaffold once, then again; returns the new keys' suites."""
    suites: list[str] = []
    for key, args in RUNS:
        result = scaffold(repo, args)
        if not check(result.returncode == 0, f"{key}: the scaffold succeeds: {result.stderr.strip()}"):
            continue
        for line in result.stdout.splitlines():
            kind, _, rest = line.partition(" ")
            if kind == "created":
                check((repo / rest).is_file(), f"{key}: created file exists: {rest}")
                suite = re.match(r"^game/tests/test_(\w+)\.gd$", rest)
                if suite:
                    suites.append(suite.group(1))
            elif kind == "added":
                path, _, added = rest.partition(": ")
                text = (repo / path).read_text(encoding="utf-8")
                check(added.removesuffix(" in KEYS") in text, f"{key}: added line is in {path}: {added}")
            else:
                check(False, f"{key}: output is only created and added lines: {line}")
    after = snapshot(repo)
    for args in [args for _, args in RUNS] + REFUSED:
        result = scaffold(repo, args)
        check(result.returncode == 1 and result.stdout == "" and "nothing written" in result.stderr, f"Refused without output: {args}: {result.stdout} {result.stderr}")
        check(snapshot(repo) == after, f"A refused run leaves every file as it was: {args}")
    for path, old in before.items():
        new = after.get(path)
        if not check(new is not None, f"No file is removed: {path}"):
            continue
        if new == old:
            continue
        check(path in SHARED, f"Only the shared chapter lists change: {path}")
        old_lines, new_lines = lines(old), lines(new)
        # A family catalog's KEYS line gains keys at its end; every other line stays.
        keys = [line for line in old_lines if line.startswith("const KEYS := [")]
        new_lines = [keys[0] if keys and line.startswith(keys[0][:-1]) else line for line in new_lines]
        for op, i1, i2, j1, j2 in difflib.SequenceMatcher(None, old_lines, new_lines, autojunk=False).get_opcodes():
            check(op in ("equal", "insert"), f"{path} only gains lines: {op} {old_lines[i1:i2]} -> {new_lines[j1:j2]}")
    shard_names = [line.split(" ")[0] for line in lines(after["game/tests/ci_shards.txt"]) if line and not line.startswith("#")]
    check(shard_names == sorted(set(shard_names)), "ci_shards.txt stays sorted with one line per suite")
    for suite in suites:
        check(f"\n{suite} " in after["game/tests/ci_shards.txt"].decode("utf-8").replace("\r\n", "\n"), f"ci_shards.txt lists {suite}")
    # One Home keepsake per chapter: a new chapter brings its own builder, a new version keeps the earlier one's.
    for key, args in RUNS:
        stem = key.split("@")[0].replace("-", "_") + ("" if key.endswith("@1") else "_v" + key.split("@")[1])
        text = after.get(f"game/content/chapters/{stem}.gd", b"").decode("utf-8")
        new = "--version-of" not in args
        check(('"home_keepsake": {' in text) == new and (f"game/presentation/keepsakes/{stem}.gd" in after) == new,
              f"{key}: {'its own Home keepsake and builder' if new else 'no Home keepsake of its own'}")
    descriptors = (ROOT / "game/tests/test_chapter_descriptors.gd").read_text(encoding="utf-8")
    rules = Rules(ROOT)
    index = (ROOT / "game/content/chapters/index.gd").read_text(encoding="utf-8")
    check(f'const DEVELOPMENT_TURN_LIMITS := {{"a_ticks": {rules.cap_a}, "b_ticks": {rules.cap_b}}}' in index,
          f"index.gd's development turn limits are the longest the rules and the server accept: A {rules.cap_a}, B {rules.cap_b} ticks")
    for key in ("scaffold-test-journey@1", "conservatory@2"):
        shape = chapter_shape(Chapter(repo, key))
        check(shape.capped and shape.max_branches == rules.dev_max_branches,
              f"{key}: scaffolded with capped input and the {rules.dev_max_branches} branches the room archives hold (got {shape})")
    placeholder = hashlib.sha256((Path(__file__).resolve().parent / "chapter_templates/placeholder-thumbnail.png").read_bytes()).hexdigest()
    check(f'PLACEHOLDER_THUMBNAIL_SHA256 := "{placeholder}"' in descriptors, "test_chapter_descriptors.gd knows the placeholder thumbnail")
    return suites


def godot(binary: str, game: Path, state: Path, args: list[str], timeout: int = 400) -> tuple[bool, str]:
    return run_godot(binary, game, state, args, timeout)


def tool(binary: str, repo: Path, script: str, args: list[str]) -> tuple[bool, str]:
    """Runs one of the chapter scripts on the copy, in its imported game/."""
    result = subprocess.run([sys.executable, str(SCRIPTS / script), "--root", str(repo), "--in-place", "--godot", binary, *args],
                            capture_output=True, text=True, encoding="utf-8", errors="replace", timeout=1200)
    return result.returncode == 0, result.stdout + result.stderr


def check_godot(binary: str, repo: Path, before: dict[str, bytes], suites: list[str]) -> None:
    game, state = repo / "game", repo.parent / "state"
    ok, log = godot(binary, game, state / "import", ["--editor", "--import", "--quit"], timeout=600)
    if not check(ok, "The copy imports: " + log[-2000:]):
        return
    for key, _ in RUNS:
        ok, log = tool(binary, repo, "chapter_fixtures.py", ["--key", key])
        check(ok and "created game/tests/fixtures/" in log and "created backend/src/v2/" in log, f"{key}: chapter_fixtures.py writes its fixtures and backend copies: " + log[-2000:])
    after = snapshot(repo)
    golden = "game/tests/fixtures/golden/"
    changed = sorted(path for path in set(before) | set(after) if path.startswith(golden) and before.get(path) != after.get(path))
    print("GOLDENS CHANGED: " + (", ".join(changed) or "none"))
    check(changed == [golden + "chapter_manifest.json"], f"Only the chapter manifest golden changes: {changed}")
    if golden + "chapter_manifest.json" in changed:
        old = json.loads(before[golden + "chapter_manifest.json"])
        new = json.loads(after[golden + "chapter_manifest.json"])
        added = [key for key, _ in RUNS]
        check(new["keys"] == old["keys"] + added, f"The manifest lists the new keys after the others: {new['keys']}")
        check(all(new["chapters"].get(key) == row for key, row in old["chapters"].items()), "Every earlier manifest row is unchanged")
        check(sorted(new["chapters"]) == sorted(list(old["chapters"]) + added), "The manifest gains one row per new chapter")
    fixtures = sorted(path for path in after if path not in before and path.startswith("game/tests/fixtures/"))
    print("FIXTURES WRITTEN: " + ", ".join(fixtures))
    names = suites + EXISTING_SUITES
    with ThreadPoolExecutor(max_workers=3) as pool:
        results = list(pool.map(lambda name: (name, *godot(binary, game, state / name, ["--script", f"res://tests/test_{name}.gd"])), names))
    for name, ok, log in results:
        summary = [line for line in log.splitlines() if re.search(r"checks|failures", line)]
        print(f"SUITE {name}: {'ok' if ok else 'FAILED'} {summary[-1] if summary else ''}")
        check(ok, f"Suite {name} passes with the new chapters: " + "\n".join(line for line in log.splitlines() if "ERROR" in line or "FAIL" in line)[:3000])
    check_recordings(binary, repo)


def check_recordings(binary: str, repo: Path) -> None:
    """The journey chapter's own run (its final checkpoint holds every stage's
    pair) becomes its routes and writes the same fixtures; the routes replay;
    turn limits are refused past the server's bound and written within it."""
    final = repo / "game/tests/fixtures/journey/scaffold-test-journey-final-checkpoint.json"
    fixtures = {path: data for path, data in snapshot(repo).items() if path.startswith("game/tests/fixtures/")}
    ok, log = tool(binary, repo, "chapter_recording.py", ["--key", JOURNEY, "--recording", str(final)])
    print("CHAPTER RECORDING: " + log.strip().replace("\n", "\n  "))
    rules = Rules(ROOT)
    # Each turn is shown against the development limit it was played under.
    check(ok and f"updated game/tests/routes/{JOURNEY}.json" in log and "suggested turn_limits" in log and f" of {rules.seconds(rules.cap_a)} (" in log,
          f"chapter_recording.py takes {JOURNEY}'s run: " + log[-2000:])
    routes = json.loads((repo / f"game/tests/routes/{JOURNEY}.json").read_text(encoding="utf-8"))
    check(all(step[0] == "input" for stage in routes.values() for role in ("a", "b") for step in stage[role]), "The recorded routes are input runs")
    now = {path: data for path, data in snapshot(repo).items() if path.startswith("game/tests/fixtures/")}
    check(now == fixtures, "Routes from the chapter's own run write the same fixtures: " + ", ".join(sorted(p for p in set(now) | set(fixtures) if now.get(p) != fixtures.get(p))))
    ok, log = tool(binary, repo, "chapter_recheck.py", ["--key", JOURNEY])
    check(ok and "2 of 2 stages finish" in log, "chapter_recheck.py replays the recorded routes: " + log[-1500:])
    ok, log = tool(binary, repo, "chapter_turn_limits.py", ["--key", JOURNEY, "--a-seconds", "900", "--b-seconds", "910"])
    check(not ok and "may last at most 900 s" in log, "chapter_turn_limits.py refuses turns past the rules' 15 minutes: " + log[-1500:])
    ok, log = tool(binary, repo, "chapter_turn_limits.py", ["--key", JOURNEY, "--a-seconds", "60", "--b-seconds", "90"])
    definition = json.loads((repo / "game/tests/fixtures/journey/scaffold-test-journey-definition.json").read_text(encoding="utf-8"))
    check(ok and definition.get("turn_limits") == {"a_ticks": 1800, "b_ticks": 2700} and "updated backend/src/v2/scaffold-test-journey.json" in log,
          "chapter_turn_limits.py writes the limits and rewrites the fixtures and backend copies: " + log[-2000:])


def copy_game(source: Path, target: Path) -> None:
    """Copies a game folder with its service settings blanked. Its import cache
    comes along only from a copy that was imported for the suites (--game)."""
    copy_offline_game(source, target, keep_import=source != ROOT / "game")


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    parser.add_argument("--godot", default=os.environ.get("GODOT", ""), help="Godot binary for the suite checks (default: $GODOT)")
    parser.add_argument("--keep", action="store_true", help="keep the temporary copy")
    parser.add_argument("--game", default=str(ROOT / "game"), help="the game folder to copy (default: this repository's; CI passes its imported offline copy)")
    args = parser.parse_args(argv)
    work = Path(tempfile.mkdtemp(prefix="after-you-new-chapter-"))
    repo = work / "repo"
    try:
        copy_game(Path(args.game).resolve(), repo / "game")
        for folder in ("backend", "scripts"):
            shutil.copytree(ROOT / folder, repo / folder, ignore=IGNORED)
        before = snapshot(repo)
        suites = check_scaffold(repo, before)
        if args.godot:
            check_godot(args.godot, repo, before, suites)
        else:
            print("No Godot binary: the suite checks did not run")
    finally:
        if args.keep:
            print(f"Kept {work}")
        else:
            shutil.rmtree(work, ignore_errors=True)
    print(f"NEW CHAPTER SCAFFOLD: {len(failures)} failures")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
