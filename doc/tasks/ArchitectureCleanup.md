# Architecture Cleanup Plan

## Goal

Reduce the current architectural caveats by making ownership of playback state, loading state, and hardware state more explicit and easier to test.

The target outcome is:

- `ContentView` stays focused on rendering and short-lived UI interaction state.
- `AudioPlayer` becomes the single owner of screen-facing state and user workflows.
- `AudioPlaybackEngine` becomes a lower-level playback service instead of a second UI-visible state holder.
- Tests stop depending on real hardware behavior.

## Current Pain Points

### 1. Split playback coordination

Playback behavior is currently spread across:

- `AdaptiveMusicPlayer/Playback/UI/ContentView.swift`
- `AdaptiveMusicPlayer/Playback/UI/AudioPlayer.swift`
- `AdaptiveMusicPlayer/Playback/Engine/AudioPlaybackEngine.swift`

This makes it harder to answer simple questions like:

- Which layer owns the current loading state?
- Which layer is responsible for playlist navigation intent?
- Which layer should transition from loading to error?

### 2. Mixed state model

The screen behavior is derived from several parallel pieces of state:

- `playbackState`
- `hasError`
- `statusMessage`
- `playlistSession`
- async task references such as `loadingTask` and `playbackStartupTask`

That allows awkward combinations and makes regressions like “error shown while spinner keeps running” easier to introduce.

### 3. Runtime-dependent tests

`AudioPlayer` performs real hardware observation and queries during initialization. That makes unit tests less deterministic and caused CI failures when a virtual machine reported no usable hardware sample rate.

## Refactor Principles

### Single owner per concern

Each concern should have one obvious owner:

- playback session control
- loading workflow
- hardware diagnostics
- playlist/session navigation
- presentation state

### UI derives from explicit state

Spinner, error presentation, button enablement, and status text should derive from a structured model rather than from loosely coordinated flags.

### Unit tests should not depend on Core Audio

Hardware-dependent behavior should be fully replaceable with test doubles.

## Proposed End State

### ContentView

`ContentView` should keep only view-local interaction state, for example:

- importer presentation
- active import target
- slider editing progress
- purely visual local state if needed

`ContentView` should not own workflow decisions such as:

- how folder loading is sequenced
- when loading becomes error
- whether a selected track should autoplay

### AudioPlayer

`AudioPlayer` should become the single screen-facing coordinator:

- owns presentation state
- owns loading workflow
- owns playlist workflow
- owns playback intent
- maps engine/service results into UI state

It should expose a coherent model to the view instead of forcing the view to infer behavior from several separate flags.

### AudioPlaybackEngine

`AudioPlaybackEngine` should narrow toward low-level playback responsibilities:

- load prepared track into the playback backend
- play / pause / stop / seek
- synchronize hardware sample rate
- surface current engine state in a narrow, predictable way

It should avoid owning UI-facing concerns such as screen status text or higher-level workflow state.

## Proposed Steps

### Phase 1. Introduce an explicit screen state model

Create a structured screen-facing model inside `AudioPlayer`, for example:

- `PlaybackPresentationState`
- `LoadingState`
- `BannerState` or `StatusState`
- `PlaylistPresentationState`
- `HardwarePresentationState`

Possible shape:

```swift
struct PlayerScreenState {
    var playback: PlaybackPresentationState
    var loading: LoadingState
    var status: StatusState
    var playlist: PlaylistPresentationState
    var hardware: HardwarePresentationState
}
```

This phase should replace ad-hoc combinations such as:

- `hasError`
- `statusMessage`
- `playbackState.isLoading`

with a clearer representation.

Expected payoff:

- easier UI rendering
- fewer impossible state combinations
- clearer transitions for loading and error states

### Phase 2. Make AudioPlayer the workflow owner

Move workflow-level transitions fully into `AudioPlayer`:

- file load flow
- folder scan flow
- playlist setup
- autoplay after selection
- cancellation and generation handling

Keep `AudioPlaybackEngine` focused on low-level playback mechanics.

Expected payoff:

- one obvious place for behavior changes
- less ambiguity around who owns playback workflow
- easier debugging of state transitions

### Phase 3. Narrow engine state responsibilities

Review whether `AudioPlaybackEngine.state` should remain a broad enum or be simplified.

Options:

1. Keep engine state but make it backend-oriented only.
2. Replace it with narrower return values and let `AudioPlayer` own most presentation-oriented state.

Questions to answer during this phase:

- Should `.error` live in the engine or only in `AudioPlayer`?
- Should loading state exist in the engine, or only in the coordinator/view model?
- Can playlist/session state be fully removed from engine-adjacent flows?

Expected payoff:

- cleaner separation between backend playback and screen state

### Phase 4. Formalize dependency injection for hardware behavior

Make hardware behavior fully injectable:

- hardware observer
- hardware info provider
- sample-rate manager
- optional scheduler/clock for async waits

This may involve separating “observe hardware changes” from “fetch current hardware snapshot” into distinct protocols if that improves clarity.

Expected payoff:

- deterministic unit tests
- no reliance on VM/device audio configuration
- simpler CI behavior

### Phase 5. Tighten view boundaries

Keep only genuinely local state in `ContentView`.

Good candidates to remain local:

- importer sheet presentation
- transient slider editing state

Good candidates to route through `AudioPlayer` methods:

- imported file/folder handling
- seek completion behavior
- command routing intent

Expected payoff:

- thinner view
- less behavior hidden in SwiftUI closures

## Concrete First Tasks

These are the best low-risk starting points:

1. Introduce a dedicated loading/error presentation model in `AudioPlayer`.
2. Replace spinner/error derivation in `ContentView` with that new model.
3. Refactor folder loading to produce explicit outcomes:
   - scanning
   - empty folder
   - track ready
   - cancelled
   - failed
4. Add hardware-provider test doubles and migrate `AudioPlayerTests` away from real hardware assumptions.

## Non-Goals

To keep the cleanup focused, avoid doing these in the first pass:

- a full rewrite into “clean architecture”
- moving every single piece of state out of `ContentView`
- changing the visual design while refactoring architecture
- replacing working use cases unless they block clearer ownership

## Success Criteria

The cleanup is successful when:

- screen loading/error behavior is represented explicitly
- `AudioPlayer` is the obvious owner of user workflow state
- `AudioPlaybackEngine` is easier to describe as a lower-level service
- unit tests do not require real hardware sample-rate information
- contributors can tell where to add new behavior without reading three layers first
