import Testing
import Foundation
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

        player.loadFolder(url: rootFolder)
        await player.waitForCurrentLoad()

        #expect(player.currentFileName == "track.wav")
        #expect(player.playlistTrackPosition == "1 of 1")
        #expect(player.hasError == false)
        #expect(player.isLoading == false)
    }

    @Test("Moving to the next playlist track starts playback automatically")
    func nextTrackAutoplays() async throws {
        let rootFolder = try TemporaryFolder.make()
        defer { try? TemporaryFolder.remove(rootFolder) }

        try TemporaryFolder.writeWaveFile(at: rootFolder.appending(path: "album/01-first.wav"))
        try TemporaryFolder.writeWaveFile(at: rootFolder.appending(path: "album/02-second.wav"))

        let player = AudioPlayer(
            engine: AudioPlaybackEngine(sampleRateManager: StubSampleRateManager()),
            hardwareObserver: StubAudioHardwareObserver(),
            hardwareInfoProvider: StubAudioHardwareInfoProvider()
        )

        player.loadFolder(url: rootFolder)
        await player.waitForCurrentLoad()

        player.playNextTrack()
        await player.waitForCurrentLoad()

        #expect(player.currentFileName == "02-second.wav")
        #expect(player.playlistTrackPosition == "2 of 2")
        #expect(player.isPlaying == true)
        #expect(player.hasError == false)
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

        player.loadFolder(url: rootFolder)
        await player.waitForCurrentLoad()

        #expect(player.hasError == true)
        #expect(player.isLoading == false)
        #expect(player.statusMessage == "Error loading file: No playable audio files were found in the selected folder.")
    }

    @Test("Selecting a playlist track updates the current track")
    func selectPlaylistTrackMovesToChosenEntry() async throws {
        let rootFolder = try TemporaryFolder.make()
        defer { try? TemporaryFolder.remove(rootFolder) }

        try TemporaryFolder.writeWaveFile(at: rootFolder.appending(path: "album/01-first.wav"))
        try TemporaryFolder.writeWaveFile(at: rootFolder.appending(path: "album/02-second.wav"))

        let player = AudioPlayer(
            engine: AudioPlaybackEngine(sampleRateManager: StubSampleRateManager()),
            hardwareObserver: StubAudioHardwareObserver(),
            hardwareInfoProvider: StubAudioHardwareInfoProvider()
        )

        player.loadFolder(url: rootFolder)
        await player.waitForCurrentLoad()

        player.selectPlaylistTrack(at: 1)
        await player.waitForCurrentLoad()

        #expect(player.currentFileName == "02-second.wav")
        #expect(player.playlistTrackPosition == "2 of 2")
        #expect(player.playlistTracks.count == 2)
        #expect(player.playlistTracks.last?.isCurrent == true)
    }
}
