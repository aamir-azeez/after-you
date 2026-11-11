"""Plays a chapter's routes through game/tests/chapter_recordings.gd and reads
its report; shared by chapter_recording.py, chapter_recheck.py and
chapter_turn_limits.py."""
from __future__ import annotations

import json
import os
from pathlib import Path

from chapter_tools.godot import Game, ToolError
from chapter_tools.turn_limits import Rules, TIGHT_SHARE


def play(game: Game, key: str, mode: str, extra: list[str] | None = None) -> dict:
    out = game.scratch(f"report-{mode}") / "report.json"
    ok, log = game.script("res://tests/chapter_recordings.gd", ["--mode", mode, "--key", key, "--out", str(out), *(extra or [])], mode)
    if not ok or not out.is_file():
        errors = "\n".join(line for line in log.splitlines() if "ERROR" in line)[-1500:]
        raise ToolError(f"{key}: chapter_recordings.gd did not run:\n{errors or log[-1500:]}")
    return json.loads(out.read_text(encoding="utf-8"))


def stage_lines(rules: Rules, report: dict) -> list[str]:
    """One line a stage: whether it finished, each turn's played time against its
    limit (TIGHT over TIGHT_SHARE of it), and how long the replay took."""
    limits = report.get("limits", {})
    lines = []
    for row in report.get("stages", []):
        if row.get("error") == "not reached":
            lines.append(f"  not reached  {row['id']}")
            continue
        turns = []
        for role in ("a", "b"):
            played, limit = int(row.get(f"{role}_ticks", 0)), int(limits.get(role, 0))
            if not played:
                continue
            share = played / limit if limit else 0
            turns.append(f"{role.upper()} {rules.seconds(played)}" + (f" of {rules.seconds(limit)} ({share:.0%})" + ("  TIGHT" if share > TIGHT_SHARE else "") if limit else ""))
        status = "finishes" if row.get("ok") else "FAILS"
        lines.append(f"  {status:<12} {row['id']}: " + ", ".join(turns) + f"  [{row.get('msec', 0)} ms]" + ("" if row.get("ok") else f"\n               {row.get('error')}"))
    return lines


def longest(report: dict) -> tuple[int, int]:
    """The longest finished A and B turns, in ticks."""
    rows = [row for row in report.get("stages", []) if row.get("ok")]
    return max((int(r["a_ticks"]) for r in rows), default=0), max((int(r["b_ticks"]) for r in rows), default=0)


def real_saves() -> Path | None:
    """The folder the game's own saves live in on Windows (never read here), or None elsewhere."""
    appdata = os.environ.get("APPDATA", "")
    return Path(appdata, "AfterYou").resolve() if appdata else None


def refuse_real_save(path: Path) -> None:
    """A source inside the game's real save folder is refused: copy it out first."""
    saves = real_saves()
    if saves and (path == saves or saves in path.parents):
        raise ToolError(f"{path} is in the game's own save folder; copy the file somewhere else first and pass the copy")
