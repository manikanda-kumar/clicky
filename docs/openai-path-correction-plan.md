# OpenAI Path Correction Plan

## Purpose

This document turns the architecture review of commit `e94b857` into a concrete patch plan.

The provider-based direction remains the right long-term path. The goal of this plan is not to undo the OpenAI and provider refactor. The goal is to correct the three architectural issues that became visible after moving away from the original Claude-only path.

## Summary

Keep:

- provider-based chat abstraction
- provider-based grounding abstraction
- local OpenAI development path
- native-first grounding strategy as a general direction

Correct:

1. explicit point tags must be authoritative
2. OpenAI computer-use grounding must not block spoken response unnecessarily
3. provider selection and model state must become provider-neutral and explicit

## Why This Needs Correction

Compared to the original Claude-based path, the current refactor improved flexibility and local development, but it also introduced a new ambiguity.

The system still prompts the assistant to emit `[POINT:...]` tags, but the grounding stack can currently override or bypass that explicit instruction by trying native and vision-based grounding first.

That creates two regressions relative to the original behavior:

- valid model-directed coordinates are no longer guaranteed to win
- speech can now wait on extra grounding work before TTS starts

## Fix 1: Make Explicit Point Tags Authoritative

### Problem

The current provider ordering is:

1. native grounding
2. OpenAI computer-use grounding
3. point-tag parsing

This means:

- a valid `[POINT:x,y:label]` can be overridden by heuristic grounding
- `[POINT:none]` can still lead to inferred pointing if an earlier provider returns a coordinate

### Desired Behavior

- if the assistant emitted a valid point tag, use it
- if the assistant emitted `[POINT:none]`, stop there and do not infer a point
- only if there is no point tag at all should fallback providers try to infer a point

### Patch Plan

#### Introduce an explicit grounding match type

Replace the current soft `ClickyGroundingResult?` matching contract with a clearer match outcome.

Suggested shape:

```swift
enum ClickyGroundingMatch {
    case noMatch
    case explicitNone(spokenText: String)
    case grounded(ClickyGroundingResult)
}
```

#### Update point-tag parsing semantics

`PointTagGroundingProvider` should return:

- `.grounded(...)` when `[POINT:x,y...]` exists
- `.explicitNone(...)` when `[POINT:none]` exists
- `.noMatch` when no point tag exists at all

#### Update coordinator precedence

`GroundingCoordinator` should:

1. check point-tag grounding first
2. short-circuit on explicit point tag
3. short-circuit on explicit none
4. only then try native and vision fallback providers

### Files To Change

- `leanring-buddy/Providers/Grounding/ClickyGroundingTypes.swift`
- `leanring-buddy/Providers/Grounding/PointTagGroundingProvider.swift`
- `leanring-buddy/Providers/Grounding/GroundingCoordinator.swift`
- `leanring-buddy/CompanionManager.swift`

### Success Criteria

- valid point tags always beat inferred grounding
- `[POINT:none]` prevents accidental inferred pointing
- behavior matches the original assistant contract more closely

## Fix 2: Make Computer-Use Grounding Best-Effort

### Problem

The current response flow waits for full grounding before starting TTS.

That means the app can incur:

- assistant response latency
- then native grounding time
- then OpenAI computer-use network time
- then TTS startup

That is risky for a voice-first product.

### Desired Behavior

- speech should not be blocked by slow fallback grounding
- explicit point tags should remain immediate
- native grounding can stay inline if it remains fast
- OpenAI computer-use grounding should be a strict best-effort fallback

### Patch Plan

#### Split grounding into fast and slow stages

Create a two-stage mental model:

- Stage 1: explicit point tag parsing and native grounding
- Stage 2: optional computer-use grounding fallback

#### Keep the fast path synchronous

Inline before TTS:

- point tag parse
- native grounding attempt

#### Move computer-use to a bounded async fallback

Options, in order of preference:

1. start TTS after fast grounding and run computer-use concurrently with a short timeout
2. if the UI requires the pointer before speech, cap computer-use with a tight deadline such as one to two seconds

The product should prefer speaking promptly over perfectly grounded late pointing.

#### Tighten timeouts and scope

Reduce the very generous network timeout profile for computer-use fallback.

Also keep the fallback scoped only to situations where:

- there is no explicit point tag
- native grounding found no match
- pointing would materially help

### Files To Change

- `leanring-buddy/CompanionManager.swift`
- `leanring-buddy/Providers/Grounding/GroundingCoordinator.swift`
- `leanring-buddy/Providers/Grounding/OpenAIComputerUseGroundingProvider.swift`

### Success Criteria

- TTS starts promptly on native misses
- fallback grounding still improves pointing when available
- perceived voice latency stays close to the original Claude flow

## Fix 3: Make Provider Selection Explicit And Provider-Neutral

### Problem

The refactor added good seams, but `CompanionManager` still owns provider policy and Claude-specific naming.

Examples:

- `selectedClaudeModel`
- `supportsClaudeModelPicker`
- concrete type checks for provider display
- implicit provider selection based on whichever config happens to be present

### Desired Behavior

- provider selection is explicit
- model persistence is provider-neutral
- provider capability display does not depend on concrete type checks in `CompanionManager`

### Patch Plan

#### Add a chat provider factory

Create a small factory that resolves the selected chat backend.

Suggested config key:

```text
AssistantProvider = worker | openai
```

Fallback behavior can remain, but explicit config should win.

#### Move provider capability metadata out of CompanionManager

Expose metadata such as:

- provider display name
- whether the provider supports a model picker
- default model name

This can live on the provider or on a small provider descriptor.

#### Rename model persistence

Replace `selectedClaudeModel` with a provider-neutral key, or persist model per provider.

Examples:

- `selectedAssistantModel`
- `selectedModelByProvider.openai`
- `selectedModelByProvider.worker`

#### Make unavailable states explicit

If neither worker nor OpenAI is configured, do not silently create a provider pointed at the placeholder worker URL.

Instead:

- surface an unavailable assistant state in the panel
- return a clear runtime explanation

### Files To Change

- `leanring-buddy/CompanionManager.swift`
- `leanring-buddy/AppBundleConfiguration.swift`
- `leanring-buddy/Providers/Chat/ClickyChatProvider.swift`
- new factory file under `leanring-buddy/Providers/Chat/`
- `leanring-buddy/CompanionPanelView.swift`

### Success Criteria

- chat backend choice is obvious and deterministic
- OpenAI no longer feels like an awkward fallback inside Claude-shaped UI state
- adding another provider later does not require more type checks in `CompanionManager`

## Recommended Order

### Step 1

Implement Fix 1 first.

Reason:

- it restores the most important behavior contract immediately
- it reduces risk of incorrect pointing
- it simplifies reasoning about all later grounding work

### Step 2

Implement Fix 2 second.

Reason:

- once grounding precedence is clear, latency policy becomes easier to tune
- this step improves the actual voice UX

### Step 3

Implement Fix 3 last.

Reason:

- it is the cleanest improvement to the architecture but not the most urgent runtime risk
- it benefits from knowing whether the product will keep both worker and direct OpenAI paths long-term

## Suggested Verification

### Fix 1 Verification

- response with `[POINT:x,y:label]` lands exactly on the tagged coordinate
- response with `[POINT:none]` never triggers native or computer-use pointing
- response with no point tag can still use native fallback

### Fix 2 Verification

- speech begins promptly when native grounding misses
- computer-use fallback does not stall the entire interaction
- pointer can still arrive shortly after speech when fallback succeeds

### Fix 3 Verification

- panel shows the chosen backend clearly
- model selection persists correctly for the chosen backend
- unconfigured states fail clearly instead of trying the placeholder worker host

## Non-Goals

- do not redesign the collaborative UI architecture in this patch set
- do not replace the provider abstraction that was added in `e94b857`
- do not remove the worker-backed Claude path
- do not make direct OpenAI the production distribution security model by default

## Bottom Line

The provider and OpenAI refactor should be kept. The correction work is about making the behavior contract crisp again.

If these three fixes are applied, the new architecture will preserve the local-development benefits of the OpenAI path while restoring the predictability and responsiveness that the original Claude-based flow had.
