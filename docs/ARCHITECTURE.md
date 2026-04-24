# Architecture Notes

This document collects implementation details that are useful when working on the codebase but are too internal for the main project README.

At a high level, the app flows like this:

`ContentView` presents the macOS interface and forwards user actions as commands.
`AudioPlayer` is the `@Observable` bridge used by SwiftUI.
`AudioPlayerSessionController` owns app-level playback orchestration and updates a reducer-backed `AudioPlayerSessionState`.
`AudioPlaybackEngine` owns the active `AVAudioPlayer` runtime and delegates focused work to engine operations and services.

## Current Structure

The project is organized by feature area under `Playback/`, with a small app shell under `App/`.

### App Layer

- `AdaptiveMusicPlayer/App/AdaptiveMusicPlayerApp.swift`
  Creates the main `WindowGroup` and installs app commands.
- `AdaptiveMusicPlayer/App/Commands/PlaybackCommands.swift`
  Defines menu items and keyboard shortcuts and dispatches them to the focused player scene.
- `AdaptiveMusicPlayer/Playback/UI/PlaybackCommandActions.swift`
  Defines the focused-value bridge used to expose window-local playback actions from `ContentView` to the app command layer.

### Playback Domain

- `AdaptiveMusicPlayer/Playback/Domain/EnginePlaybackState.swift`
   Defines the engine's runtime state enum (`EnginePlaybackState`), `AudioInfo`, and typed `PlaybackError` values.
- `AdaptiveMusicPlayer/Playback/Domain/PlaybackPlaylist.swift`
  Defines playlist data structures used by folder-based playback.
- `AdaptiveMusicPlayer/Playback/Domain/PlaylistSession.swift`
  Tracks current playlist position and navigation rules.

### Playback Coordination

- `AdaptiveMusicPlayer/Playback/Engine/AudioPlaybackEngine.swift`
  Owns the underlying `AVAudioPlayer`, loads tracks, controls playback, synchronizes sample rates, and bridges progress events.
- `AdaptiveMusicPlayer/Playback/UI/AudioPlayer.swift`
  Acts as the `@Observable` view model used by SwiftUI. It exposes projected UI state plus a single `send(_:)` command entry point for the view layer.
- `AdaptiveMusicPlayer/Playback/UI/Coordination/AudioPlayerSessionController.swift`
  Central app-level orchestrator for loading, playlist navigation, playback commands, startup cancellation, progress tracking, and hardware refresh.
- `AdaptiveMusicPlayer/Playback/UI/Coordination/AudioPlayerLoadCoordinator.swift`
  Manages file and folder loading with latest-request-wins behavior.
- `AdaptiveMusicPlayer/Playback/UI/Coordination/PlaybackStartupCoordinator.swift`
  Manages cancellable playback-start work, especially sample-rate synchronization before playback.
- `AdaptiveMusicPlayer/Playback/UI/Coordination/LatestAsyncRequestCoordinator.swift`
  Shared helper for replacing in-flight async work while suppressing stale results.

App-level playback rules are centered in the session controller. The engine remains a narrower runtime dependency rather than a second user-visible state owner.

### Services

- `AdaptiveMusicPlayer/Playback/Services/AudioFileLoader.swift`
  Handles security-scoped file loading.
- `AdaptiveMusicPlayer/Playback/Services/AudioHardwareObserver.swift`
  Observes hardware changes so the UI can refresh device state.
- `AdaptiveMusicPlayer/Playback/Services/AudioPlaylistFolderScanner.swift`
  Scans folders for supported audio files.
- `AdaptiveMusicPlayer/Playback/Services/AudioSessionManager.swift`
  Creates `AVAudioPlayer` sessions and performs initial sample-rate configuration.
- `AdaptiveMusicPlayer/Playback/Services/PlaybackProgressTracker.swift`
  Tracks playback progress and finish events.
- `AdaptiveMusicPlayer/Playback/Services/SampleRateManager.swift`
  Wraps Core Audio sample-rate queries and changes.
- `AdaptiveMusicPlayer/Playback/Services/ScopedFolderAccess.swift`
  Manages security-scoped folder access.

### Operations

- `AdaptiveMusicPlayer/Playback/Engine/Operations/LoadFileOperation.swift`
- `AdaptiveMusicPlayer/Playback/Engine/Operations/PlaybackControlOperation.swift`
- `AdaptiveMusicPlayer/Playback/Engine/Operations/SeekingOperation.swift`
- `AdaptiveMusicPlayer/Playback/Engine/Operations/SyncSampleRateOperation.swift`

These files hold smaller units of playback behavior, but the codebase is not a strict clean-architecture implementation. Important orchestration still lives in the engine and the view model.

### UI State And Presentation

- `AdaptiveMusicPlayer/Playback/UI/State/AudioPlayerSessionState.swift`
  Holds the authoritative UI-facing session state.
- `AdaptiveMusicPlayer/Playback/UI/State/AudioPlayerSessionReducer.swift`
  Applies app actions to the session state.
- `AdaptiveMusicPlayer/Playback/UI/State/AudioPlayerStateStore.swift`
  Stores session state and exposes presentation helpers to the rest of the UI layer.
- `AdaptiveMusicPlayer/Playback/UI/State/AudioPlayerCommand.swift`
  Defines the command set sent from SwiftUI into the session controller.
- `AdaptiveMusicPlayer/Playback/UI/Presentation/ContentViewStatePresenter.swift`
  Builds the main `ContentViewState` projection used by the view.
- `AdaptiveMusicPlayer/Playback/UI/Presentation/PlayerStatusPresenter.swift`
  Builds status and loading messages.
- `AdaptiveMusicPlayer/Playback/UI/Presentation/SampleRatePresenter.swift`
  Builds sample-rate diagnostics and banner state.
- `AdaptiveMusicPlayer/Playback/UI/Workflow/AudioPlayerHardwareMonitor.swift`
  Observes hardware changes and refreshes hardware state in the store.

### UI

- `AdaptiveMusicPlayer/Playback/UI/ContentView.swift`
  Main player interface. It binds to `AudioPlayer`, presents the file importer, and publishes focused command actions for the active window.

### Utilities

- `AdaptiveMusicPlayer/Utilities/TimeFormatter.swift`
  Formats playback times for display.

## Command Flow

Keyboard shortcuts and menu commands are defined at the app layer and routed through SwiftUI focused values. The active `ContentView` publishes a `PlaybackCommandActions` value, `PlaybackCommands` reads that focused value, and the selected action calls into `AudioPlayer`, which then drives `AudioPlaybackEngine`.

This keeps command routing window-scoped instead of broadcasting process-wide actions.

## File Loading Flow

`ContentView` delegates file and folder selection results to `AudioPlayer`, which forwards them as commands. `AudioPlayerSessionController` asks `AudioPlayerLoadCoordinator` to start a new load, applies loading-state transitions through the reducer, performs asynchronous file loading or folder scanning, and updates `AudioPlayerSessionState` when the load completes.

Folder scanning runs off the main actor and uses latest-request-wins cancellation so stale scans cannot publish tracks after a newer request has taken over.

View-local interaction state such as importer presentation and slider editing still remains in `ContentView`.

## Playback Flow

Playback commands also pass through `AudioPlayer.send(_:)` into `AudioPlayerSessionController`.

- The controller starts playback through `PlaybackStartupCoordinator`.
- The startup coordinator handles cancellation and stale startup suppression.
- `AudioPlaybackEngine` performs the actual `AVAudioPlayer` and sample-rate work.
- `PlaybackProgressTracker` emits progress and finish events back to the controller.
- The controller dispatches reducer actions into the state store, and presenters derive `ContentViewState` plus status/sample-rate UI from that state.

## Testing Overview

For build and test commands, see the root README. This section only summarizes the current test coverage areas.

Tests live in:

- `AdaptiveMusicPlayerTests`
- `AdaptiveMusicPlayerUITests`

The unit tests currently cover:

- `AudioPlayer` behavior and user-visible workflows
- `AudioPlayerSessionReducer` and session-state transitions
- `AudioPlayerLoadCoordinator` and latest-request-wins loading behavior
- `PlaybackStartupCoordinator`
- `PlaybackControlOperation`
- `PlaybackProgressTracker`
- `AudioPlaybackEngine`
- Playlist and folder-scanning behavior
- Presentation helpers and sample-rate UI logic
- `SampleRateManager` helper logic
- `TimeFormatter`

Some behavior still depends on the runtime environment, especially hardware audio state. Tests should prefer injected doubles over assumptions about available devices or sample-rate information.
