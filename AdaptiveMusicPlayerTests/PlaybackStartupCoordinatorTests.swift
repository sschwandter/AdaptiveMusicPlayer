import Testing
import Foundation
@testable import AdaptiveMusicPlayerCore
@testable import AdaptiveMusicPlayer

@Suite("PlaybackStartupCoordinator Tests", .serialized)
@MainActor
struct PlaybackStartupCoordinatorTests {
    @Test("successful startup emits began then finished")
    func startupSuccess() async {
        let coordinator = PlaybackStartupCoordinator()
        let recorder = StartupEventRecorder()

        coordinator.startPlayback(
            play: {
                AudioInfo(
                    fileName: "track.wav",
                    displayTitle: "Track",
                    duration: 1,
                    sampleRate: 44_100
                )
            },
            handleEvent: { event in
                await recorder.record(event)
            }
        )

        await coordinator.waitForCurrentStartup()

        #expect(await recorder.summaries() == [
            "began",
            "finished:track.wav"
        ])
    }

    @Test("cancelling startup suppresses later completion and returns true")
    func startupCancellation() async throws {
        let coordinator = PlaybackStartupCoordinator()
        let recorder = StartupEventRecorder()

        coordinator.startPlayback(
            play: {
                try await Task.sleep(for: .milliseconds(200))
                return AudioInfo(
                    fileName: "track.wav",
                    displayTitle: "Track",
                    duration: 1,
                    sampleRate: 44_100
                )
            },
            handleEvent: { event in
                await recorder.record(event)
            }
        )

        #expect(coordinator.cancelStartup() == true)
        await coordinator.waitForCurrentStartup()
        try await Task.sleep(for: .milliseconds(50))

        #expect(await recorder.summaries() == ["began"])
    }

    @Test("stale startup result is reported when a newer startup supersedes the first")
    func staleStartupResult() async throws {
        let coordinator = PlaybackStartupCoordinator()
        let recorder = StartupEventRecorder()

        coordinator.startPlayback(
            play: {
                do {
                    try await Task.sleep(for: .milliseconds(200))
                } catch is CancellationError {
                    // Simulate an underlying operation that still completes after cancellation.
                }
                return AudioInfo(
                    fileName: "first.wav",
                    displayTitle: "First",
                    duration: 1,
                    sampleRate: 44_100
                )
            },
            handleEvent: { event in
                await recorder.record(event)
            }
        )

        #expect(coordinator.cancelStartup() == true)

        coordinator.startPlayback(
            play: {
                AudioInfo(
                    fileName: "second.wav",
                    displayTitle: "Second",
                    duration: 1,
                    sampleRate: 48_000
                )
            },
            handleEvent: { event in
                await recorder.record(event)
            }
        )

        await coordinator.waitForCurrentStartup()
        try await Task.sleep(for: .milliseconds(250))

        #expect(await recorder.summaries() == [
            "began",
            "began",
            "finished:second.wav",
            "stale-finished"
        ])
    }
}

actor StartupEventRecorder {
    private var summariesStorage: [String] = []

    func record(_ event: PlaybackStartupCoordinator.Event) {
        switch event {
        case .startupBegan:
            summariesStorage.append("began")
        case .startupCancelled:
            summariesStorage.append("cancelled")
        case .startupFinished(let audioInfo):
            summariesStorage.append("finished:\(audioInfo.fileName)")
        case .startupFailed(let error):
            summariesStorage.append("failed:\(error.localizedDescription)")
        case .staleStartupFinished:
            summariesStorage.append("stale-finished")
        }
    }

    func summaries() -> [String] {
        summariesStorage
    }
}
