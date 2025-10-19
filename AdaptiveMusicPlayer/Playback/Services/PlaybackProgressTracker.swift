import Foundation
import AVFoundation
import Combine

/// Protocol for tracking audio playback progress
@MainActor
protocol PlaybackProgressTracking {
    /// Start tracking playback progress
    /// - Parameters:
    ///   - player: The AVAudioPlayer to track
    ///   - duration: Total duration of the audio
    ///   - updateInterval: How often to check progress (in seconds)
    ///   - onProgressUpdate: Called when currentTime changes
    ///   - onPlaybackFinished: Called when playback reaches the end
    ///   - onPeriodicUpdate: Called periodically for other updates (e.g., sample rate display)
    func startTracking(
        player: AVAudioPlayer,
        duration: Double,
        updateInterval: TimeInterval,
        onProgressUpdate: @escaping (Double) -> Void,
        onPlaybackFinished: @escaping () -> Void,
        onPeriodicUpdate: @escaping () -> Void
    )

    /// Stop tracking playback progress
    func stopTracking()
}

/// Tracks audio playback progress using timer-based polling and delegate for finish detection
final class PlaybackProgressTracker: NSObject, PlaybackProgressTracking, AVAudioPlayerDelegate {

    // MARK: - Constants

    private enum Constants {
        static let periodicUpdateTicks = 20  // timer ticks between periodic updates
    }

    // MARK: - Properties

    private var progressUpdateTask: Task<Void, Never>?
    private var timerTickCount = 0
    private var onPlaybackFinished: (() -> Void)?

    // MARK: - Public Methods

    func startTracking(
        player: AVAudioPlayer,
        duration: Double,
        updateInterval: TimeInterval,
        onProgressUpdate: @escaping (Double) -> Void,
        onPlaybackFinished: @escaping () -> Void,
        onPeriodicUpdate: @escaping () -> Void
    ) {
        // Ensure we don't have multiple tasks running
        stopTracking()

        // Store callback for delegate to use
        self.onPlaybackFinished = onPlaybackFinished

        // Set ourselves as the player's delegate for finish detection
        player.delegate = self

        progressUpdateTask = Task { @MainActor in
            // Use Timer.publish as an AsyncSequence for modern Swift concurrency
            for await _ in Timer.publish(every: updateInterval, on: .main, in: .common).autoconnect().values {
                guard !Task.isCancelled else { break }

                // Update current time from player
                let currentTime = player.currentTime
                onProgressUpdate(currentTime)

                // Trigger periodic updates (e.g., for hardware sample rate display)
                timerTickCount += 1
                if timerTickCount >= Constants.periodicUpdateTicks {
                    onPeriodicUpdate()
                    timerTickCount = 0
                }
            }
        }
    }

    func stopTracking() {
        progressUpdateTask?.cancel()
        progressUpdateTask = nil
        timerTickCount = 0
        onPlaybackFinished = nil
    }

    // MARK: - AVAudioPlayerDelegate

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        // Delegate is called on arbitrary thread, dispatch to main actor
        Task { @MainActor in
            onPlaybackFinished?()
        }
    }
}
