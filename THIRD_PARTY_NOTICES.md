# Third-party notices

Murmur release builds include [whisper.cpp](https://github.com/ggml-org/whisper.cpp) and its GGML components, and link `libwhisper` directly into the application so the model stays resident between dictations.

This repository also vendors the unmodified whisper.cpp v1.8.4 public headers under `Sources/CWhisper/include/` (`whisper.h`, `ggml.h`, `ggml-alloc.h`, `ggml-backend.h`, `ggml-cpu.h`, `ggml-metal.h`, and related headers) so the Swift package can compile against the runtime. The compiled libraries themselves are still built locally by `script/stage_whisper_runtime.sh` and are not committed.

whisper.cpp and GGML are licensed under the MIT License:

> Copyright (c) 2023-2026 The ggml authors
>
> Permission is hereby granted, free of charge, to any person obtaining a copy
> of this software and associated documentation files (the "Software"), to deal
> in the Software without restriction, including without limitation the rights
> to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
> copies of the Software, and to permit persons to whom the Software is
> furnished to do so, subject to the following conditions:
>
> The above copyright notice and this permission notice shall be included in all
> copies or substantial portions of the Software.
>
> THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
> IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
> FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
> AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
> LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
> OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
> SOFTWARE.

Whisper model files are not distributed in this repository or bundled with the app. The app downloads a model only after the user chooses one.

## Optional local writing runtime

Murmur can optionally use these pinned Swift packages for in-process local text transformation:

- `ml-explore/mlx-swift-lm` 3.31.3 and its MLX Swift dependency — MIT License.
- `huggingface/swift-huggingface` 0.9.0 — Apache License 2.0.
- `huggingface/swift-transformers` 1.3.0 — Apache License 2.0.

The optional `mlx-community/Qwen3-0.6B-4bit` model is pinned to revision
`73e3e38d981303bc594367cd910ea6eb48349da8` and identified as Apache-2.0 by its
model repository. Its weights are not committed or bundled. Murmur downloads the exact
required snapshot only after explicit user action, verifies every required file, and then
loads the verified local directory without a network-capable model loader.
