# Clicky - Agent Instructions

<!-- This is the single source of truth for all AI coding agents. CLAUDE.md is a symlink to this file. -->
<!-- AGENTS.md spec: https://github.com/agentsmd/agents.md — supported by Claude Code, Cursor, Copilot, Gemini CLI, and others. -->

## Overview

macOS menu bar companion app. Lives entirely in the macOS status bar (no dock icon, no main window). Clicking the menu bar icon opens a custom floating panel with companion voice controls. Uses push-to-talk (ctrl+option) to capture voice input, transcribes it via AssemblyAI streaming, and sends the transcript + a screenshot of the user's screen to the assistant. The default assistant path still uses Claude through the worker proxy, but local testing can now fall back to direct OpenAI chat plus system TTS when the worker is not configured. Grounding is provider-based: native macOS accessibility first, OpenAI computer use as a fallback, and `[POINT:x,y:label]` tags as a final fallback. A blue cursor overlay can fly to and point at UI elements the assistant references on any connected monitor.

## Architecture

- **App Type**: Menu bar-only (`LSUIElement=true`), no dock icon or main window
- **Framework**: SwiftUI (macOS native) with AppKit bridging for menu bar panel and cursor overlay
- **Pattern**: MVVM with `@StateObject` / `@Published` state management
- **AI Chat**: Provider abstraction with Claude via Cloudflare Worker proxy by default, plus direct OpenAI fallback for local testing when `OpenAIAPIKey` is configured and the worker is not
- **Speech-to-Text**: The checked-in app bundle defaults to OpenAI transcription (`gpt-4o-transcribe`) for local development. AssemblyAI real-time streaming (`u3-rt-pro` model) remains available when `AssemblyAITokenProxyURL` is configured, with Apple Speech as a fallback.
- **Text-to-Speech**: ElevenLabs (`eleven_flash_v2_5` model) via Cloudflare Worker proxy, with local macOS system speech fallback when the worker is unavailable
- **Screen Capture**: ScreenCaptureKit (macOS 14.2+), multi-monitor support
- **Voice Input**: Push-to-talk via `AVAudioEngine` + pluggable transcription-provider layer. System-wide keyboard shortcut via listen-only CGEvent tap.
- **Element Pointing**: Native macOS accessibility inspection runs first, OpenAI computer use can provide screenshot-based fallback grounding, and Claude-style `[POINT:x,y:label:screenN]` tags remain the final fallback. The overlay parses grounded coordinates, maps them to the correct monitor, and animates the blue cursor along a bezier arc to the target.
- **Concurrency**: `@MainActor` isolation, async/await throughout
- **Analytics**: PostHog via `ClickyAnalytics.swift`

### API Proxy (Cloudflare Worker)

Most external requests go through a Cloudflare Worker (`worker/src/index.ts`) that holds the Claude, ElevenLabs, and AssemblyAI keys as secrets. OpenAI chat, transcription, and OpenAI computer-use fallback calls can be made directly from the app via bundle configuration keys or matching environment variables during local development.

| Route | Upstream | Purpose |
|-------|----------|---------|
| `POST /chat` | `api.anthropic.com/v1/messages` | Claude vision + streaming chat |
| `POST /tts` | `api.elevenlabs.io/v1/text-to-speech/{voiceId}` | ElevenLabs TTS audio |
| `POST /transcribe-token` | `streaming.assemblyai.com/v3/token` | Fetches a short-lived (480s) AssemblyAI websocket token |

Worker secrets: `ANTHROPIC_API_KEY`, `ASSEMBLYAI_API_KEY`, `ELEVENLABS_API_KEY`
Worker vars: `ELEVENLABS_VOICE_ID`

### Key Architecture Decisions

**Menu Bar Panel Pattern**: The companion panel uses `NSStatusItem` for the menu bar icon and a custom borderless `NSPanel` for the floating control panel. This gives full control over appearance (dark, rounded corners, custom shadow) and avoids the standard macOS menu/popover chrome. The panel is non-activating so it doesn't steal focus. A global event monitor auto-dismisses it on outside clicks.

**Cursor Overlay**: A full-screen transparent `NSPanel` hosts the blue cursor companion. It's non-activating, joins all Spaces, and never steals focus. The cursor position, response text, waveform, and pointing animations all render in this overlay via SwiftUI through `NSHostingView`.

**Global Push-To-Talk Shortcut**: Background push-to-talk uses a listen-only `CGEvent` tap instead of an AppKit global monitor so modifier-based shortcuts like `ctrl + option` are detected more reliably while the app is running in the background.

**Shared URLSession for AssemblyAI**: A single long-lived `URLSession` is shared across all AssemblyAI streaming sessions (owned by the provider, not the session). Creating and invalidating a URLSession per session corrupts the OS connection pool and causes "Socket is not connected" errors after a few rapid reconnections.

**Transient Cursor Mode**: When "Show Clicky" is off, pressing the hotkey fades in the cursor overlay for the duration of the interaction (recording → response → TTS → optional pointing), then fades it out automatically after 1 second of inactivity.

## Key Files

| File | Lines | Purpose |
|------|-------|---------|
| `leanring_buddyApp.swift` | ~89 | Menu bar app entry point. Uses `@NSApplicationDelegateAdaptor` with `CompanionAppDelegate` which creates `MenuBarPanelManager` and starts `CompanionManager`. No main window — the app lives entirely in the status bar. |
| `CompanionManager.swift` | ~984 | Central state machine. Owns dictation, shortcut monitoring, screen capture, assistant and grounding orchestration, ElevenLabs TTS, and overlay management. Tracks voice state (idle/listening/processing/responding), conversation history, model selection, and cursor visibility. Coordinates the full push-to-talk → screenshot → assistant → grounding → TTS → pointing pipeline. |
| `MenuBarPanelManager.swift` | ~243 | NSStatusItem + custom NSPanel lifecycle. Creates the menu bar icon, manages the floating companion panel (show/hide/position), installs click-outside-to-dismiss monitor. |
| `CompanionPanelView.swift` | ~761 | SwiftUI panel content for the menu bar dropdown. Shows companion status, push-to-talk instructions, model picker (Sonnet/Opus), permissions UI, DM feedback button, and quit button. Dark aesthetic using `DS` design system. |
| `OverlayWindow.swift` | ~881 | Full-screen transparent overlay hosting the blue cursor, response text, waveform, and spinner. Handles cursor animation, element pointing with bezier arcs, multi-monitor coordinate mapping, and fade-out transitions. |
| `CompanionResponseOverlay.swift` | ~217 | SwiftUI view for the response text bubble and waveform displayed next to the cursor in the overlay. |
| `CompanionScreenCaptureUtility.swift` | ~132 | Multi-monitor screenshot capture using ScreenCaptureKit. Returns labeled image data for each connected display. |
| `BuddyDictationManager.swift` | ~866 | Push-to-talk voice pipeline. Handles microphone capture via `AVAudioEngine`, provider-aware permission checks, keyboard/button dictation sessions, transcript finalization, shortcut parsing, contextual keyterms, and live audio-level reporting for waveform feedback. |
| `BuddyTranscriptionProvider.swift` | ~100 | Protocol surface and provider factory for voice transcription backends. Resolves provider based on `VoiceTranscriptionProvider` in Info.plist — AssemblyAI, OpenAI, or Apple Speech. |
| `AssemblyAIStreamingTranscriptionProvider.swift` | ~478 | Streaming transcription provider. Fetches temp tokens from the Cloudflare Worker, opens an AssemblyAI v3 websocket, streams PCM16 audio, tracks turn-based transcripts, and delivers finalized text on key-up. Shares a single URLSession across all sessions. |
| `OpenAIAudioTranscriptionProvider.swift` | ~317 | Upload-based transcription provider. Buffers push-to-talk audio locally, uploads as WAV on release, returns finalized transcript. |
| `AppleSpeechTranscriptionProvider.swift` | ~147 | Local fallback transcription provider backed by Apple's Speech framework. |
| `BuddyAudioConversionSupport.swift` | ~108 | Audio conversion helpers. Converts live mic buffers to PCM16 mono audio and builds WAV payloads for upload-based providers. |
| `GlobalPushToTalkShortcutMonitor.swift` | ~132 | System-wide push-to-talk monitor. Owns the listen-only `CGEvent` tap and publishes press/release transitions. |
| `ClaudeAPI.swift` | ~291 | Claude vision API client with streaming (SSE) and non-streaming modes. TLS warmup optimization, image MIME detection, conversation history support. |
| `OpenAIAPI.swift` | ~142 | OpenAI GPT vision API client. |
| `ElevenLabsTTSClient.swift` | ~81 | ElevenLabs TTS client. Sends text to the Worker proxy, plays back audio via `AVAudioPlayer`. Exposes `isPlaying` for transient cursor scheduling. |
| `ElementLocationDetector.swift` | ~335 | Detects UI element locations in screenshots for cursor pointing. |
| `Providers/Chat/ClickyChatProvider.swift` | ~20 | Shared assistant chat provider protocol used by the orchestration layer. |
| `Providers/Chat/ClaudeWorkerChatProvider.swift` | ~39 | Claude-backed chat provider that routes through the worker proxy. |
| `Providers/Chat/OpenAIChatProvider.swift` | ~52 | Direct OpenAI chat provider used for local development when the worker chat route is not configured. |
| `Providers/Automation/ClickyAutomationTypes.swift` | ~35 | Read-only automation snapshot types used by native grounding. |
| `Providers/Automation/NativeMacOSAutomationProvider.swift` | ~148 | Accessibility-backed inspection of frontmost app, focused UI element, and menu items. |
| `Providers/Grounding/ClickyGroundingTypes.swift` | ~34 | Shared grounding request/result types for transcript + assistant response matching. |
| `Providers/Grounding/GroundingCoordinator.swift` | ~36 | Tries native macOS grounding first, then OpenAI computer use, then point-tag fallback. |
| `Providers/Grounding/NativeMacOSGroundingProvider.swift` | ~225 | Scores accessibility candidates and maps native frames back into screenshot coordinates. |
| `Providers/Grounding/OpenAIComputerUseGroundingProvider.swift` | ~213 | Screenshot-based fallback grounding using OpenAI computer use, without executing actions. |
| `Providers/Grounding/PointTagGroundingProvider.swift` | ~63 | Parses the legacy `[POINT:...]` response tag format. |
| `SystemTTSClient.swift` | ~31 | Local macOS speech-synthesis fallback used when ElevenLabs is unavailable during development. |
| `Makefile.clickycli` | ~154 | Namespaced xcode-makefiles entry point for CLI diagnose/build/test flows without colliding with repo-level Make targets. |
| `scripts/clickycli/create_dmg.sh` | ~67 | Packages a built macOS app bundle into a simple DMG with an `Applications` shortcut for local installs. |
| `scripts/clickycli/install_app_bundle.sh` | ~61 | Copies the resolved built app bundle into an install directory, defaulting to `~/Applications` when used through the make target. |
| `scripts/clickycli/resolve_built_app_path.sh` | ~56 | Resolves the actual built `.app` path from Xcode products so run/packaging targets do not rely on the scheme name matching the bundle name. |
| `scripts/clickycli/xcbuild.sh` | ~104 | Wrapper around `xcodebuild` that isolates logs, result bundles, caches, and per-agent temp directories for CLI validation. |
| `DesignSystem.swift` | ~880 | Design system tokens — colors, corner radii, shared styles. All UI references `DS.Colors`, `DS.CornerRadius`, etc. |
| `ClickyAnalytics.swift` | ~121 | PostHog analytics integration for usage tracking. |
| `WindowPositionManager.swift` | ~262 | Window placement logic, Screen Recording permission flow, and accessibility permission helpers. |
| `AppBundleConfiguration.swift` | ~62 | Runtime configuration reader for Info.plist values plus local-development environment variable overrides. |
| `worker/src/index.ts` | ~142 | Cloudflare Worker proxy. Three routes: `/chat` (Claude), `/tts` (ElevenLabs), `/transcribe-token` (AssemblyAI temp token). |

## Build & Run

```bash
# Open in Xcode
open leanring-buddy.xcodeproj

# Select the leanring-buddy scheme, set signing team, Cmd+R to build and run

# CLI validation via the namespaced xcode-makefiles toolkit
AGENT_NAME=codex make -f Makefile.clickycli clickycli-diagnose
AGENT_NAME=codex TREAT_WARNINGS_AS_ERRORS=NO make -f Makefile.clickycli clickycli-build
AGENT_NAME=codex TREAT_WARNINGS_AS_ERRORS=NO make -f Makefile.clickycli clickycli-dmg
AGENT_NAME=codex TREAT_WARNINGS_AS_ERRORS=NO make -f Makefile.clickycli clickycli-install
AGENT_NAME=codex TREAT_WARNINGS_AS_ERRORS=NO make -f Makefile.clickycli clickycli-test

# Local OpenAI-only testing from a terminal-launched app
export OPENAI_API_KEY=...
export CLICKY_VOICE_TRANSCRIPTION_PROVIDER=openai

# If you launch from Xcode.app instead of a terminal, add OPENAI_API_KEY
# to the scheme's Run > Arguments > Environment Variables.

# Release DMG packaging
AGENT_NAME=codex CONFIGURATION=Release TREAT_WARNINGS_AS_ERRORS=NO make -f Makefile.clickycli clickycli-dmg

# Direct local install without Xcode
AGENT_NAME=codex INSTALL_DIR=$(pwd)/build/install/codex TREAT_WARNINGS_AS_ERRORS=NO make -f Makefile.clickycli clickycli-install

# Known non-blocking warnings: Swift 6 concurrency warnings,
# deprecated onChange warning in OverlayWindow.swift. Do NOT attempt to fix these.
```

**Do NOT run `xcodebuild` from the terminal** — it invalidates TCC (Transparency, Consent, and Control) permissions and the app will need to re-request screen recording, accessibility, etc.
Use the generated `Makefile.clickycli` targets instead if you need a terminal-driven validation pass.

## Cloudflare Worker

```bash
cd worker
npm install

# Add secrets
npx wrangler secret put ANTHROPIC_API_KEY
npx wrangler secret put ASSEMBLYAI_API_KEY
npx wrangler secret put ELEVENLABS_API_KEY

# Deploy
npx wrangler deploy

# Local dev (create worker/.dev.vars with your keys)
npx wrangler dev
```

## Code Style & Conventions

### Variable and Method Naming

IMPORTANT: Follow these naming rules strictly. Clarity is the top priority.

- Be as clear and specific with variable and method names as possible
- **Optimize for clarity over concision.** A developer with zero context on the codebase should immediately understand what a variable or method does just from reading its name
- Use longer names when it improves clarity. Do NOT use single-character variable names
- Example: use `originalQuestionLastAnsweredDate` instead of `originalAnswered`
- When passing props or arguments to functions, keep the same names as the original variable. Do not shorten or abbreviate parameter names. If you have `currentCardData`, pass it as `currentCardData`, not `card` or `cardData`

### Code Clarity

- **Clear is better than clever.** Do not write functionality in fewer lines if it makes the code harder to understand
- Write more lines of code if additional lines improve readability and comprehension
- Make things so clear that someone with zero context would completely understand the variable names, method names, what things do, and why they exist
- When a variable or method name alone cannot fully explain something, add a comment explaining what is happening and why

### Swift/SwiftUI Conventions

- Use SwiftUI for all UI unless a feature is only supported in AppKit (e.g., `NSPanel` for floating windows)
- All UI state updates must be on `@MainActor`
- Use async/await for all asynchronous operations
- Comments should explain "why" not just "what", especially for non-obvious AppKit bridging
- AppKit `NSPanel`/`NSWindow` bridged into SwiftUI via `NSHostingView`
- All buttons must show a pointer cursor on hover
- For any interactive element, explicitly think through its hover behavior (cursor, visual feedback, and whether hover should communicate clickability)

### Do NOT

- Do not add features, refactor code, or make "improvements" beyond what was asked
- Do not add docstrings, comments, or type annotations to code you did not change
- Do not try to fix the known non-blocking warnings (Swift 6 concurrency, deprecated onChange)
- Do not rename the project directory or scheme (the "leanring" typo is intentional/legacy)
- Do not run `xcodebuild` from the terminal — it invalidates TCC permissions

## Git Workflow

- Branch naming: `feature/description` or `fix/description`
- Commit messages: imperative mood, concise, explain the "why" not the "what"
- Do not force-push to main

## Self-Update Instructions

<!-- AI agents: follow these instructions to keep this file accurate. -->

When you make changes to this project that affect the information in this file, update this file to reflect those changes. Specifically:

1. **New files**: Add new source files to the "Key Files" table with their purpose and approximate line count
2. **Deleted files**: Remove entries for files that no longer exist
3. **Architecture changes**: Update the architecture section if you introduce new patterns, frameworks, or significant structural changes
4. **Build changes**: Update build commands if the build process changes
5. **New conventions**: If the user establishes a new coding convention during a session, add it to the appropriate conventions section
6. **Line count drift**: If a file's line count changes significantly (>50 lines), update the approximate count in the Key Files table

Do NOT update this file for minor edits, bug fixes, or changes that don't affect the documented architecture or conventions.
