#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Verify the bundled original recording and its metadata-free WAV container."""
import argparse
import hashlib
import math
import struct
from pathlib import Path

ROOT = Path(__file__).resolve().parent
PCM_SHA256 = "10e474c24ebdad0020c1df96fe32739d28527b46836e91f46b2e5128e05caa59"
SAMPLE_COUNT = 173717


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("directory", nargs="?", type=Path, default=ROOT / "App/Samples")
    directory = parser.parse_args().directory
    if sorted(p.name for p in directory.iterdir()) != ["sample_noisy.wav"]:
        raise SystemExit("The sample directory must contain only sample_noisy.wav.")
    data = (directory / "sample_noisy.wav").read_bytes()
    if data[:4] != b"RIFF" or data[8:12] != b"WAVE" or struct.unpack_from("<I", data, 4)[0] != len(data) - 8:
        raise SystemExit("Invalid WAV container.")
    offset = 12
    chunks = {}
    while offset + 8 <= len(data):
        tag, size = struct.unpack_from("<4sI", data, offset)
        end = offset + 8 + size
        if tag in chunks or end > len(data):
            raise SystemExit("Invalid WAV chunk.")
        chunks[tag] = data[offset + 8:end]
        offset = end + (size % 2)
    if offset != len(data) or set(chunks) != {b"fmt ", b"fact", b"data"}:
        raise SystemExit("Unexpected metadata or WAV chunks.")
    if chunks[b"fmt "] != struct.pack("<HHIIHH", 3, 1, 16000, 64000, 4, 32):
        raise SystemExit("Expected 16 kHz mono Float32 PCM.")
    if chunks[b"fact"] != struct.pack("<I", SAMPLE_COUNT) or len(chunks[b"data"]) != SAMPLE_COUNT * 4:
        raise SystemExit("Sample count does not match the original recording.")
    if hashlib.sha256(chunks[b"data"]).hexdigest() != PCM_SHA256:
        raise SystemExit("Sample audio does not match the original recording.")
    if not all(math.isfinite(value) for (value,) in struct.iter_unpack("<f", chunks[b"data"])):
        raise SystemExit("Non-finite audio samples.")
    print("Sample verified: sample_noisy.wav, 16 kHz mono Float32, 10.8573125 seconds, no metadata tags")


if __name__ == "__main__":
    main()
