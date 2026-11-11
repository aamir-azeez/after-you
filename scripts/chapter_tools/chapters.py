"""Facts about one chapter that the chapter scripts share: its descriptor,
whether it is released, its catalog, witness and routes, the suite that writes
its fixtures, and its backend copies. Read from the repository's files (the
descriptor parsing is new_chapter.py's own), never from a running game.
"""
from __future__ import annotations

import json
from pathlib import Path
import re

from chapter_tools.godot import ToolError
import new_chapter

## The suite that writes a chapter's fixtures, where it is not the scaffold's
## tests/test_<slug>.gd with "--write-fixtures" (chapter_suite.gd), and how it
## is asked to write: "argument" (-- --write-fixtures) or "env"
## (AFTER_YOU_WRITE_FIXTURES=1). Published chapters older than the scaffold.
FIXTURE_WRITERS = {
    "turn-of-the-tide@1": ("turn_of_the_tide", "env"),
    "the-wishing-well@1": ("wishing_well", "argument"),
    "a-house-for-two@1": ("house", "argument"),
}
## Backend copies named otherwise than backend/src/v2/<level id>[-v<N>].json and -initial.json.
BACKEND_FILES = {
    "relay-isles@2": ("relay-isles.json", "initial-checkpoint.json"),
}
MANIFEST = "game/tests/fixtures/golden/chapter_manifest.json"
## Families whose recordings game/tests/chapter_witness.gd replays: both run on
## core/physical/runtime.gd (input runs expand as /100, a turn has duration_limit()).
REPLAYABLE_FAMILIES = ("cooperative", "journey")


class Chapter:
    def __init__(self, root: Path, key: str):
        found = new_chapter.KEY_PATTERN.match(key)
        if not found:
            raise ToolError(f"{key} is not a chapter key such as the-quiet-mill@1")
        descriptors = new_chapter.descriptor_files(root)
        if key not in descriptors:
            raise ToolError(f"{key} is not a registered chapter (no descriptor in game/content/chapters/)")
        self.root = root
        self.key = key
        self.level_id, self.version = found.group(1), int(found.group(2))
        self.descriptor = descriptors[key]
        self.slug = self.descriptor.stem
        self.released = new_chapter.descriptor_field(self.descriptor, "released") != "false"
        self.family = new_chapter.descriptor_field(self.descriptor, "family").strip('"')
        spec = json.loads(new_chapter.descriptor_field(self.descriptor, "definition") or "[]")
        self.catalog = root / "game" / spec[0].removeprefix("res://") if spec else None
        self.witness = root / f"game/tests/{self.slug}_witness.gd"
        self.routes = root / f"game/tests/routes/{key}.json"

    def refuse_released(self, what: str) -> None:
        if self.released:
            raise ToolError(f"{self.key} is released: a published chapter's definition, fixtures and routes never change ({what} refused)")

    def refuse_unreplayable(self) -> None:
        if self.family not in REPLAYABLE_FAMILIES:
            raise ToolError(f"{self.key}: {self.family} chapters have no recorded routes; only {' and '.join(REPLAYABLE_FAMILIES)} chapters do")

    def writer(self) -> tuple[str, list[str], dict[str, str]]:
        """(res:// suite, user arguments, environment) that write this chapter's fixtures."""
        suite, mode = FIXTURE_WRITERS.get(self.key, (self.slug, "argument"))
        if not (self.root / f"game/tests/test_{suite}.gd").is_file():
            raise ToolError(f"{self.key}: no suite writes its fixtures (game/tests/test_{suite}.gd is missing); name it in FIXTURE_WRITERS in scripts/chapter_tools/chapters.py")
        if mode == "env":
            return f"res://tests/test_{suite}.gd", [], {"AFTER_YOU_WRITE_FIXTURES": "1"}
        return f"res://tests/test_{suite}.gd", ["--write-fixtures"], {}

    def backend_files(self) -> tuple[str, str]:
        stem = self.level_id + ("" if self.version == 1 else f"-v{self.version}")
        return BACKEND_FILES.get(self.key, (f"{stem}.json", f"{stem}-initial.json"))

    def routes_from_recordings(self) -> bool:
        """True when the witness plays tests/routes/<key>.json (chapter_witness.gd's chapter())."""
        if not self.witness.is_file():
            return False
        text = self.witness.read_text(encoding="utf-8")
        return 'extends "res://tests/chapter_witness.gd"' in text and ("func chapter(" not in text or "super()" in text)


def manifest(root: Path) -> dict:
    return json.loads((root / MANIFEST).read_text(encoding="utf-8"))


def same_text(first: bytes, second: bytes) -> bool:
    """Equal once line ends are LF: a Windows checkout may hold either."""
    return first.replace(b"\r\n", b"\n") == second.replace(b"\r\n", b"\n")


def write_like(path: Path, data: bytes) -> bool:
    """Writes `data` (LF) to `path` in the line ends the file already has;
    returns False and leaves the file alone when its text is already `data`."""
    if path.is_file():
        old = path.read_bytes()
        if same_text(old, data):
            return False
        if b"\r\n" in old:
            data = data.replace(b"\r\n", b"\n").replace(b"\n", b"\r\n")
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(data)
    return True


def routes_text(routes: dict, stage_order: list[str]) -> str:
    """A routes file: stages in the chapter's order, one step a line, whole numbers as integers."""
    def plain(value):
        if isinstance(value, float) and value.is_integer():
            return int(value)
        if isinstance(value, list):
            return [plain(item) for item in value]
        if isinstance(value, dict):
            return {key: plain(item) for key, item in value.items()}
        return value
    blocks = []
    for stage in [s for s in stage_order if s in routes] + sorted(s for s in routes if s not in stage_order):
        entry = plain(routes[stage])
        fields = []
        for name in ("a", "b"):
            steps = ",\n".join("\t\t\t" + json.dumps(step) for step in entry.get(name, []))
            fields.append(f'\t\t"{name}": [\n{steps}\n\t\t]')
        fields += [f"\t\t{json.dumps(name)}: {json.dumps(value)}" for name, value in entry.items() if name not in ("a", "b")]
        blocks.append(f"\t{json.dumps(stage)}: {{\n" + ",\n".join(fields) + "\n\t}")
    return "{\n" + ",\n".join(blocks) + "\n}\n"


def stage_ids(root: Path, key: str) -> list[str]:
    """The chapter's stage ids in order, from its manifest row's definition fixture."""
    row = manifest(root)["chapters"].get(key)
    if not row:
        return []
    definition = json.loads((root / "game/tests/fixtures" / row["definition_fixture"]).read_text(encoding="utf-8"))
    return [stage["id"] for stage in definition.get("stages", [])]


def hash_constant(root: Path, old_hash: str) -> tuple[Path, str] | None:
    """The backend constant holding `old_hash` (export const X = "<hash>"), or None."""
    found = []
    for path in sorted((root / "backend/src/v2").glob("*.ts")):
        for match in re.finditer(r'^export const (\w+) = "' + re.escape(old_hash) + r'";', path.read_text(encoding="utf-8"), re.M):
            found.append((path, match.group(1)))
    if len(found) > 1:
        raise ToolError(f"the definition hash {old_hash} is held by {len(found)} backend constants; there must be one")
    return found[0] if found else None


TURN_LIMITS = re.compile(r'\{"a_ticks":\s*(\d+),\s*"b_ticks":\s*(\d+)\}')


def turn_limits_edit(chapter: Chapter, a: int, b: int) -> tuple[str, bytes]:
    """(catalog path, its text with turn_limits {a, b}): the catalog holds exactly
    one {"a_ticks": N, "b_ticks": M} literal, as the scaffold writes it."""
    if chapter.catalog is None or not chapter.catalog.is_file():
        raise ToolError(f"{chapter.key}: its catalog is missing ({chapter.catalog})")
    text = chapter.catalog.read_text(encoding="utf-8")
    found = TURN_LIMITS.findall(text)
    if len(found) != 1:
        raise ToolError(f'{chapter.key}: {chapter.catalog.relative_to(chapter.root).as_posix()} must hold exactly one {{"a_ticks": N, "b_ticks": M}} '
                        f"(it holds {len(found)}); the scaffold writes it into a new chapter's definition")
    return chapter.catalog.relative_to(chapter.root).as_posix(), TURN_LIMITS.sub(f'{{"a_ticks":{a},"b_ticks":{b}}}', text).encode("utf-8")
