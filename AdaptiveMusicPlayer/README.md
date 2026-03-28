# Adaptive Music Player

Adaptive Music Player is a macOS audio player focused on sample-rate-aware playback. It loads local audio files, displays both file and hardware sample rates, and attempts to switch the system output rate to match the file for bit-perfect playback when possible.

## What It Does

- Plays local audio files with `AVAudioPlayer`
- Shows playback progress, volume, and transport controls
- Displays file sample rate and current hardware sample rate
- Attempts automatic hardware sample-rate switching through Core Audio
- Exposes keyboard shortcuts for open, play/pause, stop, and skipping

## Current Structure

The project is organized by feature area under `Playback/`, with a lightweight app shell under `App/`.

### App Layer

- `AdaptiveMusicPlayerApp.swift`
  Creates the main `WindowGroup` and installs app commands.
- `PlaybackCommands.swift`
  Defines menu items and keyboard shortcuts.
- `PlaybackNotifications.swift`
  Uses `NotificationCenter` names to route commands from the app layer into the main view.

### Playback Domain

- `PlaybackState.swift`
  Defines the playback state enum, `AudioInfo`, and typed `PlaybackError` values.

### Playback Coordination

- `AudioPlaybackEngine.swift`
  Owns the underlying `AVAudioPlayer`, coordinates use cases, and is the main stateful playback coordinator.
- `AudioPlayer.swift`
  Acts as the `@Observable` view model used by SwiftUI. It translates engine state into UI-facing properties and user-facing status messages.

### Services

- `AudioFileLoader.swift`
  Handles security-scoped file loading.
- `AudioSessionManager.swift`
  Creates `AVAudioPlayer` sessions and performs initial sample-rate configuration.
- `PlaybackProgressTracker.swift`
  Tracks playback progress and finish events.
- `SampleRateManager.swift`
  Wraps Core Audio sample-rate queries and changes.

### Use Cases

- `LoadFileUseCase.swift`
- `PlaybackControlUseCase.swift`
- `SeekingUseCase.swift`
- `SyncSampleRateUseCase.swift`

These files hold smaller units of playback behavior, but the codebase is not a strict clean-architecture implementation. The engine and view model still contain important orchestration logic.

### UI

- `ContentView.swift`
  Main player interface.

### Utilities

- `TimeFormatter.swift`
  Formats playback times for display.

## Command Flow

Keyboard shortcuts and menu commands are defined at the app layer and currently routed to `ContentView` through `NotificationCenter`. `ContentView` forwards those actions to `AudioPlayer`, which then drives `AudioPlaybackEngine`.

This works for the current app, but it is worth knowing that command routing is global rather than window-scoped.

## Sample Rate Behavior

When a file is loaded, the app reads the file sample rate from the prepared `AVAudioPlayer` and tries to set the default output device to the same nominal rate. If that fails, playback still proceeds and the UI shows that the hardware and file rates differ.

The UI uses:

- Green indicator when hardware and file sample rates are effectively aligned
- Orange indicator when playback is likely being resampled
- A manual sync button when a mismatch is detected

## Supported Formats

The app relies on system audio support through `AVAudioPlayer` / Core Audio. In practice, that includes common formats such as:

- MP3
- WAV
- AIFF
- AAC / M4A
- Other formats supported by the current macOS audio stack

## Tests

Tests live in:

- `AdaptiveMusicPlayerTests`
- `AdaptiveMusicPlayerUITests`

The unit tests currently cover:

- Basic `AudioPlayer` behavior
- `PlaybackControlUseCase`
- `PlaybackProgressTracker`
- `SampleRateManager` helper logic
- `TimeFormatter`

Run unit tests with:

```sh
xcodebuild test -scheme AdaptiveMusicPlayer -destination 'platform=macOS' -only-testing:AdaptiveMusicPlayerTests
```

UI tests exist, but command-line execution may depend on the local environment and permissions available to the test runner.

## Requirements

- macOS
- Xcode with current macOS SDK support

The project currently targets modern macOS SDKs configured in the Xcode project.

## Notes

- The codebase aims for clear separation of concerns, but some state and orchestration are still split between the engine, the view model, and the view.
- The README is intended to describe the code as it exists today, not an idealized future architecture.
