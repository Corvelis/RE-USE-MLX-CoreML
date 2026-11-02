#!/usr/bin/env python3
"""Assemble the app's complete notices from the distributed license texts."""
import argparse
from pathlib import Path

ROOT = Path(__file__).resolve().parent


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true", help="Verify the bundled notices without changing files")
    args = parser.parse_args()
    inputs = [ROOT / "LICENSE", ROOT / "NOTICE", *sorted((ROOT / "licenses").glob("*.txt"))]
    parts = ["RE-USE Lab — Third-Party Notices\n"]
    for path in inputs:
        body = path.read_text()
        if not body.strip():
            raise SystemExit(f"Empty license text: {path.name}")
        parts.append("\n" + "=" * 72 + "\n" + path.name + "\n" + "=" * 72 + "\n\n" + body.rstrip() + "\n")
    value = "".join(parts)
    destination = ROOT / "App/Notices.txt"
    if args.check:
        if not destination.exists() or destination.read_text() != value:
            raise SystemExit("App notices are out of date. Run python3 make_notices.py.")
        print(f"Notices verified: {len(inputs)} license/notice files")
    else:
        destination.write_text(value)
        print(f"Notices generated: {len(inputs)} license/notice files")


if __name__ == "__main__":
    main()
