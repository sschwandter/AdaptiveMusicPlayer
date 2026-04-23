import Foundation
import AVFoundation

/// Events emitted during playback progress tracking
enum ProgressEvent: Sendable {
    case progress(Double)  // Current playback time
    case finished          // Playback reached end
}

/// Stateful playback coordinator around AVAudioPlayer
/// Owns playback state and delegates smaller operations to focused operation types
@MainActor
final class AudioPlaybackEngine {
    private enum Constants {
        static let sampleRateTolerance: Double = 1.0
    }

// MARK: - Properties

private var playbackState: EnginePlaybackState = .idle
private var player: AVAudioPlayer?

// MARK: - Internal State Queries (for runtime coordination only)

/// Returns whether the engine has an active player ready for playback.
/// This is an internal runtime check, not the authoritative app state.
var hasActivePlayer: Bool { player != nil }

/// Returns the current audio info if a file is loaded.
var currentAudioInfo: AudioInfo? { playbackState.audioInfo }

    // MARK: - Dependencies

    private let loadFileOperation: LoadFileOperationProtocol
    private let playbackControlOperation: PlaybackControlOperationProtocol
    private let seekingOperation: SeekingOperationProtocol
    private let syncSampleRateOperation: SyncSampleRateOperationProtocol
    private let sampleRateManager: SampleRateManaging

    // MARK: - Initialization

    init(
        loadFileOperation: LoadFileOperationProtocol? = nil,
        playbackControlOperation: PlaybackControlOperationProtocol = PlaybackControlOperation(),
        seekingOperation: SeekingOperationProtocol = SeekingOperation(),
        syncSampleRateOperation: SyncSampleRateOperationProtocol = SyncSampleRateOperation(),
        sampleRateManager: SampleRateManaging = CoreAudioSampleRateManager()
    ) {
        self.sampleRateManager = sampleRateManager
        self.loadFileOperation = loadFileOperation ?? LoadFileOperation(sessionManager: AudioSessionManager())
        self.playbackControlOperation = playbackControlOperation
        self.seekingOperation = seekingOperation
        self.syncSampleRateOperation = syncSampleRateOperation
    }

    // MARK: - File Loading

    /// Move the engine into a loading state before async file work begins.
    func beginLoading() -> AudioInfo? {
        let preservedAudioInfo = playbackState.audioInfo
        if let player {
            player.stop()
            player.currentTime = 0
        }
        playbackState = .loading(preservedAudioInfo)
        return preservedAudioInfo
    }

    /// Load an audio file and prepare for playback
func loadFile(from url: URL) async throws -> AudioInfo {
        playbackState = .loading(playbackState.audioInfo)

        do {
            let session = try await loadFileOperation.execute(from: url)

            guard !Task.isCancelled else {
                playbackState = .idle
                throw PlaybackError.loadingCancelled
             }

            let audioInfo = AudioInfo(
                fileName: session.fileName,
                displayTitle: session.displayTitle,
                duration: session.duration,
                sampleRate: session.sampleRate
             )

            player = session.player
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
        guard let player = player else {
            throw PlaybackError.noFileLoaded
        }
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
        guard self.player === player, self.playbackState.audioInfo == requestedAudioInfo else {
            throw CancellationError()
         }

        let isAtEnd = if case .finished = playbackState { true } else { false }
        playbackState = try playbackControlOperation.play(player: player, audioInfo: requestedAudioInfo, isAtEnd: isAtEnd)
        return requestedAudioInfo
    }

    /// Pause playback
 func pause() throws -> AudioInfo {
        guard let player = player else {
            throw PlaybackError.noFileLoaded
        }
        guard let audioInfo = playbackState.audioInfo else {
            throw PlaybackError.noFileLoaded
        }

        playbackState = try playbackControlOperation.pause(player: player, audioInfo: audioInfo)
        return audioInfo
    }

    /// Stop playback and reset to beginning
    func stop() -> AudioInfo? {
        guard let player = player else { return nil }
        guard let audioInfo = playbackState.audioInfo else { return nil }

        playbackState = playbackControlOperation.stop(player: player, audioInfo: audioInfo)
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
        guard let player = player else {
            throw PlaybackError.noFileLoaded
        }
        guard let audioInfo = playbackState.audioInfo else {
            throw PlaybackError.noFileLoaded
        }

        return try seekingOperation.seek(to: time, player: player, audioInfo: audioInfo)
    }

/// Skip forward by the configured interval
      /// - Parameter currentTime: Current playback time
      /// - Returns: New time after skipping
     func skipForward(from currentTime: Double) throws -> Double {
         guard let player = player else {
             throw PlaybackError.noFileLoaded
          }
         guard let audioInfo = playbackState.audioInfo else {
             throw PlaybackError.noFileLoaded
          }

         return try seekingOperation.skipForward(from: currentTime, player: player, audioInfo: audioInfo)
      }

      /// Skip backward by the configured interval
      /// - Parameter currentTime: Current playback time
      /// - Returns: New time after skipping
     func skipBackward(from currentTime: Double) throws -> Double {
         guard let player = player else {
             throw PlaybackError.noFileLoaded
          }
         guard let audioInfo = playbackState.audioInfo else {
             throw PlaybackError.noFileLoaded
          }

         return try seekingOperation.skipBackward(from: currentTime, player: player, audioInfo: audioInfo)
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
        let clampedVolume = max(0, min(volume, 1))
        player?.volume = Float(clampedVolume)
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
        AsyncStream { continuation in
            let task = Task { @MainActor in
                await tracker.trackProgressStream(
                    player: self.player,
                    updateInterval: updateInterval,
                    continuation: continuation
                )
            }

            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }
}
