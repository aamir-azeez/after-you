"""Reports a chapter's turn lengths against its played routes, and sets them.

Without --a-seconds and --b-seconds it replays the chapter's routes headless
(game/tests/routes/<key>.json, or a published chapter's stage fixtures) and
prints each turn's played time against the limit, flagging a turn over 70% of
it, with a suggested turn_limits: twice the longest played turn, rounded up to
5 seconds, never under a minute. Turn times are generous, for exploring, not
racing; the owner sets the final number.

With --a-seconds and --b-seconds it writes them as the definition's
turn_limits (or the suggestion, with --suggested), then rewrites the fixtures
and everything they decide (chapter_fixtures.py). Values the rules or the
server would refuse are an error and nothing is written. Released chapters are
refused: a changed turn length ships as a new version.

  python scripts/chapter_turn_limits.py --key the-quiet-mill@1 [--a-seconds 90 --b-seconds 120 | --suggested] [--godot <console exe>]
"""
from __future__ import annotations

import argparse
from pathlib import Path
import sys

import chapter_fixtures
from chapter_recording import suggestion_lines
from chapter_tools import recordings
from chapter_tools.chapters import Chapter, turn_limits_edit
from chapter_tools.godot import Game, ToolError, binary
from chapter_tools.turn_limits import Rules

ROOT = Path(__file__).resolve().parent.parent


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    parser.add_argument("--key", required=True, help="the chapter, such as the-quiet-mill@1")
    parser.add_argument("--a-seconds", type=int, help="the first turn's length to write, in seconds")
    parser.add_argument("--b-seconds", type=int, help="the second turn's length to write, in seconds (longer than the first)")
    parser.add_argument("--suggested", action="store_true", help="write the suggestion")
    parser.add_argument("--godot", default="", help="Godot console binary (default: $GODOT)")
    parser.add_argument("--root", default=str(ROOT), help="the repository (default: this one)")
    parser.add_argument("--in-place", action="store_true", help="run in the repository's own imported game/ instead of a temporary copy")
    parser.add_argument("--keep", action="store_true", help="keep the temporary copy")
    args = parser.parse_args(argv)
    if (args.a_seconds is None) != (args.b_seconds is None) or (args.suggested and args.a_seconds is not None):
        parser.error("give both --a-seconds and --b-seconds, or --suggested, or neither to only report")
    root = Path(args.root).resolve()
    try:
        chapter = Chapter(root, args.key)
        chapter.refuse_unreplayable()
        rules = Rules(root)
        writing = args.suggested or args.a_seconds is not None
        if writing:
            chapter.refuse_released("changing its turn limits")
        if args.a_seconds is not None:
            a, b = args.a_seconds * rules.tick_rate, args.b_seconds * rules.tick_rate
            problems = rules.problems(a, b)
            if problems:
                raise ToolError(f"{args.key}: A {args.a_seconds} s, B {args.b_seconds} s refused: " + "; ".join(problems))
        with Game(binary(args.godot), root / "game", args.in_place, args.keep) as game:
            report = recordings.play(game, args.key, "recheck")
            print(f"CHAPTER TURN LIMITS {args.key}: A {rules.seconds(report['limits'].get('a', 0))}, B {rules.seconds(report['limits'].get('b', 0))} "
                  f"(routes: {report['source']})")
            for line in recordings.stage_lines(rules, report):
                print(line)
            for line in suggestion_lines(rules, report):
                print(line)
            if not report["ok"]:
                raise ToolError(f"the routes do not finish: {report['error']}")
            if not writing:
                return 0
            if args.suggested:
                a, b, _ = rules.suggest(*recordings.longest(report))
            relative, catalog = turn_limits_edit(chapter, a, b)
            changes, notes = chapter_fixtures.plan(game, chapter, {relative: catalog})
            lines = chapter_fixtures.apply(root, chapter, changes, notes)
    except ToolError as error:
        print(f"chapter_turn_limits.py: {error}", file=sys.stderr)
        return 1
    print(f"turn_limits set to A {rules.seconds(a)}, B {rules.seconds(b)}")
    for line in lines:
        print("  " + line)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
