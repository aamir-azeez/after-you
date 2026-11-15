"""Plans and balances the Godot CI shards.

game/tests/ci_shards.txt names every suite and its shard; game/tests/ci_suite_times.txt
holds each suite's measured seconds from CI. verify.yml runs `plan <shard>` to get a
shard's suites, longest first, and runs them several at a time. `refresh` reads the
SUITE TIME lines of recent green CI runs into the times file and rebalances the shard
numbers; `balance` rebalances from the times file alone.

Run: python3 scripts/ci_shards.py plan 2
     python3 scripts/ci_shards.py refresh [RUN_ID ...]   (default: the latest green run on main)
     python3 scripts/ci_shards.py balance
"""
from __future__ import annotations

import json
import re
import statistics
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SHARDS_FILE = ROOT / "game/tests/ci_shards.txt"
TIMES_FILE = ROOT / "game/tests/ci_suite_times.txt"
SHARDS = ["1", "2", "3"]
# The chapter scaffold check (scripts/test_new_chapter.py) runs as one more item on this shard.
SCAFFOLD = "@new_chapter_scaffold"
SCAFFOLD_SHARD = "2"
SUITE_TIME = re.compile(r"^\S+Z SUITE TIME (@?[a-z0-9_]+) (\d+) s$")
REPO = "aamir-azeez/after-you"
ANSI = re.compile(r"\x1b\[[0-9;]*m")


def read_lines(path: Path) -> list[str]:
    return path.read_text(encoding="utf-8").replace("\r\n", "\n").split("\n")


def shard_lines() -> list[tuple[str, str]]:
    """(suite, shard or "skip") for every suite line, in file order."""
    rows = []
    for line in read_lines(SHARDS_FILE):
        if line and not line.startswith("#"):
            parts = line.split(" ")
            rows.append((parts[0], parts[1]))
    return rows


def read_times() -> dict[str, float]:
    times = {}
    if TIMES_FILE.exists():
        for line in read_lines(TIMES_FILE):
            if line and not line.startswith("#"):
                name, seconds = line.split(" ")
                times[name] = float(seconds)
    return times


def weights(times: dict[str, float], names: list[str]) -> dict[str, float]:
    """Measured seconds, or the median for a suite CI has not timed yet. Startup counts as a second."""
    known = [times[name] for name in names if name in times]
    default = statistics.median(known) if known else 5.0
    return {name: max(times.get(name, default), 1.0) for name in names}


def plan(shard: str) -> list[str]:
    rows = shard_lines()
    if not any(name == "ci_shards" and value in SHARDS for name, value in rows):
        raise SystemExit("game/tests/ci_shards.txt must run ci_shards on a shard")
    names = [name for name, value in rows if value == shard]
    if shard == SCAFFOLD_SHARD:
        names.append(SCAFFOLD)
    if not names:
        raise SystemExit(f"No suites for shard {shard} in game/tests/ci_shards.txt")
    weight = weights(read_times(), names)
    # Longest first, so the long suites start early and the short ones fill the lanes at the end.
    return sorted(names, key=lambda name: (-weight[name], name))


def balance(times: dict[str, float]) -> dict[str, float]:
    """Gives each running suite the shard with the least measured time so far (longest first)."""
    rows = shard_lines()
    names = [name for name, value in rows if value != "skip"]
    weight = weights(times, names + [SCAFFOLD])
    load = {shard: 0.0 for shard in SHARDS}
    load[SCAFFOLD_SHARD] += weight[SCAFFOLD]
    chosen = {}
    for name in sorted(names, key=lambda name: (-weight[name], name)):
        shard = min(SHARDS, key=lambda shard: (load[shard], shard))
        chosen[name] = shard
        load[shard] += weight[name]
    out = []
    for line in read_lines(SHARDS_FILE):
        parts = line.split(" ")
        if line and not line.startswith("#") and parts[0] in chosen:
            line = f"{parts[0]} {chosen[parts[0]]}"
        out.append(line)
    SHARDS_FILE.write_text("\n".join(out), encoding="utf-8", newline="\n")
    return load


def gh(*args: str) -> str:
    return subprocess.run(["gh", *args], check=True, capture_output=True, text=True, encoding="utf-8", errors="replace").stdout


def run_times(run_id: str) -> dict[str, int]:
    jobs = json.loads(gh("api", f"repos/{REPO}/actions/runs/{run_id}/jobs?per_page=100"))["jobs"]
    found = {}
    for job in jobs:
        if not job["name"].startswith("Godot native logic"):
            continue
        log = ANSI.sub("", gh("api", "--allow-escape-sequences", f"repos/{REPO}/actions/jobs/{job['id']}/logs"))
        for line in log.splitlines():
            match = SUITE_TIME.match(line.strip())
            if match:
                found[match.group(1)] = int(match.group(2))
    return found


def refresh(run_ids: list[str]) -> None:
    if not run_ids:
        runs = json.loads(gh("api", f"repos/{REPO}/actions/workflows/verify.yml/runs?branch=main&status=success&per_page=1"))
        run_ids = [str(runs["workflow_runs"][0]["id"])]
    samples: dict[str, list[int]] = {}
    for run_id in run_ids:
        for name, seconds in run_times(run_id).items():
            samples.setdefault(name, []).append(seconds)
    if not samples:
        raise SystemExit(f"No SUITE TIME lines in runs {', '.join(run_ids)}")
    times = read_times()
    times.update({name: round(statistics.mean(values), 1) for name, values in samples.items()})
    known = {name for name, _ in shard_lines()} | {SCAFFOLD}
    times = {name: value for name, value in times.items() if name in known}
    header = ["# Seconds each Godot suite took in CI (SUITE TIME lines), which scripts/ci_shards.py",
              f"# uses to balance the shards and run long suites first. Refreshed from runs {', '.join(run_ids)}.",
              "# Refresh: python3 scripts/ci_shards.py refresh [RUN_ID ...]"]
    body = [f"{name} {value:g}" for name, value in sorted(times.items())]
    TIMES_FILE.write_text("\n".join(header + body) + "\n", encoding="utf-8", newline="\n")
    report(balance(times))


def report(load: dict[str, float]) -> None:
    print("Shard loads (s): " + ", ".join(f"{shard}: {round(seconds)}" for shard, seconds in load.items()))


def main(argv: list[str]) -> int:
    if len(argv) == 2 and argv[0] == "plan" and argv[1] in SHARDS:
        print("\n".join(plan(argv[1])))
    elif argv and argv[0] == "refresh":
        refresh(argv[1:])
    elif argv == ["balance"]:
        report(balance(read_times()))
    else:
        print(__doc__)
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
