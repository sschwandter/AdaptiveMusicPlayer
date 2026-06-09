# Architecture Notes

This document is the authoritative architecture reference for Adaptive Music Player. The root `README.md` stays focused on project overview, setup, and links; implementation details for the app target, UI layer, and core framework live here.

At a high level, playback flows like this:

```text
ContentView
  -> AudioPlayer
  -> AudioPlayerSessionController
  -> AudioPlaybackEngine
  -> AVAudioPlayer / Core Audio
```

`ContentView` presents the macOS interface and forwards user actions as commands. `AudioPlayer` is the `@Observable` bridge used by SwiftUI. `AudioPlayerSessionController` owns app-level playback orchestration and updates a reducer-backed `AudioPlayerSessionState`. `AudioPlaybackEngine` owns the active `AVAudioPlayer` runtime and delegates focused work to engine operations and services.

## Targets

### AdaptiveMusicPlayer

`AdaptiveMusicPlayer/` contains the app shell and SwiftUI-facing playback layer.

Responsibilities:

- Create the macOS app scene and commands.
- Present playback state through SwiftUI.
- Route user intent as commands.
- Own app-level orchestration, UI-facing state, and presentation models.

Non-responsibilities:

- Direct `AVAudioPlayer` ownership.
- Core Audio hardware manipulation.
- Audio session creation and sample-rate switching rules.
- Playlist domain rules that can live independently of the UI.

### AdaptiveMusicPlayerCore

`AdaptiveMusicPlayerCore/` contains the playback framework used by the app target.

Responsibilities:

- Playback domain models and playlist rules.
- Event-driven playback engine behavior.
- Focused engine operations for loading, playback control, seeking, and sample-rate synchronization.
- System-facing audio services such as Core Audio sample-rate access, folder scanning, file loading, progress tracking, and security-scoped access.
- Shared utilities.

Non-responsibilities:

- SwiftUI view state.
- App menu command routing.
- User-facing presentation text and banner state.
- Window-scoped command focus.

## Current Structure

The project is organized by feature area under `Playback/`, with a small app shell under `AdaptiveMusicPlayer/App/`.

### App Layer

- `AdaptiveMusicPlayer/App/AdaptiveMusicPlayerApp.swift`
  Creates the single player `Window`, installs app commands, and owns the
  shared `AudioPlayer`. Because the player is app-scoped rather than
  window-scoped, playback continues when the window closes, and reopening it
  binds back to the live session state. The `Window` scene (instead of
  `WindowGroup`) means there is exactly one player window.
- `AdaptiveMusicPlayer/App/Commands/PlaybackCommands.swift`
  Defines menu items and keyboard shortcuts and dispatches them to the focused player scene.
- `AdaptiveMusicPlayer/Playback/UI/PlaybackCommandActions.swift`
  Defines the focused-value bridge used to expose window-local playback actions from `ContentView` to the app command layer.

### Playback UI Layer

- `AdaptiveMusicPlayer/Playback/UI/ContentView.swift`
  Main player interface. It binds to the app-owned `AudioPlayer` passed in by the app shell, presents file and folder importers, and publishes focused command actions for the active window.
- `AdaptiveMusicPlayer/Playback/UI/AudioPlayer.swift`
  Acts as the `@Observable` view model used by SwiftUI. It exposes projected UI state plus a single `send(_:)` command entry point for the view layer.

### UI Coordination

- `AdaptiveMusicPlayer/Playback/UI/Coordination/AudioPlayerSessionController.swift`
  Central app-level orchestrator for loading, playlist navigation, playback commands, startup cancellation, progress tracking, and hardware refresh.
- `AdaptiveMusicPlayer/Playback/UI/Coordination/AudioPlayerLoadCoordinator.swift`
  Manages file and folder loading with latest-request-wins behavior.
- `AdaptiveMusicPlayer/Playback/UI/Coordination/PlaybackStartupCoordinator.swift`
  Manages cancellable playback-start work, especially sample-rate synchronization before playback.
- `AdaptiveMusicPlayer/Playback/UI/Coordination/LatestAsyncRequestCoordinator.swift`
  Shared helper for replacing in-flight async work while suppressing stale results.

App-level playback rules are centered in the session controller. The engine remains a narrower runtime dependency rather than a second user-visible state owner.

### UI State And Presentation

- `AdaptiveMusicPlayer/Playback/UI/State/AudioPlayerSessionState.swift`
  Holds the authoritative UI-facing session state.
- `AdaptiveMusicPlayer/Playback/UI/State/AudioPlayerSessionReducer.swift`
  Applies app actions to the session state.
- `AdaptiveMusicPlayer/Playback/UI/State/AudioPlayerStateStore.swift`
  Stores session state and exposes presentation helpers to the rest of the UI layer.
- `AdaptiveMusicPlayer/Playback/UI/State/AudioPlayerCommand.swift`
  Defines the command set sent from SwiftUI into the session controller.
- `AdaptiveMusicPlayer/Playback/UI/State/AudioPlayerPresentationTypes.swift`
  Defines UI-facing presentation data types.
- `AdaptiveMusicPlayer/Playback/UI/Presentation/ContentViewStatePresenter.swift`
  Builds the main `ContentViewState` projection used by the view.
- `AdaptiveMusicPlayer/Playback/UI/Presentation/PlayerStatusPresenter.swift`
  Builds status and loading messages.
- `AdaptiveMusicPlayer/Playback/UI/Presentation/SampleRatePresenter.swift`
  Builds sample-rate diagnostics and banner state.
- `AdaptiveMusicPlayer/Playback/UI/Workflow/AudioPlayerHardwareMonitor.swift`
  Observes hardware changes and refreshes hardware state in the store.

### Core Domain

- `AdaptiveMusicPlayerCore/Playback/Domain/EnginePlaybackState.swift`
  Defines the engine's runtime state enum (`EnginePlaybackState`), `AudioInfo`, and typed `PlaybackError` values.
- `AdaptiveMusicPlayerCore/Playback/Domain/PlaybackPlaylist.swift`
  Defines playlist data structures used by folder-based playback.
- `AdaptiveMusicPlayerCore/Playback/Domain/PlaylistSession.swift`
  Tracks current playlist position and navigation rules.

### Core Engine

- `AdaptiveMusicPlayerCore/Playback/Engine/AudioPlaybackEngine.swift`
  Owns the underlying `AVAudioPlayer`, loads tracks, controls playback, synchronizes sample rates, and emits engine events.
- `AdaptiveMusicPlayerCore/Playback/Engine/Operations/LoadFileOperation.swift`
- `AdaptiveMusicPlayerCore/Playback/Engine/Operations/PlaybackControlOperation.swift`
- `AdaptiveMusicPlayerCore/Playback/Engine/Operations/SeekingOperation.swift`
- `AdaptiveMusicPlayerCore/Playback/Engine/Operations/SyncSampleRateOperation.swift`

The operation files hold smaller units of playback behavior, but the codebase is not a strict clean-architecture implementation. Important runtime behavior still lives in the engine, while app-level orchestration lives in the session controller and coordinators.

### Core Services

- `AdaptiveMusicPlayerCore/Playback/Services/AudioFileLoader.swift`
  Handles security-scoped file loading.
- `AdaptiveMusicPlayerCore/Playback/Services/AudioHardwareObserver.swift`
  Observes hardware changes so the UI can refresh device state.
- `AdaptiveMusicPlayerCore/Playback/Services/AudioPlaylistFolderScanner.swift`
  Scans folders for supported audio files.
- `AdaptiveMusicPlayerCore/Playback/Services/AudioSessionManager.swift`
  Creates `AVAudioPlayer` sessions and performs initial sample-rate configuration.
- `AdaptiveMusicPlayerCore/Playback/Services/FinderItemRevealer.swift`
  Opens Finder to reveal the current track or folder item.
- `AdaptiveMusicPlayerCore/Playback/Services/PlaybackProgressTracker.swift`
  Tracks playback progress and finish events.
- `AdaptiveMusicPlayerCore/Playback/Services/SampleRateManager.swift`
  Wraps Core Audio sample-rate queries and changes.
- `AdaptiveMusicPlayerCore/Playback/Services/ScopedFolderAccess.swift`
  Manages security-scoped folder access.

### Utilities

- `AdaptiveMusicPlayerCore/Utilities/TimeFormatter.swift`
  Formats playback times for display.

## Command Flow

Keyboard shortcuts and menu commands are defined at the app layer and routed through SwiftUI focused values. The active `ContentView` publishes a `PlaybackCommandActions` value, `PlaybackCommands` reads that focused value, and the selected action calls into `AudioPlayer`, which then sends a command to `AudioPlayerSessionController`.

This keeps command routing window-scoped instead of broadcasting process-wide actions.

## File Loading Flow

`ContentView` delegates file and folder selection results to `AudioPlayer`, which forwards them as commands. `AudioPlayerSessionController` asks `AudioPlayerLoadCoordinator` to start a new load, applies loading-state transitions through the reducer, performs asynchronous file loading or folder scanning, and updates `AudioPlayerSessionState` when the load completes.

Folder scanning runs off the main actor and uses latest-request-wins cancellation so stale scans cannot publish tracks after a newer request has taken over.

View-local interaction state such as importer presentation and slider editing remains in `ContentView`.

## Playback Flow

Playback commands pass through `AudioPlayer.send(_:)` into `AudioPlayerSessionController`.

- The controller starts playback through `PlaybackStartupCoordinator`.
- The startup coordinator handles cancellation and stale startup suppression.
- `AudioPlaybackEngine` performs the actual `AVAudioPlayer` and sample-rate work.
- `PlaybackProgressTracker` emits progress and finish events back through the engine event stream.
- The controller dispatches reducer actions into the state store.
- Presenters derive `ContentViewState` plus status/sample-rate UI from that state.

## Event Flow

The core engine communicates runtime changes through asynchronous events. The UI layer consumes those events and translates them into reducer actions rather than mutating presentation state directly from the engine.

```text
AudioPlaybackEngine
  -> EngineEvent stream
  -> AudioPlayerSessionController
  -> AudioPlayerSessionReducer
  -> AudioPlayerStateStore
  -> Presenters
  -> ContentView
```

This keeps the engine focused on playback runtime state and the app target focused on user-visible state.

## Design Principles

- Views send commands; they should not own playback rules.
- `AudioPlayerSessionState` is the authoritative UI-facing state.
- Reducer-style transitions are the default way to update UI-facing playback state.
- `AudioPlayerSessionController` owns app-level orchestration.
- `AudioPlaybackEngine` owns runtime playback, not app presentation.
- Async work should use explicit cancellation or latest-request-wins suppression when user intent can change quickly.
- Services and engine operations should stay narrow and focused.

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
