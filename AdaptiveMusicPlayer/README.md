# Adaptive Music Player

A high-quality audio player for macOS that automatically adapts the system's sample rate to match your audio files, ensuring bit-perfect playback.

## Features

### 🎵 Core Functionality
- **Bit-perfect audio playback** using AVAudioPlayer with automatic sample rate switching
- **Automatic sample rate switching** to match audio files via Core Audio
- **Real-time sample rate monitoring** with visual feedback (green = matched, orange = resampling)
- **Comprehensive playback controls** (play, pause, stop, skip forward/backward)
- **Precise seeking** with interactive progress bar
- **Volume control** with percentage display

### 🎛️ User Experience
- **Loading states** with visual feedback
- **Error handling** with clear status messages
- **Keyboard shortcuts** for all major functions
- **Tooltips** for button help
- **Responsive UI** that adapts to loading states
- **Drag-enabled progress bar** for smooth seeking

### 🔧 Technical Features
- **Domain-driven architecture** with clear separation of concerns
- **Protocol-oriented design** with dependency injection
- **Swift 6 strict concurrency** with @MainActor and proper isolation
- **Delegate-based progress tracking** for efficient playback monitoring
- **Memory management** with proper cleanup and task cancellation
- **Comprehensive error states** with typed domain errors

## System Requirements

- **macOS 13.0+**
- **Swift 6.0+**
- **Xcode 15.0+**

## Keyboard Shortcuts

| Shortcut | Action |
|----------|--------|
| `Space` | Play/Pause |
| `←` | Skip Backward (10s) |
| `→` | Skip Forward (10s) |
| `⌘O` | Open File |
| `⌘.` | Stop |

## Supported Audio Formats

The app supports all audio formats supported by Core Audio:
- **Lossless**: FLAC, ALAC, WAV, AIFF
- **Compressed**: MP3, AAC, OGG
- **High-resolution**: Up to 192kHz/32-bit

## Sample Rate Handling

### Automatic Sample Rate Switching
The app automatically detects your audio file's sample rate and attempts to switch your system's audio hardware to match:

- **Green indicator**: Hardware sample rate matches file (bit-perfect playback)
- **Orange indicator**: Sample rate mismatch (resampling will occur)
- **Dash (—)**: No audio loaded or hardware info unavailable

### Supported Sample Rates
Common sample rates supported:
- 44.1 kHz (CD quality)
- 48 kHz (DVD quality)
- 88.2 kHz, 96 kHz (HD audio)
- 176.4 kHz, 192 kHz (studio master quality)

## Architecture

The app follows a **Domain Model + ViewModel** pattern with clear layered architecture:

### Domain Layer (Business Logic)
**PlaybackState** - Explicit state machine with business rules:
- States: `.idle`, `.loading`, `.ready`, `.playing`, `.paused`, `.finished`, `.error`
- State queries: `canPlay`, `canPause`, `canSeek`
- Enforces valid state transitions

**AudioInfo** - Domain data with business rules:
- File metadata (name, duration, sample rate)
- Business logic: `clampSeekTime()`, `skipForward()`, `skipBackward()`

**PlaybackError** - Typed domain errors:
- `.notReady`, `.noFileLoaded`, `.loadingCancelled`, `.loadFailed(String)`

### Business Logic Layer
**AudioPlaybackEngine** - Core playback logic (`@MainActor`):
- Manages state transitions
- Enforces business rules (can't play when not ready, etc.)
- Returns domain results, throws domain errors
- No presentation concerns

### Infrastructure Layer
**AudioSessionManager** - Creates complete audio sessions:
- Coordinates file loading, player creation, hardware configuration
- Returns `AudioSession` with ready-to-play AVAudioPlayer

**AudioFileLoader** - Security-scoped file loading:
- Handles sandbox permissions
- Loads files asynchronously with cancellation support

**SampleRateManager** - Core Audio hardware control:
- Detects file sample rates
- Switches hardware sample rate via Core Audio APIs
- Queries supported sample rates

**PlaybackProgressTracker** - Efficient progress monitoring:
- Timer-based progress updates (100ms intervals)
- AVAudioPlayerDelegate for finish detection (no polling)
- Periodic callbacks for hardware sample rate display

### Presentation Layer
**AudioPlayer (ViewModel)** - Presentation logic (`@MainActor`, `@Observable`):
- Owns `AudioPlaybackEngine`
- Translates domain state → UI properties
- Centralizes status messages in `updateStatus()`
- Derives `isLoading` from presentation state
- Coordinates between domain and view

**ContentView** - SwiftUI interface:
- Reactive UI updates via Observation framework
- Keyboard shortcut handling
- File selection interface
- Real-time status display

### Key Design Patterns
- **Domain Model + ViewModel** - Clear separation of "what can happen" (domain) vs "how to show it" (presentation)
- **Protocol-oriented design** - All dependencies injectable via protocols
- **Swift 6 strict concurrency** - `@MainActor` for UI, `nonisolated` for background work
- **Async/await** for all asynchronous operations
- **Observation framework** - Modern reactive UI (not ObservableObject/Combine)
- **Delegate pattern** - Efficient playback finish detection
- **Error handling** - Typed domain errors with user-friendly presentation

## Error Handling

The app provides comprehensive error handling for:
- **File access errors** (permissions, missing files)
- **Audio format errors** (unsupported formats, corrupt files)
- **Hardware errors** (audio device issues)
- **Sample rate errors** (unsupported rates)
- **System interruptions** (phone calls, other audio apps)

## Testing

The project includes comprehensive tests using Swift Testing:

```swift
@Suite("AudioPlayer Tests")
struct AudioPlayerTests {
    @Test("AudioPlayer initializes with default values")
    func initialState() async throws { /* ... */ }
    
    @Test("Volume changes are applied correctly")
    func volumeControl() async throws { /* ... */ }
}
```

Run tests with: `⌘U` in Xcode

## Building and Running

1. **Clone the repository**
2. **Open in Xcode 15+**
3. **Build and run** (`⌘R`)

No external dependencies required - uses only system frameworks.

## Performance Considerations

### Memory Management
- Proper Task cancellation for async operations
- Weak references in closures to prevent retain cycles
- Security-scoped resource cleanup

### CPU Usage
- Optimized timer intervals (100ms for progress, 2s for hardware monitoring)
- Delegate pattern for finish detection (eliminates polling overhead)
- Minimal UI updates via Observation framework

### Audio Quality
- AVAudioPlayer with hardware sample rate matching for bit-perfect playback
- Core Audio APIs for direct hardware control
- No unnecessary audio processing or effects

## Troubleshooting

### Audio Not Playing
1. Check file permissions and accessibility
2. Verify audio format support
3. Check system audio output device
4. Restart the app to reset audio session

### Sample Rate Issues
1. Some audio interfaces don't support all sample rates
2. Check Audio MIDI Setup app for supported rates
3. Manual system sample rate switching may be required

### Performance Issues
1. Large audio files may take time to load
2. Check available system memory
3. Close other audio applications that might conflict

## Contributing

1. Fork the repository
2. Create a feature branch
3. Add comprehensive tests
4. Submit a pull request

### Code Style
- Use Swift 6 features where appropriate
- Follow Apple's API design guidelines
- Add comprehensive documentation
- Include unit tests for new functionality

## License

MIT License - see LICENSE file for details.

## Acknowledgments

- **AVFoundation** for robust audio handling
- **SwiftUI** for modern UI development
- **Core Audio** for low-level audio control
- **Swift Testing** for modern test framework