import Testing
import Foundation
@testable import AdaptiveMusicPlayerCore
@testable import AdaptiveMusicPlayer

@Suite("Stale Load Replacement Tests")
@MainActor
struct AudioPlayerStaleLoadReplacementTests {
    @Test("A load replaced during the hardware refresh publishes no stale status and starts no stale playback")
    func replacedLoadDoesNotPublishStaleReadyStatusOrAutoplay() async throws {
        let folderURL = try TemporaryFolder.make()
        defer { try? TemporaryFolder.remove(folderURL) }

        let firstTrack = folderURL.appending(path: "01-first.wav")
        let secondTrack = folderURL.appending(path: "02-second.wav")
        let replacementTrack = URL(fileURLWithPath: "/tmp/replacement.wav")

        let gate = HardwareRefreshGate()
        let stateStore = AudioPlayerStateStore()
        let engine = AudioPlaybackEngine(
            loadFileOperation: RoutingStubLoadFileOperation(dataByURL: [
                firstTrack: Self.loadedData(for: firstTrack),
                secondTrack: Self.loadedData(for: secondTrack),
                replacementTrack: Self.loadedData(for: replacementTrack)
            ]),
            playbackControlOperation: SucceedingPlaybackControlOperation(),
            sampleRateManager: StubSampleRateManager()
        )
        let controller = AudioPlayerSessionController(
            stateStore: stateStore,
            engine: engine,
            progressTracker: RecordingPlaybackProgressTracker(),
            loadCoordinator: AudioPlayerLoadCoordinator(
                folderScanner: DelayedFolderScanner(delay: 0, tracks: [firstTrack, secondTrack])
            ),
            refreshHardwareInfo: { await gate.refresh() },
            currentVolume: { 1 }
        )

        controller.send(.loadFolder(url: folderURL, importerDismissalDelay: .zero))
        await controller.waitForCurrentActivity()
        #expect(stateStore.currentTrackURL == firstTrack)

        // Suspend the next track's finish inside the hardware refresh —
        // exactly the window where a replacing load can slip in.
        gate.armNextCall()
        controller.send(.navigatePlaylist(next: true, autoplay: true))
        try await waitUntil { gate.blockedCallCount == 1 }

        controller.send(.loadFile(url: replacementTrack, importerDismissalDelay: .zero))
        await controller.waitForCurrentActivity()
        #expect(stateStore.currentTrackURL == replacementTrack)
        let statusAfterReplacement = stateStore.statusMessage

        // Resume the stale finish: it must not publish ready status for the
        // replaced track, and its autoplay must not start playback.
        gate.release()
        try await Task.sleep(for: .milliseconds(50))

        #expect(controller.isStartingPlayback == false)
        #expect(stateStore.isPlaying == false)
        #expect(stateStore.statusMessage == statusAfterReplacement)
        #expect(stateStore.currentTrackURL == replacementTrack)
    }

    private static func loadedData(for url: URL) -> LoadedAudioData {
        LoadedAudioData(
            data: WaveData.make(),
            fileName: url.lastPathComponent,
            fileExtension: "wav",
            displayTitle: url.lastPathComponent,
            sampleRate: 44_100,
            duration: 1
        )
    }
}

/// Lets a test suspend one `refreshHardwareInfo` call at a controlled point
/// and resume it later, simulating a slow hardware query.
@MainActor
private final class HardwareRefreshGate {
    private var pending: [CheckedContinuation<Void, Never>] = []
    private var armed = false
    private(set) var blockedCallCount = 0

    func armNextCall() {
        armed = true
    }

    func refresh() async {
        guard armed else { return }
        armed = false
        blockedCallCount += 1
        await withCheckedContinuation { pending.append($0) }
    }

    func release() {
        pending.forEach { $0.resume() }
        pending.removeAll()
    }
}
