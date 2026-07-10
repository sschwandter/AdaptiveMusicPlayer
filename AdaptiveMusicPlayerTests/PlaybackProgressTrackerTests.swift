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

    @Test("A stale session's cancelled cleanup does not clear a session that already replaced it")
    func cancelledSessionDoesNotClearNewerSession() async throws {
        let tracker = PlaybackProgressTracker()
        let stalePlayer = try StubAudioPlayer()
        let newPlayer = try StubAudioPlayer()

        // Short interval so the stale session's polling loop reliably wakes
        // up and notices cancellation instead of staying parked awaiting its
        // first tick for the rest of the test.
        let (staleStream, staleContinuation) = AsyncStream<ProgressEvent>.makeStream()
        let staleTask = Task { @MainActor in
            await tracker.trackProgressStream(
                player: stalePlayer,
                updateInterval: 0.02,
                continuation: staleContinuation
            )
        }
        let staleDrain = Task { @MainActor in
            for await _ in staleStream {}
        }

        // Let the stale session's synchronous setup run before cancelling it.
        try await Task.sleep(for: .milliseconds(20))
        staleTask.cancel()

        // Replace it immediately, like the controller does when it cancels
        // the old lifetime task and starts a new one back-to-back with no
        // await in between.
        let (newStream, newContinuation) = AsyncStream<ProgressEvent>.makeStream()
        let collector = ProgressEventCollector()
        let newConsumer = collector.consume(newStream)
        let newTask = Task { @MainActor in
            await tracker.trackProgressStream(
                player: newPlayer,
                updateInterval: 1,
                continuation: newContinuation
            )
        }

        // Wait past the stale session's tick interval so its cancelled loop
        // wakes up and runs its trailing cleanup.
        try await Task.sleep(for: .milliseconds(150))

        // If the stale session's trailing cleanup wiped the tracker's shared
        // state, this finish callback would be silently dropped.
        tracker.audioPlayerDidFinishPlaying(newPlayer, successfully: true)
        try await waitUntil { collector.didFinish }
        #expect(collector.didFinish)

        newConsumer.cancel()
        newTask.cancel()
        staleDrain.cancel()
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
