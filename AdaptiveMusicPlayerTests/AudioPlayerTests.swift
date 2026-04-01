import Testing
import Foundation
@testable import AdaptiveMusicPlayer

@Suite("AudioPlayer Tests", .serialized)
@MainActor
struct AudioPlayerTests {

    @Test("AudioPlayer initializes with default values")
    func initialState() async throws {
        let player = AudioPlayer(
            hardwareObserver: StubAudioHardwareObserver(),
            hardwareInfoProvider: StubAudioHardwareInfoProvider()
        )

        #expect(player.isPlaying == false)
        #expect(player.currentTime == 0)
        #expect(player.duration == 0)
        #expect(player.volume == 1.0)
        #expect(player.currentFileName == nil)
        #expect(player.fileSampleRate == 0)
        try await Task.sleep(for: .milliseconds(100))
        #expect(!player.sampleRateStatusDetail.isEmpty)
        #expect(player.statusMessage == "")
        #expect(player.hasError == false)
        #expect(player.isLoading == false)
    }

    @Test("AudioPlayer initializes cleanly when hardware info is unavailable")
    func initialStateWithoutHardwareSnapshot() async throws {
        let player = AudioPlayer(
            hardwareObserver: StubAudioHardwareObserver(),
            hardwareInfoProvider: StubAudioHardwareInfoProvider(deviceInfo: nil)
        )

        try await Task.sleep(for: .milliseconds(20))

        #expect(player.hardwareSampleRate == 0)
        #expect(player.hardwareDeviceDisplayName == "Unknown output")
        #expect(!player.sampleRateStatusDetail.isEmpty)
        #expect(player.hasError == false)
        #expect(player.isLoading == false)
    }

    @Test("Volume changes are applied correctly")
    func volumeControl() async throws {
        let player = AudioPlayer(
            hardwareObserver: StubAudioHardwareObserver(),
            hardwareInfoProvider: StubAudioHardwareInfoProvider()
        )

        player.volume = 0.8
        #expect(player.volume == 0.8)

        player.volume = 0.0
        #expect(player.volume == 0.0)

        player.volume = 1.0
        #expect(player.volume == 1.0)
    }

    @Test("Time formatting works correctly")
    func timeFormatting() async throws {
        #expect(TimeFormatter.format(0) == "0:00")
        #expect(TimeFormatter.format(30) == "0:30")
        #expect(TimeFormatter.format(60) == "1:00")
        #expect(TimeFormatter.format(90) == "1:30")
        #expect(TimeFormatter.format(3661) == "61:01")
    }

    @Test("Toggle play/pause with no file loaded")
    func toggleWithoutFile() async throws {
        let player = AudioPlayer(
            hardwareObserver: StubAudioHardwareObserver(),
            hardwareInfoProvider: StubAudioHardwareInfoProvider()
        )

        player.togglePlayPause()
        #expect(player.isPlaying == false)
    }

    @Test("Stop functionality")
    func stopFunctionality() async throws {
        let player = AudioPlayer(
            hardwareObserver: StubAudioHardwareObserver(),
            hardwareInfoProvider: StubAudioHardwareInfoProvider()
        )

        player.stop()
        #expect(player.isPlaying == false)
        #expect(player.currentTime == 0)
    }

    @Test("Skip operations without file")
    func skipWithoutFile() async throws {
        let player = AudioPlayer(
            hardwareObserver: StubAudioHardwareObserver(),
            hardwareInfoProvider: StubAudioHardwareInfoProvider()
        )

        player.skipForward()
        player.skipBackward()

        #expect(player.currentTime == 0)
        #expect(player.isPlaying == false)
    }

    @Test("Seek bounds checking")
    func seekBounds() async throws {
        let player = AudioPlayer(
            hardwareObserver: StubAudioHardwareObserver(),
            hardwareInfoProvider: StubAudioHardwareInfoProvider()
        )

        player.seek(to: 10.0)
        #expect(player.currentTime == 0)

        player.seek(to: -5.0)
        #expect(player.currentTime == 0)
    }

    @Test("Error state management")
    func errorStates() async throws {
        let player = AudioPlayer(
            hardwareObserver: StubAudioHardwareObserver(),
            hardwareInfoProvider: StubAudioHardwareInfoProvider()
        )

        #expect(player.hasError == false)

        let invalidURL = URL(fileURLWithPath: "/nonexistent/file.mp3")
        player.loadFile(url: invalidURL)
        await player.waitForCurrentLoad()

        #expect(player.hasError == true)
        #expect(!player.statusMessage.isEmpty)
        #expect(!player.sampleRateStatusDetail.isEmpty)
    }

    @Test("Main play/pause button cancels a pending playback start")
    func togglePlayPauseCancelsPendingPlaybackStart() async throws {
        let context = try StartupTestContext(syncDelay: .milliseconds(100))
        await context.loadFirstFile()

        context.player.togglePlayPause()
        context.player.togglePlayPause()
        try await context.settleStartup(after: .milliseconds(250))

        #expect(context.player.isPlaying == false)
        #expect(context.player.hasError == false)
        #expect(context.player.statusMessage == "Paused")
        #expect(context.firstPlayer.playCallCount == 0)
    }

    @Test("Stop cancels a pending playback start")
    func stopCancelsPendingPlaybackStart() async throws {
        let context = try StartupTestContext(syncDelay: .milliseconds(200))
        await context.loadFirstFile()

        context.player.togglePlayPause()
        context.player.stop()
        try await context.settleStartup(after: .milliseconds(350))

        #expect(context.player.isPlaying == false)
        #expect(context.player.hasError == false)
        #expect(context.player.statusMessage == "Stopped")
    }

    @Test("Loading a new file cancels a pending playback start for the previous file")
    func loadingNewFileCancelsPendingPlaybackStart() async throws {
        let context = try StartupTestContext(
            firstURL: URL(fileURLWithPath: "/tmp/first.wav"),
            secondURL: URL(fileURLWithPath: "/tmp/second.wav"),
            firstSampleRate: 44_100,
            secondSampleRate: 48_000,
            syncDelay: .milliseconds(200)
        )
        await context.loadFirstFile()

        context.player.togglePlayPause()
        context.player.loadFile(url: try #require(context.secondURL))
        try await context.settleStartup(after: .milliseconds(400))

        #expect(context.player.currentFileName == "second.wav")
        #expect(context.player.isPlaying == false)
        #expect(context.player.hasError == false)
        #expect(context.firstPlayer.playCallCount == 0)
        #expect(try #require(context.secondPlayer).playCallCount == 0)
    }

    @Test("Selecting a playlist track during startup preserves autoplay intent")
    func selectingPlaylistTrackDuringStartupKeepsPlaybackIntent() async throws {
        let rootFolder = try TemporaryFolder.make()
        defer { try? TemporaryFolder.remove(rootFolder) }

        let firstURL = rootFolder.appending(path: "album/01-first.wav")
        let secondURL = rootFolder.appending(path: "album/02-second.wav")
        try TemporaryFolder.writeWaveFile(at: firstURL)
        try TemporaryFolder.writeWaveFile(at: secondURL)

        let firstPlayer = try StubAudioPlayer()
        let secondPlayer = try StubAudioPlayer()
        let player = AudioPlayer(
            engine: AudioPlaybackEngine(
                loadFileUseCase: RoutingStubLoadFileUseCase(sessionsByURL: [
                    firstURL: AudioSession(player: firstPlayer, fileName: "01-first.wav", sampleRate: 44_100, duration: 1),
                    secondURL: AudioSession(player: secondPlayer, fileName: "02-second.wav", sampleRate: 48_000, duration: 1)
                ]),
                syncSampleRateUseCase: DelayedSyncSampleRateUseCase(delay: .milliseconds(200)),
                sampleRateManager: StubSampleRateManager()
            ),
            hardwareObserver: StubAudioHardwareObserver(),
            hardwareInfoProvider: StubAudioHardwareInfoProvider()
        )

        player.loadFolder(url: rootFolder)
        await player.waitForCurrentLoad()

        player.togglePlayPause()
        player.selectPlaylistTrack(at: 1)
        await player.waitForCurrentLoad()
        try await waitUntil(timeout: .seconds(3)) {
            player.currentFileName == "02-second.wav" &&
            player.playlistTrackPosition == "2 of 2" &&
            player.isPlaying &&
            secondPlayer.playCallCount == 1
        }

        #expect(player.currentFileName == "02-second.wav")
        #expect(player.playlistTrackPosition == "2 of 2")
        #expect(player.isPlaying == true)
        #expect(player.hasError == false)
        #expect(firstPlayer.playCallCount == 0)
        #expect(secondPlayer.playCallCount == 1)
    }
}
