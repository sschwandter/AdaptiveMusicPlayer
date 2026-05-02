# AdaptiveMusicPlayerCore

`AdaptiveMusicPlayerCore` is the central playback framework for the Adaptive Music Player. It provides the essential domain models, engine logic, and low-level services required for audio playback and hardware synchronization.

## Structure

The framework is organized into the following layers:

### Domain (`Playback/Domain/`)
Contains the foundational playback models and business rules.
- `AudioInfo`: Metadata and business rules for audio files.
- `EnginePlaybackState`: The internal runtime state of the playback engine.
- `PlaybackPlaylist` & `PlaylistSession`: Logic for managing track sequences and folder-based playback.

### Engine (`Playback/Engine/`)
The stateful coordinator for audio playback.
- `AudioPlaybackEngine`: An event-driven adapter around `AVAudioPlayer` that emits state and volume changes via an asynchronous stream.
- `Operations/`: Focused, atomic operations for loading files, controlling playback, seeking, and synchronizing sample rates.

### Services (`Playback/Services/`)
Wrappers and adapters for system-level functionality.
- `AudioSessionManager`: Coordinates file loading and metadata extraction.
- `SampleRateManager`: Direct interface with Core Audio for hardware sample rate control.
- `AudioHardwareObserver`: Observes system-wide audio device changes.
- `AudioPlaylistFolderScanner`: Recursively scans directories for playable audio files.
- `PlaybackProgressTracker`: Tracks and emits playback progress events.
- `ScopedFolderAccess`: Manages security-scoped resource access for macOS App Sandbox.

### Utilities (`Utilities/`)
General purpose helpers.
- `TimeFormatter`: Formatting logic for playback time and remaining duration.

## Architecture

The core framework follows an **event-driven** and **operation-based** design. The `AudioPlaybackEngine` delegates complex tasks to specialized operations while maintaining a consistent internal state. It communicates with the UI layer via an `AsyncStream` of `EngineEvent` objects, ensuring a clean separation between playback logic and user interface state.
