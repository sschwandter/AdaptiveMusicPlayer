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
        updateInterval: TimeInterval,
        onProgressUpdate: @escaping (Double) -> Void,
        onPlaybackFinished: @escaping () -> Void,
        onPeriodicUpdate: @escaping () -> Void
    )

    /// Stop tracking playback progress
    func stopTracking()

    /// Track progress as an AsyncStream for modern Swift concurrency.
    /// - Parameters:
    ///   - player: The AVAudioPlayer to track
    ///   - updateInterval: How often to check progress (in seconds)
    ///   - continuation: The AsyncStream continuation to yield events to
    func trackProgressStream(
        player: AVAudioPlayer?,
        updateInterval: TimeInterval,
        continuation: AsyncStream<ProgressEvent>.Continuation
    ) async
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
    private weak var trackedPlayer: AVAudioPlayer?
    private var trackedPlayerID: ObjectIdentifier?

    // MARK: - Public Methods

    func startTracking(
        player: AVAudioPlayer,
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
        trackedPlayer = player
        trackedPlayerID = ObjectIdentifier(player)
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
        trackedPlayer?.delegate = nil
        trackedPlayer = nil
        trackedPlayerID = nil
    }

    func trackProgressStream(
        player: AVAudioPlayer?,
        updateInterval: TimeInterval,
        continuation: AsyncStream<ProgressEvent>.Continuation
    ) async {
        guard let player else {
            continuation.finish()
            return
        }

        // Weak reference to avoid retention cycles
        weak var weakPlayer = player

        // Use Timer.publish as an AsyncSequence for modern Swift concurrency
        let timerSequence = Timer.publish(every: updateInterval, on: .main, in: .common)
            .autoconnect()
            .values

        // Track if we've already finished to avoid duplicate events
        var hasFinished = false

        // Create a detached task to handle finish detection via delegate
        let finishTask = Task { @MainActor [weak self] in
            while !Task.isCancelled && !hasFinished {
                // Check if playback finished naturally (via currentTime >= duration)
                if let p = weakPlayer, p.currentTime >= p.duration - 0.1 && p.currentTime > 0 {
                    hasFinished = true
                    continuation.yield(.finished)
                    continuation.finish()
                    break
                }
                try? await Task.sleep(for: .milliseconds(100))
            }
        }

        // Process timer updates
        for await _ in timerSequence {
            guard !Task.isCancelled, !hasFinished else { break }

            guard let currentPlayer = weakPlayer else {
                break
            }

            // Update current time from player
            let currentTime = currentPlayer.currentTime
            continuation.yield(.progress(currentTime))

            // Trigger periodic updates (e.g., for hardware sample rate display)
            timerTickCount += 1
            if timerTickCount >= Constants.periodicUpdateTicks {
                // Note: Periodic updates are handled separately by the consumer
                // using AsyncAlgorithms timers or Task.sleep
                timerTickCount = 0
            }
        }

        finishTask.cancel()

        // Ensure we finish the stream
        if !hasFinished {
            continuation.finish()
        }
    }

    // MARK: - AVAudioPlayerDelegate

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        let finishedPlayerID = ObjectIdentifier(player)

        // Delegate is called on arbitrary thread, dispatch to main actor
        Task { @MainActor in
            guard flag, finishedPlayerID == trackedPlayerID else { return }
            onPlaybackFinished?()
        }
    }
}
