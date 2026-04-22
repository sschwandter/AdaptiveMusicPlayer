import Testing
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
}
