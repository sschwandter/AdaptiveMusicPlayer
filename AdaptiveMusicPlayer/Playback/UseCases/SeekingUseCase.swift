import Foundation
import AVFoundation

/// Protocol for seeking and navigation within audio tracks
protocol SeekingUseCaseProtocol: Sendable {
    /// Seek to a specific time position
    /// - Parameters:
    ///   - time: Target time in seconds
    ///   - player: The audio player instance
    ///   - state: Current playback state
    /// - Returns: Actual time seeked to (clamped to valid range)
    /// - Throws: PlaybackError if seeking is not allowed in current state
    func seek(to time: Double, player: AVAudioPlayer, state: PlaybackState) throws -> Double

    /// Skip forward by configured interval
    /// - Parameters:
    ///   - currentTime: Current playback time
    ///   - player: The audio player instance
    ///   - state: Current playback state
    /// - Returns: New time after skipping
    /// - Throws: PlaybackError if operation fails
    func skipForward(from currentTime: Double, player: AVAudioPlayer, state: PlaybackState) throws -> Double

    /// Skip backward by configured interval
    /// - Parameters:
    ///   - currentTime: Current playback time
    ///   - player: The audio player instance
    ///   - state: Current playback state
    /// - Returns: New time after skipping
    /// - Throws: PlaybackError if operation fails
    func skipBackward(from currentTime: Double, player: AVAudioPlayer, state: PlaybackState) throws -> Double
}

/// Use case for seeking and navigation within audio tracks
/// Handles seeking to specific positions and skip forward/backward operations
@MainActor
final class SeekingUseCase: SeekingUseCaseProtocol {

    // MARK: - Constants

    private enum Constants {
        static let skipInterval: TimeInterval = 10.0  // seconds
    }

    // MARK: - Public Methods

    func seek(to time: Double, player: AVAudioPlayer, state: PlaybackState) throws -> Double {
        guard state.canSeek else {
            throw PlaybackError.notReady
        }

        guard let audioInfo = state.audioInfo else {
            throw PlaybackError.noFileLoaded
        }

        let clampedTime = audioInfo.clampSeekTime(time)
        player.currentTime = clampedTime
        return clampedTime
    }

    func skipForward(from currentTime: Double, player: AVAudioPlayer, state: PlaybackState) throws -> Double {
        guard let audioInfo = state.audioInfo else {
            throw PlaybackError.noFileLoaded
        }

        let newTime = audioInfo.skipForward(from: currentTime, by: Constants.skipInterval)
        return try seek(to: newTime, player: player, state: state)
    }

    func skipBackward(from currentTime: Double, player: AVAudioPlayer, state: PlaybackState) throws -> Double {
        guard let audioInfo = state.audioInfo else {
            throw PlaybackError.noFileLoaded
        }

        let newTime = audioInfo.skipBackward(from: currentTime, by: Constants.skipInterval)
        return try seek(to: newTime, player: player, state: state)
    }
}
