"""Check that an exported Android APK carries the repository's exact notices."""
from pathlib import Path
import argparse
import hashlib
import zipfile


def native_inventory_errors(repo: Path) -> list[str]:
    """Keep the public inventory in sync with the native runtime, including transitives."""
    index_path = repo / "game/assets/licenses/native-components.txt"
    lock_path = repo / "native/plugin/gradle.lockfile"
    if not index_path.is_file() or not lock_path.is_file():
        return ["Native dependency lock or public component inventory is missing."]
    index_lines = index_path.read_text(encoding="utf-8").splitlines()
    errors = []
    count = 0
    for line in lock_path.read_text(encoding="utf-8").splitlines():
        if not line or line.startswith("#") or "=" not in line:
            continue
        coordinate, configurations = line.split("=", 1)
        if not {"debugRuntimeClasspath", "releaseRuntimeClasspath"}.intersection(configurations.split(",")):
            continue
        count += 1
        if coordinate not in index_lines:
            errors.append("Native runtime notice inventory missing: " + coordinate)
            continue
        position = index_lines.index(coordinate)
        if position + 1 >= len(index_lines) or not index_lines[position + 1].strip():
            errors.append("Native runtime license declaration missing: " + coordinate)
    if count == 0:
        errors.append("No pinned native runtime dependencies found.")
    notices = (repo / "game/assets/licenses/native-notices.txt").read_text(encoding="utf-8")
    if "androidx.datastore:datastore-preferences-external-protobuf:" in index_path.read_text(encoding="utf-8"):
        start = notices.find("Copyright 2008 Google Inc.  All rights reserved.")
        closing = "support library is itself covered by the above license."
        end = notices.find(closing, start)
        text = notices[start:end + len(closing)] + "\n" if start >= 0 and end >= start else ""
        # Exact upstream v28.2 LICENSE, also used by the AndroidX 1.1.7 repackaging.
        if hashlib.sha256(text.encode()).hexdigest() != "6e5e117324afd944dcf67f36cf329843bc1a92229a8cd9bb573d7a83130fea7d":
            errors.append("The repackaged protobuf-lite copyright and complete license are missing.")
    return errors


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("apk", type=Path)
    args = parser.parse_args()
    game = Path(__file__).resolve().parents[1] / "game"
    inventory_errors = native_inventory_errors(game.parent)
    if inventory_errors:
        raise SystemExit("\n".join(inventory_errors))
    notices = sorted((game / "assets" / "licenses").glob("*.txt"))
    fonts = sorted((game / "assets" / "fonts").glob("*-OFL.txt"))
    if not notices or len(fonts) != 2:
        raise SystemExit("Repository notice files are missing or incomplete.")
    failures = []
    with zipfile.ZipFile(args.apk) as apk:
        for source in notices + fonts:
            entry = "assets/" + source.relative_to(game).as_posix()
            try:
                packaged = apk.read(entry)
            except KeyError:
                failures.append("Missing: " + entry)
                continue
            if hashlib.sha256(packaged).digest() != hashlib.sha256(source.read_bytes()).digest():
                failures.append("Notice bytes differ: " + entry)
    if failures:
        raise SystemExit("\n".join(failures))
    print(f"PASS: {len(notices) + len(fonts)} complete license notices match the APK")


if __name__ == "__main__":
    main()
