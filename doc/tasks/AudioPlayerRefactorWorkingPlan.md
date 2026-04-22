# AudioPlayer Refactor Working Plan

This document is the working plan for reducing the size and responsibility of `AdaptiveMusicPlayer/Playback/UI/AudioPlayer.swift` without repeating the failed extraction attempt.

It is intended to be updated during implementation. Treat it as the source of truth for:

- target structure
- refactor sequencing
- invariants that must remain true
- open questions and follow-up work

## Goal

Make `AudioPlayer.swift` small enough to function as a facade instead of a god object.

The desired end state is:

- `AudioPlayer` remains the single `@Observable` type consumed by SwiftUI
- the current public API used by `ContentView` and tests remains stable while the refactor is in progress
- mutable UI state ownership is separated from orchestration logic
- load/playback/hardware workflows are separated into focused collaborators
- extracted presentation/state types do not depend on `AudioPlayer` as a namespace

## Non-Goals

These are explicitly out of scope for this refactor unless later added as separate tasks:

- redesigning the visible UI
- changing playback-engine responsibilities
- changing command routing between `ContentView` and app commands
- replacing existing coordinators that already have good test coverage unless needed for cleaner boundaries
- broad domain model changes outside the playback UI layer

## Current Problems

`AudioPlayer.swift` currently mixes too many responsibilities:

1. State type definitions
2. Mutable UI state ownership
3. Computed presentation accessors
4. File and folder loading orchestration
5. Playback startup and shutdown orchestration
6. Playlist navigation policy
7. Progress tracking callbacks
8. Hardware observation and refresh
9. Finder reveal behavior
10. Error and status transition policy

Some presentation logic has already been extracted successfully, but `AudioPlayer` still owns too many transition rules and too much mutable state.

## Constraints

The refactor should preserve these constraints:

- `ContentView` continues to talk to `AudioPlayer`, not a graph of smaller objects
- tests can keep targeting `AudioPlayer` as the public UI-facing entry point
- extracted helpers must not mutate `AudioPlayer` internals directly through hidden backdoors
- state transitions should remain typed and explicit
- no placeholder `AudioInfo` values are ever introduced
- autoplay intent must be passed explicitly through workflow boundaries
- behavior should remain stable after each step, not only at the end

## Failure Modes To Avoid

The previous split exposed the main design traps. Avoid these specifically:

### 1. Moving state types under a helper object namespace

Do not move `AudioPlayer` nested presentation types into another class such as `AudioPlayerViewModel` while the rest of the code still references `AudioPlayer.*`.

Preferred fix:

- move these types to top-level files
- update all call sites in one mechanical pass

### 2. Splitting by file count instead of responsibility

Do not extract classes that merely mirror sections of `AudioPlayer.swift` while still depending on broad mutable access to everything.

Preferred fix:

- separate state ownership from workflows
- separate workflows from pure presentation mapping

### 3. Recomputing intent from UI state

Do not derive autoplay intent or playback intent later from incidental state like `isPlaying`.

Preferred fix:

- carry intent explicitly as parameters and event payloads

### 4. Inventing placeholder state

Do not create fake `AudioInfo` values to satisfy APIs.

Preferred fix:

- preserve real audio info
- or keep state unchanged when no real audio info exists

## Target Architecture

### Public Surface

`AudioPlayer` remains the only UI-facing object used by SwiftUI.

Responsibilities of `AudioPlayer` in the target design:

- own dependency wiring
- expose stable public computed properties
- expose user intent methods such as `loadFile`, `togglePlayPause`, `stop`, `seek`, `skipForward`
- delegate state mutation and workflow logic to focused collaborators

`AudioPlayer` should not directly implement most state-transition details.

### State Layer

Introduce a dedicated state ownership layer for UI-facing playback state.

Proposed files:

- `Playback/UI/State/AudioPlayerScreenState.swift`
- `Playback/UI/State/AudioPlayerPresentationTypes.swift`
- `Playback/UI/State/AudioPlayerStateStore.swift`

`AudioPlayerStateStore` responsibilities:

- own `screenState`
- own `currentTime`
- own `displayTitlesByTrackURL`
- own `playlistSession`
- expose computed state used by `AudioPlayer`
- provide typed mutation methods for workflow code

The state store should be `@MainActor`.

### Workflow Layer

Create focused workflow types rather than generic helper classes.

Proposed files:

- `Playback/UI/Workflow/AudioPlayerLoadWorkflow.swift`
- `Playback/UI/Workflow/AudioPlayerPlaybackWorkflow.swift`
- `Playback/UI/Workflow/AudioPlayerHardwareMonitor.swift`

Responsibilities:

- `AudioPlayerLoadWorkflow`
  - begin loading
  - finish track loading
  - handle load coordinator events
  - playlist track selection
  - adjacent-track loading
  - startup cancellation when a new load begins

- `AudioPlayerPlaybackWorkflow`
  - start playback
  - pause
  - stop
  - startup event handling
  - progress tracking callbacks
  - playback-finished behavior
  - seek and skip operations
  - sample-rate sync action

- `AudioPlayerHardwareMonitor`
  - observe hardware changes
  - refresh hardware info
  - write device state into the state store

### Existing Coordinators

Keep these existing coordinator files:

- `Playback/UI/Coordination/AudioPlayerLoadCoordinator.swift`
- `Playback/UI/Coordination/PlaybackStartupCoordinator.swift`

They already encode useful async lifecycle behavior and should remain lower-level coordination helpers.

The new workflows should consume their typed events rather than replacing them immediately.

### Presentation Layer

Keep presentation mapping pure and top-level.

Existing files already aligned with this direction:

- `Playback/UI/Presentation/SampleRatePresenter.swift`
- `Playback/UI/Presentation/ContentViewStatePresenter.swift`
- `Playback/UI/Presentation/PlayerStatusPresenter.swift`
- `Playback/UI/Presentation/PlayerScreenStateReducer.swift`

Important design rule:

These files should depend on top-level state and presentation types, not on `AudioPlayer` as a namespace.

## Proposed End-State File Layout

```text
Playback/UI/
  AudioPlayer.swift
  ContentView.swift
  PlaybackCommandActions.swift
  Coordination/
    AudioPlayerLoadCoordinator.swift
    PlaybackStartupCoordinator.swift
  Presentation/
    ContentViewStatePresenter.swift
    PlayerScreenStateReducer.swift
    PlayerStatusPresenter.swift
    SampleRatePresenter.swift
  State/
    AudioPlayerPresentationTypes.swift
    AudioPlayerScreenState.swift
    AudioPlayerStateStore.swift
  Workflow/
    AudioPlayerHardwareMonitor.swift
    AudioPlayerLoadWorkflow.swift
    AudioPlayerPlaybackWorkflow.swift
```

## Refactor Strategy

Do the refactor in behavior-preserving passes. Each pass should leave the project compiling and tests running.

### Phase 1: Extract top-level state and presentation types

Objective:

- remove the large nested type block from `AudioPlayer.swift`
- keep behavior unchanged

Tasks:

- move nested state/presentation structs and enums to top-level files
- update all presentation and reducer files to reference the top-level types
- keep `AudioPlayer` storing the same state for now

Why first:

- it is the safest structural reduction
- it removes a large amount of file size immediately
- it prevents future helper classes from becoming accidental namespaces

Success criteria:

- no code depends on `AudioPlayer.SomeType`
- `AudioPlayer.swift` is smaller
- tests remain green

### Phase 2: Introduce `AudioPlayerStateStore`

Objective:

- centralize mutable UI state ownership

Tasks:

- create `AudioPlayerStateStore`
- move `screenState`, `currentTime`, `playlistSession`, and `displayTitlesByTrackURL` into it
- move computed accessors like `duration`, `isPlaying`, `currentFileName`, `fileSampleRate`, `hardwareSampleRate`
- move `applyStatusPresentation` and `applyScreenStateAction` into store methods
- have `AudioPlayer` forward public properties to the store

Why second:

- it creates a clear boundary for all remaining workflow extractions

Success criteria:

- `AudioPlayer` no longer mutates raw state directly
- state transitions happen through named store methods

### Phase 3: Extract load workflow

Objective:

- remove loading and playlist-load orchestration from `AudioPlayer`

Tasks:

- create `AudioPlayerLoadWorkflow`
- move:
  - `beginLoading`
  - `finishLoadingTrack`
  - `handleLoadEvent`
  - `moveToAdjacentTrack`
  - `selectPlaylistTrack` policy
- keep `AudioPlayerLoadCoordinator` as the async coordinator underneath
- pass autoplay intent explicitly through workflow methods

Why third:

- load behavior has a clean existing seam via coordinator events

Success criteria:

- `AudioPlayer` delegates load-related public methods to the workflow
- no direct loading-state mutation remains in `AudioPlayer`

### Phase 4: Extract playback workflow

Objective:

- remove startup, pause, stop, seek, skip, and progress tracking orchestration from `AudioPlayer`

Tasks:

- create `AudioPlayerPlaybackWorkflow`
- move:
  - `togglePlayPause`
  - `startPlayback`
  - `pause`
  - `stop`
  - `seek`
  - `skipForward`
  - `skipBackward`
  - `handlePlaybackStartupEvent`
  - `startProgressTracking`
  - `stopProgressTracking`
  - playback-finished handling
- keep `PlaybackStartupCoordinator` as the startup lifecycle helper

Why fourth:

- it depends on the state store and the existing startup coordinator

Success criteria:

- `AudioPlayer` delegates playback public methods to the workflow
- progress callbacks mutate state only through the store boundary

### Phase 5: Extract hardware monitor

Objective:

- remove hardware observation and refresh lifecycle from `AudioPlayer`

Tasks:

- create `AudioPlayerHardwareMonitor`
- move hardware observer startup logic out of `AudioPlayer.init`
- move `refreshHardwareInfo`
- let periodic refreshes and startup refreshes call the monitor

Success criteria:

- `AudioPlayer` no longer owns direct hardware observer callback logic

### Phase 6: Final facade cleanup

Objective:

- make `AudioPlayer.swift` read like a facade

Tasks:

- reduce `AudioPlayer.swift` to wiring, public properties, and public intent methods
- remove any remaining duplicated transition and error-presentation logic
- confirm all collaborators have tight ownership boundaries
- trim any facade-only adapter glue that exists only to translate between workflows

Success criteria:

- `AudioPlayer.swift` is roughly 120-180 lines
- responsibilities are obvious from file names and ownership

## Invariants To Check After Every Phase

These must remain true after each incremental step:

- no build errors from namespace moves
- no placeholder `AudioInfo` values
- Finder reveal still works
- selecting a playlist track during startup preserves autoplay intent
- stopping or loading a new file still cancels pending playback startup correctly
- sample-rate banner behavior is unchanged
- progress tracking still updates `currentTime`
- stale load and stale startup suppression still works

## Suggested Verification Matrix

Run targeted tests after each phase rather than waiting until the end.

Recommended suite slices:

- `AdaptiveMusicPlayerTests/AudioPlayerTests`
- `AdaptiveMusicPlayerTests/AudioPlayerFolderLoadingTests`
- `AdaptiveMusicPlayerTests/AudioPlayerLoadCoordinatorTests`
- `AdaptiveMusicPlayerTests/PlaybackStartupCoordinatorTests`
- `AdaptiveMusicPlayerTests/PlayerScreenStateReducerTests`
- `AdaptiveMusicPlayerTests/PlayerStatusPresenterTests`
- `AdaptiveMusicPlayerTests/ContentViewStatePresenterTests`
- `AdaptiveMusicPlayerTests/SampleRatePresenterTests`

After larger phases:

- run the full `AdaptiveMusicPlayerTests` target

## Working Task Board

Update this section during implementation.

### Backlog

- Decide whether sample-rate synchronization should remain in playback workflow or get its own action type
- Consider renaming `State` vs `Model` folder once the extraction settles

### In Progress

- Phase 6: Final facade cleanup
  Notes:
  - Phase 5 is complete and committed. Phase 6 is now limited to facade cleanup only.
  - Collapsed repeated load-time closure wiring behind a typed `AudioPlayerLoadWorkflow.Callbacks` bundle.
  - `AudioPlayer.swift` is down to 276 lines after the latest pass, but it has not reached the target size or boundary clarity yet.
  - Remaining responsibilities still under review in `AudioPlayer`:
    - duplicated error-presentation policy that is also implemented in playback workflow
    - direct access to playlist session only to support Finder reveal
    - adapter glue between load workflow and playback workflow (`loadWorkflowCallbacks`, `startPlaybackAfterLoad`, `loadAdjacentTrack`)
  - Next cleanup target:
    - move load-related error presentation out of `AudioPlayer`
    - remove the direct `playlistSession` proxy from `AudioPlayer` if Finder reveal can read from store or a tiny helper
    - evaluate whether workflow bridge closures should become a stored bridge/helper instead of facade-local glue
  - Focused verification remains green:
    `xcodebuild test -scheme AdaptiveMusicPlayer -destination 'platform=macOS' -only-testing:AdaptiveMusicPlayerTests/AudioPlayerTests -only-testing:AdaptiveMusicPlayerTests/AudioPlayerFolderLoadingTests -only-testing:AdaptiveMusicPlayerTests/AudioPlayerLoadCoordinatorTests -only-testing:AdaptiveMusicPlayerTests/PlaybackStartupCoordinatorTests -only-testing:AdaptiveMusicPlayerTests/ContentViewStatePresenterTests -only-testing:AdaptiveMusicPlayerTests/PlayerStatusPresenterTests -only-testing:AdaptiveMusicPlayerTests/SampleRatePresenterTests -only-testing:AdaptiveMusicPlayerTests/PlayerScreenStateReducerTests -derivedDataPath /tmp/AdaptiveMusicPlayerDerivedData`

### Deferred Decisions

- Decide whether `FinderItemRevealing` should stay on `AudioPlayer` or move to a tiny navigation helper once Phase 6 boundaries are finalized

### Done

- [x] Phase 1: Extract top-level state and presentation types
  Notes:
  - Moved the nested presentation and screen-state types out of `AudioPlayer.swift` into top-level files under `Playback/UI/State/`.
  - Updated `ContentView`, presenters, coordinators, and affected tests to reference the top-level types instead of `AudioPlayer.*`.
  - Kept `AudioPlayer` behavior unchanged; this step only removed namespace coupling and reduced file size.
  - Verified with:
    `xcodebuild test -scheme AdaptiveMusicPlayer -destination 'platform=macOS' -only-testing:AdaptiveMusicPlayerTests/AudioPlayerTests -only-testing:AdaptiveMusicPlayerTests/AudioPlayerFolderLoadingTests -only-testing:AdaptiveMusicPlayerTests/ContentViewStatePresenterTests -only-testing:AdaptiveMusicPlayerTests/PlayerStatusPresenterTests -only-testing:AdaptiveMusicPlayerTests/SampleRatePresenterTests -only-testing:AdaptiveMusicPlayerTests/PlayerScreenStateReducerTests -derivedDataPath /tmp/AdaptiveMusicPlayerDerivedData`

- [x] Phase 2: Introduce `AudioPlayerStateStore`
  Notes:
  - Added `Playback/UI/State/AudioPlayerStateStore.swift` and moved UI-facing mutable state ownership into it.
  - `AudioPlayer` now forwards `currentTime`, playlist session, display-title mapping, and computed playback/hardware state through the store.
  - Kept workflow logic in `AudioPlayer` for this phase so the change stayed behavioral and testable.
  - Verified with:
    `xcodebuild test -scheme AdaptiveMusicPlayer -destination 'platform=macOS' -only-testing:AdaptiveMusicPlayerTests/AudioPlayerTests -only-testing:AdaptiveMusicPlayerTests/AudioPlayerFolderLoadingTests -only-testing:AdaptiveMusicPlayerTests/ContentViewStatePresenterTests -only-testing:AdaptiveMusicPlayerTests/PlayerStatusPresenterTests -only-testing:AdaptiveMusicPlayerTests/SampleRatePresenterTests -only-testing:AdaptiveMusicPlayerTests/PlayerScreenStateReducerTests -derivedDataPath /tmp/AdaptiveMusicPlayerDerivedData`

- [x] Phase 3: Extract load workflow
  Notes:
  - Added `Playback/UI/Workflow/AudioPlayerLoadWorkflow.swift`.
  - Moved file/folder load orchestration, load-event handling, adjacent-track loading, playlist-track selection, load-cancellation handling, and ready-status updates out of `AudioPlayer`.
  - Kept `AudioPlayerLoadCoordinator` as the lower-level async coordinator underneath the workflow.
  - Preserved explicit autoplay intent by passing `shouldAutoplay` through the workflow boundary instead of recomputing it later.
  - Verified with:
    `xcodebuild test -scheme AdaptiveMusicPlayer -destination 'platform=macOS' -only-testing:AdaptiveMusicPlayerTests/AudioPlayerTests -only-testing:AdaptiveMusicPlayerTests/AudioPlayerFolderLoadingTests -only-testing:AdaptiveMusicPlayerTests/AudioPlayerLoadCoordinatorTests -only-testing:AdaptiveMusicPlayerTests/ContentViewStatePresenterTests -only-testing:AdaptiveMusicPlayerTests/PlayerStatusPresenterTests -only-testing:AdaptiveMusicPlayerTests/SampleRatePresenterTests -only-testing:AdaptiveMusicPlayerTests/PlayerScreenStateReducerTests -derivedDataPath /tmp/AdaptiveMusicPlayerDerivedData`

- [x] Phase 4: Extract playback workflow
  Notes:
  - Added `Playback/UI/Workflow/AudioPlayerPlaybackWorkflow.swift`.
  - Moved playback startup, pause, stop, seek, skip, sample-rate sync, progress tracking, and playback-finished behavior out of `AudioPlayer`.
  - Kept `PlaybackStartupCoordinator` as the startup lifecycle helper underneath the playback workflow.
  - Removed `@Observable` from `AudioPlayerStateStore` so `AudioPlayer` remains the only observable public surface, matching the plan recommendation.
  - Verified with:
    `xcodebuild test -scheme AdaptiveMusicPlayer -destination 'platform=macOS' -only-testing:AdaptiveMusicPlayerTests/AudioPlayerTests -only-testing:AdaptiveMusicPlayerTests/AudioPlayerFolderLoadingTests -only-testing:AdaptiveMusicPlayerTests/AudioPlayerLoadCoordinatorTests -only-testing:AdaptiveMusicPlayerTests/PlaybackStartupCoordinatorTests -only-testing:AdaptiveMusicPlayerTests/ContentViewStatePresenterTests -only-testing:AdaptiveMusicPlayerTests/PlayerStatusPresenterTests -only-testing:AdaptiveMusicPlayerTests/SampleRatePresenterTests -only-testing:AdaptiveMusicPlayerTests/PlayerScreenStateReducerTests -derivedDataPath /tmp/AdaptiveMusicPlayerDerivedData`

- [x] Phase 5: Extract hardware monitor
  Notes:
  - Added `Playback/UI/Workflow/AudioPlayerHardwareMonitor.swift`.
  - Moved hardware observer startup and hardware-info refresh logic out of `AudioPlayer` and into the dedicated monitor.
  - Updated load and playback workflows to request hardware refresh through an injected closure instead of depending on the hardware provider directly.
  - Verified with:
    `xcodebuild test -scheme AdaptiveMusicPlayer -destination 'platform=macOS' -only-testing:AdaptiveMusicPlayerTests/AudioPlayerTests -only-testing:AdaptiveMusicPlayerTests/AudioPlayerFolderLoadingTests -only-testing:AdaptiveMusicPlayerTests/AudioPlayerLoadCoordinatorTests -only-testing:AdaptiveMusicPlayerTests/PlaybackStartupCoordinatorTests -only-testing:AdaptiveMusicPlayerTests/ContentViewStatePresenterTests -only-testing:AdaptiveMusicPlayerTests/PlayerStatusPresenterTests -only-testing:AdaptiveMusicPlayerTests/SampleRatePresenterTests -only-testing:AdaptiveMusicPlayerTests/PlayerScreenStateReducerTests -derivedDataPath /tmp/AdaptiveMusicPlayerDerivedData`

## First Concrete Task

Next implementation target is Phase 6 only.

Implementation target:

- reduce `AudioPlayer.swift` to facade wiring, public properties, and public intent methods
- remove duplicated error-presentation policy from the facade
- remove or justify direct playlist-session access in the facade
- reduce workflow-to-workflow adapter glue that currently lives in private facade helpers

Do not broaden Phase 6 into domain changes outside the playback UI layer. Keep it focused on facade cleanup only.

## Open Questions

- Should `AudioPlayerStateStore` itself be `@Observable`, or should only `AudioPlayer` remain observable and forward properties from the store?
  Answer:
  keep only `AudioPlayer` as the observable public object during the refactor. `@Observable` was removed from `AudioPlayerStateStore` in Phase 4.

- Should adjacent-track autoplay live in load workflow or playback workflow?
  Answer:
  keep track-loading mechanics in load workflow and let playback workflow own only actual playback startup and progress.

- Should `synchronizeSampleRates()` be treated as playback workflow or hardware monitor behavior?
  Answer:
  keep it in playback workflow because it is initiated as a playback action and depends on loaded-file context. Implemented in Phase 4.

- Should Finder reveal stay as a facade responsibility or move behind a tiny helper/store accessor?
  Current leaning:
  keep the public intent on `AudioPlayer`, but avoid keeping raw playlist-session access on the facade just to resolve the current track URL.

- Should the load/playback bridge remain as callback closures on the facade or become a dedicated helper?
  Current leaning:
  the current callback bundle was a useful intermediate step, but Phase 6 should revisit whether a dedicated bridge/helper would make ownership clearer than private facade glue.

## Notes

When this plan changes, prefer editing this file rather than leaving important design decisions in chat history.
