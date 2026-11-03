#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Check app video I/O using generated fixtures; requires macOS, Xcode and FFmpeg."""
import hashlib
import json
import shutil
import struct
import subprocess
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent


def run(*args):
    return subprocess.check_output([str(arg) for arg in args])


def ffmpeg(*args):
    return run("ffmpeg", "-v", "error", "-nostdin", "-y", *args)


def pcm(path):
    return ffmpeg("-i", path, "-map", "0:a:0", "-f", "f32le", "-acodec", "pcm_f32le", "-")


def video_hash(path):
    return ffmpeg("-i", path, "-map", "0:v:0", "-c", "copy", "-f", "hash", "-hash", "sha256", "-")


def video_info(path):
    data = run("ffprobe", "-v", "error", "-count_packets", "-select_streams", "v:0",
               "-show_streams", "-of", "json", path)
    return json.loads(data)["streams"][0]


def main():
    for tool in ("xcrun", "ffmpeg", "ffprobe"):
        if shutil.which(tool) is None:
            raise SystemExit(f"Install {tool} before running video checks.")
    with tempfile.TemporaryDirectory(prefix="reuse-video-checks-") as directory:
        root = Path(directory)
        source, aac, delayed, silent = [root / name for name in
                                       ("source.mov", "source-aac.mp4", "delayed.mov", "silent.mov")]
        # A generated picture and tone; no downloaded or personal media.
        ffmpeg("-f", "lavfi", "-i", "color=c=black:s=96x160:r=15:d=2",
               "-f", "lavfi", "-i", "sine=frequency=440:sample_rate=44100:duration=2",
               "-af", "pan=stereo|c0=c0|c1=c0", "-c:v", "libx264", "-pix_fmt", "yuv420p",
               "-c:a", "pcm_f32le", "-shortest", source)
        ffmpeg("-i", source, "-c:v", "copy", "-c:a", "aac", "-b:a", "128k", aac)
        ffmpeg("-display_rotation", "90", "-i", source, "-itsoffset", "0.75", "-i", source, "-map", "0:v:0", "-map", "1:a:0",
               "-c", "copy", "-t", "2", delayed)
        ffmpeg("-i", source, "-map", "0:v:0", "-c", "copy", "-an", silent)
        executable = root / "media-checks"
        run("xcrun", "swiftc", "-parse-as-library", "-swift-version", "5",
            ROOT / "App/VideoMedia.swift", ROOT / "App/VideoComparison.swift",
            ROOT / "Tests/VideoMediaChecks/MediaChecks.swift", "-o", executable)
        results = root / "results"
        run(executable, aac, delayed, silent, results)
        decoded = pcm(results / "original-extracted.wav")
        assert all(pcm(results / f"repeated-{trial}.wav") == decoded for trial in range(3)), \
            "Repeated AAC imports must produce identical native-rate audio"
        samples = [value[0] for value in struct.iter_unpack("<f", decoded)]
        rms = (sum(value * value for value in samples) / len(samples)) ** 0.5
        assert 0.085 < rms < 0.091, "Dual-mono input level must be preserved"
        for original, exported in [(aac, results / "original/enhanced-video.mov"),
                                   (delayed, results / "rotated/enhanced-video.mov")]:
            assert video_hash(original) == video_hash(exported), "Video bitstream changed"
            before, after = video_info(original), video_info(exported)
            for key in ("width", "height", "nb_read_packets", "side_data_list"):
                assert before.get(key) == after.get(key), f"Video {key} changed"
        assert pcm(results / "original/enhanced-video.mov") == decoded, "Saved PCM audio changed"
        report = json.loads((results / "checks.json").read_text())
        assert report["status"] == "passed"
        print(json.dumps({**report, "deterministicAACImports": True,
                          "dualMonoRMS": rms, "videoBitstreamAndOrientationUnchanged": True,
                          "savedPCMUnchanged": True,
                          "decodedSHA256": hashlib.sha256(decoded).hexdigest()}, indent=2))


if __name__ == "__main__":
    main()
