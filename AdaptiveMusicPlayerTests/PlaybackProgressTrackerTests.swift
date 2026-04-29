import Testing
import Foundation
@testable import AdaptiveMusicPlayerCore
@testable import AdaptiveMusicPlayer

@Suite("PlaybackProgressTracker Tests")
@MainActor
struct PlaybackProgressTrackerTests {

    @Test("Ignoring finish callbacks from a previously tracked player")
    func ignoresStaleFinishCallbacks() async throws {
        let tracker = PlaybackProgressTracker()
        let stalePlayer = try StubAudioPlayer()
        let activePlayer = try StubAudioPlayer()
        var finishCount = 0

        tracker.startTracking(
            player: stalePlayer,
            updateInterval: 1,
            onProgressUpdate: { _ in },
            onPlaybackFinished: { finishCount += 1 },
            onPeriodicUpdate: {}
        )

        tracker.startTracking(
            player: activePlayer,
            updateInterval: 1,
            onProgressUpdate: { _ in },
            onPlaybackFinished: { finishCount += 1 },
            onPeriodicUpdate: {}
        )

        tracker.audioPlayerDidFinishPlaying(stalePlayer, successfully: true)
        try await Task.sleep(for: .milliseconds(10))

        #expect(finishCount == 0)
    }

    @Test("Ignoring unsuccessful finish callbacks")
    func ignoresUnsuccessfulFinishCallbacks() async throws {
        let tracker = PlaybackProgressTracker()
        let player = try StubAudioPlayer()
        var finishCount = 0

        tracker.startTracking(
            player: player,
            updateInterval: 1,
            onProgressUpdate: { _ in },
            onPlaybackFinished: { finishCount += 1 },
            onPeriodicUpdate: {}
        )

        tracker.audioPlayerDidFinishPlaying(player, successfully: false)
        try await Task.sleep(for: .milliseconds(10))

        #expect(finishCount == 0)
    }

    @Test("Async progress stream emits finished when the delegate reports completion")
    func asyncProgressStreamFinishesFromDelegateCallback() async throws {
        let tracker = PlaybackProgressTracker()
        let player = try StubAudioPlayer()

        let stream = AsyncStream<ProgressEvent> { continuation in
            Task { @MainActor in
                await tracker.trackProgressStream(
                    player: player,
                    updateInterval: 1,
                    continuation: continuation
                )
            }
        }

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
