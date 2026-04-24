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
            "trackLoading:1 of 1",
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

    @Test("folder scanning runs off the main thread")
    func folderScanRunsOffMainThread() async throws {
        let rootFolder = try TemporaryFolder.make()
        defer { try? TemporaryFolder.remove(rootFolder) }

        let trackURL = rootFolder.appending(path: "album/track.wav")
        try TemporaryFolder.writeWaveFile(at: trackURL)

        let scanner = ThreadRecordingFolderScanner(tracks: [trackURL])
        let coordinator = AudioPlayerLoadCoordinator(folderScanner: scanner)
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

        await coordinator.waitForCurrentLoad()

        #expect(scanner.wasCalled)
        #expect(scanner.wasCalledOnMainThread == false)
    }

    @Test("replacing a folder load cancels the in-flight folder scan")
    func replacingFolderLoadCancelsInFlightScan() async throws {
        let rootFolder = try TemporaryFolder.make()
        defer { try? TemporaryFolder.remove(rootFolder) }

        let replacementURL = rootFolder.appending(path: "replacement.wav")
        try TemporaryFolder.writeWaveFile(at: replacementURL)

        let scanner = CancellableFolderScanner(tracks: [rootFolder.appending(path: "album/track.wav")])
        let coordinator = AudioPlayerLoadCoordinator(folderScanner: scanner)
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

        await scanner.waitUntilStarted()

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
        try await Task.sleep(for: .milliseconds(50))

        #expect(await scanner.didObserveCancellation())
    }
}

actor LoadCoordinatorEventRecorder {
    private var summariesStorage: [String] = []
    private var loadedTrackURLsStorage: [URL] = []

    func record(_ event: AudioPlayerLoadCoordinator.Event) {
        switch event {
        case .scanningFolderStarted:
            summariesStorage.append("scanning")
        case .trackLoadingStarted(let playlistSession):
            summariesStorage.append("trackLoading:\(playlistSession.positionDescription)")
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

final class ThreadRecordingFolderScanner: AudioPlaylistFolderScanning, @unchecked Sendable {
    private let tracks: [URL]
    private let lock = NSLock()
    private(set) var wasCalled = false
    private(set) var wasCalledOnMainThread = false

    init(tracks: [URL]) {
        self.tracks = tracks
    }

    func scan(folderURL: URL) async throws -> [URL] {
        lock.lock()
        wasCalled = true
        wasCalledOnMainThread = Thread.isMainThread
        lock.unlock()
        return tracks
    }
}

actor CancellableFolderScanner: AudioPlaylistFolderScanning {
    private let tracks: [URL]
    private var started = false
    private var observedCancellation = false

    init(tracks: [URL]) {
        self.tracks = tracks
    }

    func scan(folderURL: URL) async throws -> [URL] {
        started = true

        do {
            try await Task.sleep(for: .seconds(5))
            return tracks
        } catch is CancellationError {
            observedCancellation = true
            throw CancellationError()
        }
    }

    func waitUntilStarted() async {
        while !started {
            await Task.yield()
        }
    }

    func didObserveCancellation() -> Bool {
        observedCancellation
    }
}
