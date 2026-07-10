import Foundation
import AVFoundation
import Combine

/// Protocol for tracking audio playback progress
@MainActor
public protocol PlaybackProgressTracking {
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
public final class PlaybackProgressTracker: NSObject, PlaybackProgressTracking, AVAudioPlayerDelegate {

    // MARK: - Properties

    private var onPlaybackFinished: (() -> Void)?
    private weak var trackedPlayer: AVAudioPlayer?
    private var trackedPlayerID: ObjectIdentifier?

    /// Bumped by every `stopTracking()` call. A `trackProgressStream`
    /// invocation whose cancellation is only noticed after a newer session
    /// has already started (the polling loop only checks `Task.isCancelled`
    /// once per timer tick) uses this to recognize its trailing cleanup is
    /// stale, so it doesn't clear state that now belongs to the new session.
    private var generation = 0

    // MARK: - Public Methods

    public func stopTracking() {
        generation += 1
        onPlaybackFinished = nil
        trackedPlayer?.delegate = nil
        trackedPlayer = nil
        trackedPlayerID = nil
    }

    public func trackProgressStream(
        player: AVAudioPlayer?,
        updateInterval: TimeInterval,
        continuation: AsyncStream<ProgressEvent>.Continuation
    ) async {
        guard let player else {
            continuation.finish()
            return
        }

        stopTracking()
        let myGeneration = generation

        // Weak reference to avoid retention cycles
        weak let weakPlayer = player
        trackedPlayer = player
        trackedPlayerID = ObjectIdentifier(player)
        player.delegate = self

        // Use Timer.publish as an AsyncSequence for modern Swift concurrency
        let timerSequence = Timer.publish(every: updateInterval, on: .main, in: .common)
            .autoconnect()
            .values

        // Track if we've already finished to avoid duplicate events
        var hasFinished = false

        onPlaybackFinished = {
            guard !hasFinished else { return }
            hasFinished = true
            continuation.yield(.finished)
            continuation.finish()
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
        }

        if !hasFinished {
            continuation.finish()
        }

        // A newer session may have already taken over the tracker's shared
        // state by the time this cancelled loop wakes up; only tear it down
        // if no one has replaced this invocation in the meantime.
        if generation == myGeneration {
            stopTracking()
        }
    }

    // MARK: - AVAudioPlayerDelegate

    public func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        let finishedPlayerID = ObjectIdentifier(player)

        // Delegate is called on arbitrary thread, dispatch to main actor
        Task { @MainActor in
            guard flag, finishedPlayerID == trackedPlayerID else { return }
            onPlaybackFinished?()
        }
    }
}
