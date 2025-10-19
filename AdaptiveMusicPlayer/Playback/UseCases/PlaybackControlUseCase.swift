import Foundation
import AVFoundation

/// Protocol for controlling playback state
protocol PlaybackControlUseCaseProtocol: Sendable {
    /// Start or resume playback
    /// - Parameters:
    ///   - player: The audio player instance
    ///   - state: Current playback state
    /// - Returns: New playback state after starting playback
    /// - Throws: PlaybackError if playback cannot be started
    func play(player: AVAudioPlayer, state: PlaybackState) throws -> PlaybackState

    /// Pause playback
    /// - Parameters:
    ///   - player: The audio player instance
    ///   - state: Current playback state
    /// - Returns: New playback state after pausing
    /// - Throws: PlaybackError if playback cannot be paused
    func pause(player: AVAudioPlayer, state: PlaybackState) throws -> PlaybackState

    /// Stop playback and reset to beginning
    /// - Parameters:
    ///   - player: The audio player instance
    ///   - state: Current playback state
    /// - Returns: New playback state after stopping
    func stop(player: AVAudioPlayer, state: PlaybackState) -> PlaybackState
}

/// Use case for controlling playback state
/// Handles play, pause, and stop operations with state validation
@MainActor
final class PlaybackControlUseCase: PlaybackControlUseCaseProtocol {

    func play(player: AVAudioPlayer, state: PlaybackState) throws -> PlaybackState {
        guard state.canPlay else {
            throw state.isPlaying ? PlaybackError.alreadyPlaying : PlaybackError.notReady
        }

        guard let audioInfo = state.audioInfo else {
            throw PlaybackError.noFileLoaded
        }

        player.play()
        return .playing(audioInfo)
    }

    func pause(player: AVAudioPlayer, state: PlaybackState) throws -> PlaybackState {
        guard state.canPause else {
            throw PlaybackError.notPlaying
        }

        guard let audioInfo = state.audioInfo else {
            throw PlaybackError.noFileLoaded
        }

        player.pause()
        return .paused(audioInfo)
    }

    func stop(player: AVAudioPlayer, state: PlaybackState) -> PlaybackState {
        guard let audioInfo = state.audioInfo else {
            return state
        }

        player.stop()
        player.currentTime = 0
        return .ready(audioInfo)
    }
}
