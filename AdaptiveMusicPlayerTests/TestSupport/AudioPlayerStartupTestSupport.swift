import Foundation
import Testing
@testable import AdaptiveMusicPlayerCore
@testable import AdaptiveMusicPlayer

@MainActor
struct StartupTestContext {
    let player: AudioPlayer
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

        var dataByURL: [URL: LoadedAudioData] = [
            firstURL: LoadedAudioData(
                data: WaveData.make(),
                fileName: firstURL.lastPathComponent,
                fileExtension: "wav",
                displayTitle: firstURL.lastPathComponent,
                sampleRate: firstSampleRate,
                duration: 1
            )
        ]

        if let secondURL, let secondSampleRate {
            dataByURL[secondURL] = LoadedAudioData(
                data: WaveData.make(),
                fileName: secondURL.lastPathComponent,
                fileExtension: "wav",
                displayTitle: secondURL.lastPathComponent,
                sampleRate: secondSampleRate,
                duration: 1
            )
        }

        player = AudioPlayer(
            engine: AudioPlaybackEngine(
                loadFileOperation: RoutingStubLoadFileOperation(dataByURL: dataByURL),
                syncSampleRateOperation: DelayedSyncSampleRateOperation(delay: syncDelay),
                sampleRateManager: StubSampleRateManager()
            ),
            hardwareObserver: StubAudioHardwareObserver(),
            hardwareInfoProvider: StubAudioHardwareInfoProvider()
        )
    }

    func loadFirstFile() async {
        player.send(.loadFile(url: firstURL, importerDismissalDelay: .zero))
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
