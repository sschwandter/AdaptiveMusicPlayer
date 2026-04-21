import Foundation
import AVFoundation

/// Stateful playback coordinator around AVAudioPlayer
/// Owns playback state and delegates smaller operations to use cases
@MainActor
final class AudioPlaybackEngine {
    private enum Constants {
        static let sampleRateTolerance: Double = 1.0
    }

    // MARK: - Properties

    private(set) var state: PlaybackState = .idle
    private var player: AVAudioPlayer?

    // MARK: - Dependencies

    private let loadFileUseCase: LoadFileUseCaseProtocol
    private let playbackControlUseCase: PlaybackControlUseCaseProtocol
    private let seekingUseCase: SeekingUseCaseProtocol
    private let syncSampleRateUseCase: SyncSampleRateUseCaseProtocol
    private let sampleRateManager: SampleRateManaging

    // MARK: - Initialization

    init(
        loadFileUseCase: LoadFileUseCaseProtocol? = nil,
        playbackControlUseCase: PlaybackControlUseCaseProtocol = PlaybackControlUseCase(),
        seekingUseCase: SeekingUseCaseProtocol = SeekingUseCase(),
        syncSampleRateUseCase: SyncSampleRateUseCaseProtocol = SyncSampleRateUseCase(),
        sampleRateManager: SampleRateManaging = CoreAudioSampleRateManager()
    ) {
        self.sampleRateManager = sampleRateManager
        self.loadFileUseCase = loadFileUseCase ?? LoadFileUseCase(sessionManager: AudioSessionManager())
        self.playbackControlUseCase = playbackControlUseCase
        self.seekingUseCase = seekingUseCase
        self.syncSampleRateUseCase = syncSampleRateUseCase
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
            let session = try await loadFileUseCase.execute(from: url)

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
                    try await syncSampleRateUseCase.execute(state: state, sampleRateManager: sampleRateManager)
                } catch {
                    // Playback should still start even if the device refuses the requested rate.
                }
            }
        }

        try Task.checkCancellation()
        guard self.player === player, self.state.audioInfo == requestedAudioInfo else {
            throw CancellationError()
        }

        state = try playbackControlUseCase.play(player: player, state: state)
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

        state = try playbackControlUseCase.pause(player: player, state: state)
        guard let audioInfo = state.audioInfo else {
            throw PlaybackError.notReady
        }
        return audioInfo
    }

    /// Stop playback and reset to beginning
    func stop() -> AudioInfo? {
        guard let player = player else { return nil }

        state = playbackControlUseCase.stop(player: player, state: state)
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

        return try seekingUseCase.seek(to: time, player: player, state: state)
    }

    /// Skip forward by the configured interval
    /// - Parameter currentTime: Current playback time
    /// - Returns: New time after skipping
    func skipForward(from currentTime: Double) throws -> Double {
        guard let player = player else {
            throw PlaybackError.noFileLoaded
        }

        return try seekingUseCase.skipForward(from: currentTime, player: player, state: state)
    }

    /// Skip backward by the configured interval
    /// - Parameter currentTime: Current playback time
    /// - Returns: New time after skipping
    func skipBackward(from currentTime: Double) throws -> Double {
        guard let player = player else {
            throw PlaybackError.noFileLoaded
        }

        return try seekingUseCase.skipBackward(from: currentTime, player: player, state: state)
    }

    // MARK: - Sample Rate Management

    /// Synchronize hardware sample rate to match current audio file.
    /// The sample-rate manager owns the concurrency boundary for Core Audio access.
    func synchronizeSampleRates() async throws {
        try await syncSampleRateUseCase.execute(state: state, sampleRateManager: sampleRateManager)
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

    /// Expose the active player to the progress tracker
    /// This keeps progress tracking separate, but still couples the engine to AVAudioPlayer.
    func getPlayer() -> AVAudioPlayer? {
        player
    }
}
