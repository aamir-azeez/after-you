"""Makes a real run of a chapter its witness routes and its fixtures.

The source is a file holding the run's recorded pairs, both turns of each stage:
a run's final checkpoint (its proof holds every stage's pair), a solo journey
save, a recording pair {"a", "b"}, or any of these in the shared blob format
(game/tests/recorded_routes.gd lists them). Its pairs become input routes in
game/tests/routes/<key>.json (only --stage's with it, the other stages keep
theirs), which are replayed headless through the real simulation, every stage
from the checkpoint the stage before derives. If a stage does not finish,
nothing is written and the stage and reason are printed. Otherwise the routes
are written, the fixtures and everything they decide are rewritten
(chapter_fixtures.py), and each turn's played time is reported against its
limit with a suggested turn_limits (chapter_turn_limits.py writes limits).

  python scripts/chapter_recording.py --key the-quiet-mill@1 --recording <copy of a run> [--stage <id>] [--godot <console exe>]

Pass a copy: a file inside the game's own save folder is refused. Released
chapters are refused: their routes and fixtures never change.
"""
from __future__ import annotations

import argparse
from pathlib import Path
import sys

import chapter_fixtures
from chapter_tools import recordings
from chapter_tools.chapters import Chapter, routes_text, stage_ids
from chapter_tools.godot import Game, ToolError, binary
from chapter_tools.turn_limits import Rules

ROOT = Path(__file__).resolve().parent.parent


def suggestion_lines(rules: Rules, report: dict) -> list[str]:
    a_played, b_played = recordings.longest(report)
    if not a_played or not b_played:
        return []
    a, b, notes = rules.suggest(a_played, b_played)
    return [f"suggested turn_limits: A {rules.seconds(a)}, B {rules.seconds(b)} (longest played A {rules.seconds(a_played)}, B {rules.seconds(b_played)})"] + \
        [f"  {note}" for note in notes] + \
        [f"  set them with: python scripts/chapter_turn_limits.py --key {report['key']} --a-seconds {a // rules.tick_rate} --b-seconds {b // rules.tick_rate}"]


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    parser.add_argument("--key", required=True, help="the chapter, such as the-quiet-mill@1")
    parser.add_argument("--recording", required=True, help="a copy of the run: JSON or a blob")
    parser.add_argument("--stage", default="", help="take only this stage's pair from the run")
    parser.add_argument("--godot", default="", help="Godot console binary (default: $GODOT)")
    parser.add_argument("--root", default=str(ROOT), help="the repository (default: this one)")
    parser.add_argument("--in-place", action="store_true", help="run in the repository's own imported game/ instead of a temporary copy")
    parser.add_argument("--keep", action="store_true", help="keep the temporary copy")
    args = parser.parse_args(argv)
    root = Path(args.root).resolve()
    try:
        chapter = Chapter(root, args.key)
        chapter.refuse_released("taking routes from a recording")
        chapter.refuse_unreplayable()
        if not chapter.routes_from_recordings():
            raise ToolError(f"{args.key}'s witness {chapter.witness.relative_to(root).as_posix()} plays routes of its own, not game/tests/routes/{args.key}.json")
        source = Path(args.recording).resolve()
        recordings.refuse_real_save(source)
        if not source.is_file():
            raise ToolError(f"no recording at {source}")
        rules = Rules(root)
        with Game(binary(args.godot), root / "game", args.in_place, args.keep) as game:
            report = recordings.play(game, args.key, "import", ["--source", str(source)] + (["--stage", args.stage] if args.stage else []))
            print(f"CHAPTER RECORDING {args.key} from {source.name}: took {', '.join(report['imported']) or 'no stage'}")
            for note in report.get("notes", []):
                print("  " + note)
            for line in recordings.stage_lines(rules, report):
                print(line)
            if not report["ok"]:
                raise ToolError(f"the run does not finish: {report['error']}; nothing written")
            relative = chapter.routes.relative_to(root).as_posix()
            routes = routes_text(report["routes"], [row["id"] for row in report["stages"]] or stage_ids(root, args.key)).encode("utf-8")
            changes, notes = chapter_fixtures.plan(game, chapter, {relative: routes})
            lines = chapter_fixtures.apply(root, chapter, changes, notes)
    except ToolError as error:
        print(f"chapter_recording.py: {error}", file=sys.stderr)
        return 1
    for line in lines:
        print("  " + line)
    for line in suggestion_lines(rules, report):
        print(line)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
