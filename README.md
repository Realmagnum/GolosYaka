<div align="center">
  <img src="GolosYaka/Assets.xcassets/AppLogo.imageset/icon_idle.png" width="96" height="96" alt="GolosYaka Logo">

  <h1>GolosYaka</h1>

  <p>
    <strong>Native macOS voice dictation, offline media transcription & AI text processing on Apple Silicon</strong>
  </p>

  <p>
    <strong>English</strong> · <a href="README_RU.md">Русский</a>
    &nbsp;|&nbsp;
    <a href="#highlights">Highlights</a> ·
    <a href="#shortcuts">Shortcuts</a> ·
    <a href="#installation">Installation</a> ·
    <a href="#building-from-source">Build</a>
  </p>
</div>

---

GolosYaka turns speech into clean text right at your cursor (`⌥ + Space`), transcribes long audio and video files locally without cloud uploads, and optionally refines notes or selected text with your preferred LLM provider.

## Highlights

- **100% Local Speech Recognition** — Powered by **Sber GigaAM v3** and **Whisper Large v3 Turbo** on Apple Silicon (~70 MB idle RAM). Audio never leaves your Mac.
- **Instant Direct Input** — Dictate into any app (Xcode, VS Code, Obsidian, Telegram, Slack, browsers) or use Push-to-Talk mode.
- **IT-Term Dictionary & Auto-Learning** — Automatically restores phonetic technical terms and bilingual slang (`Tailscale`, `OpenCode`, `Ollama`, `Kubernetes`, etc.) with an AI candidate review buffer.
- **Lossless Long-Audio Chunking** — Splits long recordings along adaptive silence boundaries so words at chunk edges are never dropped.
- **Word-Level Karaoke & Stage Diff** — Follow word timings during playback and compare Raw ASR → IT Dictionary → Final AI output at any time.
- **In-Place Selection AI (`⌥ + ⇧ + Space`)** — Select text in any app to summarize, rewrite, translate, or run custom prompts with real-time streaming.
- **Bring Your Own AI (Primary + Failover)** — Connect OpenAI, DeepSeek, Groq, Neuraldeep, Ollama / LM Studio, or any OpenAI-compatible endpoint with automatic failover.

## Shortcuts

| Shortcut | Action |
| :--- | :--- |
| `⌥ + Space` | Start / stop voice dictation (or hold in Push-to-Talk mode) |
| `⌥ + ⇧ + Space` | Run an AI action on selected text in any application |
| `Esc` | Cancel current recording without saving or pasting |

## Installation

1. Download the latest `GolosYaka.dmg` from [Releases](https://github.com/Realmagnum/GolosYaka/releases).
2. Drag `GolosYaka.app` into `/Applications`.
3. Clear the macOS quarantine flag before first launch (the app uses an open-source ad-hoc signature):

```bash
xattr -cr /Applications/GolosYaka.app
```

4. Grant **Microphone** (voice capture) and **Accessibility** (cursor paste & selection hotkey) permissions when prompted.

> **Updating note:** Because ad-hoc signatures change between builds, macOS may ask to refresh Accessibility after an update. Remove GolosYaka with `-` in *System Settings → Privacy & Security → Accessibility* and add it again.

## Specifications

| Parameter | Value |
| :--- | :--- |
| **OS** | macOS 13.0+ (Ventura, Sonoma, Sequoia) |
| **Hardware** | Apple Silicon (M1 – M5) |
| **Speech Engines** | GigaAM v3 RNN-T (`GGUF Q8_0`), Whisper Large v3 Turbo, Custom Remote ASR |
| **Memory Footprint** | ~70 MB idle / ~100 MB active inference |
| **Interface Languages** | English & Russian (live switching) |

## Building from Source

```bash
git clone https://github.com/Realmagnum/GolosYaka.git
cd GolosYaka

# Download GigaAM v3 weights
curl -L -o GolosYaka/gigaam.gguf \
  https://huggingface.co/memoravox/gigaam-v3-e2e-rnnt-gguf/resolve/main/gigaam-v3-e2e-rnnt-Q8_0.gguf

# Build & run via Xcode
open GolosYaka.xcodeproj
```

### CLI Build & Verification (Command Line Tools)

```bash
./build-dev.sh --arch arm64   # Fast dev bundle (../GolosYaka-Build/GolosYaka-Dev.app)
./scripts/run-tests.sh        # Smoke & invariant test suite
```

See [`docs/RELEASE.md`](docs/RELEASE.md) for DMG packaging and [`THIRD-PARTY-NOTICES.md`](THIRD-PARTY-NOTICES.md) for bundled open-source licenses.
