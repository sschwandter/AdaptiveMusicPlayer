import Foundation
import Testing
@testable import AdaptiveMusicPlayer

@MainActor
struct StartupTestContext {
    let player: AudioPlayer
    let firstPlayer: StubAudioPlayer
    let secondPlayer: StubAudioPlayer?
    let firstURL: URL
    let secondURL: URL?

    init(
        firstURL: URL = URL(fileURLWithPath: "/tmp/test.wav"),
        secondURL: URL? = nil,
        firstSampleRate: Double = 44_100,
        secondSampleRate: Double? = nil,
        syncDelay: Duration
    ) throws {
        self.firstURL = firstURL
        self.secondURL = secondURL
        firstPlayer = try StubAudioPlayer()
        if secondURL != nil {
            secondPlayer = try StubAudioPlayer()
        } else {
            secondPlayer = nil
        }

        var sessionsByURL: [URL: AudioSession] = [
            firstURL: AudioSession(
                player: firstPlayer,
                fileName: firstURL.lastPathComponent,
                sampleRate: firstSampleRate,
                duration: 1
            )
        ]

        if let secondURL, let secondPlayer, let secondSampleRate {
            sessionsByURL[secondURL] = AudioSession(
                player: secondPlayer,
                fileName: secondURL.lastPathComponent,
                sampleRate: secondSampleRate,
                duration: 1
            )
        }

        player = AudioPlayer(
            engine: AudioPlaybackEngine(
                loadFileUseCase: RoutingStubLoadFileUseCase(sessionsByURL: sessionsByURL),
                syncSampleRateUseCase: DelayedSyncSampleRateUseCase(delay: syncDelay),
                sampleRateManager: StubSampleRateManager()
            ),
            hardwareObserver: StubAudioHardwareObserver(),
            hardwareInfoProvider: StubAudioHardwareInfoProvider()
        )
    }

    func loadFirstFile() async {
        player.loadFile(url: firstURL)
        await player.waitForCurrentLoad()
    }

    func settleStartup(after delay: Duration? = nil) async throws {
        await player.waitForCurrentLoad()
        if let delay {
            try await Task.sleep(for: delay)
        }
    }
}

@MainActor
func waitUntil(
    timeout: Duration = .seconds(1),
    pollInterval: Duration = .milliseconds(10),
    _ condition: @escaping @MainActor () -> Bool
) async throws {
    let start = ContinuousClock.now

    while !condition() {
        if ContinuousClock.now - start >= timeout {
            Issue.record("Timed out waiting for test condition.")
            return
        }

        try await Task.sleep(for: pollInterval)
    }
}
