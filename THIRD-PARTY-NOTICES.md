# Third-Party Notices — Golosok

Golosok ships third-party executables and model weights inside `Golosok.app/Contents/Resources`.
This file lists them, their licenses, and where the exact source can be obtained.

Golosok itself is distributed under the MIT License (see `LICENSE`). It is a fork of
[Berliner187/Golosok](https://github.com/Berliner187/Golosok), also MIT.

| Component | File in bundle | Version | License | Upstream |
| :--- | :--- | :--- | :--- | :--- |
| FFmpeg | `ffmpeg` | 7.1 | LGPL-2.1-or-later | https://ffmpeg.org |
| whisper.cpp | `whisper-cli` | — | MIT | https://github.com/ggerganov/whisper.cpp |
| transcribe.cpp | `transcribe-cli` | — | MIT | https://github.com/handy-computer/transcribe.cpp |
| ggml (static, inside the binaries above) | — | — | MIT | https://github.com/ggerganov/ggml |
| GigaAM v3 RNN-T weights (GGUF Q8_0) | `gigaam.gguf` | v3 `e2e_rnnt` | MIT | https://huggingface.co/memoravox/gigaam-v3-e2e-rnnt-gguf, base: https://huggingface.co/ai-sage/GigaAM-v3 |

## FFmpeg (LGPL-2.1-or-later)

The bundled `ffmpeg` is a minimal **LGPL** build: no `--enable-gpl`, no `--enable-nonfree`,
no GPL-only codecs. Its build configuration (as reported by `ffmpeg -version`) is:

```
--disable-everything --disable-autodetect --disable-doc --disable-debug --disable-network
--enable-static --disable-shared
--enable-demuxer=matroska,webm,ogg,mov,wav,aiff,flac,mp3
--enable-decoder=opus,vorbis,flac,aac,mp3float,alac,pcm_s16le,pcm_s24le,pcm_s32le,pcm_f32le,pcm_u8,wavpack
--enable-encoder=pcm_s16le,pcm_f32le --enable-muxer=wav --enable-protocol=file
--enable-swresample --enable-filter=aresample
```

Because the binary is statically linked against LGPL libraries, the corresponding source
code is available from https://ffmpeg.org/download.html (release 7.1) and can be rebuilt
with the configuration above. Written offer: open an issue at
https://github.com/Realmagnum/Golosok/issues and the maintainers will provide the exact
sources used for a given release.

## GigaAM v3 weights

The GGUF conversion of GigaAM v3 is distributed under the MIT license inherited from the
base model (`ai-sage/GigaAM-v3`). The model card and license text:
https://huggingface.co/ai-sage/GigaAM-v3

## MIT license text (whisper.cpp, transcribe.cpp, ggml, GigaAM)

```
MIT License

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

The release build script copies this file into the app bundle as
`Contents/Resources/THIRD-PARTY-NOTICES.md`, so every distributed DMG carries the notices.
