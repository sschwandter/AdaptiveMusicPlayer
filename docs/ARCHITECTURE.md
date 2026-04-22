# Architecture Notes

This document collects implementation details that are useful when working on the codebase but are too internal for the main project README.

At a high level, the app flows like this:

`ContentView` presents the macOS interface and forwards user actions to `AudioPlayer`.
`AudioPlayer` owns UI-facing state, async loading, playlist coordination, and hardware refresh behavior.
`AudioPlaybackEngine` owns the active playback session and delegates focused operations to use cases and services.
Use cases and services wrap lower-level playback, file-loading, seeking, progress, playlist, and Core Audio behavior.

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
  Owns the underlying `AVAudioPlayer`, coordinates use cases, and is the main stateful playback coordinator.
- `AdaptiveMusicPlayer/Playback/UI/AudioPlayer.swift`
  Acts as the `@Observable` view model used by SwiftUI. It exposes UI-facing playback state, status/error text, hardware diagnostics, playlist state, and asynchronous load orchestration for the view.

Playback coordination is intentionally split between the engine and the view model rather than centered in a single orchestration layer. The engine owns the active playback session and lower-level transitions, while the view model owns UI-facing state and higher-level loading and playlist behavior.

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

`ContentView` delegates file and folder selection results to `AudioPlayer`. The view model moves into loading state, coordinates any short importer-dismissal delay, performs asynchronous loading or folder scanning work, and then updates the engine-backed playback state for the UI.

This keeps the UI-facing loading contract in one place instead of splitting it between the view and lower-level playback services, although a small amount of view-local interaction state still remains in `ContentView`, such as importer presentation and slider editing state.

## Testing Overview

For build and test commands, see the root README. This section only summarizes the current test coverage areas.

Tests live in:

- `AdaptiveMusicPlayerTests`
- `AdaptiveMusicPlayerUITests`

The unit tests currently cover:

- Basic `AudioPlayer` behavior
- `PlaybackControlOperation`
- `PlaybackProgressTracker`
- `SampleRateManager` helper logic
- `TimeFormatter`

Some behavior still depends on the runtime environment, especially hardware audio state. Tests should prefer injected doubles over assumptions about available devices or sample-rate information.
