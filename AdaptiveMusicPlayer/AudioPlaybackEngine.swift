import Foundation
import AVFoundation

/// Core business logic for audio playback
/// Manages state transitions and enforces business rules
@MainActor
final class AudioPlaybackEngine {

    // MARK: - Constants

    private enum Constants {
        static let skipInterval: Double = 10  // seconds
    }

    // MARK: - Properties

    private(set) var state: PlaybackState = .idle
    private var player: AVAudioPlayer?
    private let sessionManager: AudioSessionManaging
    private let sampleRateManager: SampleRateManaging

    // MARK: - Initialization

    init(
        sessionManager: AudioSessionManaging = AudioSessionManager(),
        sampleRateManager: SampleRateManaging = CoreAudioSampleRateManager()
    ) {
        self.sessionManager = sessionManager
        self.sampleRateManager = sampleRateManager
    }

    // MARK: - File Loading

    /// Load an audio file and prepare for playback
    func loadFile(from url: URL) async throws -> AudioInfo {
        state = .loading

        do {
            let session = try await sessionManager.createSession(from: url)
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
        } catch {
            let playbackError = PlaybackError.loadFailed(error.localizedDescription)
            state = .error(playbackError)
            throw playbackError
        }
    }

    // MARK: - Playback Control

    /// Start or resume playback
    func play() throws {
        guard state.canPlay else {
            throw state.isPlaying ? PlaybackError.alreadyPlaying : PlaybackError.notReady
        }

        guard let player = player, let audioInfo = state.audioInfo else {
            throw PlaybackError.noFileLoaded
        }

        player.play()
        state = .playing(audioInfo)
    }

    /// Pause playback
    func pause() throws {
        guard state.canPause else {
            throw PlaybackError.notPlaying
        }

        guard let player = player, let audioInfo = state.audioInfo else {
            throw PlaybackError.noFileLoaded
        }

        player.pause()
        state = .paused(audioInfo)
    }

    /// Stop playback and reset to beginning
    func stop() {
        guard let audioInfo = state.audioInfo else { return }

        player?.stop()
        player?.currentTime = 0
        state = .ready(audioInfo)
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
        guard state.canSeek else {
            throw PlaybackError.notReady
        }

        guard let player = player, let audioInfo = state.audioInfo else {
            throw PlaybackError.noFileLoaded
        }

        let clampedTime = audioInfo.clampSeekTime(time)
        player.currentTime = clampedTime
        return clampedTime
    }

    /// Skip forward by the configured interval
    /// - Parameter currentTime: Current playback time
    /// - Returns: New time after skipping
    func skipForward(from currentTime: Double) throws -> Double {
        guard let audioInfo = state.audioInfo else {
            throw PlaybackError.noFileLoaded
        }

        let newTime = audioInfo.skipForward(from: currentTime, by: Constants.skipInterval)
        return try seek(to: newTime)
    }

    /// Skip backward by the configured interval
    /// - Parameter currentTime: Current playback time
    /// - Returns: New time after skipping
    func skipBackward(from currentTime: Double) throws -> Double {
        guard let audioInfo = state.audioInfo else {
            throw PlaybackError.noFileLoaded
        }

        let newTime = audioInfo.skipBackward(from: currentTime, by: Constants.skipInterval)
        return try seek(to: newTime)
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
