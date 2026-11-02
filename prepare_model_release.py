#!/usr/bin/env python3
"""Prepare a verified local model release folder; no network requests are made."""
import argparse
import hashlib
import json
import shutil
import tempfile
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent


def digest(path):
    value = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            value.update(chunk)
    return value.hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("model_directory", type=Path)
    parser.add_argument("destination", type=Path)
    parser.add_argument("--sdk-archive", type=Path, required=True)
    args = parser.parse_args()
    pack = args.model_directory.resolve()
    destination = args.destination.resolve()
    if destination.exists() or destination.is_relative_to(pack):
        parser.error("Choose a new destination outside the source model directory.")
    catalog_path = ROOT / "App/ModelCatalog.json"
    catalog = json.loads(catalog_path.read_text())
    for entry in catalog["files"]:
        source = (pack / entry["path"]).resolve()
        if not source.is_relative_to(pack) or not source.is_file():
            parser.error(f"Missing or invalid model file: {entry['path']}")
        if source.stat().st_size != entry["bytes"] or digest(source) != entry["sha256"]:
            parser.error(f"Model file does not match the catalog: {entry['path']}")
    with zipfile.ZipFile(args.sdk_archive) as sdk:
        names = set(sdk.namelist())
        required = {"ReuseKit/Package.swift", "ReuseKit/LICENSE", "ReuseKit/NOTICE"}
        if not required.issubset(names) or sdk.testzip() is not None:
            parser.error("Use a complete ReuseKit ZIP created by export_source.py.")
        if any(".git" in Path(name).parts or ".build" in Path(name).parts for name in names):
            parser.error("The SDK archive must contain source files only.")
    destination.parent.mkdir(parents=True, exist_ok=True)
    total = sum(entry["bytes"] for entry in catalog["files"]) + args.sdk_archive.stat().st_size
    if shutil.disk_usage(destination.parent).free < total + 32 * 1024 * 1024:
        parser.error("Insufficient free space for the release folder.")
    with tempfile.TemporaryDirectory(prefix="reuse-release-", dir=destination.parent) as temporary:
        staging = Path(temporary) / "ModelPack"
        staging.mkdir()
        for entry in catalog["files"]:
            target = staging / entry["path"]
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(pack / entry["path"], target)
            if digest(target) != entry["sha256"]:
                raise RuntimeError(f"Copied model failed verification: {entry['path']}")
        shutil.copyfile(catalog_path, staging / "ModelCatalog.json")
        shutil.copyfile(ROOT / "licenses/NVIDIA-RE-USE.txt", staging / "LICENSE")
        shutil.copyfile(ROOT / "ModelCard.md", staging / "README.md")
        shutil.copyfile(args.sdk_archive, staging / "ReuseKit.zip")
        if destination.exists():
            raise FileExistsError(destination.name)
        staging.rename(destination)
    print(json.dumps({"files": sum(p.is_file() for p in destination.rglob("*")),
                      "bytes": sum(p.stat().st_size for p in destination.rglob("*") if p.is_file()),
                      "model_files_verified": len(catalog["files"])}))
    print(destination)


if __name__ == "__main__":
    main()
