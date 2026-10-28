"""Scaffolds a new chapter: its own files from a family template
(scripts/chapter_templates/<family>/) and one line or one block in each shared
file that lists chapters. The chapter starts unreleased ("released": false),
with "TODO copy" placeholder text and a placeholder thumbnail, which
test_chapter_descriptors refuses for a released chapter.

    python scripts/new_chapter.py --key the-quiet-mill@1 --family cooperative \
        --title "The Quiet Mill" --shard 2 [--stages first-id,second-id] [--premium]
    python scripts/new_chapter.py --version-of conservatory@1 --shard 2

--version-of makes the next version of a registered chapter. Its catalog reads
the earlier definition and gives it the new version on rules 9; the world, the
thumbnail, the copy, the Home places and the Home keepsake stay the earlier
version's, and the earlier version's descriptor is left as it is. A chapter
has exactly one Home keepsake, on the version nothing supersedes: releasing
the new version (superseded_by on the earlier one) moves the earlier
descriptor's "home_keepsake" to it, and test_chapter_descriptors says so.

A new chapter gets its Home keepsake: the descriptor's "home_keepsake" field,
a placeholder builder in game/presentation/keepsakes/ (from
chapter_templates/keepsake.gd.tmpl) and "TODO copy" names for it. Its slot is
the middle of its island, where another keepsake stands: an unreleased chapter
is not on Home, and test_home_keepsake_layer fails a released one until its
slot is moved clear.

Nothing is written when any file to create already exists, any shared entry is
already there, a stage id is already used in game/core, or a fixture the
chapter's suite writes already exists. On success it prints each file created
and each line added.
"""
from __future__ import annotations

import argparse
import json
from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parent.parent
TEMPLATES = Path(__file__).resolve().parent / "chapter_templates"
KEY_PATTERN = re.compile(r"^([a-z][a-z0-9]*(?:-[a-z0-9]+)*)@([1-9][0-9]*)$")
STAGE_PATTERN = re.compile(r"^[a-z][a-z0-9]*(?:-[a-z0-9]+)*$")
TITLE_PATTERN = re.compile(r"^[A-Za-z0-9][A-Za-z0-9 ,'.!?-]*$")


class Refused(Exception):
    pass


def pascal(level_id: str) -> str:
    return "".join(part.capitalize() for part in level_id.split("-"))


def camel(level_id: str) -> str:
    name = pascal(level_id)
    return name[0].lower() + name[1:]


class Text:
    """An existing text file, edited in memory and written back with its own line endings."""

    def __init__(self, root: Path, relative: str):
        self.relative = relative
        self.path = root / relative
        if not self.path.is_file():
            raise Refused(f"{relative} is missing")
        raw = self.path.read_bytes().decode("utf-8")
        self.newline = "\r\n" if "\r\n" in raw else "\n"
        self.trailing = raw.endswith(("\n", "\r\n"))
        self.lines = raw.replace("\r\n", "\n").split("\n")
        if self.trailing:
            self.lines.pop()

    def find(self, pattern: str, start: int = 0) -> int:
        regex = re.compile(pattern)
        for index in range(start, len(self.lines)):
            if regex.search(self.lines[index]):
                return index
        return -1

    def find_last(self, pattern: str) -> int:
        regex = re.compile(pattern)
        for index in range(len(self.lines) - 1, -1, -1):
            if regex.search(self.lines[index]):
                return index
        return -1

    def contains(self, needle: str) -> bool:
        return any(needle in line for line in self.lines)

    def write(self) -> None:
        body = self.newline.join(self.lines) + (self.newline if self.trailing else "")
        self.path.write_bytes(body.encode("utf-8"))


class Plan:
    """Everything one run creates and adds, checked in full before anything is written."""

    def __init__(self, root: Path):
        self.root = root
        self.created: list[tuple[str, bytes]] = []
        self.edited: dict[str, Text] = {}
        self.added: list[tuple[str, str]] = []
        self.newline = self.text("game/content/chapters/index.gd").newline

    def text(self, relative: str) -> Text:
        if relative not in self.edited:
            self.edited[relative] = Text(self.root, relative)
        return self.edited[relative]

    def create(self, relative: str, content: str | bytes) -> None:
        if (self.root / relative).exists():
            raise Refused(f"{relative} already exists")
        if any(path == relative for path, _ in self.created):
            raise Refused(f"{relative} would be written twice")
        data = content if isinstance(content, bytes) else content.replace("\n", self.newline).encode("utf-8")
        self.created.append((relative, data))

    def insert(self, relative: str, index: int, lines: list[str]) -> None:
        text = self.text(relative)
        text.lines[index:index] = lines
        for line in lines:
            if line.strip():
                self.added.append((relative, line.strip()))

    def write(self) -> None:
        for relative, data in self.created:
            path = self.root / relative
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(data)
        for text in self.edited.values():
            text.write()

    def report(self) -> None:
        for relative, _ in self.created:
            print(f"created {relative}")
        for relative, line in self.added:
            print(f"added {relative}: {line}")


def fill(template: str, values: dict[str, str]) -> str:
    for name, value in values.items():
        template = template.replace("{{" + name + "}}", value)
    left = re.findall(r"\{\{[A-Z0-9_]+\}\}", template)
    if left:
        raise Refused(f"template value missing: {left[0]}")
    return template


def template(name: str, values: dict[str, str]) -> str:
    return fill((TEMPLATES / name).read_text(encoding="utf-8"), values)


def descriptor_files(root: Path) -> dict[str, Path]:
    """Every descriptor under game/content/chapters by its key."""
    result: dict[str, Path] = {}
    for path in sorted((root / "game/content/chapters").glob("*.gd")):
        found = re.search(r'^\t"key": "([^"]+)",$', path.read_text(encoding="utf-8").replace("\r\n", "\n"), re.M)
        if found:
            result[found.group(1)] = path
    return result


def descriptor_field(path: Path, field: str) -> str:
    found = re.search(r'^\t"' + field + r'": (.+),$', path.read_text(encoding="utf-8").replace("\r\n", "\n"), re.M)
    return found.group(1) if found else ""


def family_config(family: str) -> dict:
    path = TEMPLATES / family / "family.json"
    if not path.is_file():
        known = sorted(p.name for p in TEMPLATES.iterdir() if (p / "family.json").is_file())
        raise Refused(f"no chapter template for family {family} (templates: {', '.join(known)})")
    return json.loads(path.read_text(encoding="utf-8"))


def check_stage_free(root: Path, stage: str, folder: Path) -> None:
    """A first version's stage fixtures are named by stage id alone in the family
    folder, so a stage id another definition or fixture already uses is refused."""
    for path in sorted((root / "game/core").rglob("*.gd")):
        if f'"{stage}"' in path.read_text(encoding="utf-8"):
            raise Refused(f"the stage id {stage} is already a name in {path.relative_to(root).as_posix()}")
    for suffix in ("-a.json", "-b.json", "-checkpoint.json"):
        if (folder / (stage + suffix)).exists():
            raise Refused(f"{(folder / (stage + suffix)).relative_to(root).as_posix()} already exists")


def check_free(plan: Plan, relative: str, needle: str, what: str) -> None:
    if plan.text(relative).contains(needle):
        raise Refused(f"{relative} already has {what}")


def add_to_index(plan: Plan, slug: str) -> None:
    index = plan.text("game/content/chapters/index.gd")
    line = f'\tpreload("res://content/chapters/{slug}.gd"),'
    check_free(plan, index.relative, f"/{slug}.gd\"", f"the descriptor {slug}.gd")
    start = index.find(r"^const CHAPTERS := \[$")
    end = index.find(r"^\]$", start) if start >= 0 else -1
    if end < 0:
        raise Refused(f"{index.relative} has no CHAPTERS list")
    plan.insert(index.relative, end, [line])


def add_to_family_catalog(plan: Plan, family: str, key: str, level_id: str, version: int, const: str, catalog_res: str) -> None:
    relative = f"game/core/{family}/stage_catalog.gd"
    catalog = plan.text(relative)
    check_free(plan, relative, f"const {const} ", f"a constant {const}")
    check_free(plan, relative, f'"{key}"', f"the key {key}")
    keys = catalog.find(r"^const KEYS := \[.*\]$")
    last_preload = catalog.find_last(r"^const \w+ = preload\(")
    start = catalog.find(r"^static func definition\(")
    end = catalog.find(r"^\treturn \{\}$", start) if start >= 0 else -1
    if keys < 0 or last_preload < 0 or end < 0:
        raise Refused(f"{relative} has no KEYS line, preload constants or definition() to extend")
    plan.insert(relative, last_preload + 1, [f'const {const} = preload("{catalog_res}")'])
    keys, end = keys + (keys > last_preload), end + 1
    separator = "," if '","' in catalog.lines[keys] else ", "
    catalog.lines[keys] = catalog.lines[keys][:-1] + (separator if catalog.lines[keys].endswith('"]') else "") + f'"{key}"]'
    plan.added.append((relative, f'"{key}" in KEYS'))
    if version == 1 and catalog.lines[end - 1].startswith("\t\t"):
        arm = f'\t\t"{level_id}", "{key}": return {const}.definition()'
    elif version == 1:
        arm = f'\tif key in ["{level_id}", "{key}"]: return {const}.definition()'
    else:
        arm = f'\tif key == "{key}": return {const}.definition()'
    plan.insert(relative, end, [arm])


def add_to_shards(plan: Plan, suites: list[str], shard: str) -> None:
    shards = plan.text("game/tests/ci_shards.txt")
    for suite in suites:
        if shards.find(r"^" + re.escape(suite) + r" ") >= 0:
            raise Refused(f"{shards.relative} already lists {suite}")
        position = len(shards.lines)
        for index, line in enumerate(shards.lines):
            if line and not line.startswith("#") and line.split(" ")[0] > suite:
                position = index
                break
        while position > 0 and shards.lines[position - 1] == "":
            position -= 1
        plan.insert(shards.relative, position, [f"{suite} {shard}"])


def add_flag(plan: Plan, flag: str, accessor: str) -> None:
    wrangler = plan.text("backend/wrangler.jsonc")
    check_free(plan, wrangler.relative, f'"{flag}"', f"the var {flag}")
    last = wrangler.find_last(r'^\s*"[A-Z0-9_]+_CHAPTERS?_ENABLED": "false",$')
    if last < 0:
        raise Refused(f"{wrangler.relative} has no chapter flag lines")
    indent = re.match(r"^\s*", wrangler.lines[last]).group(0)
    plan.insert(wrangler.relative, last + 1, [f'{indent}"{flag}": "false",'])
    flags = plan.text("backend/src/flags.ts")
    check_free(plan, flags.relative, f'"{flag}"', f"the var {flag}")
    check_free(plan, flags.relative, f" {accessor}:", f"an accessor {accessor}")
    last = flags.find_last(r'^\s+\w+Chapters?: "[A-Z0-9_]+_ENABLED",$')
    if last < 0:
        raise Refused(f"{flags.relative} has no chapter flag rows")
    indent = re.match(r"^\s*", flags.lines[last]).group(0)
    plan.insert(flags.relative, last + 1, [f'{indent}{accessor}: "{flag}",'])


def add_copy(plan: Plan, const: str, title: str, key: str, stage_copy: bool) -> None:
    relative = "game/presentation/player_copy.gd"
    check_free(plan, relative, f"const {const}_", f"constants named {const}_*")
    block = ["", f"# {title} ({key}): placeholder copy from scripts/new_chapter.py.",
             f'const {const}_TITLE := "{title}"',
             f'const {const}_SUMMARY := "TODO copy: {title} summary"',
             f'const {const}_COMPLETION := "TODO copy: {title} completion"']
    for stage in (1, 2):
        block.append(f'const {const}_STAGE_{stage}_TITLE := "TODO copy: {title}, stage {stage}"')
        if stage_copy:
            block.append(f'const {const}_STAGE_{stage}_HINT_A := "TODO copy: {title}, stage {stage}, first turn"')
            block.append(f'const {const}_STAGE_{stage}_HINT_B := "TODO copy: {title}, stage {stage}, second turn"')
    for name in KEEPSAKE_COPY:
        block.append(f'const {const}_KEEPSAKE_{name} := "TODO copy: {title} keepsake {name.lower()}"')
    copy = plan.text(relative)
    plan.insert(relative, len(copy.lines), block)


def descriptor(values: dict[str, str], stage_copy: bool) -> str:
    v = values
    lines = ["extends RefCounted",
             f"## Descriptor for {v['KEY']}. Fields: content/chapters/index.gd.",
             'const PlayerCopy = preload("res://presentation/player_copy.gd")',
             "const DATA := {",
             f'\t"key": "{v["KEY"]}",',
             f'\t"family": "{v["FAMILY"]}",',
             f'\t"definition": ["{v["CATALOG_RES"]}", "definition"],',
             f'\t"world": "{v["WORLD_RES"]}",',
             f'\t"scene": "{v["SCENE_RES"]}",',
             f'\t"local_path": "{v["LOCAL_PATH"]}",',
             '\t"released": false,',
             '\t"copy": {',
             f'\t\t"title": PlayerCopy.{v["CONST"]}_TITLE,',
             f'\t\t"summary": PlayerCopy.{v["CONST"]}_SUMMARY,',
             f'\t\t"completion": PlayerCopy.{v["CONST"]}_COMPLETION,',
             "\t},"]
    stages = [v["STAGE_1"], v["STAGE_2"]]
    if stage_copy:
        lines.append('\t"stage_copy": {')
        for number, stage in enumerate(stages, 1):
            lines += [f'\t\t"{stage}": {{',
                      f'\t\t\t"title": PlayerCopy.{v["CONST"]}_STAGE_{number}_TITLE,',
                      f'\t\t\t"hint_a": PlayerCopy.{v["CONST"]}_STAGE_{number}_HINT_A,',
                      f'\t\t\t"hint_b": PlayerCopy.{v["CONST"]}_STAGE_{number}_HINT_B,',
                      "\t\t},"]
        lines.append("\t},")
    lines.append(f'\t"thumbnail": "{v["THUMBNAIL_RES"]}",')
    lines.append('\t"keepsakes": [')
    for number, stage in enumerate(stages, 1):
        lines.append(f'\t\t{{"stage_id": "{stage}", "title": PlayerCopy.{v["CONST"]}_STAGE_{number}_TITLE}},')
    lines.append("\t],")
    lines += home_keepsake(v)
    lines += [f'\t"server": {{"flag": "{v["FLAG"]}", "max_branches": 32}},', "}", ""]
    return "\n".join(lines)


# The cues a placeholder keepsake plays, one per beat (services/sound_cues.gd CUES).
KEEPSAKE_SOUNDS = {"base": "garden_opened", "together": "lift_ready", "hard": "bell_rung", "top": "island_bloomed"}
KEEPSAKE_COPY = ("NAME", "ACTION", "TOGETHER", "HARD", "TOP")


def home_keepsake(v: dict[str, str]) -> list[str]:
    """The descriptor's home_keepsake field (content/chapters/index.gd): the
    placeholder builder, the middle of the chapter's island, its copy and sounds."""
    sounds = ", ".join(f'"{beat}": "{cue}"' for beat, cue in KEEPSAKE_SOUNDS.items())
    lines = ["\t# The chapter's keepsake on Home (presentation/keepsakes/).", '\t"home_keepsake": {',
             f'\t\t"builder": "{v["KEEPSAKE_RES"]}",',
             f'\t\t"island": "{"left" if v["PREMIUM"] == "true" else "right"}",',
             '\t\t"slot": [0.0, 0.0],',
             '\t\t"copy": {']
    lines += [f'\t\t\t"{name.lower()}": PlayerCopy.{v["CONST"]}_KEEPSAKE_{name},' for name in KEEPSAKE_COPY]
    lines += ["\t\t},", f'\t\t"sounds": {{{sounds}}},', "\t},"]
    return lines


def version_descriptor(earlier: Path, values: dict[str, str]) -> str:
    """The earlier descriptor's fields with this version's key, definition, scene,
    save and flag, version_of set, unreleased and without Home places of its own."""
    text = earlier.read_text(encoding="utf-8").replace("\r\n", "\n")
    head, _, rest = text.partition("const DATA := {\n")
    body, _, _ = rest.rpartition("}")
    entries: list[tuple[str, list[str]]] = []
    pending: list[str] = []
    for line in body.rstrip("\n").split("\n"):
        field = re.match(r'^\t"(\w+)": ', line)
        if line.startswith("\t#"):
            pending.append(line)
        elif field:
            entries.append((field.group(1), pending + [line]))
            pending = []
        elif entries:
            entries[-1][1].append(line)
    replaced = {
        "key": f'\t"key": "{values["KEY"]}",',
        "definition": f'\t"definition": ["{values["CATALOG_RES"]}", "definition"],',
        "scene": f'\t"scene": "{values["SCENE_RES"]}",',
        "local_path": f'\t"local_path": "{values["LOCAL_PATH"]}",',
    }
    out = ["extends RefCounted", f"## Descriptor for {values['KEY']}. Fields: content/chapters/index.gd."]
    out += [line for line in head.split("\n")[2:] if line]
    out.append("const DATA := {")
    for name, lines in entries:
        if name in ("keepsakes", "home_keepsake", "superseded_by", "version_of", "released"):
            continue
        if name in replaced:
            lines = [replaced[name]]
        if name == "server":
            lines = [re.sub(r'"flag": "[^"]*"', f'"flag": "{values["FLAG"]}"', line) for line in lines]
        out += lines
        if name == "local_path":
            out += [f'\t"version_of": "{values["PLACES_OF"]}",', '\t"released": false,']
    out += ["}", ""]
    return "\n".join(out)


def scaffold(args: argparse.Namespace, root: Path) -> Plan:
    plan = Plan(root)
    registered = descriptor_files(root)
    if args.version_of:
        earlier = args.version_of
        if earlier not in registered:
            raise Refused(f"{earlier} is not a registered chapter")
        level_id, earlier_version = KEY_PATTERN.match(earlier).groups()
        latest = max(int(k.split("@")[1]) for k in registered if k.split("@")[0] == level_id)
        if latest != int(earlier_version):
            raise Refused(f"{level_id}@{latest} is the latest version of {level_id}")
        version = latest + 1
        family = descriptor_field(registered[earlier], "family").strip('"')
        title = ""
    else:
        found = KEY_PATTERN.match(args.key or "")
        if not found or found.group(2) != "1":
            raise Refused("--key is <level id>@1, such as the-quiet-mill@1; later versions come from --version-of")
        level_id, version, family, title = found.group(1), 1, args.family, args.title or ""
        if not TITLE_PATTERN.match(title):
            raise Refused("--title is the chapter's name: letters, digits, spaces and , ' . ! ? -")
    key = f"{level_id}@{version}"
    if key in registered:
        raise Refused(f"{key} is already registered ({registered[key].relative_to(root).as_posix()})")
    config = family_config(family)
    if args.version_of and "version_witness" not in config:
        raise Refused(f"--version-of is not available for the {family} family: {config.get('no_versions', 'no version witness')}")
    stem = level_id.replace("-", "_") + ("" if version == 1 else f"_v{version}")
    const = stem.upper()
    class_name = pascal(level_id) + ("" if version == 1 else f"V{version}")
    local_path = f"user://{level_id}-journey-v{version}.json"
    for path in registered.values():
        if descriptor_field(path, "local_path") == f'"{local_path}"':
            raise Refused(f"{path.relative_to(root).as_posix()} already saves to {local_path}")
    values = {
        "KEY": key, "ID": level_id, "VERSION": str(version), "TITLE": title, "FAMILY": family,
        "CONST": const, "NODE": class_name, "FLAG": f"{const}_CHAPTER_ENABLED",
        "PREMIUM": "true" if args.premium else "false",
        "CATALOG_RES": f"res://core/{family}/{stem}_catalog.gd", "SCENE_RES": f"res://{stem}.tscn",
        "WORLD_RES": f"res://presentation/{stem}_world.gd", "THUMBNAIL_RES": f"res://assets/chapter_thumbnails/{level_id}.png",
        "LOCAL_PATH": local_path, "WITNESS_FILE": f"{stem}_witness.gd", "WORLD_BASE": config["world_base"],
        "KEEPSAKE_RES": f"res://presentation/keepsakes/{stem}.gd",
    }
    families = (root / "game/services/chapter_families.gd").read_text(encoding="utf-8")
    row = re.search(r'^\t"' + re.escape(family) + r'": \{(.*?)\n(?=\t[^\t]|\})', families, re.M | re.S)
    fixture_dir = re.search(r'"fixture_dir": "([^"]+)"', row.group(1)) if row else None
    stage_hud = re.search(r'"stage_hud": "([^"]+)"', row.group(1)) if row else None
    if not fixture_dir or not stage_hud:
        raise Refused(f"game/services/chapter_families.gd has no {family} row with fixture_dir and stage_hud")
    # The fixtures the chapter's suite writes (golden_support.gd fixture_prefixes)
    # never replace another chapter's.
    folder = root / "game/tests/fixtures" / fixture_dir.group(1)
    if version == 1:
        taken = [f"{level_id}-{name}.json" for name in ("definition", "initial-checkpoint", "final-checkpoint") if (folder / f"{level_id}-{name}.json").exists()]
    else:
        taken = sorted(path.name for path in folder.glob(f"{level_id}-v{version}-*.json"))
    if taken:
        raise Refused(f"game/tests/fixtures/{fixture_dir.group(1)}/ already has {taken[0]}")
    # A family whose HUD reads the descriptor's stage_copy gets a title and two hints per stage.
    stage_copy = stage_hud.group(1) == "stage_copy"
    suites = [stem, f"{stem}_world"]

    if args.version_of:
        earlier_path = registered[args.version_of]
        spec = json.loads(descriptor_field(earlier_path, "definition"))
        call = f"{spec[1]}({', '.join(json.dumps(arg) for arg in spec[2:])})"
        # version_of names the version whose Home places this one earns: the first one.
        places = descriptor_field(earlier_path, "version_of").strip('"') or args.version_of
        values.update({"EARLIER": args.version_of, "PLACES_OF": places, "EARLIER_SCRIPT": spec[0], "EARLIER_CALL": call,
                       "FAMILY_WITNESS": config["version_witness"]})
        plan.create(f"game/content/chapters/{stem}.gd", version_descriptor(earlier_path, values))
        plan.create(f"game/core/{family}/{stem}_catalog.gd", template("version_catalog.gd.tmpl", values))
        plan.create(f"game/tests/{stem}_witness.gd", template("version_witness.gd.tmpl", values))
    else:
        stages = (args.stages or f"{level_id}-first,{level_id}-second").split(",")
        if len(stages) != 2 or len(set(stages)) != 2 or not all(STAGE_PATTERN.match(s) for s in stages):
            raise Refused("--stages is two different stage ids, such as the-quiet-mill-first,the-quiet-mill-second")
        for stage in stages:
            check_stage_free(root, stage, folder)
        values.update({"STAGE_1": stages[0], "STAGE_2": stages[1]})
        values["ROUTES"] = (TEMPLATES / family / "routes.gd.tmpl").read_text(encoding="utf-8").strip()
        plan.create(f"game/content/chapters/{stem}.gd", descriptor(values, stage_copy))
        plan.create(f"game/core/{family}/{stem}_catalog.gd", template(f"{family}/catalog.gd.tmpl", values))
        plan.create(f"game/presentation/{stem}_world.gd", template("world.gd.tmpl", values))
        plan.create(f"game/assets/chapter_thumbnails/{level_id}.png", (TEMPLATES / "placeholder-thumbnail.png").read_bytes())
        plan.create(f"game/tests/{stem}_witness.gd", template("witness.gd.tmpl", values))
        plan.create(f"game/presentation/keepsakes/{stem}.gd", template("keepsake.gd.tmpl", values))
    plan.create(f"game/{stem}.tscn", template("scene.tscn.tmpl", values))
    plan.create(f"game/tests/test_{stem}.gd", template("test_chapter.gd.tmpl", values))
    plan.create(f"game/tests/test_{stem}_world.gd", template("test_chapter_world.gd.tmpl", values))

    add_to_index(plan, stem)
    add_to_family_catalog(plan, family, key, level_id, version, f"{class_name}Catalog", values["CATALOG_RES"])
    if not args.version_of:
        add_copy(plan, const, title, key, stage_copy)
    add_to_shards(plan, suites, args.shard)
    add_flag(plan, values["FLAG"], camel(level_id) + ("" if version == 1 else f"V{version}") + "Chapter")
    return plan


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description="Scaffold a new, unreleased chapter.")
    parser.add_argument("--key", help="<level id>@1 of a new chapter")
    parser.add_argument("--family", help="a family with a template in scripts/chapter_templates/")
    parser.add_argument("--title", help="the chapter's name")
    parser.add_argument("--stages", help="two stage ids, comma separated (default <level id>-first,<level id>-second)")
    parser.add_argument("--premium", action="store_true", help="the chapter needs Full Journey")
    parser.add_argument("--version-of", help="a registered chapter key; makes its next version")
    parser.add_argument("--shard", required=True, choices=["1", "2", "3"], help="the CI shard for the new suites")
    parser.add_argument("--root", default=str(ROOT), help="the repository to write into (default: this one)")
    args = parser.parse_args(argv)
    if args.version_of and (args.key or args.family or args.title or args.stages or args.premium):
        parser.error("--version-of takes the key, family, title, stages and premium of the earlier version")
    if not args.version_of and not (args.key and args.family and args.title):
        parser.error("a new chapter needs --key, --family and --title")
    try:
        plan = scaffold(args, Path(args.root).resolve())
    except Refused as refusal:
        print(f"new_chapter.py: nothing written: {refusal}", file=sys.stderr)
        return 1
    plan.write()
    plan.report()
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
