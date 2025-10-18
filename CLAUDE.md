# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Adaptive Music Player is a macOS audio player application built with SwiftUI that provides bit-perfect audio playback by automatically adapting the system's sample rate to match audio files.

**Swift 6 Compliant**: This codebase is fully refactored for Swift 6 strict concurrency checking with modern patterns.

## Build and Test Commands

### Building
```bash
# Build the project
xcodebuild -project AdaptiveMusicPlayer.xcodeproj -scheme AdaptiveMusicPlayer build

# Build and run (or use ⌘R in Xcode)
xcodebuild -project AdaptiveMusicPlayer.xcodeproj -scheme AdaptiveMusicPlayer build run
```

### Testing
```bash
# Run all tests
xcodebuild test -project AdaptiveMusicPlayer.xcodeproj -scheme AdaptiveMusicPlayer

# Run tests in Xcode: ⌘U
```

The project uses Swift Testing framework (not XCTest). Tests are located in:
- `AdaptiveMusicPlayer/AdaptiveMusicPlayerTestsAudioPlayerTests.swift` - Main test suite
- `AdaptiveMusicPlayerTests/` - Additional test targets

## Architecture

### Core Components

**AudioPlayer** (`AudioPlayer.swift`)
- `@MainActor @Observable` class managing all audio playback state
- Uses modern Observation framework (not ObservableObject/Combine)
- Conforms to `@unchecked Sendable` for Swift 6 concurrency safety
- Built on AVAudioEngine + AVAudioPlayerNode for low-level control
- Handles automatic sample rate switching via Core Audio APIs
- Key responsibilities:
  - Async file loading with task cancellation support
  - Security-scoped resource access for file operations
  - Sample rate detection and hardware switching (`setSystemSampleRate`, `getSupportedSampleRates`)
  - Playback control (play/pause/stop/seek)
  - Timer-based progress tracking (100ms intervals)
  - Structured error handling
- Note: Does NOT use AVAudioSession (iOS-only API not available on macOS)

**ContentView** (`ContentView.swift`)
- SwiftUI interface following MVVM pattern
- `@State` property for AudioPlayer (Observation framework pattern)
- Keyboard shortcuts handled via NotificationCenter + hidden Button workaround
- Custom View extensions for keyboard handling (`onKeyDown`, `onDrag`, `onRelease`)
- Loading states disable UI interactions to prevent race conditions
- Async file loading with proper Task handling

**AdaptiveMusicPlayerApp** (`AdaptiveMusicPlayerApp.swift`)
- App entry point with window configuration
- Global keyboard shortcuts via CommandGroup
- NotificationCenter-based event dispatch to bridge menu commands to ContentView

### Critical Design Patterns

**Thread Safety (Swift 6 Strict Concurrency)**
- Class is `@MainActor` ensuring all methods/properties run on main thread
- Uses `@Observable` macro (Swift 5.9+) instead of ObservableObject for better performance
- Conforms to `@unchecked Sendable` - safe due to MainActor isolation
- **No `nonisolated(unsafe)`** - all concurrency is properly checked
- **No unnecessary `MainActor.run`** - methods already MainActor-isolated
- Async/await patterns throughout for file operations
- Task cancellation support via `loadingTask` property
- Weak self captures in AVFoundation callbacks with proper guard checks
- No deinit needed - Swift 6 prevents accessing MainActor properties from nonisolated deinit

**Sample Rate Management**
- File sample rate detected from AVAudioFile's `processingFormat.sampleRate`
- Hardware sample rate queried via Core Audio `kAudioDevicePropertyNominalSampleRate`
- Automatic switching attempts to set hardware to match file, falls back gracefully with warning
- Hardware sample rate updated:
  - After loading a file (with 0.5 second delay for hardware to switch)
  - When playback starts
  - Every 2 seconds during playback (via timer polling)
- Visual feedback: green = matched (bit-perfect), orange = mismatched (resampling), dash = no file

**State Synchronization**
- Slider dragging uses local `@State` (`isDraggingSlider`, `sliderValue`) to prevent seek-during-drag issues
- Loading state (`isLoading`) disables all controls to prevent concurrent operations
- Interruption handling preserves play state (`wasPlayingBeforeInterruption`) for auto-resume

**Seeking Implementation**
- Always stops player node, schedules new segment from target frame position
- Clamps time values to `0...duration` to prevent crashes
- Resumes playback if `wasPlaying` flag is true
- Skip forward/backward use same mechanism with ±10 second offsets

**File Loading and Playback Scheduling**
- **Async file loading** with `loadFile(url:) async` method
- **Task cancellation**: Loading new file cancels previous load operation
- Cancellation checks at key points (`Task.isCancelled`) to abort early
- When loading, `audioFile` is set to nil first to prevent old file playback
- All scheduling happens at playback time (play/seek/skip), not pre-scheduled in stop()
- Each play operation schedules the current `audioFile` fresh to avoid stale buffers
- `stop()` only stops the player node without rescheduling
- Proper error handling with `CancellationError` caught separately

### File Structure

```
AdaptiveMusicPlayer/
├── AdaptiveMusicPlayerApp.swift       # App entry, global commands
├── AudioPlayer.swift                  # Core audio engine logic
├── ContentView.swift                  # Main UI
├── AdaptiveMusicPlayerTestsAudioPlayerTests.swift  # Test suite
└── README.md                          # User documentation

AdaptiveMusicPlayerTests/
└── AdaptiveMusicPlayerTests.swift     # Additional tests

AdaptiveMusicPlayerUITests/
└── UI test targets
```

## Key Technical Constraints

- **macOS 13.0+ only** - macOS-specific APIs (no iOS AVAudioSession)
- **Swift 6.0+ Strict Concurrency** - Fully compliant with Swift 6 concurrency checking
  - All `@MainActor` methods must be called from main thread
  - Cannot call actor-isolated methods or create Tasks in deinit
  - **No `nonisolated(unsafe)` used** - proper actor isolation throughout
  - Uses `@Observable` instead of ObservableObject for modern SwiftUI
  - Task cancellation support with structured concurrency
- **No external dependencies** - Pure Apple frameworks (AVFoundation, Core Audio, SwiftUI, Observation)
- **Security-scoped resources** - All file access must call `startAccessingSecurityScopedResource()` / `stopAccessingSecurityScopedResource()`
- **Sample rate switching** - Not all audio interfaces support all rates; verify with `getSupportedSampleRates()` before setting

## Testing Notes

- Tests use `@MainActor` annotations due to AudioPlayer being MainActor-isolated
- File loading tests require async waits (`Task.sleep`) for state propagation
- `ContentView.timeString` is duplicated in extension for testing access (private methods not testable)
- Invalid file loading should set `hasError = true` and populate `statusMessage`

## Common Modification Patterns

**Adding new playback controls**
1. Add published property to AudioPlayer if needed
2. Implement method in AudioPlayer (must be `@MainActor`)
3. Add UI button/control in ContentView
4. Add keyboard shortcut in AdaptiveMusicPlayerApp CommandGroup
5. Add NotificationCenter observer in ContentView if global command

**Modifying sample rate logic**
- Core Audio code is in `setSystemSampleRate()` and `updateHardwareSampleRate()`
- Always check supported rates before setting to avoid `kAudioHardwareUnspecifiedError`
- Add delay after setting rate (`Task.sleep`) before reading back hardware rate

**Error handling**
- Set `hasError = true` for critical errors (file loading, engine start)
- Set `hasError = false` for warnings (sample rate mismatch)
- Always populate `statusMessage` with user-friendly description
- Clear loading state (`isLoading = false`) in all error/success paths
