#!/usr/bin/env python3
"""Test the Foundation-only model manager without compiling/downloading MLX."""
import shutil
import subprocess
import tempfile
from pathlib import Path

TOOLS = Path(__file__).resolve().parent


def main():
    if shutil.disk_usage(TOOLS).free < 1024**3:
        raise RuntimeError("Less than 1 GiB free; test build not started")
    with tempfile.TemporaryDirectory(prefix="reuse-model-assets-") as temporary:
        root = Path(temporary)
        shutil.copytree(TOOLS / "Sources/ReuseModelAssets", root / "Sources/ReuseModelAssets")
        shutil.copytree(TOOLS / "Tests/ReuseModelAssetsTests", root / "Tests/ReuseModelAssetsTests")
        (root / "Package.swift").write_text('''// swift-tools-version: 6.0
import PackageDescription
let package = Package(name: "ModelAssetsChecks", platforms: [.macOS(.v15)], targets: [
    .target(name: "ReuseModelAssets"),
    .testTarget(name: "ReuseModelAssetsTests", dependencies: ["ReuseModelAssets"])
], swiftLanguageModes: [.v5])
''')
        subprocess.run(["xcrun", "swift", "test", "--package-path", str(root), "--scratch-path",
            str(TOOLS / ".build/model-assets-tests"), "--cache-path", str(TOOLS / ".build/package-cache"),
            "--disable-index-store", "-debug-info-format", "none", "-c", "release", "-j", "4"], check=True, timeout=120)


if __name__ == "__main__":
    main()
