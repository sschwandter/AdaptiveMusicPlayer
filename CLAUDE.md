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
- `.notReady`, `.noFileLoaded`, `.alreadyPlaying`, `.notPlaying`, `.loadingCancelled`, `.loadFailed(String)`, `.sampleRateSyncFailed(String)`
- Conforms to `LocalizedError` for user-friendly messages

### Use Cases Layer

Use cases represent explicit user goals and actions. Each is a first-class code entity:

**LoadFileUseCase** (`LoadFileUseCase.swift`) - Load and prepare audio file:
- User goal: "I want to open an audio file for playback"
- Coordinates file loading, player creation, sample rate detection
- Returns `AudioSession` with ready player and metadata
- Protocol: `LoadFileUseCaseProtocol`

**PlaybackControlUseCase** (`PlaybackControlUseCase.swift`) - Control playback state:
- User goal: "I want to play, pause, or stop the audio"
- Validates state transitions via `PlaybackState` business rules
- Updates AVAudioPlayer and returns new state
- Protocol: `PlaybackControlUseCaseProtocol`

**SeekingUseCase** (`SeekingUseCase.swift`) - Navigate within track:
- User goal: "I want to jump to a different position"
- Handles seek, skip forward, skip backward operations
- Clamps time to valid range via `AudioInfo` business rules
- Skip interval: 10 seconds
- Protocol: `SeekingUseCaseProtocol`

**SyncSampleRateUseCase** (`SyncSampleRateUseCase.swift`) - Fix sample rate mismatch:
- User goal: "I want bit-perfect playback without resampling"
- Sets hardware sample rate to match audio file's native rate
- Enables one-click fix for sample rate mismatches
- Protocol: `SyncSampleRateUseCaseProtocol`

### Business Logic Layer (Coordination)

**AudioPlaybackEngine** (`AudioPlaybackEngine.swift`) - Playback coordinator (`@MainActor`):
- Orchestrates use cases to fulfill higher-level operations
- Manages `PlaybackState` and `AVAudioPlayer` lifecycle
- Provides unified API for presentation layer
- Injects use case dependencies (protocol-oriented)
- Handles state transitions and error propagation
- No direct business logic - delegates to use cases

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
- Translates domain state → UI properties (`statusMessage`, `hasError`, `isLoading`, `hasSampleRateMismatch`)
- Centralizes status messages in `updateStatus()` method
- Derives `isLoading` from `currentStatus: StatusEvent` (single source of truth)
- Provides `synchronizeSampleRates()` for UI-triggered sample rate fixes
- Shows mismatch warnings in playing status ("hardware resampling from X Hz")
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
- Sample rate sync button appears when mismatch detected (inline icon next to hardware rate)

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
│   ├── UseCases/
│   │   ├── LoadFileUseCase.swift            # Use case: Load audio file
│   │   ├── PlaybackControlUseCase.swift     # Use case: Play/pause/stop
│   │   ├── SeekingUseCase.swift             # Use case: Seek and skip
│   │   └── SyncSampleRateUseCase.swift      # Use case: Fix sample rate mismatch
│   ├── Engine/
│   │   └── AudioPlaybackEngine.swift        # Coordinator (orchestrates use cases)
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

**Adding new use cases**
1. Identify the user goal (e.g., "I want to create a playlist")
2. Create new file in `Playback/UseCases/` (e.g., `CreatePlaylistUseCase.swift`)
3. Define protocol (e.g., `CreatePlaylistUseCaseProtocol`)
4. Implement use case class with `execute()` method
5. Inject dependencies via initializer (services, managers)
6. Add use case to `AudioPlaybackEngine` as dependency
7. Create coordinator method in `AudioPlaybackEngine` that delegates to use case
8. Add presentation method in `AudioPlayer` if UI-triggered
9. Add UI controls in `ContentView`

**Adding new playback controls**
1. Determine if it's a new use case or modification of existing one
2. If new use case, follow "Adding new use cases" pattern above
3. If extending existing, add method to appropriate use case
4. Add coordinator method in `AudioPlaybackEngine`
5. Add presentation logic to `AudioPlayer` (must be `@MainActor`)
6. Add UI button/control in `ContentView`
7. Add keyboard shortcut in `AdaptiveMusicPlayerApp` CommandGroup
8. Add NotificationCenter observer in `ContentView` if global command

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
