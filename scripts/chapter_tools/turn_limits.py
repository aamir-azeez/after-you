"""Turn lengths: what the rules and the server accept, what play suggests, and
which recorded turns run close to their limit.

A definition's "turn_limits" {"a_ticks", "b_ticks"} must satisfy the rules
(game/core/physical/runtime.gd: 1 <= a < b <= MAX_DECLARED_TURN_TICKS, or
a <= b <= MAX_OPEN_TURN_TICKS on open turns, where every turn has the same
limit) and the server,
which grows a chapter's stored bounds with its turns and refuses to load a
chapter whose widest pair outgrows a room row (backend/src/v2/
protocol-physical-recording.ts scaledLimits and checkTurnBounds) or, on open
turns, whose widest turn outgrows a row, the Worker's body or the rows a room
holds (backend/src/v2/open-turns.ts openTurnLimits, which sizes every open turn
by the widest packed recording, packedRecordingBytes; earlier turns are kept as
fingerprints, so the number of stages no longer matters). Both are read from
their sources here, and a change to the server's formula stops these scripts
until this file follows it.

Turn times are generous, for exploring, not racing: a suggestion doubles the
longest played turn, rounds up to whole 5 seconds and never goes under a
minute; on open turns it is one number for every turn. The owner sets the
final number.
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
        self.open_rule_cap = _constant(runtime, r"^const MAX_OPEN_TURN_TICKS := (\d+)$", "MAX_OPEN_TURN_TICKS")
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
        # Open turns: open-turns.ts openTurnLimits, openBodyLimits and OPEN_TURNS_BRANCHES.
        open_turns = v2 / "open-turns.ts"
        self.open_envelope_bytes = _constant(open_turns, r"^const ENVELOPE_BYTES = ([\d_]+);$", "ENVELOPE_BYTES")
        self.open_checkpoint_bytes = _constant(open_turns, r"^const CHECKPOINT_BYTES = ([\d_]+);$", "CHECKPOINT_BYTES")
        self.worker_body_bytes = _constant(open_turns, r"^const MAX_WORKER_BODY_BYTES = ([\d_]+);$", "MAX_WORKER_BODY_BYTES")
        found = re.search(r"^export const MAX_ROOM_TURNS = (\d+), MAX_ROOM_PAIRS = (\d+);$", (v2 / "row-bound.ts").read_text(encoding="utf-8"), re.M)
        if not found:
            raise ToolError(f"{(v2 / 'row-bound.ts').as_posix()} no longer declares MAX_ROOM_TURNS and MAX_ROOM_PAIRS; update scripts/chapter_tools/turn_limits.py")
        self.room_turns, self.room_pairs = (int(group) for group in found.groups())
        self.archive_bytes = _constant(v2 / "row-bound.ts", r"^export const MAX_REPLAY_ARCHIVE_BYTES = ([\d_ *]+);$", "MAX_REPLAY_ARCHIVE_BYTES")
        self.open_branches = _constant(open_turns, r"^export const OPEN_TURNS_BRANCHES = (\d+);$", "OPEN_TURNS_BRANCHES")
        # Open turns are always packed: open-turns.ts packedRecordingBytes, with recording-codec.ts's checks.
        self.packed_header_bytes = _constant(open_turns, r"^const PACKED_HEADER_BYTES = ([\d_]+);$", "PACKED_HEADER_BYTES")
        codec = v2 / "recording-codec.ts"
        found = re.search(r"^export const CHECK_EVERY = (\d+), FULL_CHECK_EVERY = (\d+), SHORT_HASH_BYTES = (\d+), FULL_HASH_BYTES = (\d+);$", codec.read_text(encoding="utf-8"), re.M)
        if not found:
            raise ToolError(f"{codec.as_posix()} no longer declares its check spacing; update scripts/chapter_tools/turn_limits.py")
        self.check_every, self.full_check_every, self.short_hash_bytes, self.full_hash_bytes = (int(group) for group in found.groups())
        # Every family's open turns adapter sizes them in protocol-physical-recording.ts openPhysicalRecording. Carry-over
        # turns (rules 18 to 21) only pass their flag through: their hand-off fields sit inside PACKED_HEADER_BYTES, so
        # every rule set's open turns size the same.
        if "openTurnLimits(definition.stages, packedRecordingBytes(turns?.b_ticks ?? 1200), maxBranches, carry)" not in recording.read_text(encoding="utf-8"):
            raise ToolError(f"{recording.as_posix()} changed how it sizes open turns; update scripts/chapter_tools/turn_limits.py")
        source = open_turns.read_text(encoding="utf-8")
        # The formula mirrored by open_fits(); any change to it must change this file too.
        for expected in ("if (recordingBytes + ENVELOPE_BYTES > MAX_ROW_BYTES || recordingBytes + CHECKPOINT_BYTES + ENVELOPE_BYTES > MAX_WORKER_BODY_BYTES) throw",
                         "const held = MAX_ROOM_TURNS * (PACKED_HEADER_BYTES + ENVELOPE_BYTES) + MAX_ROOM_PAIRS * (2 * PACKED_HEADER_BYTES + CHECKPOINT_BYTES + ENVELOPE_BYTES);",
                         "if (held + branches * 2 * recordingBytes <= MAX_REPLAY_ARCHIVE_BYTES) return",
                         "let raw = 1 + Math.max(1, Math.ceil(Math.log2(ticks + 1) / 7)) + 3 * ticks;",
                         "for (const tick of checkTicks(ticks)) raw += checkBytes(tick, ticks);",
                         "return PACKED_HEADER_BYTES + 4 * Math.ceil(raw / 3);"):
            if expected not in source:
                raise ToolError(f"{open_turns.as_posix()} changed how it bounds open turns ({expected}); update scripts/chapter_tools/turn_limits.py")
        top = self.rule_cap // self.tick_rate * self.tick_rate
        self.whole_seconds = range(self.tick_rate, top + 1, self.tick_rate)
        self.open_whole_seconds = range(self.tick_rate, self.open_rule_cap // self.tick_rate * self.tick_rate + 1, self.tick_rate)
        # The longest whole-second turn each role may have: the factor is the larger of the two roles', so each cap holds on its own and together.
        self.cap_a = max((t for t in self.whole_seconds if self.server_fits(t, 1) and t < self.rule_cap), default=0)
        self.cap_b = max((t for t in self.whole_seconds if self.server_fits(1, t)), default=0)

    def server_fits(self, a: int, b: int) -> bool:
        factor = max(1, a / self.published_a, b / self.published_b)
        scale = lambda published: math.ceil(published * factor)  # noqa: E731
        return scale(self.checkpoint_bytes) + 2 * scale(self.recording_bytes) + self.envelope_bytes <= self.row_bytes

    def packed_bytes(self, ticks: int) -> int:
        """The widest packed turn `ticks` long (open-turns.ts packedRecordingBytes): a new stick every tick, every check, base64 and the header."""
        raw = 1 + max(1, math.ceil(math.log2(ticks + 1) / 7)) + 3 * ticks
        for tick in range(self.check_every, ticks, self.check_every):
            raw += self.full_hash_bytes if tick % self.full_check_every == 0 else self.short_hash_bytes
        return self.packed_header_bytes + 4 * math.ceil(raw / 3)

    def open_fits(self, a: int, b: int, stages: int) -> bool:
        """Whether an open turns chapter with turn_limits {a, b} loads (any number of `stages`: earlier turns are kept as
        fingerprints, so nothing nests): its widest turn fits a row and, with a flat checkpoint, the Worker's body, and
        some branch count from OPEN_TURNS_BRANCHES down keeps every row a room may hold inside the archive."""
        # Every open turn has the second turn's limit (b), recorded packed.
        recording = self.packed_bytes(max(a, b))
        if recording + self.open_envelope_bytes > self.row_bytes or recording + self.open_checkpoint_bytes + self.open_envelope_bytes > self.worker_body_bytes:
            return False
        held = (self.room_turns * (self.packed_header_bytes + self.open_envelope_bytes)
                + self.room_pairs * (2 * self.packed_header_bytes + self.open_checkpoint_bytes + self.open_envelope_bytes))
        return any(held + branches * 2 * recording <= self.archive_bytes for branches in range(self.open_branches, 0, -1))

    def cap_open(self, stages: int) -> int:
        """The longest whole-second turn, one for every turn, an open turns chapter of `stages` stages may have (0: none fits)."""
        return max((t for t in self.open_whole_seconds if self.open_fits(t, t, stages)), default=0)

    def problems(self, a: int, b: int, open_stages: int = 0) -> list[str]:
        """Why the rules or the server would refuse turn_limits {a, b} (ticks); [] when both accept.
        `open_stages`: an open turns chapter's stage count, 0 for any other chapter."""
        result: list[str] = []
        if open_stages and (a < 1 or b < a):
            result.append(f"the second turn may not be shorter than the first: got A {self.seconds(a)}, B {self.seconds(b)}")
        elif not open_stages and (a < 1 or b <= a):
            result.append(f"the second turn must be longer than the first (the receiver waits out the first turn): got A {self.seconds(a)}, B {self.seconds(b)}")
        if open_stages and (b > self.open_rule_cap or a > self.open_rule_cap):
            result.append(f"an open turn may last at most {self.seconds(self.open_rule_cap)} (MAX_OPEN_TURN_TICKS {self.open_rule_cap})")
        elif not open_stages and (b > self.rule_cap or a > self.rule_cap):
            result.append(f"a turn may last at most {self.seconds(self.rule_cap)} (MAX_DECLARED_TURN_TICKS {self.rule_cap})")
        if open_stages and not self.open_fits(a, b, open_stages):
            result.append(f"the server cannot store turns that long: at most {self.seconds(self.cap_open(open_stages))} a turn fits {open_stages} open turns stages "
                          "(backend openTurnLimits; longer turns need a backend storage change)")
        elif not open_stages and not self.server_fits(a, b):
            result.append(f"the server cannot store pairs that long: at most A {self.seconds(self.cap_a)} and B {self.seconds(self.cap_b)} fit a room row "
                          "(backend checkTurnBounds; longer turns need a backend storage change)")
        return result

    def seconds(self, ticks: int) -> str:
        whole, rest = divmod(ticks, self.tick_rate)
        return f"{whole} s" if rest == 0 else f"{ticks / self.tick_rate:.1f} s"

    def suggest(self, a_played: int, b_played: int, open_stages: int = 0) -> tuple[int, int, list[str]]:
        """Suggested turn_limits (ticks) for the longest played A and B turns, and notes. On open turns
        (`open_stages`: the chapter's stage count) every turn has the same limit, so A and B get one number
        from the longest turn of all."""
        notes: list[str] = []

        def round_up(played: int) -> int:
            seconds = played / self.tick_rate * (1 + SUGGESTION_MARGIN)
            seconds = max(SUGGESTION_FLOOR_SECONDS, math.ceil(seconds / SUGGESTION_STEP_SECONDS) * SUGGESTION_STEP_SECONDS)
            return int(seconds * self.tick_rate)
        if open_stages:
            turn, cap = round_up(max(a_played, b_played)), self.cap_open(open_stages)
            if turn > cap:
                notes.append(f"clamped to the longest turn the server can store for {open_stages} open turns stages ({self.seconds(cap)})")
                turn = cap
            return turn, turn, notes
        a, b = round_up(a_played), round_up(b_played)
        if b < a + self.grace:
            b = a + self.grace
            notes.append(f"B is A plus the receiver's {self.seconds(self.grace)} grace, as published turns are")
        if a > self.cap_a or b > self.cap_b:
            notes.append(f"clamped to the longest turns the server can store (A {self.seconds(self.cap_a)}, B {self.seconds(self.cap_b)})")
            a, b = min(a, self.cap_a), min(b, self.cap_b)
        return a, b, notes

