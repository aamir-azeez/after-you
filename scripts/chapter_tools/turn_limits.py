"""Turn lengths: what the rules and the server accept, what play suggests, and
which recorded turns run close to their limit.

A definition's "turn_limits" {"a_ticks", "b_ticks"} must satisfy the rules
(game/core/physical/runtime.gd: 1 <= a < b <= MAX_DECLARED_TURN_TICKS, or
LONG_TURN_TICKS when it declares "input_rules") and the server. For a published
chapter without input_rules the server grows its stored bounds with its turns
and refuses to load one whose widest pair outgrows a room row (backend/src/v2/
protocol-physical-recording.ts scaledLimits and checkTurnBounds). A chapter with
input_rules (every new one) records at most so many input changes, so the server
bounds its widest pair from the turns, the stage count and the initial
checkpoint, and its branches from the room's archives (longTurnRows and
checkLongTurnBounds). Both are read from their sources here, and a change to the
server's formulas stops these scripts until this file follows it.

Turn times are generous, for exploring, not racing: a suggestion doubles the
longest played turn, rounds up to whole 5 seconds and never goes under a
minute. The owner sets the final number.
"""
from __future__ import annotations

from dataclasses import dataclass
import json
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


@dataclass(frozen=True)
class Shape:
    """What the server's bounds read from a chapter besides its turns: capped
    input (input_rules), its stage count, its initial checkpoint's JSON bytes,
    its id and longest stage id, and the branches its descriptor allows."""
    capped: bool = True
    stages: int = 2
    initial_bytes: int = 2048
    id_bytes: int = 80
    max_branches: int | None = None


## A new chapter before it has a backend copy: two stages (the scaffold's), capped
## input, and an initial checkpoint and ids wider than any chapter's so far.
DEVELOPMENT_SHAPE = Shape()


def chapter_shape(chapter) -> Shape:
    """The Shape of a chapter_tools.chapters.Chapter: its backend definition and
    initial checkpoint when they exist, else the development shape; capped when
    its catalog declares input_rules."""
    # A catalog declares it as a literal ("input_rules":1) or, for a later version, by assignment (level.input_rules = 1).
    catalog = chapter.catalog.read_text(encoding="utf-8") if chapter.catalog is not None and chapter.catalog.is_file() else ""
    capped = re.search(r'"input_rules"\s*:|\.input_rules\s*=', catalog) is not None
    branches = re.search(r'"max_branches": (\d+)', chapter.descriptor.read_text(encoding="utf-8"))
    definition_name, initial_name = chapter.backend_files()
    v2 = chapter.root / "backend/src/v2"
    shape = Shape(capped=capped, max_branches=int(branches.group(1)) if branches else None)
    if (v2 / definition_name).is_file() and (v2 / initial_name).is_file():
        definition = json.loads((v2 / definition_name).read_text(encoding="utf-8"))
        initial = json.loads((v2 / initial_name).read_text(encoding="utf-8"))
        shape = Shape(capped=capped or "input_rules" in definition, stages=len(definition["stages"]), max_branches=shape.max_branches,
                      initial_bytes=len(json.dumps(initial, separators=(",", ":"), ensure_ascii=False).encode("utf-8")),
                      id_bytes=len(definition["id"]) + max(len(stage["id"]) for stage in definition["stages"]))
    return shape


def entries_bytes(entries: int, ticks: int) -> int:
    """protocol-physical-recording.ts entriesBytes: the widest JSON of `entries` action entries over `ticks` ticks."""
    digits, power = entries, 10
    while power <= ticks:
        digits += ticks // power
        power *= 10
    return entries * 44 + min(digits, entries * len(str(ticks)))


class Rules:
    """The rule and server bounds, read from the repository at `root`."""

    def __init__(self, root: Path):
        runtime = root / "game/core/physical/runtime.gd"
        self.tick_rate = _constant(runtime, r"^const TICK_RATE := (\d+)$", "TICK_RATE")
        self.rule_cap = _constant(runtime, r"^const MAX_DECLARED_TURN_TICKS := (\d+)$", "MAX_DECLARED_TURN_TICKS")
        self.long_cap = _constant(runtime, r"^const LONG_TURN_TICKS := (\d+)$", "LONG_TURN_TICKS")
        self.grace = _constant(runtime, r"^const RECEIVER_GRACE_TICKS := (\d+)$", "RECEIVER_GRACE_TICKS")
        self.change_ticks = _constant(runtime, r'^const INPUT_RULES := \{1: \{"change_ticks": (\d+),', "INPUT_RULES")
        self.burst = _constant(runtime, r'^const INPUT_RULES := \{1: \{"change_ticks": \d+, "burst": (\d+),', "INPUT_RULES")
        v2 = root / "backend/src/v2"
        recording = v2 / "protocol-physical-recording.ts"
        bounds = v2 / "row-bound.ts"
        self.checkpoint_bytes = _constant(v2 / "protocol-relay.ts", r"^export const MAX_CHECKPOINT_BYTES = ([\d_]+);$", "MAX_CHECKPOINT_BYTES")
        self.row_bytes = _constant(bounds, r"^export const MAX_ROW_BYTES = ([\d_ *]+);$", "MAX_ROW_BYTES")
        self.replay_archive_bytes = _constant(bounds, r"^export const MAX_REPLAY_ARCHIVE_BYTES = ([\d_ *]+);$", "MAX_REPLAY_ARCHIVE_BYTES")
        # Both as ARCHIVE_BOUNDS in protocol-physical-recording.ts derives them (checked below).
        self.room_archive_bytes = _constant(bounds, r"^export const MAX_ROOM_V2_ARCHIVE_BYTES = ([\d_ *]+);$", "MAX_ROOM_V2_ARCHIVE_BYTES") - 4096
        self.max_photos = _constant(bounds, r"^export const MAX_PHOTOS = (\d+);$", "MAX_PHOTOS")
        self.photo_row_bytes = math.ceil(_constant(v2 / "photo-image.ts", r"^export const MAX_PHOTO_BYTES = ([\d_ *]+);$", "MAX_PHOTO_BYTES") / 3) * 4 + 1024
        self.envelope_bytes = _constant(recording, r"^export const ROW_ENVELOPE_BYTES = ([\d_]+);$", "ROW_ENVELOPE_BYTES")
        self.published_a = _constant(recording, r"^const MAX_TICKS = ([\d_]+),", "MAX_TICKS")
        self.recording_fixed = _constant(recording, r"^const RECORDING_FIXED_BYTES = ([\d_]+);$", "RECORDING_FIXED_BYTES")
        self.checkpoint_fixed = _constant(recording, r"^const CHECKPOINT_FIXED_BYTES = ([\d_]+);$", "CHECKPOINT_FIXED_BYTES")
        self.pair_keys = _constant(recording, r"^const PAIR_KEYS_BYTES = ([\d_]+);$", "PAIR_KEYS_BYTES")
        self.small_tables = _constant(recording, r"^const ARCHIVE_SMALL_TABLES_BYTES = ([\d_ *]+);$", "ARCHIVE_SMALL_TABLES_BYTES")
        source = recording.read_text(encoding="utf-8")
        # The formulas mirrored by server_fits() and capped_rows(); any change to them must change this file too.
        for expected in ("const factor = Math.max(1, turns.a_ticks / MAX_TICKS, turns.b_ticks / 1200);",
                         "const scale = (published: number) => Math.ceil(published * factor);",
                         "recording_bytes: scale(65_536)", "checkpoint_bytes: scale(MAX_CHECKPOINT_BYTES)",
                         "const pair = limits.checkpoint_bytes + 2 * (limits.recording_bytes ?? 65_536) + ROW_ENVELOPE_BYTES;",
                         "return Math.min(ticks, 1 + rules.burst + Math.floor(ticks / rules.change_ticks));",
                         "for (let power = 10; power <= ticks; power *= 10) digits += Math.floor(ticks / power);",
                         "return entries * 44 + Math.min(digits, entries * String(ticks).length);",
                         "const checkBytes = (ticks: number) => 90 + String(ticks).length;",
                         "return RECORDING_FIXED_BYTES + idBytes + entriesBytes(maxActionEntries(rules, ticks), ticks) + (Math.floor(ticks / 30) + 1) * checkBytes(ticks);",
                         "const checkpoint = (stage: number) => initial + stage * (initial + fixed + a + b);",
                         "branch += keys + a + b + checkpoint(stage) + 2 * keys + a + b;",
                         "pair: keys + a + b + checkpoint(shape.stages), branch };",
                         "if (rows.pair + ROW_ENVELOPE_BYTES > MAX_ROW_BYTES)",
                         "const history = (maxBranches as number) * rows.branch + rows.checkpoint + ROW_ENVELOPE_BYTES;",
                         "const snapshot = (maxBranches as number) * escaped.branch + escaped.checkpoint + ESCAPED_REST * ROW_ENVELOPE_BYTES;",
                         "return widestRecordingBytes(rules, ticks, idBytes) + maxActionEntries(rules, ticks) * ESCAPED_ENTRY_BYTES + (Math.floor(ticks / 30) + 1) * ESCAPED_CHECK_BYTES +",
                         "const record = escaped ? escapedRecordingBytes : widestRecordingBytes, rest = escaped ? ESCAPED_REST : 1;",
                         "const photos = Math.min(archives.max_photos, (maxBranches as number) * 2 * shape.stages) * archives.photo_row_bytes;",
                         "if (history > archives.replay_archive_bytes || snapshot + photos + ARCHIVE_SMALL_TABLES_BYTES > archives.room_archive_bytes)",
                         "const ESCAPED_ENTRY_BYTES = 8, ESCAPED_CHECK_BYTES = 6, ESCAPED_REST = 2;",
                         "(ESCAPED_REST - 1) * (RECORDING_FIXED_BYTES + idBytes);",
                         "const initial = rest * shape.initial_bytes, fixed = rest * CHECKPOINT_FIXED_BYTES, keys = rest * PAIR_KEYS_BYTES;",
                         "room_archive_bytes: MAX_ROOM_V2_ARCHIVE_BYTES - 4096,",
                         "photo_row_bytes: Math.ceil(MAX_PHOTO_BYTES / 3) * 4 + 1024, max_photos: MAX_PHOTOS });"):
            if expected not in source:
                raise ToolError(f"{recording.as_posix()} changed how it bounds longer turns ({expected}); update scripts/chapter_tools/turn_limits.py")
        self.published_b = 1200
        self.recording_bytes = 65_536
        top = self.long_cap // self.tick_rate * self.tick_rate
        # A new chapter's development turns (index.gd DEVELOPMENT_TURN_LIMITS): the longest whole-second
        # receiver turn the rules and the server accept with capped input in the development shape, the
        # first turn the receiver's grace shorter, as published turns are.
        self.cap_b = max((t for t in range(self.tick_rate + self.grace, top + 1, self.tick_rate) if self.capped_fits(t - self.grace, t, DEVELOPMENT_SHAPE)), default=0)
        self.cap_a = self.cap_b - self.grace
        self.dev_max_branches = self.max_branches(self.cap_a, self.cap_b, DEVELOPMENT_SHAPE)

    def server_fits(self, a: int, b: int) -> bool:
        """Whether a published-style chapter (no input_rules) with these turns loads."""
        factor = max(1, a / self.published_a, b / self.published_b)
        scale = lambda published: math.ceil(published * factor)  # noqa: E731
        return scale(self.checkpoint_bytes) + 2 * scale(self.recording_bytes) + self.envelope_bytes <= self.row_bytes

    def _recording(self, ticks: int, shape: Shape) -> int:
        entries = min(ticks, 1 + self.burst + ticks // self.change_ticks)
        return self.recording_fixed + shape.id_bytes + entries_bytes(entries, ticks) + (ticks // 30 + 1) * (90 + len(str(ticks)))

    def capped_rows(self, a: int, b: int, shape: Shape, escaped: bool = False) -> dict[str, int]:
        """protocol-physical-recording.ts longTurnRows; `escaped`: as a room snapshot measures them."""
        rest = 2 if escaped else 1

        def record(ticks: int) -> int:
            if not escaped:
                return self._recording(ticks, shape)
            entries = min(ticks, 1 + self.burst + ticks // self.change_ticks)
            return self._recording(ticks, shape) + entries * 8 + (ticks // 30 + 1) * 6 + (rest - 1) * (self.recording_fixed + shape.id_bytes)
        wa, wb = record(a), record(b)
        initial, fixed, keys = rest * shape.initial_bytes, rest * self.checkpoint_fixed, rest * self.pair_keys
        checkpoint = lambda stage: initial + stage * (initial + fixed + wa + wb)  # noqa: E731
        branch = sum(keys + wa + wb + checkpoint(stage) + 2 * keys + wa + wb for stage in range(1, shape.stages + 1))
        return {"checkpoint": checkpoint(shape.stages), "pair": keys + wa + wb + checkpoint(shape.stages), "branch": branch}

    def capped_fits(self, a: int, b: int, shape: Shape) -> bool:
        return self.capped_rows(a, b, shape)["pair"] + self.envelope_bytes <= self.row_bytes

    def max_branches(self, a: int, b: int, shape: Shape) -> int:
        """The most branches checkLongTurnBounds lets a capped chapter with these turns hold (0: none fit)."""
        rows, escaped = self.capped_rows(a, b, shape), self.capped_rows(a, b, shape, escaped=True)
        best = 0
        for count in range(1, 33):
            history = count * rows["branch"] + rows["checkpoint"] + self.envelope_bytes
            snapshot = count * escaped["branch"] + escaped["checkpoint"] + 2 * self.envelope_bytes
            photos = min(self.max_photos, count * 2 * shape.stages) * self.photo_row_bytes
            if history > self.replay_archive_bytes or snapshot + photos + self.small_tables > self.room_archive_bytes:
                break
            best = count
        return best

    def problems(self, a: int, b: int, shape: Shape | None = None) -> list[str]:
        """Why the rules or the server would refuse turn_limits {a, b} (ticks) for a chapter of `shape`
        (default: the development shape); [] when both accept."""
        shape = shape or DEVELOPMENT_SHAPE
        cap = self.long_cap if shape.capped else self.rule_cap
        result: list[str] = []
        if a < 1 or b <= a:
            result.append(f"the second turn must be longer than the first (the receiver waits out the first turn): got A {self.seconds(a)}, B {self.seconds(b)}")
        if b > cap or a > cap:
            result.append(f"a turn may last at most {self.seconds(cap)} ({'LONG_TURN_TICKS' if shape.capped else 'MAX_DECLARED_TURN_TICKS'} {cap})")
        elif not shape.capped and not self.server_fits(a, b):
            result.append(f"the server cannot store pairs that long without input_rules: at most A {self.seconds(self.longest(1, shape))} and "
                          f"B {self.seconds(self.longest(2, shape))} fit a room row (backend checkTurnBounds)")
        elif shape.capped and not self.capped_fits(a, b, shape):
            result.append(f"the server cannot store pairs that long in {shape.stages} stages: a room row holds every record of the last stage's "
                          "checkpoint (backend longTurnRows); shorten the turns")
        elif shape.capped and shape.max_branches is not None and shape.max_branches > self.max_branches(a, b, shape):
            result.append(f"the descriptor's max_branches {shape.max_branches} outgrows the room archives at these turns: at most "
                          f"{self.max_branches(a, b, shape)} (backend checkLongTurnBounds)")
        return result

    def longest(self, role: int, shape: Shape) -> int:
        """The longest whole-second uncapped turn for A (role 1) or B (role 2) on its own."""
        top = self.rule_cap // self.tick_rate * self.tick_rate
        fits = (lambda t: self.server_fits(t, 1) and t < self.rule_cap) if role == 1 else (lambda t: self.server_fits(1, t))
        return max((t for t in range(self.tick_rate, top + 1, self.tick_rate) if fits(t)), default=0)

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

