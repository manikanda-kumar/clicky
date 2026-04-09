# Clicky

Clicky is a macOS menu bar companion that listens with push-to-talk, looks at your screen, answers out loud, and can point at UI elements with a cursor overlay.

This repo currently supports two practical ways to run it:

- local OpenAI-first development
- worker-backed Claude/ElevenLabs/AssemblyAI development

For your current setup, the easiest path is the local OpenAI one.

## What Works Right Now

- The app builds successfully from the CLI with the namespaced makefile flow.
- Local testing can run without Cloudflare if OpenAI is configured.
- Grounding is provider-based:
  - native macOS accessibility first
  - OpenAI computer use fallback
  - legacy `[POINT:x,y:label]` fallback

Current limitation:

- the shared CLI `test` path still fails in the existing boilerplate UI-test runner for this menu bar app
- build is green, automated UI tests are not

## Requirements

- macOS 14.2+
- Xcode 15+
- an OpenAI API key for the local path

Optional, only if you want the full worker-backed stack:

- Cloudflare account
- Anthropic API key
- AssemblyAI API key
- ElevenLabs API key

## Quick Start: Local OpenAI Path

This is the recommended way to use the current repo locally.

### 1. Open the project

```bash
open leanring-buddy.xcodeproj
```

Yes, `leanring` is intentionally misspelled in the project name.

### 2. Configure the OpenAI key

The app can read the key from either:

- `OPENAI_API_KEY` in the environment
- `OpenAIAPIKey` inside `leanring-buddy/Info.plist`

The checked-in `Info.plist` keeps `OpenAIAPIKey` empty. If you want Finder or DMG launches to work without shell environment inheritance, add your own local key there and keep that change out of git.

If you prefer Xcode env vars instead of embedding the key:

1. In Xcode, open `Product > Scheme > Edit Scheme...`
2. Select `Run`
3. Open the `Arguments` tab
4. Add an environment variable:

```text
OPENAI_API_KEY=your-key-here
```

### 3. Transcription defaults to OpenAI

The checked-in app bundle defaults to:

```text
VoiceTranscriptionProvider = openai
OpenAITranscriptionModel = gpt-4o-transcribe
```

So once the OpenAI key is available, push-to-talk transcription should use OpenAI automatically.

### 4. Run the app

In Xcode:

1. select the `leanring-buddy` scheme
2. set your signing team
3. press `Cmd + R`

The app lives in the menu bar, not the Dock.

### 5. Grant permissions

Clicky needs:

- Microphone
- Accessibility
- Screen Recording
- Screen content access through ScreenCaptureKit

Without these, push-to-talk and screen-aware behavior will not work correctly.

## Launch Without Xcode

If you want a launchable app without opening Xcode, you have two options.

### Option 1: Install the app bundle directly

Install into a local directory inside the repo:

```bash
AGENT_NAME=codex INSTALL_DIR=$(pwd)/build/install/codex TREAT_WARNINGS_AS_ERRORS=NO make -f Makefile.clickycli clickycli-install
```

Install into your user Applications folder:

```bash
AGENT_NAME=codex TREAT_WARNINGS_AS_ERRORS=NO make -f Makefile.clickycli clickycli-install
```

By default, `clickycli-install` copies the built app into `~/Applications/Clicky.app`.

### Option 2: Build a DMG

Debug DMG:

```bash
AGENT_NAME=codex TREAT_WARNINGS_AS_ERRORS=NO make -f Makefile.clickycli clickycli-dmg
```

Release DMG:

```bash
AGENT_NAME=codex CONFIGURATION=Release TREAT_WARNINGS_AS_ERRORS=NO make -f Makefile.clickycli clickycli-dmg
```

Artifacts:

- Installed app target by default: `~/Applications/Clicky.app`
- Example local install target: `build/install/codex/Clicky.app`
- Debug DMG: `build/dist/codex/leanring-buddy-Debug.dmg`
- Release DMG: `build/dist/codex/leanring-buddy-Release.dmg`

What this does:

- builds the app through the same CLI build flow
- resolves the actual built app bundle path
- either installs it directly or packages it into a DMG
- packages the app plus an `Applications` shortcut into a DMG

If you only want the built `.app` bundle without a DMG, it is placed under:

- `build/DerivedData/codex/Build/Products/Debug/Clicky.app`
- or the matching `Release` path if you build with `CONFIGURATION=Release`

Because this is currently an unsigned local build, macOS may warn when you open it outside Xcode. For local testing, use Finder's `Open` action if Gatekeeper blocks a normal double-click.

## How Local OpenAI Mode Behaves

When the worker is not configured:

- chat falls back to direct OpenAI
- transcription uses OpenAI if selected
- grounding can use OpenAI computer use
- speech falls back to macOS system TTS if ElevenLabs is unavailable

So for local use, OpenAI is enough to get a working development loop.

## Optional: Worker-Backed Path

If you want the original hosted stack instead of local OpenAI fallback, configure the Cloudflare Worker.

### Worker setup

```bash
cd worker
npm install
npx wrangler secret put ANTHROPIC_API_KEY
npx wrangler secret put ASSEMBLYAI_API_KEY
npx wrangler secret put ELEVENLABS_API_KEY
npx wrangler deploy
```

Then provide a real worker URL through either:

- `WorkerBaseURL` in `Info.plist`
- `CLICKY_WORKER_BASE_URL` in the environment

If you want AssemblyAI streaming through the worker token route, also make sure:

- `AssemblyAITokenProxyURL` is configured, or
- the worker base URL points to a worker with `/transcribe-token`

## CLI Build And Validation

Do not run raw `xcodebuild` directly for this project. Use the generated namespaced makefile instead.

```bash
AGENT_NAME=codex make -f Makefile.clickycli clickycli-diagnose
AGENT_NAME=codex TREAT_WARNINGS_AS_ERRORS=NO make -f Makefile.clickycli clickycli-build
AGENT_NAME=codex TREAT_WARNINGS_AS_ERRORS=NO make -f Makefile.clickycli clickycli-dmg
AGENT_NAME=codex TREAT_WARNINGS_AS_ERRORS=NO make -f Makefile.clickycli clickycli-install
AGENT_NAME=codex TREAT_WARNINGS_AS_ERRORS=NO make -f Makefile.clickycli clickycli-test
```

Notes:

- `clickycli-build` currently succeeds
- `clickycli-test` currently fails in the menu bar app UI-test runner
- logs and result bundles are written under `build/logs/codex/`

Useful artifacts:

- `build/logs/codex/build.log`
- `build/logs/codex/build.xcresult`
- `build/logs/codex/test.log`
- `build/logs/codex/test.xcresult`

## Project Layout

```text
leanring-buddy/
  CompanionManager.swift
  CompanionPanelView.swift
  OverlayWindow.swift
  BuddyDictationManager.swift
  BuddyTranscriptionProvider.swift
  OpenAIAudioTranscriptionProvider.swift
  AssemblyAIStreamingTranscriptionProvider.swift
  Providers/
    Chat/
    Automation/
    Grounding/
worker/
  src/index.ts
Makefile.clickycli
AGENTS.md
```

## Security Notes

- If `OpenAIAPIKey` is stored in `leanring-buddy/Info.plist`, treat that as local-only.
- Do not commit a real API key in the repo.
- Do not ship a public DMG with an embedded shared key unless you accept that the key can be extracted.

## Current Architecture

At a high level:

- push-to-talk captures microphone audio
- transcription provider turns audio into text
- screen capture grabs one or more screenshots
- chat provider generates a spoken answer
- grounding provider tries to locate the relevant UI target
- overlay animates the cursor to the target
- TTS speaks the result

The key architectural direction in this repo is:

- native macOS tooling first
- vision fallback second

## Feedback

If you are hacking on this locally and want the full internal architecture details, read [AGENTS.md](AGENTS.md).

## Design Docs

- [Collaborative UI Architecture Plan](docs/collaborative-ui-architecture.md)
- [OpenAI Path Correction Plan](docs/openai-path-correction-plan.md)
