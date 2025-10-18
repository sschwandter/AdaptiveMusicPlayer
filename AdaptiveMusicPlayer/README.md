# Adaptive Music Player

A high-quality audio player for macOS that automatically adapts the system's sample rate to match your audio files, ensuring bit-perfect playback.

## Features

### 🎵 Core Functionality
- **Bit-perfect audio playback** using AVAudioEngine
- **Automatic sample rate switching** to match audio files
- **Real-time sample rate monitoring** with visual feedback
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
- **Audio session management** with proper interruption handling
- **Background/foreground handling** for phone calls and system alerts
- **Audio route change detection** (headphone disconnect, etc.)
- **Memory management** with proper cleanup
- **Thread safety** with MainActor usage
- **Comprehensive error states** and recovery

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

### AudioPlayer Class
The core `AudioPlayer` class handles:
- Audio file loading and management
- AVAudioEngine configuration
- Sample rate detection and switching
- Playback state management
- Timer-based progress tracking
- Audio session and interruption handling

### ContentView
The SwiftUI interface provides:
- Reactive UI updates
- Keyboard shortcut handling
- File selection interface
- Real-time status display
- Accessible controls with tooltips

### Key Design Patterns
- **MVVM architecture** with ObservableObject
- **Async/await** for file operations
- **MainActor** for thread safety
- **Combine publishers** for reactive updates
- **Error handling** with proper user feedback

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
- Proper cleanup of timers and observers
- Weak references to prevent retain cycles
- Efficient audio buffer management

### CPU Usage
- Optimized timer intervals (100ms updates)
- Minimal UI updates during playback
- Efficient audio processing with AVAudioEngine

### Audio Quality
- Direct AVAudioEngine usage for minimal latency
- Hardware sample rate matching for bit-perfect playback
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