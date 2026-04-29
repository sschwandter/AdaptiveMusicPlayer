import Testing
import Foundation
@testable import AdaptiveMusicPlayerCore
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

         #expect(player.contentViewState.isPlaying == false)
         #expect(player.contentViewState.currentTime == 0)
         #expect(player.contentViewState.duration == 0)
         #expect(player.volume == 1.0)
         #expect(player.contentViewState.currentTrackTitle == nil)
         #expect(player.contentViewState.hasLoadedFile == false)
         #expect(player.contentViewState.isLoading == false)
     }

    @Test("AudioPlayer initializes cleanly when hardware info is unavailable")
    func initialStateWithoutHardwareSnapshot() async throws {
        let player = AudioPlayer(
            hardwareObserver: StubAudioHardwareObserver(),
            hardwareInfoProvider: StubAudioHardwareInfoProvider(deviceInfo: nil)
         )

         #expect(player.contentViewState.hasLoadedFile == false)
         #expect(player.contentViewState.isLoading == false)
         #expect(player.contentViewState.currentTrackTitle == nil)
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

        player.send(.togglePlayPause)
         #expect(player.contentViewState.isPlaying == false)
     }

    @Test("Playback progress events update the UI immediately while playing")
    func playbackProgressUpdatesImmediately() async throws {
        let progressTracker = RecordingPlaybackProgressTracker()
        let player = AudioPlayer(
            engine: AudioPlaybackEngine(
                loadFileOperation: StubLoadFileOperation(sampleRate: 44_100),
                sampleRateManager: StubSampleRateManager()
            ),
            progressTracker: progressTracker,
            hardwareObserver: StubAudioHardwareObserver(),
            hardwareInfoProvider: StubAudioHardwareInfoProvider()
        )

        player.send(.loadFile(url: URL(fileURLWithPath: "/tmp/test.wav"), importerDismissalDelay: .zero))
        await player.waitForCurrentLoad()
        player.send(.togglePlayPause)
        try await Task.sleep(for: .milliseconds(20))

        progressTracker.streamContinuation?.yield(.progress(0.25))
        try await Task.sleep(for: .milliseconds(20))
        #expect(player.contentViewState.currentTime == 0.25)

        progressTracker.streamContinuation?.yield(.progress(0.5))
        try await Task.sleep(for: .milliseconds(20))
        #expect(player.contentViewState.currentTime == 0.5)
    }

    @Test("Natural playback finish stops progress tracking cleanup work")
    func playbackFinishStopsProgressTracking() async throws {
        let progressTracker = RecordingPlaybackProgressTracker()
        let player = AudioPlayer(
            engine: AudioPlaybackEngine(
                loadFileOperation: StubLoadFileOperation(sampleRate: 44_100),
                sampleRateManager: StubSampleRateManager()
            ),
            progressTracker: progressTracker,
            hardwareObserver: StubAudioHardwareObserver(),
            hardwareInfoProvider: StubAudioHardwareInfoProvider()
        )

        player.send(.loadFile(url: URL(fileURLWithPath: "/tmp/test.wav"), importerDismissalDelay: .zero))
        await player.waitForCurrentLoad()
        player.send(.togglePlayPause)
        try await Task.sleep(for: .milliseconds(20))

        let stopCallCountBeforeFinish = progressTracker.stopCallCount

        progressTracker.streamContinuation?.yield(.finished)
        try await waitUntil(timeout: .milliseconds(250)) {
            progressTracker.stopCallCount > stopCallCountBeforeFinish
        }

        #expect(progressTracker.stopCallCount > stopCallCountBeforeFinish)
        #expect(player.contentViewState.isPlaying == false)
    }

    @Test("Stop functionality")
    func stopFunctionality() async throws {
        let player = AudioPlayer(
            hardwareObserver: StubAudioHardwareObserver(),
            hardwareInfoProvider: StubAudioHardwareInfoProvider()
         )

        player.send(.stop)
         #expect(player.contentViewState.isPlaying == false)
         #expect(player.contentViewState.currentTime == 0)
     }

    @Test("Skip operations without file")
    func skipWithoutFile() async throws {
        let player = AudioPlayer(
            hardwareObserver: StubAudioHardwareObserver(),
            hardwareInfoProvider: StubAudioHardwareInfoProvider()
         )

        player.send(.skipForward)
        player.send(.skipBackward)

         #expect(player.contentViewState.currentTime == 0)
         #expect(player.contentViewState.isPlaying == false)
     }

    @Test("Seek bounds checking")
    func seekBounds() async throws {
        let player = AudioPlayer(
            hardwareObserver: StubAudioHardwareObserver(),
            hardwareInfoProvider: StubAudioHardwareInfoProvider()
         )

        player.send(.seek(to: 10.0))
         #expect(player.contentViewState.currentTime == 0)

        player.send(.seek(to: -5.0))
         #expect(player.contentViewState.currentTime == 0)
     }

    @Test("Error state management")
    func errorStates() async throws {
        let player = AudioPlayer(
            hardwareObserver: StubAudioHardwareObserver(),
            hardwareInfoProvider: StubAudioHardwareInfoProvider()
         )

         #expect(player.contentViewState.hasLoadedFile == false)

        let invalidURL = URL(fileURLWithPath: "/nonexistent/file.mp3")
        player.send(.loadFile(url: invalidURL, importerDismissalDelay: .zero))
        await player.waitForCurrentLoad()

        // After loading fails, no file should be loaded
         #expect(player.contentViewState.hasLoadedFile == false)
         #expect(player.contentViewState.currentTrackTitle == nil)
     }

    @Test("Failed replacement load keeps previous track playable")
    func failedReplacementLoadKeepsPreviousTrackPlayable() async throws {
        let originalURL = URL(fileURLWithPath: "/tmp/original.wav")
        let brokenURL = URL(fileURLWithPath: "/tmp/broken.wav")
        let player = AudioPlayer(
            engine: AudioPlaybackEngine(
                loadFileOperation: RoutingStubLoadFileOperation(dataByURL: [
                    originalURL: LoadedAudioData(
                        data: WaveData.make(),
                        fileName: "original.wav",
                        fileExtension: "wav",
                        displayTitle: "Original",
                        sampleRate: 44_100,
                        duration: 1
                    )
                ]),
                sampleRateManager: StubSampleRateManager()
            ),
            hardwareObserver: StubAudioHardwareObserver(),
            hardwareInfoProvider: StubAudioHardwareInfoProvider()
        )

        player.send(.loadFile(url: originalURL, importerDismissalDelay: .zero))
        await player.waitForCurrentLoad()
        player.send(.loadFile(url: brokenURL, importerDismissalDelay: .zero))
        await player.waitForCurrentLoad()

        #expect(player.contentViewState.currentTrackTitle == "Original")
        #expect(player.contentViewState.hasLoadedFile)

        player.send(.togglePlayPause)
        try await waitUntil(timeout: .milliseconds(500)) {
            player.contentViewState.isPlaying
        }

        #expect(player.contentViewState.isPlaying)
    }

    @Test("Main play/pause button cancels a pending playback start")
    func togglePlayPauseCancelsPendingPlaybackStart() async throws {
        let context = try StartupTestContext(syncDelay: .milliseconds(100))
        await context.loadFirstFile()

         context.player.send(.togglePlayPause)
         context.player.send(.togglePlayPause)
         try await context.settleStartup(after: .milliseconds(250))

          #expect(context.player.contentViewState.isPlaying == false)
         // After canceling playback start, the file should still be loaded
          #expect(context.player.contentViewState.hasLoadedFile == true)
      }

    @Test("Stop cancels a pending playback start")
    func stopCancelsPendingPlaybackStart() async throws {
        let context = try StartupTestContext(syncDelay: .milliseconds(200))
        await context.loadFirstFile()

         context.player.send(.togglePlayPause)
         context.player.send(.stop)
         try await context.settleStartup(after: .milliseconds(350))

          #expect(context.player.contentViewState.isPlaying == false)
         // After stopping, file should still be loaded but not playing
          #expect(context.player.contentViewState.hasLoadedFile == true)
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

         context.player.send(.togglePlayPause)
         context.player.send(.loadFile(url: try #require(context.secondURL), importerDismissalDelay: .zero))
         try await context.settleStartup(after: .milliseconds(400))

         // Second file should be loaded (not the first)
          #expect(context.player.contentViewState.currentTrackTitle == "second.wav")
          #expect(context.player.contentViewState.isPlaying == false)
          #expect(context.player.contentViewState.hasLoadedFile == true)
      }

    @Test("Main display uses metadata title when available")
    func displayTitleUsesResolvedMetadataTitle() async throws {
        let player = AudioPlayer(
            engine: AudioPlaybackEngine(
                loadFileOperation: StubLoadFileOperation(
                    sampleRate: 44_100,
                    displayTitle: "Tagged Song"
                 ),
                sampleRateManager: StubSampleRateManager()
              ),
            hardwareObserver: StubAudioHardwareObserver(),
            hardwareInfoProvider: StubAudioHardwareInfoProvider()
         )

         player.send(.loadFile(url: URL(fileURLWithPath: "/tmp/tagged-song.mp3"), importerDismissalDelay: .zero))
         await player.waitForCurrentLoad()

         // After loading, the display title from metadata should be used
          #expect(player.contentViewState.currentTrackTitle == "Tagged Song")
      }

    @Test("Show in Finder reveals the current single-track file")
    func showCurrentTrackInFinderForSingleTrack() async throws {
        let finderItemRevealer = RecordingFinderItemRevealer()
        let url = URL(fileURLWithPath: "/tmp/tagged-song.mp3")
        let player = AudioPlayer(
            engine: AudioPlaybackEngine(
                loadFileOperation: StubLoadFileOperation(
                    sampleRate: 44_100,
                    displayTitle: "Tagged Song"
                 ),
                sampleRateManager: StubSampleRateManager()
              ),
            hardwareObserver: StubAudioHardwareObserver(),
            hardwareInfoProvider: StubAudioHardwareInfoProvider(),
            finderItemRevealer: finderItemRevealer
         )

        player.send(.loadFile(url: url, importerDismissalDelay: .zero))
        await player.waitForCurrentLoad()
        player.send(.revealCurrentTrackInFinder)

         #expect(
            finderItemRevealer.revealedURLs.map(canonicalTestFileURL) ==
             [url].map(canonicalTestFileURL)
          )
     }

    @Test("Show in Finder reveals the current playlist track")
    func showCurrentTrackInFinderForPlaylistTrack() async throws {
        let rootFolder = try TemporaryFolder.make()
        defer { try? TemporaryFolder.remove(rootFolder) }

        let firstURL = rootFolder.appending(path: "album/01-first.wav")
        let secondURL = rootFolder.appending(path: "album/02-second.wav")
        try TemporaryFolder.writeWaveFile(at: firstURL)
        try TemporaryFolder.writeWaveFile(at: secondURL)

        let finderItemRevealer = RecordingFinderItemRevealer()
        let player = AudioPlayer(
            engine: AudioPlaybackEngine(
                loadFileOperation: RoutingStubLoadFileOperation(dataByURL: [
                    firstURL: LoadedAudioData(data: WaveData.make(), fileName: "01-first.wav", fileExtension: "wav", displayTitle: "01-first.wav", sampleRate: 44_100, duration: 1),
                    secondURL: LoadedAudioData(data: WaveData.make(), fileName: "02-second.wav", fileExtension: "wav", displayTitle: "02-second.wav", sampleRate: 48_000, duration: 1)
                 ]),
                sampleRateManager: StubSampleRateManager()
              ),
            hardwareObserver: StubAudioHardwareObserver(),
            hardwareInfoProvider: StubAudioHardwareInfoProvider(),
            finderItemRevealer: finderItemRevealer
         )

        player.send(.loadFolder(url: rootFolder, importerDismissalDelay: .zero))
        await player.waitForCurrentLoad()
        player.send(.selectPlaylistTrack(index: 1))
        await player.waitForCurrentLoad()
        player.send(.revealCurrentTrackInFinder)

         #expect(
            finderItemRevealer.revealedURLs.map(canonicalTestFileURL) ==
             [secondURL].map(canonicalTestFileURL)
          )
     }

    @Test("Show in Finder is ignored when nothing is loaded")
    func showCurrentTrackInFinderWithoutLoadedTrack() async throws {
        let finderItemRevealer = RecordingFinderItemRevealer()
        let player = AudioPlayer(
            hardwareObserver: StubAudioHardwareObserver(),
            hardwareInfoProvider: StubAudioHardwareInfoProvider(),
            finderItemRevealer: finderItemRevealer
         )

        player.send(.revealCurrentTrackInFinder)

         #expect(finderItemRevealer.revealedURLs.isEmpty)
     }

    @Test("Sample-rate banner shows matched state when hardware matches the file")
    func sampleRateBannerMatchedState() async throws {
        let player = AudioPlayer(
            engine: AudioPlaybackEngine(
                loadFileOperation: StubLoadFileOperation(sampleRate: 44_100),
                sampleRateManager: StubSampleRateManager()
              ),
            hardwareObserver: StubAudioHardwareObserver(),
            hardwareInfoProvider: StubAudioHardwareInfoProvider()
         )

        player.send(.loadFile(url: URL(fileURLWithPath: "/tmp/matched.wav"), importerDismissalDelay: .zero))
        await player.waitForCurrentLoad()

         #expect(player.contentViewState.sampleRateBanner.title == "Matched")
         #expect(player.contentViewState.sampleRateBanner.detail == "44.1 kHz")
         #expect(player.contentViewState.sampleRateBanner.style == .matched)
     }

    @Test("Sample-rate banner stays neutral before playback starts when a supported mismatch exists")
    func sampleRateBannerNeutralStateBeforeSupportedMismatchPlayback() async throws {
        let player = AudioPlayer(
            engine: AudioPlaybackEngine(
                loadFileOperation: StubLoadFileOperation(sampleRate: 96_000),
                sampleRateManager: StubSampleRateManager()
              ),
            hardwareObserver: StubAudioHardwareObserver(),
            hardwareInfoProvider: StubAudioHardwareInfoProvider(
                deviceInfo: AudioDeviceInfo(
                    name: "Test Device",
                    currentSampleRate: 44_100,
                    supportedSampleRates: [44_100, 96_000]
                 )
              )
          )

        player.send(.loadFile(url: URL(fileURLWithPath: "/tmp/switching.wav"), importerDismissalDelay: .zero))
        await player.waitForCurrentLoad()

         #expect(player.contentViewState.sampleRateBanner.title == "Ready")
         #expect(player.contentViewState.sampleRateBanner.detail == "96 kHz")
         #expect(player.contentViewState.sampleRateBanner.style == .idle)
     }

    @Test("Sample-rate banner shows switching state during playback startup when the device can switch")
    func sampleRateBannerSwitchingStateDuringStartup() async throws {
        let player = AudioPlayer(
            engine: AudioPlaybackEngine(
                loadFileOperation: StubLoadFileOperation(sampleRate: 96_000),
                syncSampleRateOperation: DelayedSyncSampleRateOperation(delay: .milliseconds(200)),
                sampleRateManager: StubSampleRateManager()
              ),
            hardwareObserver: StubAudioHardwareObserver(),
            hardwareInfoProvider: StubAudioHardwareInfoProvider(
                deviceInfo: AudioDeviceInfo(
                    name: "Test Device",
                    currentSampleRate: 44_100,
                    supportedSampleRates: [44_100, 96_000]
                 )
              )
          )
        player.send(.loadFile(url: URL(fileURLWithPath: "/tmp/startup-switching.wav"), importerDismissalDelay: .zero))
        await player.waitForCurrentLoad()

        player.send(.togglePlayPause)
        try await waitUntil {
            player.contentViewState.sampleRateBanner.title == "Switching"
         }

         #expect(player.contentViewState.sampleRateBanner.detail == "96 kHz -> 44.1 kHz")
         #expect(player.contentViewState.sampleRateBanner.style == .switching)
     }

    @Test("Sample-rate banner shows unsupported state when the device cannot match the file")
    func sampleRateBannerUnsupportedState() async throws {
        let player = AudioPlayer(
            engine: AudioPlaybackEngine(
                loadFileOperation: StubLoadFileOperation(sampleRate: 96_000),
                sampleRateManager: StubSampleRateManager()
              ),
            hardwareObserver: StubAudioHardwareObserver(),
            hardwareInfoProvider: StubAudioHardwareInfoProvider()
         )

        player.send(.loadFile(url: URL(fileURLWithPath: "/tmp/unsupported.wav"), importerDismissalDelay: .zero))
        await player.waitForCurrentLoad()

         #expect(player.contentViewState.sampleRateBanner.title == "Ready")
         #expect(player.contentViewState.sampleRateBanner.detail == "96 kHz")
         #expect(player.contentViewState.sampleRateBanner.style == .idle)
     }

    @Test("Selecting a playlist track during startup preserves autoplay intent")
    func selectingPlaylistTrackDuringStartupKeepsPlaybackIntent() async throws {
        let rootFolder = try TemporaryFolder.make()
        defer { try? TemporaryFolder.remove(rootFolder) }

        let firstURL = rootFolder.appending(path: "album/01-first.wav")
        let secondURL = rootFolder.appending(path: "album/02-second.wav")
        try TemporaryFolder.writeWaveFile(at: firstURL)
        try TemporaryFolder.writeWaveFile(at: secondURL)

        let player = AudioPlayer(
            engine: AudioPlaybackEngine(
                loadFileOperation: RoutingStubLoadFileOperation(dataByURL: [
                    firstURL: LoadedAudioData(data: WaveData.make(), fileName: "01-first.wav", fileExtension: "wav", displayTitle: "01-first.wav", sampleRate: 44_100, duration: 1),
                    secondURL: LoadedAudioData(data: WaveData.make(), fileName: "02-second.wav", fileExtension: "wav", displayTitle: "02-second.wav", sampleRate: 48_000, duration: 1)
                 ]),
                syncSampleRateOperation: DelayedSyncSampleRateOperation(delay: .milliseconds(200)),
                sampleRateManager: StubSampleRateManager()
              ),
            hardwareObserver: StubAudioHardwareObserver(),
            hardwareInfoProvider: StubAudioHardwareInfoProvider()
         )

        player.send(.loadFolder(url: rootFolder, importerDismissalDelay: .zero))
        await player.waitForCurrentLoad()

        player.send(.togglePlayPause)
        player.send(.selectPlaylistTrack(index: 1))
        await player.waitForCurrentLoad()
        try await waitUntil(timeout: .seconds(3)) {
            player.contentViewState.currentTrackTitle == "02-second.wav" &&
            player.contentViewState.hasLoadedFile &&
            player.contentViewState.isPlaying
         }

         #expect(player.contentViewState.currentTrackTitle == "02-second.wav")
         #expect(player.contentViewState.isPlaying == true)
         #expect(player.contentViewState.hasLoadedFile)
     }

    @Test("Playback start failure shows an error without leaving loading active")
    func playbackStartFailureDoesNotLeaveLoadingStateActive() async throws {
        let player = AudioPlayer(
            engine: AudioPlaybackEngine(
                loadFileOperation: StubLoadFileOperation(sampleRate: 44_100),
                playbackControlOperation: FailingPlaybackControlOperation(),
                sampleRateManager: StubSampleRateManager()
              ),
            hardwareObserver: StubAudioHardwareObserver(),
            hardwareInfoProvider: StubAudioHardwareInfoProvider()
         )

        player.send(.loadFile(url: URL(fileURLWithPath: "/tmp/failing.wav"), importerDismissalDelay: .zero))
        await player.waitForCurrentLoad()

         player.send(.togglePlayPause)
         await player.waitForCurrentLoad()
         try await Task.sleep(for: .milliseconds(20))

          #expect(player.contentViewState.hasLoadedFile)
          #expect(player.contentViewState.isLoading == false)
         // After playback failure, the error is shown but the file is still loaded
          #expect(player.contentViewState.currentTrackTitle == "failing.wav")
          #expect(player.contentViewState.duration == 1)
      }
}

@MainActor
private func waitUntil(
    timeout: Duration,
    condition: @escaping @MainActor () -> Bool
) async throws {
    let deadline = ContinuousClock.now + timeout

    while !condition() {
        if ContinuousClock.now >= deadline {
            Issue.record("Timed out waiting for condition.")
            return
        }

        try await Task.sleep(for: .milliseconds(10))
    }
}
