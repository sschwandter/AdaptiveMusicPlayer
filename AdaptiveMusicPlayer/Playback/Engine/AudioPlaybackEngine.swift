import Foundation
import AVFoundation

/// Playback engine coordinator
/// Orchestrates use cases and manages playback state
@MainActor
final class AudioPlaybackEngine {

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
        loadFileUseCase: LoadFileUseCaseProtocol = LoadFileUseCase(),
        playbackControlUseCase: PlaybackControlUseCaseProtocol = PlaybackControlUseCase(),
        seekingUseCase: SeekingUseCaseProtocol = SeekingUseCase(),
        syncSampleRateUseCase: SyncSampleRateUseCaseProtocol = SyncSampleRateUseCase(),
        sampleRateManager: SampleRateManaging = CoreAudioSampleRateManager()
    ) {
        self.loadFileUseCase = loadFileUseCase
        self.playbackControlUseCase = playbackControlUseCase
        self.seekingUseCase = seekingUseCase
        self.syncSampleRateUseCase = syncSampleRateUseCase
        self.sampleRateManager = sampleRateManager
    }

    // MARK: - File Loading

    /// Load an audio file and prepare for playback
    func loadFile(from url: URL) async throws -> AudioInfo {
        state = .loading

        do {
            let session = try await loadFileUseCase.execute(from: url)

            guard !Task.isCancelled else {
                state = .idle
                throw PlaybackError.loadingCancelled
            }

            let audioInfo = AudioInfo(
                fileName: session.fileName,
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
    func play() throws {
        guard let player = player else {
            throw PlaybackError.noFileLoaded
        }

        state = try playbackControlUseCase.play(player: player, state: state)
    }

    /// Pause playback
    func pause() throws {
        guard let player = player else {
            throw PlaybackError.noFileLoaded
        }

        state = try playbackControlUseCase.pause(player: player, state: state)
    }

    /// Stop playback and reset to beginning
    func stop() {
        guard let player = player else { return }

        state = playbackControlUseCase.stop(player: player, state: state)
    }

    /// Mark playback as finished
    func markFinished() {
        guard let audioInfo = state.audioInfo else { return }
        state = .finished(audioInfo)
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

    /// Synchronize hardware sample rate to match current audio file
    /// Sets hardware to match file's native sample rate for bit-perfect playback
    func synchronizeSampleRates() throws {
        try syncSampleRateUseCase.execute(state: state, sampleRateManager: sampleRateManager)
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
    func getCurrentHardwareSampleRate() -> Double {
        sampleRateManager.getCurrentSampleRate() ?? 0
    }

    /// Get the underlying AVAudioPlayer for progress tracking
    /// Note: This is a temporary bridge until progress tracking is refactored
    func getPlayer() -> AVAudioPlayer? {
        player
    }
}
