# Architecture Cleanup Status

## Summary

The compat-first architecture cleanup is complete.

The original goals were to make ownership of playback state, loading state, and hardware state more explicit without forcing a large UI rewrite. That work is now in place:

- `AudioPlayer` is the single owner of screen-facing playback, loading, status, playlist, and hardware presentation state.
- `AudioPlaybackEngine` is narrowed to backend playback mechanics and no longer acts as the UI state model.
- `ContentView` reads from a thinner presentation surface instead of many loosely related `AudioPlayer` properties.
- hardware behavior is split into observation and info-provider dependencies and is fully testable with doubles.
- unit tests no longer depend on real machine audio hardware.

## Completed Work

### 1. Explicit screen-state model in `AudioPlayer`

Implemented in:

- `AdaptiveMusicPlayer/Playback/UI/AudioPlayer.swift`

Completed changes:

- added `PlayerScreenState`
- added explicit presentation types for playback, loading, status, playlist, and hardware
- moved `isLoading`, `hasError`, `statusMessage`, playlist helpers, and hardware display data to derive from that structured state

Result:

- spinner, error, ready, and playback presentation no longer depend on loosely coordinated flags

### 2. Workflow ownership moved into `AudioPlayer`

Implemented in:

- `AdaptiveMusicPlayer/Playback/UI/AudioPlayer.swift`

Completed changes:

- centralized file loading, folder scanning, prepared-track continuation, autoplay intent, and cancellation handling
- added explicit handling for outcomes such as:
  - scanning folder
  - loading track
  - cancelled load
  - failed load
  - playback start success
  - playback start failure

Result:

- workflow transitions are now readable in one place instead of being split across engine state and UI patch-up logic

### 3. Engine responsibilities narrowed

Implemented in:

- `AdaptiveMusicPlayer/Playback/Engine/AudioPlaybackEngine.swift`
- `AdaptiveMusicPlayer/Playback/UI/AudioPlayer.swift`

Completed changes:

- `AudioPlayer` no longer mirrors `engine.state` as its presentation model
- playback presentation transitions are driven explicitly in `AudioPlayer`
- engine operations now return concrete backend results:
  - `beginLoading() -> AudioInfo?`
  - `play() async throws -> AudioInfo`
  - `pause() throws -> AudioInfo`
  - `stop() -> AudioInfo?`
  - `markFinished() -> AudioInfo?`

Result:

- `AudioPlaybackEngine` remains stateful internally, but that state is now a backend detail rather than the source of screen behavior

### 4. Hardware behavior formalized for tests

Implemented in:

- `AdaptiveMusicPlayer/Playback/Services/AudioHardwareObserver.swift`
- `AdaptiveMusicPlayerTests/TestSupport/PlaybackTestDoubles.swift`
- `AdaptiveMusicPlayerTests/AudioPlayerTests.swift`

Completed changes:

- split hardware responsibilities into:
  - `AudioHardwareObserving`
  - `AudioHardwareInfoProviding`
- updated `AudioPlayer` to accept both dependencies
- introduced deterministic hardware doubles for tests

Result:

- `AudioPlayerTests` no longer assume real hardware sample-rate/device information exists
- CI runs are safe on virtual machines and hardware-limited environments

### 5. View boundary tightened without redesign

Implemented in:

- `AdaptiveMusicPlayer/Playback/UI/AudioPlayer.swift`
- `AdaptiveMusicPlayer/Playback/UI/ContentView.swift`

Completed changes:

- added `contentViewState` presentation data to `AudioPlayer`
- moved `ContentView` reads onto that state for:
  - header/file display
  - activity indicator
  - slider enablement and opacity
  - transport-button availability and labels
  - playlist browser visibility and row source

Result:

- `ContentView` still owns local UI state like importer presentation and slider editing, but no longer reaches into a wide scatter of playback and workflow properties

## Regression Coverage Added

Covered by unit tests:

- empty folder shows an error and stops loading
- cancelling folder scanning clears stale loading UI
- selecting a playlist track during startup preserves autoplay intent
- playback-start failure does not leave loading active
- playback-start failure preserves the loaded file presentation
- initial `AudioPlayer` state works when hardware info is unavailable
- engine playback tests verify concrete return values as well as sample-rate behavior

Primary test targets:

- `AdaptiveMusicPlayerTests/AudioPlayerTests.swift`
- `AdaptiveMusicPlayerTests/AudioPlayerFolderLoadingTests.swift`
- `AdaptiveMusicPlayerTests/AudioPlaybackEngineTests.swift`

## Remaining Opportunities

The original cleanup plan is complete. Any further work is optional follow-on refinement.

Good next opportunities:

1. Add a small integration/UI test layer for importer and command routing behavior if macOS UI test stability is acceptable.
2. Consider whether `AudioPlaybackEngine.state` still needs to remain publicly readable for tests, or whether a narrower inspection API would be cleaner.
3. If the app grows, consider splitting `AudioPlayer` into:
   - a presentation-facing observable type
   - a lower-level workflow coordinator
   but only if new features start making `AudioPlayer` too broad.

## Success Criteria Review

The cleanup goals are satisfied:

- screen loading/error behavior is represented explicitly
- `AudioPlayer` is the obvious owner of user workflow state
- `AudioPlaybackEngine` is easier to describe as a lower-level service
- unit tests do not require real hardware sample-rate information
- contributors can now find most behavior changes in one main place
