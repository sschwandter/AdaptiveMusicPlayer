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

/// Tracks audio playback progress using timer-based polling
final class PlaybackProgressTracker: PlaybackProgressTracking {

    // MARK: - Constants

    private enum Constants {
        static let finishThreshold: Double = 0.05  // seconds - how close to end counts as "finished"
        static let periodicUpdateTicks = 20  // timer ticks between periodic updates
    }

    // MARK: - Properties

    private var progressUpdateTask: Task<Void, Never>?
    private var timerTickCount = 0

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

        progressUpdateTask = Task { @MainActor in
            // Use Timer.publish as an AsyncSequence for modern Swift concurrency
            for await _ in Timer.publish(every: updateInterval, on: .main, in: .common).autoconnect().values {
                guard !Task.isCancelled else { break }

                // Update current time from player
                let currentTime = player.currentTime
                onProgressUpdate(currentTime)

                // Check if playback finished naturally
                if currentTime >= duration - Constants.finishThreshold && player.isPlaying {
                    onPlaybackFinished()
                    break  // Stop tracking when finished
                }

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
    }
}
