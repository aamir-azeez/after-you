"""Turn lengths: what the rules and the server accept, what play suggests, and
which recorded turns run close to their limit.

A definition's "turn_limits" {"a_ticks", "b_ticks"} must satisfy the rules
(game/core/physical/runtime.gd: 1 <= a < b <= MAX_DECLARED_TURN_TICKS) and the
server, which grows a chapter's stored bounds with its turns and refuses to load
a chapter whose widest pair outgrows a room row (backend/src/v2/
protocol-physical-recording.ts scaledLimits and checkTurnBounds). Both are read
from their sources here, and a change to the server's formula stops these
scripts until this file follows it.

Turn times are generous, for exploring, not racing: a suggestion doubles the
longest played turn, rounds up to whole 5 seconds and never goes under a
minute. The owner sets the final number.
"""
from __future__ import annotations

import math
from pathlib import Path
import re

from chapter_tools.godot import ToolError

## Suggested turn = played turn x (1 + SUGGESTION_MARGIN): the owner's 100%.
SUGGESTION_MARGIN = 1.0
## A suggested turn is never shorter than this, in seconds.
SUGGESTION_FLOOR_SECONDS = 60
## Suggestions round up to whole multiples of this, in seconds.
SUGGESTION_STEP_SECONDS = 5
## A recorded turn that used more than this share of its limit is flagged as tight.
TIGHT_SHARE = 0.7


def _constant(path: Path, pattern: str, what: str) -> int:
    found = re.search(pattern, path.read_text(encoding="utf-8"), re.M)
    if not found:
        raise ToolError(f"{path.as_posix()} no longer declares {what}; update scripts/chapter_tools/turn_limits.py")
    # A literal such as 229_376 or 1536 * 1024.
    return math.prod(int(factor.replace("_", "")) for factor in found.group(1).split("*"))


class Rules:
    """The rule and server bounds, read from the repository at `root`."""

    def __init__(self, root: Path):
        runtime = root / "game/core/physical/runtime.gd"
        self.tick_rate = _constant(runtime, r"^const TICK_RATE := (\d+)$", "TICK_RATE")
        self.rule_cap = _constant(runtime, r"^const MAX_DECLARED_TURN_TICKS := (\d+)$", "MAX_DECLARED_TURN_TICKS")
        self.grace = _constant(runtime, r"^const RECEIVER_GRACE_TICKS := (\d+)$", "RECEIVER_GRACE_TICKS")
        v2 = root / "backend/src/v2"
        recording = v2 / "protocol-physical-recording.ts"
        self.checkpoint_bytes = _constant(v2 / "protocol-relay.ts", r"^export const MAX_CHECKPOINT_BYTES = ([\d_]+);$", "MAX_CHECKPOINT_BYTES")
        self.row_bytes = _constant(v2 / "row-bound.ts", r"^export const MAX_ROW_BYTES = ([\d_ *]+);$", "MAX_ROW_BYTES")
        self.envelope_bytes = _constant(recording, r"^export const ROW_ENVELOPE_BYTES = ([\d_]+);$", "ROW_ENVELOPE_BYTES")
        self.published_a = _constant(recording, r"^const MAX_TICKS = ([\d_]+),", "MAX_TICKS")
        source = recording.read_text(encoding="utf-8")
        # The formula mirrored by server_fits(); any change to it must change this file too.
        for expected in ("const factor = Math.max(1, turns.a_ticks / MAX_TICKS, turns.b_ticks / 1200);",
                         "const scale = (published: number) => Math.ceil(published * factor);",
                         "recording_bytes: scale(65_536)", "checkpoint_bytes: scale(MAX_CHECKPOINT_BYTES)",
                         "const pair = limits.checkpoint_bytes + 2 * (limits.recording_bytes ?? 65_536) + ROW_ENVELOPE_BYTES;"):
            if expected not in source:
                raise ToolError(f"{recording.as_posix()} changed how it bounds longer turns ({expected}); update scripts/chapter_tools/turn_limits.py")
        self.published_b = 1200
        self.recording_bytes = 65_536
        top = self.rule_cap // self.tick_rate * self.tick_rate
        # The longest whole-second turn each role may have: the factor is the larger of the two roles', so each cap holds on its own and together.
        self.cap_a = max((t for t in range(self.tick_rate, top + 1, self.tick_rate) if self.server_fits(t, 1) and t < self.rule_cap), default=0)
        self.cap_b = max((t for t in range(self.tick_rate, top + 1, self.tick_rate) if self.server_fits(1, t)), default=0)

    def server_fits(self, a: int, b: int) -> bool:
        factor = max(1, a / self.published_a, b / self.published_b)
        scale = lambda published: math.ceil(published * factor)  # noqa: E731
        return scale(self.checkpoint_bytes) + 2 * scale(self.recording_bytes) + self.envelope_bytes <= self.row_bytes

    def problems(self, a: int, b: int) -> list[str]:
        """Why the rules or the server would refuse turn_limits {a, b} (ticks); [] when both accept."""
        result: list[str] = []
        if a < 1 or b <= a:
            result.append(f"the second turn must be longer than the first (the receiver waits out the first turn): got A {self.seconds(a)}, B {self.seconds(b)}")
        if b > self.rule_cap or a > self.rule_cap:
            result.append(f"a turn may last at most {self.seconds(self.rule_cap)} (MAX_DECLARED_TURN_TICKS {self.rule_cap})")
        if not self.server_fits(a, b):
            result.append(f"the server cannot store pairs that long: at most A {self.seconds(self.cap_a)} and B {self.seconds(self.cap_b)} fit a room row "
                          "(backend checkTurnBounds; longer turns need a backend storage change)")
        return result

    def seconds(self, ticks: int) -> str:
        whole, rest = divmod(ticks, self.tick_rate)
        return f"{whole} s" if rest == 0 else f"{ticks / self.tick_rate:.1f} s"

    def suggest(self, a_played: int, b_played: int) -> tuple[int, int, list[str]]:
        """Suggested turn_limits (ticks) for the longest played A and B turns, and notes."""
        notes: list[str] = []

        def round_up(played: int) -> int:
            seconds = played / self.tick_rate * (1 + SUGGESTION_MARGIN)
            seconds = max(SUGGESTION_FLOOR_SECONDS, math.ceil(seconds / SUGGESTION_STEP_SECONDS) * SUGGESTION_STEP_SECONDS)
            return int(seconds * self.tick_rate)
        a, b = round_up(a_played), round_up(b_played)
        if b < a + self.grace:
            b = a + self.grace
            notes.append(f"B is A plus the receiver's {self.seconds(self.grace)} grace, as published turns are")
        if a > self.cap_a or b > self.cap_b:
            notes.append(f"clamped to the longest turns the server can store (A {self.seconds(self.cap_a)}, B {self.seconds(self.cap_b)})")
            a, b = min(a, self.cap_a), min(b, self.cap_b)
        return a, b, notes

