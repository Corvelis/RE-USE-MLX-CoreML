#!/usr/bin/env python3
"""Export a standalone ReuseKit source tree, optionally with a ZIP archive."""
import argparse
import shutil
from pathlib import Path

ROOT = Path(__file__).resolve().parent
FILES = (
    "Package.swift", "Package.resolved", "README.md", "LICENSE", "NOTICE", ".gitignore",
    "build_app.sh", "install_app.sh", "make_project.py", "make_model_catalog.py",
    "make_notices.py", "make_icon.swift", "test_model_assets.py", "export_source.py",
    "prepare_model_release.py", "verify_sample.py", "ModelCard.md",
)
DIRECTORIES = ("Sources", "Tests", "App", "docs", "licenses", ".github")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("destination", type=Path)
    parser.add_argument("--archive", action="store_true", help="Also create a ZIP beside the exported directory")
    args = parser.parse_args()
    destination = args.destination.resolve()
    archive = destination.parent / (destination.name + ".zip")
    if destination == ROOT or any(destination.is_relative_to(ROOT / name) for name in DIRECTORIES):
        parser.error("Choose a destination outside the source and resource directories.")
    if destination.exists() or (args.archive and archive.exists()):
        parser.error("The destination and archive must not already exist.")
    sources = [ROOT / name for name in FILES + DIRECTORIES]
    for source in sources:
        if not source.exists():
            parser.error(f"Required source is missing: {source.name}")
        if source.is_symlink() or (source.is_dir() and any(p.is_symlink() for p in source.rglob("*"))):
            parser.error(f"Source exports do not follow symbolic links: {source.name}")
    destination.mkdir(parents=True)
    ignore = shutil.ignore_patterns("__pycache__", "*.pyc", ".DS_Store", "xcuserdata")
    for source in sources:
        target = destination / source.name
        if source.is_dir():
            shutil.copytree(source, target, ignore=ignore)
        else:
            shutil.copyfile(source, target)
    if args.archive:
        shutil.make_archive(str(archive.with_suffix("")), "zip", destination.parent, destination.name)
        print(archive)
    print(destination)


if __name__ == "__main__":
    main()
