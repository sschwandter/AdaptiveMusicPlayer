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

The app follows a **Domain Model + ViewModel** pattern with clear layered architecture:

### Domain Layer (Business Logic)

**PlaybackState** (`PlaybackState.swift`) - Explicit state machine with business rules:
- States: `.idle`, `.loading`, `.ready`, `.playing`, `.paused`, `.finished`, `.error`
- State queries: `canPlay`, `canPause`, `canSeek`, `isPlaying`, `audioInfo`
- Enforces valid state transitions
- No presentation concerns - pure business logic

**AudioInfo** (`PlaybackState.swift`) - Domain data with business rules:
- File metadata (name, duration, sample rate)
- Business logic: `clampSeekTime()`, `skipForward()`, `skipBackward()`
- Value type ensuring immutability

**PlaybackError** (`PlaybackState.swift`) - Typed domain errors:
- `.notReady`, `.noFileLoaded`, `.alreadyPlaying`, `.notPlaying`, `.loadingCancelled`, `.loadFailed(String)`
- Conforms to `LocalizedError` for user-friendly messages

### Business Logic Layer

**AudioPlaybackEngine** (`AudioPlaybackEngine.swift`) - Core playback logic (`@MainActor`):
- Manages `PlaybackState` transitions
- Enforces business rules (can't play when not ready, etc.)
- Returns domain results (`AudioInfo`), throws domain errors (`PlaybackError`)
- Delegates to infrastructure layer for file loading and sample rate management
- Owns `AVAudioPlayer` instance
- No presentation concerns - doesn't know about UI

### Infrastructure Layer

**AudioSessionManager** (`AudioSessionManager.swift`) - Creates complete audio sessions:
- Protocol: `AudioSessionManaging`
- Coordinates file loading, player creation, hardware configuration
- Returns `AudioSession` with ready-to-play `AVAudioPlayer`
- Handles security-scoped file access

**AudioFileLoader** (`AudioFileLoader.swift`) - Security-scoped file loading:
- Protocol: `AudioFileLoading`
- Handles sandbox permissions via `startAccessingSecurityScopedResource()`
- Loads files asynchronously with cancellation support
- Extracts audio metadata (sample rate, duration)

**SampleRateManager** (`SampleRateManager.swift`) - Core Audio hardware control:
- Protocol: `SampleRateManaging`
- Implementation: `CoreAudioSampleRateManager`
- Detects file sample rates from audio files
- Switches hardware sample rate via Core Audio APIs (`kAudioDevicePropertyNominalSampleRate`)
- Queries supported sample rates

**PlaybackProgressTracker** (`PlaybackProgressTracker.swift`) - Efficient progress monitoring:
- Protocol: `PlaybackProgressTracking`
- Timer-based progress updates (100ms intervals)
- `AVAudioPlayerDelegate` for finish detection (no polling overhead)
- Periodic callbacks for hardware sample rate display (2s intervals)

### Presentation Layer

**AudioPlayer** (`AudioPlayer.swift`) - Presentation logic (`@MainActor`, `@Observable`):
- ViewModel that owns `AudioPlaybackEngine`
- Translates domain state → UI properties (`statusMessage`, `hasError`, `isLoading`)
- Centralizes status messages in `updateStatus()` method
- Derives `isLoading` from `currentStatus: StatusEvent` (single source of truth)
- Coordinates between domain and view
- Uses modern Observation framework (not ObservableObject/Combine)
- Conforms to `@unchecked Sendable` for Swift 6 concurrency safety

**ContentView** (`ContentView.swift`) - SwiftUI interface:
- Reactive UI updates via Observation framework
- `@State` property for AudioPlayer
- Keyboard shortcuts handled via NotificationCenter + hidden Button workaround
- Custom View extensions for keyboard handling (`onKeyDown`)
- File selection via `fileImporter`
- Calls `setLoadingState()` synchronously before async file loading for instant UI feedback
- Real-time status display with color-coded sample rate matching

**AdaptiveMusicPlayerApp** (`AdaptiveMusicPlayerApp.swift`)
- App entry point with window configuration
- Global keyboard shortcuts via CommandGroup
- NotificationCenter-based event dispatch to bridge menu commands to ContentView

### Key Design Patterns

**Domain Model + ViewModel** - Clear separation of "what can happen" (domain) vs "how to show it" (presentation):
- Domain layer defines business rules, state machine, errors
- Business logic layer enforces rules and orchestrates domain operations
- Infrastructure layer handles external systems (files, audio hardware)
- Presentation layer translates domain state to UI properties

**Protocol-Oriented Design** - All dependencies injectable via protocols:
- `AudioSessionManaging` - Session creation protocol
- `AudioFileLoading` - File loading protocol
- `SampleRateManaging` - Sample rate control protocol
- `PlaybackProgressTracking` - Progress monitoring protocol
- Enables testing with mock implementations

**Swift 6 Strict Concurrency**:
- `@MainActor` on AudioPlayer, AudioPlaybackEngine ensuring all methods/properties run on main thread
- Uses `@Observable` macro (Swift 5.9+) instead of ObservableObject for better performance
- Conforms to `@unchecked Sendable` - safe due to MainActor isolation
- **No `nonisolated(unsafe)`** - all concurrency is properly checked
- **No unnecessary `MainActor.run`** - methods already MainActor-isolated
- Async/await patterns throughout for file operations
- Task cancellation support via `loadingTask` property
- Weak self captures in callbacks with proper guard checks
- No deinit needed - Swift 6 prevents accessing MainActor properties from nonisolated deinit

**Derived State Pattern** - Single source of truth:
- `currentStatus: StatusEvent` is the sole stored presentation state
- `isLoading` is computed: `if case .loading = currentStatus { return true }`
- `updateStatus()` sets `currentStatus` first, then derives all UI properties
- Pattern matching on state: `if case .loading = currentStatus`
- Prevents state synchronization bugs

**Observation Framework** - Modern reactive UI (not ObservableObject/Combine):
- `@Observable` macro for automatic property observation
- SwiftUI views update automatically when observed properties change
- More efficient than Combine-based updates

**Delegate Pattern** - Efficient playback finish detection:
- `AVAudioPlayerDelegate` for `audioPlayerDidFinishPlaying`
- Eliminates polling overhead for completion detection
- Timer only updates progress, not state

**Error Handling** - Typed domain errors with user-friendly presentation:
- `PlaybackError` enum with specific cases
- Domain layer throws typed errors
- Presentation layer translates to `statusMessage` and `hasError` flag

**Sample Rate Management**:
- File sample rate detected by `AudioFileLoader` from audio file metadata
- Hardware sample rate queried via Core Audio `kAudioDevicePropertyNominalSampleRate`
- Automatic switching by `SampleRateManager` to match file
- Hardware sample rate updated:
  - After loading a file
  - When playback starts
  - Periodically during playback (via `PlaybackProgressTracker` callbacks)
- Visual feedback: green = matched (bit-perfect), orange = mismatched (resampling), dash = no file

**State Synchronization**:
- Slider dragging uses local `@State` (`isEditingSlider`, `sliderPosition`) to prevent seek-during-drag issues
- Loading state (`isLoading`) disables all controls to prevent concurrent operations
- `setLoadingState()` called synchronously in ContentView before async work for instant UI feedback

**File Loading Pattern**:
- **Instant UI feedback**: `setLoadingState()` called synchronously before `Task` creation
- **Async file loading**: `loadFile(url:) async` method delegates to `AudioPlaybackEngine`
- **Task cancellation**: Loading new file cancels previous load operation via `loadingTask?.cancel()`
- Cancellation checks at key points (`Task.isCancelled`) to abort early
- Proper error handling with `CancellationError` caught separately
- Infrastructure layer handles security-scoped resource access

**Seeking Implementation**:
- Business logic in `AudioInfo`: `clampSeekTime()`, `skipForward()`, `skipBackward()`
- Engine validates state with `state.canSeek` before allowing seeks
- Player's `currentTime` property updated directly
- Skip forward/backward use domain logic with ±10 second intervals

### File Structure

```
AdaptiveMusicPlayer/
├── App/
│   └── AdaptiveMusicPlayerApp.swift         # App entry, global commands
├── Playback/
│   ├── Domain/
│   │   └── PlaybackState.swift              # Domain model (states, data, errors)
│   ├── Engine/
│   │   └── AudioPlaybackEngine.swift        # Core business logic
│   ├── Services/
│   │   ├── AudioSessionManager.swift        # Infrastructure: session creation
│   │   ├── AudioFileLoader.swift            # Infrastructure: file loading
│   │   ├── SampleRateManager.swift          # Infrastructure: Core Audio sample rate
│   │   └── PlaybackProgressTracker.swift    # Infrastructure: progress monitoring
│   └── UI/
│       ├── AudioPlayer.swift                # ViewModel (Presentation)
│       └── ContentView.swift                # Main UI (Presentation)
├── Utilities/
│   └── TimeFormatter.swift                  # Utilities
├── Assets.xcassets/                         # App assets
└── README.md                                # User documentation

AdaptiveMusicPlayerTests/
└── AdaptiveMusicPlayerTests.swift           # Test suite

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
- **Security-scoped resources** - All file access handled by `AudioFileLoader` with `startAccessingSecurityScopedResource()` / `stopAccessingSecurityScopedResource()`
- **Sample rate switching** - Not all audio interfaces support all rates; `SampleRateManager` handles this gracefully

## Testing Notes

- Tests use `@MainActor` annotations due to AudioPlayer being MainActor-isolated
- File loading tests require async waits (`Task.sleep`) for state propagation
- `ContentView.timeString` is duplicated in extension for testing access (private methods not testable)
- Invalid file loading should set `hasError = true` and populate `statusMessage`

## Common Modification Patterns

**Adding new playback controls**
1. Add business logic to `AudioPlaybackEngine` if state changes required
2. Add domain logic to `PlaybackState` or `AudioInfo` if business rules needed
3. Add presentation logic to `AudioPlayer` (must be `@MainActor`)
4. Add UI button/control in `ContentView`
5. Add keyboard shortcut in `AdaptiveMusicPlayerApp` CommandGroup
6. Add NotificationCenter observer in `ContentView` if global command

**Adding new domain states**
1. Add case to `PlaybackState` enum
2. Update state query methods (`canPlay`, `canSeek`, etc.)
3. Update `AudioPlaybackEngine` to transition to/from new state
4. Add handling in `AudioPlayer.updateStatus()` for presentation
5. Update UI in `ContentView` to reflect new state

**Modifying sample rate logic**
- Core Audio code is in `SampleRateManager` (protocol: `SampleRateManaging`)
- Implementation: `CoreAudioSampleRateManager`
- Integration in `AudioSessionManager.createSession()`
- Always check supported rates before setting to avoid errors
- UI updates happen via periodic callbacks in `PlaybackProgressTracker`

**Error handling**
- Add new cases to `PlaybackError` enum for domain errors
- Throw `PlaybackError` from `AudioPlaybackEngine` methods
- Catch and handle in `AudioPlayer.loadFile()` or playback methods
- `updateStatus(.error(error))` translates to UI properties
- `hasError` and `statusMessage` automatically set by `updateStatus()`
- Loading state automatically cleared when `currentStatus` changes

**Adding new infrastructure dependencies**
1. Define protocol (e.g., `MyServiceProtocol`)
2. Create implementation (e.g., `MyService: MyServiceProtocol`)
3. Inject via `AudioPlaybackEngine` or `AudioSessionManager` initializer
4. Use protocol type for property, not concrete type
5. Enables testing with mock implementations
