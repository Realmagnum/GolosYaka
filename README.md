# Golosok: Local Speech Recognition for macOS

> **Read this in another language: [Русский](README_RU.md)**

<p align="left">
  <a href="https://github.com/jaywcjlove/awesome-swift-macos-apps">
    <img src="https://img.shields.io/badge/Featured_in-Awesome_Swift_macOS_Apps-black?style=for-the-badge&logo=swift&logoColor=F05138" alt="Awesome Swift macOS Apps">
  </a>
  <a href="https://github.com/Berliner187/Golosok/releases">
    <img src="https://img.shields.io/github/v/release/Berliner187/Golosok?style=for-the-badge&color=black&logo=apple" alt="Latest Release">
  </a>
  <a href="https://github.com/Berliner187/Golosok/blob/main/LICENSE">
    <img src="https://img.shields.io/badge/License-Open_Source-black?style=for-the-badge" alt="License">
  </a>
</p>

**Native voice dictation powered by Sber GigaAM v3. Inference on Apple Silicon.**  
Instant text input via `⌥ + Space`, offline media transcription, and optional AI post-processing with your own provider.

## What's new in DEV

* **Long-audio transcription without dropped words.** Long recordings are split into overlapping chunks with adaptive silence-aware boundaries, so phrases at chunk edges are no longer cut in half.
* **IT-term compensation.** A built-in dictionary restores distorted English technical terms (`Tailscale`, `OpenCode`, `Hindsight`, `Ollama`, `Vaultwarden`, …). Custom terms can be added, imported, exported, and edited.
* **AI auto-learning with a review buffer.** New phonetic variants discovered by AI are staged as candidates. You can edit, approve, or reject each candidate; a batch AI validator can check the accumulated list.
* **AI post-processing for notes and selections.** Summaries, meeting minutes, style polishing, translation, and custom prompts. Results stream in real time with reasoning controls.
* **Selection transform hotkey.** Select text in any app and press `⌥ + ⇧ + Space` to run an AI action on just that fragment.
* **Any OpenAI-compatible provider.** OpenAI, DeepSeek, Groq, Neuraldeep (OAuth), Ollama/LM Studio, or a custom endpoint. Each provider keeps its own Base URL, model, and API key.
* **Manual Primary and Failover roles.** Browsing providers never changes the active one. Assign Primary or Failover explicitly; Failover automatically takes over on network errors, timeouts, 401/403/404/429, and 5xx responses.
* **Retranscription and stage inspection.** Re-run a note and compare raw ASR, the text after the IT dictionary, and the final AI-edited result.
* **Live bilingual UI.** Switch between Russian and English on the fly, including dates, relative times, and AI action names.

## Features & Architecture

* **Full local transcription (Zero Cloud).** Speech inference runs 100% locally. The audio stream never leaves your Mac. AI post-processing is optional and only uses the provider you configure.
* **Direct Input.** Press `⌥ + Space`, dictate, and the text is inserted at your cursor in any app: VS Code, Notion, Telegram, Xcode, Obsidian, Slack, and more.
* **Hardware acceleration.** The model is optimized for Apple Silicon (M-series) and runs through CoreML / Apple Neural Engine without heating the CPU.
* **Context and slang awareness.** Strong handling of Russian, English, IT slang, code-switching ("Runglish"), and automatic punctuation.
* **Batch file processing.** Offline transcription of audio and video files of any length: MP3, WAV, M4A, MP4, WebM.
* **Word-level timings.** Karaoke-style highlighting during playback, with timings kept in sync after retranscription and dictionary replacements.
* **Prompt manager.** Edit built-in AI prompts, add custom ones, and roll back changes.
* **History and analytics.** AI transforms are stored in history with before/after badges; the dashboard shows time saved, dictation speed, activity, and note-size charts.
* **Bilingual by design.** Every UI string is available in both English and Russian.
* **Secure credentials.** API keys are stored in the macOS Keychain, with per-provider isolation and a single cached access path.

## Technical Specifications

| Component | Specification |
| :--- | :--- |
| **OS** | macOS 13.0+ (Ventura, Sonoma, Sequoia) |
| **Hardware** | Apple Silicon (M1 / M2 / M3 / M4 / M5) |
| **Model Engine** | GigaAM v3 RNN-T (GGUF Q8_0) / Whisper Large v3 Turbo / custom remote ASR |
| **RAM (Idle)** | ~70 MB |
| **RAM (Active Inference)** | ~100 MB |
| **Distribution Size** | ~270 MB |

## Installation

1. Download the latest `Golosok.dmg` from the [Releases](../../releases) section.
2. Drag `Golosok.app` into your `/Applications` folder.

**Bypassing macOS Gatekeeper:**  
This project is distributed as open-source software without an annual paid Apple Developer ID certificate. To prevent macOS from blocking the first launch, remove the quarantine attribute via Terminal:

```bash
xattr -cr /Applications/Golosok.app
```

*(GUI alternative: Control + right-click the app icon → Open → Confirm).*

## System Permissions

On the first launch, the app requests two macOS permissions:
1. **Microphone** — for capturing voice input.
2. **Accessibility** — for automated text insertion (`Cmd + V`) directly at your active cursor and for the selection transform hotkey.

*(If you are updating from an older version and the Accessibility toggle seems frozen, remove Golosok from the system list using the `-` button and re-add it).*

## Controls & Shortcuts

Golosok runs silently in the background. Control is bound to global hotkeys:

* **`⌥ + Space` (Option + Space) — Start / Stop Dictation**
  * **1st press:** starts recording (white island UI with a green equalizer).
  * **2nd press:** stops recording, runs inference (~0.1 s), and pastes the text into the focused input field.
* **Push-to-Talk / Hold Mode** *(selectable in Settings)*
  * Hold `⌥ + Space` to record, release to transcribe and paste instantly.
* **`⌥ + ⇧ + Space` — AI Transform for Selected Text**
  * Opens the prompt palette for the current selection in any app.
* **`ESC` — Cancel**
  * Hard-resets the current recording without pasting or saving.

The menu bar icon (`waveform`) provides access to recent dictation history, one-click copying, and app settings.

## AI Providers

Golosok ships with presets for OpenAI, DeepSeek, Groq, Neuraldeep, and local servers (Ollama / LM Studio), plus arbitrary OpenAI-compatible endpoints. Provider settings are stored independently, so switching the inspected provider never overwrites another provider's model or key.

Primary and Failover roles are explicit:

* Open any provider to view or edit its settings.
* Use the **Primary** toggle to make it the active provider.
* Use the **Failover** toggle to make it the automatic backup.

Bring your own API key or point Golosok at a local model — no sign-up needed.

## Building from Source

If you want to clone the repository and build the Xcode project manually:

```bash
# 1. Clone the repository
git clone https://github.com/Berliner187/Golosok.git
cd Golosok

# 2. Download GigaAM model weights
curl -L -o Golosok/gigaam.gguf https://huggingface.co/memoravox/gigaam-v3-e2e-rnnt-gguf/resolve/main/gigaam-v3-e2e-rnnt-Q8_0.gguf

# 3. Open the project in Xcode
open Golosok.xcodeproj
```

In Xcode, press `⌘ + R` to build and run.

A local development build (with the invariant and localization gate) is available via:

```bash
./build-dev.sh
```
