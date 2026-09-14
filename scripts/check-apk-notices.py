"""Check that an exported Android APK carries the repository's exact notices."""
from pathlib import Path
import argparse
import hashlib
import zipfile


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("apk", type=Path)
    args = parser.parse_args()
    game = Path(__file__).resolve().parents[1] / "game"
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
