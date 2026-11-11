"""Writes everything a chapter's definition decides, in one run:
1. its fixtures, by the suite that writes them (definition, initial and final
   checkpoint, each stage's pair and checkpoint);
2. its row of the chapter manifest golden (no other row may move);
3. its water lock bakes (content/water_locks/<key>-<stage>.json), when its
   world has water locks;
4. the backend's copies of its definition and initial checkpoint
   (backend/src/v2/), byte for byte;
5. the backend constant that holds its definition hash.
Godot runs headless in a temporary copy of game/ with its own user data
folders; only what changed is copied back, and every change is printed. A
released chapter must come out unchanged: if anything would change, nothing is
written and the run fails.

  python scripts/chapter_fixtures.py --key the-quiet-mill@1 [--godot <console exe>]

--in-place runs Godot in the repository's own game/ (already imported), as
scripts/test_new_chapter.py does in its temporary copy.
"""
from __future__ import annotations

import argparse
import json
from pathlib import Path
import re
import sys

from chapter_tools.chapters import Chapter, manifest, MANIFEST, same_text, write_like, hash_constant
from chapter_tools.godot import Game, ToolError, binary

ROOT = Path(__file__).resolve().parent.parent
BAKES = "game/content/water_locks"


def _errors(log: str) -> str:
    lines = [line for line in log.splitlines() if re.search(r"ERROR|FAIL|failures", line)]
    return "\n".join(lines[-12:]) or log[-1500:]


def _snapshot(folder: Path) -> dict[str, bytes]:
    """The JSON fixtures under game/tests/fixtures (not the goldens), by repository path.
    The import adds .uid files beside scripts there, which are not results."""
    base = folder / "tests/fixtures"
    return {"game/" + path.relative_to(folder).as_posix(): path.read_bytes() for path in sorted(base.rglob("*.json")) if "golden" not in path.relative_to(base).parts}


def _restore(folder: Path, before: dict[str, bytes], paths: list[str]) -> None:
    """Puts game-folder files back as they were (in place, the repository is
    written only by apply())."""
    for relative in paths:
        target = folder / relative.removeprefix("game/")
        if relative in before:
            target.write_bytes(before[relative])
        else:
            target.unlink(missing_ok=True)


def manifest_text(manifest_value: dict) -> bytes:
    """The manifest golden as golden_support.gd text() writes it: sorted keys, tab indents."""
    return (json.dumps(manifest_value, indent="\t", sort_keys=True, ensure_ascii=False) + "\n").encode("utf-8")


def _run_writers(game: Game, chapter: Chapter, staged: dict[str, bytes]) -> tuple[dict[str, bytes], dict, list[Path]]:
    """Runs the fixture suite, the manifest suite and the bake suite in `game`
    with `staged` in place. Returns (fixtures that changed, the manifest the
    suite wrote, this chapter's bake files). In place, every file the runs or
    `staged` touched in game/ is put back afterwards, so the repository is
    written only by apply()."""
    key = chapter.key
    before = _snapshot(chapter.root / "game")
    golden = game.folder / MANIFEST.removeprefix("game/")
    touched = [MANIFEST, *staged]
    originals = {path: (game.folder / path.removeprefix("game/")).read_bytes() for path in touched if (game.folder / path.removeprefix("game/")).is_file()}
    changes: dict[str, bytes] = {}
    try:
        for relative, data in staged.items():
            (game.folder / relative.removeprefix("game/")).write_bytes(data)
        suite, user_args, env = chapter.writer()
        ok, log = game.script(suite, user_args, "fixtures", env)
        if not ok:
            raise ToolError(f"{key}: {suite} did not write its fixtures:\n{_errors(log)}")
        changes = {path: data for path, data in _snapshot(game.folder).items() if path not in before or not same_text(before[path], data)}
        # The manifest suite also fails for another chapter still without
        # fixtures; only this chapter's row is taken, and only a failure naming it counts.
        ok, log = game.script("res://tests/test_chapter_manifest.gd", ["--write-golden"], "manifest")
        failures = [line for line in log.splitlines() if "ERROR" in line and key in line]
        if "GOLDEN WRITTEN" not in log or failures:
            raise ToolError(f"{key}: its chapter manifest row was not written:\n" + ("\n".join(failures) or _errors(log)))
        written = json.loads(golden.read_text(encoding="utf-8"))
        bakes = game.scratch("bakes")
        ok, log = game.script("res://tests/test_water_locks_bake.gd", [], "bakes", {"AFTER_YOU_WRITE_BAKE": str(bakes), "AFTER_YOU_BAKE_KEY": key})
        if not ok:
            raise ToolError(f"{key}: the water lock bakes were not written:\n{_errors(log)}")
    finally:
        if game.in_place:
            # Every fixture the runs left different, even from a run that failed part way.
            now = _snapshot(game.folder)
            _restore(game.folder, before, [path for path in set(now) | set(before) if now.get(path) != before.get(path)])
            _restore(game.folder, originals, touched)
    return changes, written, sorted(bakes.glob(f"{key}-*.json"))


def plan(game: Game, chapter: Chapter, staged: dict[str, bytes] | None = None) -> tuple[dict[str, bytes], list[str]]:
    """Runs the writers in `game` with `staged` ({repository path: bytes}, such as
    new routes or a new catalog) in place, and returns ({repository path: new
    bytes}, notes). The repository is left as it was; apply() writes."""
    root, key = chapter.root, chapter.key
    staged = dict(staged or {})
    old = manifest(root)
    changes, written, baked = _run_writers(game, chapter, staged)
    changes.update(staged)
    moved = sorted(other for other, earlier in old["chapters"].items() if other != key and written["chapters"].get(other) != earlier)
    if moved:
        raise ToolError(f"{key}: the manifest rows of {', '.join(moved)} would change too; only {key}'s row may (see test_chapter_manifest)")
    row = written["chapters"][key]
    if old["chapters"].get(key) != row:
        spliced = {"keys": [k for k in written["keys"] if k in old["chapters"] or k == key], "chapters": {**old["chapters"], key: row}}
        changes[MANIFEST] = manifest_text(spliced)
    notes = [f"water locks: {len(baked)} stage bake(s)" if baked else "water locks: none in this chapter's world"]
    current = {path.name for path in baked}
    orphans = sorted(path.relative_to(root).as_posix() for path in (root / BAKES).glob(f"{key}-*.json") if path.name not in current)
    if orphans:
        notes.append("bakes of stages the chapter no longer has (delete them): " + ", ".join(orphans))
    for path in baked:
        relative = f"{BAKES}/{path.name}"
        if not (root / relative).is_file() or not same_text((root / relative).read_bytes(), path.read_bytes()):
            changes[relative] = path.read_bytes()

    # The backend's copies are the fixtures as just written.
    definition_name, initial_name = chapter.backend_files()
    for fixture, name in ((row["definition_fixture"], definition_name), (row["initial_fixture"], initial_name)):
        data = changes.get(f"game/tests/fixtures/{fixture}") or (root / "game/tests/fixtures" / fixture).read_bytes()
        target = f"backend/src/v2/{name}"
        if not (root / target).is_file() or not same_text((root / target).read_bytes(), data):
            changes[target] = data

    old_hash, new_hash = (old["chapters"].get(key) or {}).get("definition_hash", ""), row["definition_hash"]
    held = hash_constant(root, old_hash) if old_hash else None
    if old_hash and old_hash != new_hash:
        if held:
            path, name = held
            relative = path.relative_to(root).as_posix()
            text = path.read_text(encoding="utf-8")
            changes[relative] = text.replace(f'export const {name} = "{old_hash}";', f'export const {name} = "{new_hash}";').encode("utf-8")
            notes.append(f"{relative}: {name} {old_hash[:12]} -> {new_hash[:12]}")
        pinned = sorted(p.relative_to(root).as_posix() for p in (root / "backend/test").glob("*.ts") if old_hash in p.read_text(encoding="utf-8"))
        if pinned:
            notes.append("backend tests that still name the old hash (update them by hand): " + ", ".join(pinned))
    if not hash_constant(root, new_hash) and not held:
        notes.append(f"NEXT: no backend constant holds {key}'s hash yet. Add its adapter (ADDING-A-CHAPTER, On the server): "
                     f'import ./{definition_name} and ./{initial_name}, with export const <NAME>_HASH = "{new_hash}"')
    return changes, notes


def apply(root: Path, chapter: Chapter, changes: dict[str, bytes], notes: list[str]) -> list[str]:
    """Writes the planned changes (refused for a released chapter) and returns what to print."""
    if chapter.released and changes:
        raise ToolError(f"{chapter.key} is released and would change: {', '.join(sorted(changes))}. Published chapters never change; nothing written.")
    lines = []
    for relative, data in sorted(changes.items()):
        existed = (root / relative).is_file()
        if write_like(root / relative, data):
            lines.append(f"{'updated' if existed else 'created'} {relative}")
    return lines + notes


def refresh(game: Game, chapter: Chapter) -> list[str]:
    changes, notes = plan(game, chapter)
    return apply(chapter.root, chapter, changes, notes)


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    parser.add_argument("--key", required=True, help="the chapter, such as the-quiet-mill@1")
    parser.add_argument("--godot", default="", help="Godot console binary (default: $GODOT)")
    parser.add_argument("--root", default=str(ROOT), help="the repository (default: this one)")
    parser.add_argument("--in-place", action="store_true", help="run in the repository's own imported game/ instead of a temporary copy")
    parser.add_argument("--keep", action="store_true", help="keep the temporary copy")
    args = parser.parse_args(argv)
    root = Path(args.root).resolve()
    try:
        chapter = Chapter(root, args.key)
        with Game(binary(args.godot), root / "game", args.in_place, args.keep) as game:
            lines = refresh(game, chapter)
    except ToolError as error:
        print(f"chapter_fixtures.py: {error}", file=sys.stderr)
        return 1
    print(f"CHAPTER FIXTURES {args.key}: " + ("nothing changed" if not any(l.startswith(("updated", "created")) for l in lines) else "changed"))
    for line in lines:
        print("  " + line)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
