import Foundation
import AVFoundation

/// Events emitted during playback progress tracking
enum ProgressEvent: Sendable {
    case progress(Double)  // Current playback time
    case finished          // Playback reached end
}

/// Stateful playback coordinator around a pluggable playback backend
/// Owns playback state and delegates runtime media control to the backend
@MainActor
final class AudioPlaybackEngine {
    private enum Constants {
        static let sampleRateTolerance: Double = 1.0
    }

// MARK: - Properties

    private var playbackState: EnginePlaybackState = .idle

// MARK: - Internal State Queries (for runtime coordination only)

/// Returns whether the engine has an active player ready for playback.
/// This is an internal runtime check, not the authoritative app state.
    var hasActivePlayer: Bool { backend.hasLoadedItem }

/// Returns the current audio info if a file is loaded.
var currentAudioInfo: AudioInfo? { playbackState.audioInfo }

    // MARK: - Dependencies

    private let syncSampleRateOperation: SyncSampleRateOperationProtocol
    private let sampleRateManager: SampleRateManaging
    private let backend: AudioPlaybackBackend

    // MARK: - Initialization

    init(
        backend: AudioPlaybackBackend? = nil,
        loadFileOperation: LoadFileOperationProtocol? = nil,
        playbackControlOperation: PlaybackControlOperationProtocol = PlaybackControlOperation(),
        seekingOperation: SeekingOperationProtocol = SeekingOperation(),
        syncSampleRateOperation: SyncSampleRateOperationProtocol = SyncSampleRateOperation(),
        sampleRateManager: SampleRateManaging = CoreAudioSampleRateManager()
    ) {
        self.sampleRateManager = sampleRateManager
        let resolvedLoadFileOperation = loadFileOperation ?? LoadFileOperation(sessionManager: AudioSessionManager())
        self.syncSampleRateOperation = syncSampleRateOperation
        self.backend = backend ?? AVAudioPlayerPlaybackBackend(
            loadFileOperation: resolvedLoadFileOperation,
            playbackControlOperation: playbackControlOperation,
            seekingOperation: seekingOperation
        )
    }

    // MARK: - File Loading

    /// Move the engine into a loading state before async file work begins.
    func beginLoading() -> AudioInfo? {
        let preservedAudioInfo = playbackState.audioInfo
        backend.stop()
        playbackState = .loading(preservedAudioInfo)
        return preservedAudioInfo
    }

    /// Load an audio file and prepare for playback
func loadFile(from url: URL) async throws -> AudioInfo {
        playbackState = .loading(playbackState.audioInfo)

        do {
            let audioInfo = try await backend.loadFile(from: url)

            guard !Task.isCancelled else {
                playbackState = .idle
                throw PlaybackError.loadingCancelled
             }
            playbackState = .ready(audioInfo)

            return audioInfo

         } catch is CancellationError {
            playbackState = .idle
            throw PlaybackError.loadingCancelled
         } catch let error as PlaybackError {
            playbackState = .error(error)
            throw error
         } catch {
            let playbackError = PlaybackError.loadFailed(error.localizedDescription)
            playbackState = .error(playbackError)
            throw playbackError
         }
    }

    // MARK: - Playback Control

    /// Start or resume playback
 func play() async throws -> AudioInfo {
        guard let requestedAudioInfo = playbackState.audioInfo else {
            throw PlaybackError.noFileLoaded
        }

        let targetSampleRate = requestedAudioInfo.sampleRate
        if targetSampleRate > 0 {
            let currentSampleRate = await getCurrentHardwareSampleRate()
            if currentSampleRate <= 0 ||
                abs(currentSampleRate - targetSampleRate) > Constants.sampleRateTolerance
             {
                do {
                    try await syncSampleRateOperation.execute(audioInfo: requestedAudioInfo, sampleRateManager: sampleRateManager)
                 } catch {
                    // Playback should still start even if the device refuses the requested rate.
                 }
             }
        }

        try Task.checkCancellation()
        guard backend.currentAudioInfo == requestedAudioInfo, self.playbackState.audioInfo == requestedAudioInfo else {
            throw CancellationError()
         }

        let isAtEnd = if case .finished = playbackState { true } else { false }
        try backend.play(fromFinishedState: isAtEnd)
        playbackState = .playing(requestedAudioInfo)
        return requestedAudioInfo
    }

    /// Pause playback
 func pause() throws -> AudioInfo {
        guard let audioInfo = playbackState.audioInfo else {
            throw PlaybackError.noFileLoaded
        }

        try backend.pause()
        playbackState = .paused(audioInfo)
        return audioInfo
    }

    /// Stop playback and reset to beginning
    func stop() -> AudioInfo? {
        guard let audioInfo = playbackState.audioInfo else { return nil }

        backend.stop()
        playbackState = .ready(audioInfo)
        return audioInfo
    }

    /// Mark playback as finished
    func markFinished() -> AudioInfo? {
        guard let audioInfo = playbackState.audioInfo else { return nil }
        playbackState = .finished(audioInfo)
        return audioInfo
    }

    // MARK: - Seeking

    /// Seek to a specific time
    /// - Parameter time: Target time in seconds
    /// - Returns: Actual time seeked to (clamped to valid range)
    func seek(to time: Double) throws -> Double {
        guard let audioInfo = playbackState.audioInfo else {
            throw PlaybackError.noFileLoaded
        }

        return try backend.seek(to: time, audioInfo: audioInfo)
    }

/// Skip forward by the configured interval
      /// - Parameter currentTime: Current playback time
      /// - Returns: New time after skipping
     func skipForward(from currentTime: Double) throws -> Double {
         guard let audioInfo = playbackState.audioInfo else {
             throw PlaybackError.noFileLoaded
          }

         return try backend.skipForward(from: currentTime, audioInfo: audioInfo)
      }

      /// Skip backward by the configured interval
      /// - Parameter currentTime: Current playback time
      /// - Returns: New time after skipping
     func skipBackward(from currentTime: Double) throws -> Double {
         guard let audioInfo = playbackState.audioInfo else {
             throw PlaybackError.noFileLoaded
          }

         return try backend.skipBackward(from: currentTime, audioInfo: audioInfo)
      }

    // MARK: - Sample Rate Management

    /// Synchronize hardware sample rate to match current audio file.
    /// The sample-rate manager owns the concurrency boundary for Core Audio access.
    func synchronizeSampleRates() async throws {
        guard let audioInfo = playbackState.audioInfo else {
            throw PlaybackError.noFileLoaded
        }
        try await syncSampleRateOperation.execute(audioInfo: audioInfo, sampleRateManager: sampleRateManager)
    }

    // MARK: - Volume Control

    /// Set playback volume
    /// - Parameter volume: Volume level (0.0 to 1.0)
    func setVolume(_ volume: Double) {
        backend.setVolume(volume)
    }

    // MARK: - Hardware Info

    /// Get current hardware sample rate
    func getCurrentHardwareSampleRate() async -> Double {
        await sampleRateManager.getCurrentSampleRate() ?? 0
    }

    /// Get current output-device diagnostics
    func getCurrentAudioDeviceInfo() async -> AudioDeviceInfo? {
        await sampleRateManager.getCurrentDeviceInfo()
    }

    // MARK: - Progress Tracking

    /// Returns raw progress events for the current playback.
    func trackProgress(
        using tracker: PlaybackProgressTracking,
        updateInterval: TimeInterval
    ) -> AsyncStream<ProgressEvent> {
        backend.makeProgressStream(using: tracker, updateInterval: updateInterval)
    }
}
