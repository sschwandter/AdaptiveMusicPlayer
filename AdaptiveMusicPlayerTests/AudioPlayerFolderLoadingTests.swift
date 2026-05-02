import Testing
import Foundation
import Observation
@testable import AdaptiveMusicPlayerCore
@testable import AdaptiveMusicPlayer

@Suite("AudioPlayer Folder Loading Tests", .serialized)
@MainActor
struct AudioPlayerFolderLoadingTests {

    @Test("Loading a folder builds a playable playlist from discovered files")
    func loadFolderBuildsPlaylist() async throws {
        let rootFolder = try TemporaryFolder.make()
        defer { try? TemporaryFolder.remove(rootFolder) }

        let fileURL = rootFolder.appending(path: "album/track.wav")
        try TemporaryFolder.writeWaveFile(at: fileURL)

        let player = AudioPlayer(
            engine: AudioPlaybackEngine(sampleRateManager: StubSampleRateManager()),
            hardwareObserver: StubAudioHardwareObserver(),
            hardwareInfoProvider: StubAudioHardwareInfoProvider()
         )

        player.send(.loadFolder(url: rootFolder, importerDismissalDelay: .zero))
        await player.waitForCurrentLoad()

        #expect(player.contentViewState.currentTrackTitle == "track.wav")
        #expect(player.contentViewState.playlistTrackPosition == "1 of 1")
        #expect(player.contentViewState.hasLoadedFile == true)
        #expect(player.contentViewState.isLoading == false)
    }

    @Test("Moving to the next playlist track starts playback automatically")
    func nextTrackAutoplays() async throws {
        let rootFolder = try TemporaryFolder.make()
        defer { try? TemporaryFolder.remove(rootFolder) }

        try TemporaryFolder.writeWaveFile(at: rootFolder.appending(path: "album/01-first.wav"))
        try TemporaryFolder.writeWaveFile(at: rootFolder.appending(path: "album/02-second.wav"))

        let player = AudioPlayer(
            engine: AudioPlaybackEngine(
                playbackControlOperation: SucceedingPlaybackControlOperation(),
                sampleRateManager: StubSampleRateManager()
            ),
            hardwareObserver: StubAudioHardwareObserver(),
            hardwareInfoProvider: StubAudioHardwareInfoProvider()
         )

        player.send(.loadFolder(url: rootFolder, importerDismissalDelay: .zero))
        await player.waitForCurrentLoad()

        player.send(.navigatePlaylist(next: true, autoplay: true))
        await player.waitForCurrentLoad()
        try await waitUntil(timeout: .milliseconds(500)) {
            player.contentViewState.currentTrackTitle == "02-second.wav" &&
                player.contentViewState.isPlaying
        }

        #expect(player.contentViewState.currentTrackTitle == "02-second.wav")
        #expect(player.contentViewState.playlistTrackPosition == "2 of 2")
        #expect(player.contentViewState.isPlaying == true)
        #expect(player.contentViewState.hasLoadedFile == true)
    }

    @Test("Loading an empty folder stops loading and shows an error")
    func loadEmptyFolderShowsErrorWithoutSpinner() async throws {
        let rootFolder = try TemporaryFolder.make()
        defer { try? TemporaryFolder.remove(rootFolder) }

        try FileManager.default.createDirectory(
            at: rootFolder.appending(path: "empty-album"),
            withIntermediateDirectories: true
         )

        let player = AudioPlayer(
            engine: AudioPlaybackEngine(sampleRateManager: StubSampleRateManager()),
            hardwareObserver: StubAudioHardwareObserver(),
            hardwareInfoProvider: StubAudioHardwareInfoProvider()
         )

        player.send(.loadFolder(url: rootFolder, importerDismissalDelay: .zero))
        await player.waitForCurrentLoad()

        #expect(player.contentViewState.hasLoadedFile == false)
        #expect(player.contentViewState.isLoading == false)
        // When folder loading fails, currentTrackTitle should be nil (no file loaded)
        #expect(player.contentViewState.currentTrackTitle == nil)
    }

    @Test("Selecting a playlist track updates the current track")
    func selectPlaylistTrackMovesToChosenEntry() async throws {
        let rootFolder = try TemporaryFolder.make()
        defer { try? TemporaryFolder.remove(rootFolder) }

        let firstURL = rootFolder.appending(path: "album/01-first.wav")
        let secondURL = rootFolder.appending(path: "album/02-second.wav")
        try TemporaryFolder.writeWaveFile(at: firstURL)
        try TemporaryFolder.writeWaveFile(at: secondURL)

        let player = AudioPlayer(
            engine: AudioPlaybackEngine(
                loadFileOperation: RoutingStubLoadFileOperation(dataByURL: [
                    firstURL: LoadedAudioData(
                        data: WaveData.make(),
                        fileName: "01-first.wav",
                        fileExtension: "wav",
                        displayTitle: "Opening Track",
                        sampleRate: 44_100,
                        duration: 1
                     ),
                    secondURL: LoadedAudioData(
                        data: WaveData.make(),
                        fileName: "02-second.wav",
                        fileExtension: "wav",
                        displayTitle: "Finale",
                        sampleRate: 44_100,
                        duration: 1
                     )
                 ]),
                sampleRateManager: StubSampleRateManager()
             ),
            hardwareObserver: StubAudioHardwareObserver(),
            hardwareInfoProvider: StubAudioHardwareInfoProvider()
         )

        player.send(.loadFolder(url: rootFolder, importerDismissalDelay: .zero))
        await player.waitForCurrentLoad()

        #expect(player.contentViewState.playlist.tracks.first?.title == "Opening Track")
        #expect(player.contentViewState.playlist.tracks.last?.title == "02-second.wav")

        player.send(.selectPlaylistTrack(index: 1))
        await player.waitForCurrentLoad()

        // After selecting track, currentTrackTitle should be the display title "Finale"
        // Note: The track is loaded via RoutingStubLoadFileOperation which returns displayTitle "Finale"
        #expect(player.contentViewState.currentTrackTitle == "Finale")
        #expect(player.contentViewState.playlistTrackPosition == "2 of 2")
        #expect(player.contentViewState.playlist.tracks.count == 2)
        #expect(player.contentViewState.playlist.tracks.last?.isCurrent == true)
        #expect(player.contentViewState.playlist.tracks.last?.title == "Finale")
    }

    @Test("Cancelling a folder scan does not leave stale loading UI")
    func cancellingFolderScanClearsLoadingState() async throws {
        let rootFolder = try TemporaryFolder.make()
        defer { try? TemporaryFolder.remove(rootFolder) }

        let replacementURL = rootFolder.appending(path: "replacement.wav")
        try TemporaryFolder.writeWaveFile(at: replacementURL)

        let delayedTrack = rootFolder.appending(path: "album/delayed.wav")
        let player = AudioPlayer(
            engine: AudioPlaybackEngine(sampleRateManager: StubSampleRateManager()),
            hardwareObserver: StubAudioHardwareObserver(),
            hardwareInfoProvider: StubAudioHardwareInfoProvider(),
            folderScanner: DelayedFolderScanner(delay: 0.15, tracks: [delayedTrack])
         )

        player.send(.loadFolder(url: rootFolder, importerDismissalDelay: .zero))
        player.send(.loadFile(url: replacementURL, importerDismissalDelay: .zero))
        await player.waitForCurrentLoad()

        #expect(player.contentViewState.currentTrackTitle == "replacement.wav")
        #expect(player.contentViewState.isLoading == false)
        #expect(player.contentViewState.hasLoadedFile == true)
        // After successful load, status message should indicate ready to play
        #expect(player.contentViewState.sampleRateBanner.title == "Ready" || player.contentViewState.sampleRateBanner.title == "Matched")
    }

    @Test("Loading a folder invalidates observation for playlist UI state")
    func loadFolderTriggersObservationUpdates() async throws {
        let rootFolder = try TemporaryFolder.make()
        defer { try? TemporaryFolder.remove(rootFolder) }

        try TemporaryFolder.writeWaveFile(at: rootFolder.appending(path: "album/track.wav"))

        let player = AudioPlayer(
            engine: AudioPlaybackEngine(sampleRateManager: StubSampleRateManager()),
            hardwareObserver: StubAudioHardwareObserver(),
            hardwareInfoProvider: StubAudioHardwareInfoProvider()
         )

        var didObserveChange = false
        withObservationTracking {
            _ = player.contentViewState
            _ = player.contentViewState.playlistTrackPosition
            _ = player.contentViewState.playlist.tracks
        } onChange: {
            didObserveChange = true
        }

        player.send(.loadFolder(url: rootFolder, importerDismissalDelay: .zero))
        await player.waitForCurrentLoad()

        #expect(didObserveChange)
        #expect(player.contentViewState.playlistTrackPosition == "1 of 1")
        #expect(player.contentViewState.playlist.tracks.count == 1)
    }
}
