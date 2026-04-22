import Testing
import Foundation
@testable import AdaptiveMusicPlayer

@Suite("AudioPlayerLoadCoordinator Tests", .serialized)
@MainActor
struct AudioPlayerLoadCoordinatorTests {
    @Test("single-file load emits start, playlist, and loaded-track events")
    func loadFileEvents() async throws {
        let coordinator = AudioPlayerLoadCoordinator()
        let trackURL = URL(fileURLWithPath: "/tmp/track.wav")
        let playlistSession = try #require(PlaylistSession.singleTrack(trackURL))
        let recorder = LoadCoordinatorEventRecorder()

        coordinator.loadFile(
            url: trackURL,
            playlistSession: playlistSession,
            loadTrack: { url in
                AudioInfo(
                    fileName: url.lastPathComponent,
                    displayTitle: "Loaded Track",
                    duration: 1,
                    sampleRate: 44_100
                )
            },
            handleEvent: { event in
                await recorder.record(event)
            }
        )
        await coordinator.waitForCurrentLoad()

        let summaries = await recorder.summaries()
        #expect(summaries == [
            "playlist:1 of 1",
            "begin:loadingTrack:Loading file...",
            "loaded:track.wav:false"
        ])
    }

    @Test("stale folder scan cannot publish a loaded track after a newer file load")
    func staleFolderLoadIsSuppressed() async throws {
        let rootFolder = try TemporaryFolder.make()
        defer { try? TemporaryFolder.remove(rootFolder) }

        let replacementURL = rootFolder.appending(path: "replacement.wav")
        let delayedTrackURL = rootFolder.appending(path: "album/delayed.wav")
        try TemporaryFolder.writeWaveFile(at: replacementURL)
        try TemporaryFolder.writeWaveFile(at: delayedTrackURL)

        let coordinator = AudioPlayerLoadCoordinator(
            folderScanner: DelayedFolderScanner(delay: 0.15, tracks: [delayedTrackURL])
        )
        let replacementSession = try #require(PlaylistSession.singleTrack(replacementURL))
        let recorder = LoadCoordinatorEventRecorder()

        coordinator.loadFolder(
            url: rootFolder,
            loadTrack: { url in
                AudioInfo(
                    fileName: url.lastPathComponent,
                    displayTitle: url.lastPathComponent,
                    duration: 1,
                    sampleRate: 44_100
                )
            },
            handleEvent: { event in
                await recorder.record(event)
            }
        )

        coordinator.loadFile(
            url: replacementURL,
            playlistSession: replacementSession,
            loadTrack: { url in
                AudioInfo(
                    fileName: url.lastPathComponent,
                    displayTitle: url.lastPathComponent,
                    duration: 1,
                    sampleRate: 48_000
                )
            },
            handleEvent: { event in
                await recorder.record(event)
            }
        )

        await coordinator.waitForCurrentLoad()
        try await Task.sleep(for: .milliseconds(250))

        let loadedURLs = await recorder.loadedTrackURLs()
        #expect(loadedURLs.map(canonicalTestFileURL) == [replacementURL].map(canonicalTestFileURL))
    }
}

actor LoadCoordinatorEventRecorder {
    private var summariesStorage: [String] = []
    private var loadedTrackURLsStorage: [URL] = []

    func record(_ event: AudioPlayerLoadCoordinator.Event) {
        switch event {
        case .beginLoading(let loadingState, let message):
            summariesStorage.append("begin:\(String(describing: loadingState)):\(message)")
        case .playlistSessionUpdated(let playlistSession):
            summariesStorage.append("playlist:\(playlistSession.positionDescription)")
        case .trackLoaded(let url, _, let autoplayOnSuccess):
            summariesStorage.append("loaded:\(url.lastPathComponent):\(autoplayOnSuccess)")
            loadedTrackURLsStorage.append(url)
        case .cancelled:
            summariesStorage.append("cancelled")
        case .failed(let error):
            summariesStorage.append("failed:\(error.localizedDescription)")
        }
    }

    func summaries() -> [String] {
        summariesStorage
    }

    func loadedTrackURLs() -> [URL] {
        loadedTrackURLsStorage
    }
}
