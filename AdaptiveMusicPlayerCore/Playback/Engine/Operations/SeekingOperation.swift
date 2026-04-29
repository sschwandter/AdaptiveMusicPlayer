import Foundation
import AVFoundation

/// Protocol for seeking and navigation within audio tracks
public protocol SeekingOperationProtocol: Sendable {
    /// Seek to a specific time position
    /// - Parameters:
    ///   - time: Target time in seconds
    ///   - player: The audio player instance
    ///   - audioInfo: Audio file information for bounds checking
    /// - Returns: Actual time seeked to (clamped to valid range)
    /// - Throws: PlaybackError if seeking fails
    func seek(to time: Double, player: AVAudioPlayer, audioInfo: AudioInfo) throws -> Double

    /// Skip forward by configured interval
    /// - Parameters:
    ///   - currentTime: Current playback time
    ///   - player: The audio player instance
    ///   - audioInfo: Audio file information for bounds checking
    /// - Returns: New time after skipping
    /// - Throws: PlaybackError if operation fails
    func skipForward(from currentTime: Double, player: AVAudioPlayer, audioInfo: AudioInfo) throws -> Double

    /// Skip backward by configured interval
    /// - Parameters:
    ///   - currentTime: Current playback time
    ///   - player: The audio player instance
    ///   - audioInfo: Audio file information for bounds checking
    /// - Returns: New time after skipping
    /// - Throws: PlaybackError if operation fails
    func skipBackward(from currentTime: Double, player: AVAudioPlayer, audioInfo: AudioInfo) throws -> Double
}

/// Operation for seeking and navigation within audio tracks
/// Handles seeking to specific positions and skip forward/backward operations
/// Stateless — no @MainActor needed; always called from @MainActor via AudioPlaybackEngine
public final class SeekingOperation: SeekingOperationProtocol {

    // MARK: - Constants

    private enum Constants {
        static let skipInterval: TimeInterval = 10.0  // seconds
    }

    // MARK: - Public Methods

    public init() {}

    public func seek(to time: Double, player: AVAudioPlayer, audioInfo: AudioInfo) throws -> Double {
        let clampedTime = audioInfo.clampSeekTime(time)
        player.currentTime = clampedTime
        return clampedTime
    }

    public func skipForward(from currentTime: Double, player: AVAudioPlayer, audioInfo: AudioInfo) throws -> Double {
        let newTime = audioInfo.skipForward(from: currentTime, by: Constants.skipInterval)
        return try seek(to: newTime, player: player, audioInfo: audioInfo)
    }

    public func skipBackward(from currentTime: Double, player: AVAudioPlayer, audioInfo: AudioInfo) throws -> Double {
        let newTime = audioInfo.skipBackward(from: currentTime, by: Constants.skipInterval)
        return try seek(to: newTime, player: player, audioInfo: audioInfo)
    }
}
