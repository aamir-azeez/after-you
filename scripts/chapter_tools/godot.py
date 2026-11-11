"""Runs Godot for the chapter scripts: always headless, and every process with
its own user data folders (APPDATA, LOCALAPPDATA and XDG_DATA_HOME), because
user:// follows APPDATA on Windows and a run must never read or write a real
save. By default the game runs in a temporary copy of game/ with its service
settings blanked, imported once; the repository's own files change only when a
script copies a result back.
"""
from __future__ import annotations

import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile

FAILURE_TEXT = re.compile(r"SCRIPT ERROR|Parse Error|Compilation failed|being destroyed without its completion")
# The suites' own write switches: one left set in the shell would write into
# the folder it names, around the scripts' checks. A run passes its own.
WRITE_SWITCHES = ("AFTER_YOU_WRITE_GOLDEN", "AFTER_YOU_WRITE_FIXTURES", "AFTER_YOU_WRITE_BAKE", "AFTER_YOU_BAKE_KEY")
# The service settings CI blanks before any suite runs (verify.yml).
OFFLINE_CONFIG = {"api_base_url": "", "revenuecat_public_key": ""}
COPY_IGNORED = shutil.ignore_patterns("android", "node_modules", ".wrangler", "__pycache__")


class ToolError(Exception):
    """A refusal or failure the scripts print as one line and exit 1 on."""


def binary(explicit: str = "") -> str:
    found = explicit or os.environ.get("GODOT", "")
    if not found:
        raise ToolError("no Godot binary: pass --godot <console exe> or set GODOT")
    if not Path(found).is_file():
        raise ToolError(f"no Godot binary at {found}")
    return found


def run(godot: str, game: Path, state: Path, args: list[str], timeout: int = 900, env: dict[str, str] | None = None) -> tuple[bool, str]:
    """Runs one headless Godot process in `game` with user data under `state`.
    Returns (passed, log): passed is a zero exit with no script error in the log."""
    environment = {name: value for name, value in os.environ.items() if name not in WRITE_SWITCHES}
    for name in ("APPDATA", "LOCALAPPDATA", "XDG_DATA_HOME"):
        folder = state / name
        folder.mkdir(parents=True, exist_ok=True)
        environment[name] = str(folder)
    environment["GODOT_SILENCE_ROOT_WARNING"] = "1"
    environment.update(env or {})
    try:
        result = subprocess.run([godot, "--headless", "--path", str(game), *args], capture_output=True, text=True,
                                encoding="utf-8", errors="replace", timeout=timeout, env=environment)
    except subprocess.TimeoutExpired:
        return False, f"timed out after {timeout} s"
    log = result.stdout + result.stderr
    return result.returncode == 0 and not FAILURE_TEXT.search(log), log


def copy_game(source: Path, target: Path, keep_import: bool) -> None:
    """Copies a game folder with its service settings blanked. Its import cache
    comes along only when keep_import (a copy already imported for the suites)."""
    def ignored(folder: str, names: list[str]) -> set[str]:
        skip = set(COPY_IGNORED(folder, names))
        if Path(folder) == source:
            skip.add("app_config.json")
            if not keep_import:
                skip.add(".godot")
        return skip
    shutil.copytree(source, target, ignore=ignored)
    config = json.loads((source / "app_config.json").read_text(encoding="utf-8"))
    config.update(OFFLINE_CONFIG)
    (target / "app_config.json").write_text(json.dumps(config, indent=2) + "\n", encoding="utf-8")


class Game:
    """A game folder to run Godot in: a temporary imported copy of `source`
    (default), or `source` itself when in_place (it must be imported already,
    as test_new_chapter.py's copy is). Use as a context manager; the copy is
    removed on exit unless keep."""

    def __init__(self, godot: str, source: Path, in_place: bool = False, keep: bool = False):
        self.godot = godot
        self.source = source
        self.in_place = in_place
        self.keep = keep
        self.work = Path(tempfile.mkdtemp(prefix="after-you-chapter-"))
        self.folder = source if in_place else self.work / "game"
        self.runs = 0

    def __enter__(self) -> "Game":
        if not self.in_place:
            copy_game(self.source, self.folder, keep_import=False)
            ok, log = self.run(["--editor", "--import", "--quit"], "import", timeout=900)
            if not ok:
                raise ToolError("the game copy did not import: " + log[-1500:])
        return self

    def __exit__(self, *_: object) -> None:
        if self.keep:
            print(f"kept {self.work}")
        else:
            shutil.rmtree(self.work, ignore_errors=True)

    def run(self, args: list[str], name: str, timeout: int = 900, env: dict[str, str] | None = None) -> tuple[bool, str]:
        self.runs += 1
        return run(self.godot, self.folder, self.work / "state" / f"{self.runs:02d}-{name}", args, timeout, env)

    def script(self, path: str, user_args: list[str], name: str, env: dict[str, str] | None = None) -> tuple[bool, str]:
        """Runs a res:// SceneTree script with user arguments after "--"."""
        return self.run(["--script", path, *(["--", *user_args] if user_args else [])], name, env=env)

    def scratch(self, name: str) -> Path:
        """A fresh folder for a run's output, outside the game folder."""
        folder = self.work / "out" / name
        folder.mkdir(parents=True, exist_ok=True)
        return folder
