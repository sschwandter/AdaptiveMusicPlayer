import Foundation
import AVFoundation

/// Stateful playback coordinator around AVAudioPlayer
/// Owns playback state and delegates smaller operations to focused operation types
@MainActor
final class AudioPlaybackEngine {
    private enum Constants {
        static let sampleRateTolerance: Double = 1.0
    }

    // MARK: - Properties

    private(set) var state: PlaybackState = .idle
    private var player: AVAudioPlayer?

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
        let preservedAudioInfo = state.audioInfo
        if let player {
            player.stop()
            player.currentTime = 0
        }
        state = .loading(preservedAudioInfo)
        return preservedAudioInfo
    }

    /// Load an audio file and prepare for playback
    func loadFile(from url: URL) async throws -> AudioInfo {
        state = .loading(state.audioInfo)

        do {
            let session = try await loadFileOperation.execute(from: url)

            guard !Task.isCancelled else {
                state = .idle
                throw PlaybackError.loadingCancelled
            }

            let audioInfo = AudioInfo(
                fileName: session.fileName,
                displayTitle: session.displayTitle,
                duration: session.duration,
                sampleRate: session.sampleRate
            )

            player = session.player
            state = .ready(audioInfo)

            return audioInfo

        } catch is CancellationError {
            state = .idle
            throw PlaybackError.loadingCancelled
        } catch let error as PlaybackError {
            state = .error(error)
            throw error
        } catch {
            let playbackError = PlaybackError.loadFailed(error.localizedDescription)
            state = .error(playbackError)
            throw playbackError
        }
    }

    // MARK: - Playback Control

    /// Start or resume playback
    func play() async throws -> AudioInfo {
        guard let player = player else {
            throw PlaybackError.noFileLoaded
        }
        let requestedAudioInfo = state.audioInfo

        if let targetSampleRate = requestedAudioInfo?.sampleRate {
            let currentSampleRate = await getCurrentHardwareSampleRate()
            if currentSampleRate <= 0 ||
                abs(currentSampleRate - targetSampleRate) > Constants.sampleRateTolerance
            {
                do {
                    try await syncSampleRateOperation.execute(state: state, sampleRateManager: sampleRateManager)
                } catch {
                    // Playback should still start even if the device refuses the requested rate.
                }
            }
        }

        try Task.checkCancellation()
        guard self.player === player, self.state.audioInfo == requestedAudioInfo else {
            throw CancellationError()
        }

        state = try playbackControlOperation.play(player: player, state: state)
        guard let audioInfo = state.audioInfo else {
            throw PlaybackError.notReady
        }
        return audioInfo
    }

    /// Pause playback
    func pause() throws -> AudioInfo {
        guard let player = player else {
            throw PlaybackError.noFileLoaded
        }

        state = try playbackControlOperation.pause(player: player, state: state)
        guard let audioInfo = state.audioInfo else {
            throw PlaybackError.notReady
        }
        return audioInfo
    }

    /// Stop playback and reset to beginning
    func stop() -> AudioInfo? {
        guard let player = player else { return nil }

        state = playbackControlOperation.stop(player: player, state: state)
        return state.audioInfo
    }

    /// Mark playback as finished
    func markFinished() -> AudioInfo? {
        guard let audioInfo = state.audioInfo else { return nil }
        state = .finished(audioInfo)
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

        return try seekingOperation.seek(to: time, player: player, state: state)
    }

    /// Skip forward by the configured interval
    /// - Parameter currentTime: Current playback time
    /// - Returns: New time after skipping
    func skipForward(from currentTime: Double) throws -> Double {
        guard let player = player else {
            throw PlaybackError.noFileLoaded
        }

        return try seekingOperation.skipForward(from: currentTime, player: player, state: state)
    }

    /// Skip backward by the configured interval
    /// - Parameter currentTime: Current playback time
    /// - Returns: New time after skipping
    func skipBackward(from currentTime: Double) throws -> Double {
        guard let player = player else {
            throw PlaybackError.noFileLoaded
        }

        return try seekingOperation.skipBackward(from: currentTime, player: player, state: state)
    }

    // MARK: - Sample Rate Management

    /// Synchronize hardware sample rate to match current audio file.
    /// The sample-rate manager owns the concurrency boundary for Core Audio access.
    func synchronizeSampleRates() async throws {
        try await syncSampleRateOperation.execute(state: state, sampleRateManager: sampleRateManager)
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

    /// Start observing playback progress through the engine boundary rather than exposing `AVAudioPlayer`.
    func startProgressTracking(
        using tracker: PlaybackProgressTracking,
        updateInterval: TimeInterval,
        onProgressUpdate: @escaping (Double) -> Void,
        onPlaybackFinished: @escaping () -> Void,
        onPeriodicUpdate: @escaping () -> Void
    ) {
        guard let player else { return }

        tracker.startTracking(
            player: player,
            updateInterval: updateInterval,
            onProgressUpdate: onProgressUpdate,
            onPlaybackFinished: onPlaybackFinished,
            onPeriodicUpdate: onPeriodicUpdate
        )
    }

    func stopProgressTracking(using tracker: PlaybackProgressTracking) {
        tracker.stopTracking()
    }
}
