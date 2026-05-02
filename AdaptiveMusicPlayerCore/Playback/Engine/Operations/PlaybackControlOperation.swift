import Foundation
import AVFoundation

/// Protocol for controlling playback state
public protocol PlaybackControlOperationProtocol: Sendable {
    /// Start or resume playback
    /// - Parameters:
    ///   - player: The audio player instance
    ///   - audioInfo: Audio file information
    ///   - isAtEnd: Whether playback is at the end (finished state)
    /// - Returns: New playback state after starting playback
    /// - Throws: PlaybackError if playback cannot be started
    func play(player: AVAudioPlayer, audioInfo: AudioInfo, isAtEnd: Bool) throws -> EnginePlaybackState

    /// Pause playback
    /// - Parameters:
    ///   - player: The audio player instance
    ///   - audioInfo: Audio file information
    /// - Returns: New playback state after pausing
    /// - Throws: PlaybackError if playback cannot be paused
    func pause(player: AVAudioPlayer, audioInfo: AudioInfo) throws -> EnginePlaybackState

    /// Stop playback and reset to beginning
    /// - Parameters:
    ///   - player: The audio player instance
    ///   - audioInfo: Audio file information
    /// - Returns: New playback state after stopping
    func stop(player: AVAudioPlayer, audioInfo: AudioInfo) -> EnginePlaybackState
}

/// Operation for controlling playback state
/// Handles play, pause, and stop operations with state validation
/// Stateless — no @MainActor needed; always called from @MainActor via AudioPlaybackEngine
public final class PlaybackControlOperation: PlaybackControlOperationProtocol {

    public init() {}

    public func play(player: AVAudioPlayer, audioInfo: AudioInfo, isAtEnd: Bool) throws -> EnginePlaybackState {
        if isAtEnd {
            player.currentTime = 0
        }

        // Prepare against the current output-device configuration, but do not
        // treat a failed prepare as terminal. On headless/CI macOS runners,
        // `prepareToPlay()` can report failure even though the playback start
        // path remains testable via `play()`.
        player.prepareToPlay()
        guard player.play() else {
            throw PlaybackError.playbackStartFailed
        }

        return .playing(audioInfo)
    }

    public func pause(player: AVAudioPlayer, audioInfo: AudioInfo) throws -> EnginePlaybackState {
        player.pause()
        return .paused(audioInfo)
    }

    public func stop(player: AVAudioPlayer, audioInfo: AudioInfo) -> EnginePlaybackState {
        player.stop()
        player.currentTime = 0
        return .ready(audioInfo)
    }
}
