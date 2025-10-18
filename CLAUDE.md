# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Adaptive Music Player is a macOS audio player application built with SwiftUI that provides bit-perfect audio playback by automatically adapting the system's sample rate to match audio files.

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
- `@MainActor` observable object managing all audio playback state
- Built on AVAudioEngine + AVAudioPlayerNode for low-level control
- Handles automatic sample rate switching via Core Audio APIs
- Key responsibilities:
  - Audio file loading with security-scoped resource access
  - Sample rate detection and hardware switching (`setSystemSampleRate`, `getSupportedSampleRates`)
  - Playback control (play/pause/stop/seek)
  - Timer-based progress tracking (100ms intervals)
  - Error state management with user-friendly messages
- Note: Does NOT use AVAudioSession (iOS-only API not available on macOS)

**ContentView** (`ContentView.swift`)
- SwiftUI interface following MVVM pattern
- `@StateObject` owns AudioPlayer instance
- Keyboard shortcuts handled via NotificationCenter + hidden Button workaround
- Custom View extensions for keyboard handling (`onKeyDown`, `onDrag`, `onRelease`)
- Loading states disable UI interactions to prevent race conditions

**AdaptiveMusicPlayerApp** (`AdaptiveMusicPlayerApp.swift`)
- App entry point with window configuration
- Global keyboard shortcuts via CommandGroup
- NotificationCenter-based event dispatch to bridge menu commands to ContentView

### Critical Design Patterns

**Thread Safety**
- All AudioPlayer methods are `@MainActor` to ensure UI updates happen on main thread
- Async file loading with `Task` and `await MainActor.run` for state updates
- Weak self captures in timer callbacks and completion handlers to prevent retain cycles

**Sample Rate Management**
- File sample rate detected from AVAudioFile's `processingFormat.sampleRate`
- Hardware sample rate queried via Core Audio `kAudioDevicePropertyNominalSampleRate`
- Automatic switching attempts to set hardware to match file, falls back gracefully with warning
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

- **macOS 13.0+ only** - Uses AVAudioSession APIs
- **Swift 6.0+** - Strict concurrency checking with `@MainActor`
- **No external dependencies** - Pure Apple frameworks (AVFoundation, Core Audio, SwiftUI)
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
