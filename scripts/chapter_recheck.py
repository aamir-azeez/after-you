"""Replays every stored run of a chapter headless after a layout change and
says per stage whether it still finishes.

The runs are the chapter's routes (game/tests/routes/<key>.json, recorded
inputs or hand-written steps), or for a published chapter without them its
stage fixtures' inputs. Each stage plays from the checkpoint the stage before
derives on the current definition, so a changed layout is played as it is now,
not checked against the old hashes. A stage that fails is named with its reason
and the later ones are "not reached". Each turn's played time is shown against
its limit (TIGHT over 70% of it), with how long the replay took. Nothing is
written; exit 1 when a stage fails.

  python scripts/chapter_recheck.py --key the-quiet-mill@1 [--godot <console exe>]
"""
from __future__ import annotations

import argparse
from pathlib import Path
import sys
import time

from chapter_tools import recordings
from chapter_tools.chapters import Chapter
from chapter_tools.godot import Game, ToolError, binary
from chapter_tools.turn_limits import Rules

ROOT = Path(__file__).resolve().parent.parent


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    parser.add_argument("--key", required=True, help="the chapter, such as the-quiet-mill@1")
    parser.add_argument("--godot", default="", help="Godot console binary (default: $GODOT)")
    parser.add_argument("--root", default=str(ROOT), help="the repository (default: this one)")
    parser.add_argument("--in-place", action="store_true", help="run in the repository's own imported game/ instead of a temporary copy")
    parser.add_argument("--keep", action="store_true", help="keep the temporary copy")
    args = parser.parse_args(argv)
    root = Path(args.root).resolve()
    started = time.monotonic()
    try:
        Chapter(root, args.key).refuse_unreplayable()
        rules = Rules(root)
        with Game(binary(args.godot), root / "game", args.in_place, args.keep) as game:
            ready = time.monotonic()
            report = recordings.play(game, args.key, "recheck")
    except ToolError as error:
        print(f"chapter_recheck.py: {error}", file=sys.stderr)
        return 1
    stages = report.get("stages", [])
    finished = sum(1 for row in stages if row.get("ok"))
    print(f"CHAPTER RECHECK {args.key}: {finished} of {len(stages)} stages finish (routes: {report['source']})")
    for line in recordings.stage_lines(rules, report):
        print(line)
    if not stages and report.get("error"):
        print("  " + report["error"])
    print(f"replayed in {report.get('msec', 0) / 1000:.1f} s; {time.monotonic() - started:.0f} s in all, {ready - started:.0f} s of it copying and importing the game")
    return 0 if report.get("ok") else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
