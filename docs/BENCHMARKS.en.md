# Speed and quality

[日本語](BENCHMARKS.md) | English

RTF is processing time divided by input duration; lower is faster. The initial measurements were taken on November 2, 2026; the version 0.2.0 video-audio checks were run on November 4.

## Measurement conditions

| Item | Condition |
| --- | --- |
| Input | 16 kHz mono audio lasting 7.92 seconds |
| Runs | One warmup per profile, followed by five alternating AB / BA comparison pairs |
| Summary | Median and minimum–maximum RTF over five measured runs |
| Included | STFT, all 30 model stages, iSTFT, overlap-add and GPU completion |
| Additional costs | File reading and conversion, model loading, initial compilation, saving and playback |
| Model | All 30 stages, 16 FP32 recurrent states, five-second windows, 5% overlap and original time/frequency resolution |
| Device state | Low Power Mode off, thermal state nominal; Mac connected to AC power |

The 7.92-second speed evaluation uses [`fileid_26119` from URGENT 2024](https://huggingface.co/datasets/urgent-challenge/urgent2024_official) (CC BY-NC-SA 4.0). The quality evaluation pair is from the [Edinburgh Noisy Speech Database](https://doi.org/10.7488/ds/2117) (CC BY 4.0).

The bundled `sample_noisy.wav` is an original 10.8573125-second recording of Japanese speech with vacuum cleaner noise. It has no corresponding clean reference recording. It is a separate input from the 7.92-second speed evaluation and the clean/noisy quality evaluation pair.

## iPhone 17 Pro / A19 Pro

iOS 27.2, ANE + GPU mode, using `.naxFullShared16` selected by `.recommended`.

| Profile | Median RTF | Minimum–maximum | Processing time for 7.92 seconds |
| --- | ---: | ---: | ---: |
| `naxFullShared16` | 0.09480 | 0.09257–0.09809 | Approximately 0.75 seconds |

This profile is selected automatically on supported GPUs running iOS 26.2 or later. Select “ANE + GPU” in the app.

## MacBook Air / M2

8-core GPU, 24 GiB memory, macOS 27.2.

| Mode and profile | Median RTF | Minimum–maximum | Processing time for 7.92 seconds |
| --- | ---: | ---: | ---: |
| MLX GPU, `foldShared` | 0.19824 | 0.19565–0.19979 | Approximately 1.57 seconds |
| ANE + GPU, `foldSeparate` | 0.14692 | 0.14645–0.14761 | Approximately 1.16 seconds |

Automatic selection on Mac uses `warpFast`. In the same comparison, `warpFast` achieved median RTFs of 0.20935 for MLX GPU and 0.15852 for ANE + GPU. The profiles in the table combine linear layers, introducing additional FP16 rounding, and must be selected explicitly. See the [SDK configuration guide](SDK.en.md).

## Measurements on the bundled sample

These results use `sample_noisy.wav` (16 kHz mono, 10.8573125 seconds) on MacBook Air / M2. After one warmup per profile, `warpFast` and each faster profile were run in five alternating AB / BA pairs.

| Mode and profile | Median RTF | Minimum–maximum | `warpFast` median RTF |
| --- | ---: | ---: | ---: |
| MLX GPU, `foldShared` | 0.19912 | 0.19876–0.20054 | 0.21130 |
| ANE + GPU, `foldSeparate` | 0.15486 | 0.15461–0.15591 | 0.16585 |

Relative RMSE against `warpFast` in the same mode was 0.02333% for `foldShared` and 0.04757% for `foldSeparate`. This measures the numerical waveform difference introduced by optimization, not a percentage of perceived degradation.

## Quality

All modes use FP16 for SSM projections and FP32 for recurrent states and normalization. ANE + GPU also uses FP16 for CNNs and boundary tensors. `foldShared`, `foldSeparate` and `naxFullShared16` introduce additional rounding when combining linear layers.

On one clean/noisy speech pair with a clean reference, the ANE + GPU profiles were compared against `warpFast` on each device:

| Device and profile | `warpFast` STOI | Faster profile STOI | `warpFast` SI-SDR | Faster profile SI-SDR |
| --- | ---: | ---: | ---: | ---: |
| A19 Pro, `naxFullShared16` | 0.94836095 | 0.94835503 | 14.993870 dB | 14.994723 dB |
| M2, `foldSeparate` | 0.94833868 | 0.94833576 | 14.993901 dB | 14.993424 dB |

Both metrics changed only slightly on this pair. On the 7.92-second recording, additional relative RMSE was approximately 0.0578% on A19 Pro and 0.0571% on M2. Evaluation covered this pair, the 7.92-second recording, and synthetic silence, impulse, low-amplitude and short inputs.

On a synthetic impulse, M2's `foldSeparate` produced 2.24% relative RMSE and a maximum amplitude difference of 0.000977. To reduce additional rounding, select `residualFuse`; its output matched `warpFast` on the M2 7.92-second evaluation recording. Waveform RMSE is not a percentage of perceived degradation, and quality depends on the input.

## Video audio and silent sections (0.2.0)

A 26.605-second screen recording was processed on an iPhone 17 Pro / A19 Pro, iOS 27.2, using ANE + GPU with automatic profile selection. After one warmup per setting, six interleaved AB / BA pairs gave mean RTFs of 0.09809 before the fix and 0.09900 after it. The fixed version's median was 0.09979, with a range of 0.09333–0.10366. Low Power Mode was off and thermal state was nominal.

In an import-to-export video check, noise reduction took 2.578 seconds, or RTF 0.09689. Video import and export time are excluded.

The first, mostly silent window used BF16; no FP32 retry was needed. The fix removed unwanted noise from silent sections caused by internal overflow. For the same input, output after five seconds was bit-identical to the previous implementation. Output on the bundled recording was also bit-identical.

For a five-second input containing one second of speech from the bundled recording and silence, additional relative RMSE against a reference path retaining FP32 scan outputs was 0.1851%, with STOI 0.99999949 between the two outputs. These measure differences caused by the numeric format, not enhancement quality against clean ground truth.

## Measuring your workload

Use “3回でRTFを測る” (Measure RTF over three runs) in the app or [`reuse-probe`](BUILDING.en.md) on Mac. Evaluate initial preparation time separately from RTF after warmup. Results vary with input duration, temperature, power state and other running apps. Fixed call overhead accounts for a larger share of processing time on short inputs.

ANE + GPU requests Core ML's `cpuAndNeuralEngine` for CNNs. Core ML determines actual placement. Windows whose CNN shapes are absent from the model pack fall back to MLX.
