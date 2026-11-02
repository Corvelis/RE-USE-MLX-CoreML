#!/usr/bin/env python3
"""Write the small, pinned download catalog from an existing verified model pack."""
import argparse
import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parent


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("model_directory", type=Path)
    parser.add_argument("--output", type=Path, default=ROOT / "App/ModelCatalog.json")
    args = parser.parse_args()
    pack = args.model_directory.resolve()
    manifest = json.loads((pack / "manifest.json").read_text())
    files = []
    for name in sorted([*manifest["files"], "manifest.json"]):
        path = (pack / name).resolve()
        assert path.is_relative_to(pack.resolve())
        data = path.read_bytes()
        digest = hashlib.sha256(data).hexdigest()
        if name != "manifest.json":
            assert digest == manifest["files"][name], name
        files.append({"path": name, "bytes": len(data), "sha256": digest})
    value = json.dumps({"version": 1, "name": "NVIDIA RE-USE · Apple", "files": files}, ensure_ascii=False, indent=2) + "\n"
    destination = args.output
    if not destination.exists() or destination.read_text() != value:
        destination.write_text(value)
    print(json.dumps({"files": len(files), "model_bytes": sum(f["bytes"] for f in files), "catalog_bytes": len(value.encode())}))


if __name__ == "__main__":
    main()
