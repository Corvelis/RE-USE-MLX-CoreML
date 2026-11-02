# Licensing

[日本語](LICENSING.md) | English

The SDK and sample app code are licensed under [Apache License 2.0](../LICENSE). The following licenses apply to the model, dependencies and audio:

| Material | License | Notices and requirements |
| --- | --- | --- |
| ReuseKit / RE-USE Lab code | Apache-2.0 | Retain [LICENSE](../LICENSE) and [NOTICE](../NOTICE) |
| NVIDIA RE-USE model and converted models | OpenMDW-1.1 | Retain the [complete model license](../licenses/NVIDIA-RE-USE.txt) and copyright/origin notices |
| Inference code derived from SpeechLens | Apache-2.0 | Original copyright notices and modification details are included in NOTICE |
| MLX Swift / MLX / MLX C | MIT | Retain copyright and permission notices |
| Swift Numerics | Apache-2.0 + Swift Runtime Library Exception | See the [original license](../licenses/Swift-Numerics.txt) |
| Metal-cpp | Apache-2.0 | See the [original license](../licenses/Metal-CPP.txt) |
| fmt / nlohmann/json | MIT | Retain permission notices and copyright notices for included code |
| Third-party code within MLX | BSD-2-Clause / BSD-3-Clause / zlib / Apache-2.0 and others | See [third-party notices](../licenses/MLX-Third-Party.txt) |
| Sample recording | Apache-2.0 | Retain [LICENSE](../LICENSE) and the [audio notice](../licenses/Audio-Samples.txt) |

## Distributing an app or library

Include `LICENSE`, `NOTICE` and `licenses` with source distributions. For app distributions, include the notices in [App/Notices.txt](../App/Notices.txt) and make them accessible to users. The sample app displays the full text through its information button.

When distributing modified files derived from Apache-2.0 code, mark the changes in those files. Retain the terms of third-party code, including MIT and BSD components. The code's Apache-2.0 license does not replace the licenses of the model or dependencies.

## Distributing the model on Hugging Face

Use the complete text of [NVIDIA-RE-USE.txt](../licenses/NVIDIA-RE-USE.txt) as the model repository's `LICENSE`. Set the model card license to `openmdw-1.1`, and document the source model name and revision, conversion to MLX / Core ML, and mixed precision.

OpenMDW-1.1 permits commercial use, modification and redistribution, while requiring preservation of the license and applicable copyright/origin notices when redistributing. It imposes no additional conditions on model outputs. Rights in input and generated audio depend on the audio itself.

## Sample recording

The bundled `sample_noisy.wav` is an original recording of Japanese speech with vacuum cleaner noise, distributed under Apache-2.0. It is a 10.8573125-second recording converted to 16 kHz mono Float32 WAV. When redistributing, retain [LICENSE](../LICENSE) and the [audio notice](../licenses/Audio-Samples.txt), and mark any modifications.

See the [model management guide](MODELS.en.md) for download configuration.
