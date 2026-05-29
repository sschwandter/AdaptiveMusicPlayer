import Testing
import Foundation
import AVFoundation
@testable import AdaptiveMusicPlayerCore
@testable import AdaptiveMusicPlayer

@Suite("PlaybackProgressTracker Tests")
@MainActor
struct PlaybackProgressTrackerTests {

    /// Collects events from a progress stream on the main actor so tests can
    /// observe whether `.finished` was emitted without racing on a local var.
    @MainActor
    private final class ProgressEventCollector {
        private(set) var didFinish = false

        func consume(_ stream: AsyncStream<ProgressEvent>) -> Task<Void, Never> {
            Task { @MainActor in
                for await event in stream {
                    if case .finished = event { didFinish = true }
                }
            }
        }
    }

    private func makeProgressStream(
        tracker: PlaybackProgressTracker,
        player: AVAudioPlayer,
        updateInterval: TimeInterval = 1
    ) -> AsyncStream<ProgressEvent> {
        AsyncStream<ProgressEvent> { continuation in
            Task { @MainActor in
                await tracker.trackProgressStream(
                    player: player,
                    updateInterval: updateInterval,
                    continuation: continuation
                )
            }
        }
    }

    @Test("Ignoring finish callbacks from a previously tracked player")
    func ignoresStaleFinishCallbacks() async throws {
        let tracker = PlaybackProgressTracker()
        let stalePlayer = try StubAudioPlayer()
        let activePlayer = try StubAudioPlayer()
        let collector = ProgressEventCollector()

        let consumer = collector.consume(
            makeProgressStream(tracker: tracker, player: activePlayer)
        )
        try await Task.sleep(for: .milliseconds(20))

        // A finish from a player that is no longer the tracked one must be ignored.
        tracker.audioPlayerDidFinishPlaying(stalePlayer, successfully: true)
        try await Task.sleep(for: .milliseconds(20))
        #expect(collector.didFinish == false)

        // The currently tracked player's finish ends the stream.
        tracker.audioPlayerDidFinishPlaying(activePlayer, successfully: true)
        try await waitUntil { collector.didFinish }
        #expect(collector.didFinish)

        consumer.cancel()
    }

    @Test("Ignoring unsuccessful finish callbacks")
    func ignoresUnsuccessfulFinishCallbacks() async throws {
        let tracker = PlaybackProgressTracker()
        let player = try StubAudioPlayer()
        let collector = ProgressEventCollector()

        let consumer = collector.consume(
            makeProgressStream(tracker: tracker, player: player)
        )
        try await Task.sleep(for: .milliseconds(20))

        // An unsuccessful finish must not end the stream.
        tracker.audioPlayerDidFinishPlaying(player, successfully: false)
        try await Task.sleep(for: .milliseconds(20))
        #expect(collector.didFinish == false)

        // A successful finish does.
        tracker.audioPlayerDidFinishPlaying(player, successfully: true)
        try await waitUntil { collector.didFinish }
        #expect(collector.didFinish)

        consumer.cancel()
    }

    @Test("Async progress stream emits finished when the delegate reports completion")
    func asyncProgressStreamFinishesFromDelegateCallback() async throws {
        let tracker = PlaybackProgressTracker()
        let player = try StubAudioPlayer()

        let stream = makeProgressStream(tracker: tracker, player: player)

        let firstEvent = Task { () -> ProgressEvent? in
            var iterator = stream.makeAsyncIterator()
            return await iterator.next()
        }

        try await Task.sleep(for: .milliseconds(20))
        tracker.audioPlayerDidFinishPlaying(player, successfully: true)

        let event = await firstEvent.value
        guard case .finished? = event else {
            Issue.record("Expected the async progress stream to emit `.finished`.")
            return
        }
    }
}
