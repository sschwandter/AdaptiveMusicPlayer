import Testing
import Foundation
import AVFoundation
@testable import AdaptiveMusicPlayerCore
@testable import AdaptiveMusicPlayer

@Suite("Playback Regression Tests")
@MainActor
struct PlaybackRegressionTests {
    @Test("Pause reaches the engine while startup is refreshing hardware")
    func pauseWhileStartupRefreshIsPending() async throws {
        let gate = PlaybackRefreshGate()
        let operation = RecordingRegressionPlaybackOperation()
        let (controller, state) = makeController(
            operation: operation,
            refresh: { await gate.refresh() }
        )
        controller.send(.loadFile(url: trackURL("first"), importerDismissalDelay: .zero))
        await controller.waitForCurrentActivity()
        gate.armed = true
        controller.send(.togglePlayPause)
        try await waitUntil { gate.blocked && state.isPlaying }
        #expect(controller.isStartingPlayback)

        controller.send(.togglePlayPause)
        gate.release()
        try await waitUntil { !state.isPlaying }

        #expect(operation.pauseCount == 1)
        #expect(state.statusMessage == "Paused")
        controller.send(.stop)
    }

    @Test("Stale startup completion leaves a replacement load's controls disabled")
    func staleStartupMustNotClearReplacementLoading() async throws {
        let gate = PlaybackRefreshGate()
        let (controller, state) = makeController(refresh: { await gate.refresh() })
        controller.send(.loadFile(url: trackURL("first"), importerDismissalDelay: .zero))
        await controller.waitForCurrentActivity()
        gate.armed = true
        controller.send(.togglePlayPause)
        try await waitUntil { gate.blocked && state.isPlaying }

        controller.send(.loadFile(url: trackURL("second"), importerDismissalDelay: .milliseconds(500)))
        try await waitUntil { state.isLoading }
        gate.release()
        // Let the cancelled startup finish while the new load is still waiting.
        try await Task.sleep(for: .milliseconds(50))

        #expect(state.isLoading)
        #expect(state.statusMessage == "Loading file...")
        await controller.waitForCurrentActivity()
    }

    @Test("A cancelled load's late failure cannot change newer playback")
    func staleLoadFailureMustNotDowngradeNewPlayback() async throws {
        let loader = GatedFailureLoadOperation()
        let (controller, state) = makeController(loader: loader)
        controller.send(.loadFile(url: trackURL("broken"), importerDismissalDelay: .zero))
        await loader.waitUntilBlocked()
        controller.send(.loadFile(url: trackURL("good"), importerDismissalDelay: .zero))
        await controller.waitForCurrentActivity()
        controller.send(.togglePlayPause)
        await controller.waitForCurrentActivity()
        try await waitUntil { state.isPlaying }

        await loader.release()
        try await Task.sleep(for: .milliseconds(50))

        #expect(state.isPlaying)
        #expect(state.currentFileName == "good.wav")
        controller.send(.stop)
    }

    @Test("Overlapping engine loads suppress an old failure without caller cancellation")
    func engineRejectsSupersededLoad() async throws {
        let loader = GatedFailureLoadOperation()
        let engine = AudioPlaybackEngine(loadFileOperation: loader, sampleRateManager: StubSampleRateManager())
        let oldLoad = Task { try await engine.loadFile(from: trackURL("broken")) }
        await loader.waitUntilBlocked()
        let currentInfo = try await engine.loadFile(from: trackURL("good"))
        await loader.release()

        do {
            _ = try await oldLoad.value
            Issue.record("Expected the superseded load to throw CancellationError")
        } catch is CancellationError {
            #expect(engine.currentAudioInfo == currentInfo)
        } catch {
            Issue.record("Expected CancellationError, got \(error)")
        }
    }

    @Test("Failed file replacement preserves the URL of the loaded audio")
    func failedReplacementMustKeepCurrentURLConsistent() async throws {
        let good = trackURL("good")
        let (controller, state) = makeController(
            loader: RoutingStubLoadFileOperation(dataByURL: [good: regressionAudioData(good)])
        )
        controller.send(.loadFile(url: good, importerDismissalDelay: .zero))
        await controller.waitForCurrentActivity()
        controller.send(.loadFile(url: trackURL("bad"), importerDismissalDelay: .zero))
        await controller.waitForCurrentActivity()

        #expect(state.currentFileName == good.lastPathComponent)
        #expect(state.currentTrackURL == good)
        #expect(state.sessionState.pendingTrackLoad == nil)
    }

    @Test("Failed playlist selection preserves the active index and metadata")
    func failedPlaylistSelectionPreservesLoadedSession() async throws {
        let folder = try TemporaryFolder.make()
        defer { try? TemporaryFolder.remove(folder) }
        let tracks = ["01-first.wav", "02-broken.wav"].map { folder.appending(path: $0) }
        let (controller, state) = makeController(
            loader: RoutingStubLoadFileOperation(dataByURL: [tracks[0]: regressionAudioData(tracks[0])]),
            scanner: DelayedFolderScanner(delay: 0, tracks: tracks)
        )
        controller.send(.loadFolder(url: folder, importerDismissalDelay: .zero))
        await controller.waitForCurrentActivity()
        controller.send(.selectPlaylistTrack(index: 1))
        await controller.waitForCurrentActivity()

        #expect(state.currentTrackURL == tracks[0])
        #expect(state.playlistSession?.currentIndex == 0)
        #expect(state.playlistSession?.canMoveToNextTrack == true)
        #expect(state.currentDisplayTitle == tracks[0].lastPathComponent)
        #expect(state.sessionState.pendingTrackLoad == nil)
    }

    @Test("Failed first load does not commit a playlist")
    func failedFirstLoadHasNoCurrentTrack() async {
        let (controller, state) = makeController(loader: RoutingStubLoadFileOperation(dataByURL: [:]))
        controller.send(.loadFile(url: trackURL("bad"), importerDismissalDelay: .zero))
        await controller.waitForCurrentActivity()

        #expect(state.currentTrackURL == nil)
        #expect(state.playlistSession == nil)
        #expect(state.currentAudioInfo == nil)
        #expect(!state.isLoading)
    }

    @Test("Seeking or skipping backward from finished preserves the new position", arguments: [false, true])
    func seekingBackFromFinishedMustNotRewindOnPlay(skipBackward: Bool) async throws {
        let operation = RecordingRegressionPlaybackOperation()
        let url = trackURL("good")
        let engine = AudioPlaybackEngine(
            loadFileOperation: RoutingStubLoadFileOperation(dataByURL: [url: regressionAudioData(url)]),
            playbackControlOperation: operation,
            sampleRateManager: StubSampleRateManager()
        )
        _ = try await engine.loadFile(from: url)
        _ = engine.markFinished()
        let expectedTime = skipBackward
            ? try engine.skipBackward(from: 20)
            : try engine.seek(to: 5)
        _ = try await engine.play()

        #expect(!operation.lastWasAtEnd)
        #expect(abs(operation.lastStartTime - expectedTime) < 0.001)
        #expect(operation.lastStartTime > 0)
    }

    @Test("A completed sample-rate attempt displays resampling rather than switching")
    func settledMismatchMustNotClaimSwitching() {
        let output = SampleRatePresenter().build(from: SampleRatePresentationInput(
            fileSampleRate: 96_000,
            hardwareSampleRate: 44_100,
            hardwareDeviceName: "DAC",
            supportedHardwareSampleRates: [44_100, 96_000],
            hasError: false,
            statusMessage: "",
            isPlaying: true,
            isAttemptingPlaybackStart: false
        ))

        #expect(output.banner.title == "Resampling")
        #expect(output.banner.style == .resampling)
        #expect(output.banner.helpText.contains("Playback is being resampled."))
    }

    @Test("The player leaves the switching banner after hardware refuses a rate")
    func refusedSampleRateShowsResamplingAfterStartup() async {
        let player = AudioPlayer(
            engine: AudioPlaybackEngine(
                loadFileOperation: StubLoadFileOperation(sampleRate: 96_000),
                playbackControlOperation: SucceedingPlaybackControlOperation(),
                syncSampleRateOperation: RefusingSampleRateOperation(),
                sampleRateManager: StubSampleRateManager()
            ),
            progressTracker: RecordingPlaybackProgressTracker(),
            hardwareObserver: StubAudioHardwareObserver(),
            hardwareInfoProvider: StubAudioHardwareInfoProvider(deviceInfo: AudioDeviceInfo(
                name: "DAC",
                currentSampleRate: 44_100,
                supportedSampleRates: [44_100, 96_000]
            ))
        )
        player.send(.loadFile(url: trackURL("good"), importerDismissalDelay: .zero))
        await player.waitForCurrentLoad()
        player.send(.togglePlayPause)
        await player.waitForCurrentLoad()

        #expect(player.contentViewState.isPlaying)
        #expect(player.sampleRateBannerPresentation.title == "Resampling")
        player.send(.stop)
    }

    @Test("Replacing a pending playlist selection preserves autoplay", arguments: [0, 2])
    func rapidPlaylistSelectionMustPreserveAutoplay(finalIndex: Int) async throws {
        let folder = try TemporaryFolder.make()
        defer { try? TemporaryFolder.remove(folder) }
        let tracks = ["01-first.wav", "02-second.wav", "03-third.wav"].map { folder.appending(path: $0) }
        let (controller, state) = makeController(
            loader: DelayedPlaylistLoadOperation(),
            scanner: DelayedFolderScanner(delay: 0, tracks: tracks)
        )
        controller.send(.loadFolder(url: folder, importerDismissalDelay: .zero))
        await controller.waitForCurrentActivity()
        controller.send(.togglePlayPause)
        await controller.waitForCurrentActivity()
        try await waitUntil { state.isPlaying }
        controller.send(.selectPlaylistTrack(index: 1))
        try await waitUntil {
            state.isLoading && state.sessionState.pendingTrackLoad?.playlistSession.currentTrackURL == tracks[1]
        }
        #expect(state.currentTrackURL == tracks[0])

        controller.send(.selectPlaylistTrack(index: finalIndex))
        await controller.waitForCurrentActivity()

        #expect(state.currentTrackURL == tracks[finalIndex])
        #expect(state.isPlaying)
        #expect(state.sessionState.pendingTrackLoad == nil)
        controller.send(.stop)
    }

    private func makeController(
        loader: any LoadFileOperationProtocol = StubLoadFileOperation(sampleRate: 44_100),
        operation: any PlaybackControlOperationProtocol = RecordingRegressionPlaybackOperation(),
        scanner: any AudioPlaylistFolderScanning = AudioPlaylistFolderScanner(),
        refresh: @escaping @MainActor () async -> Void = {}
    ) -> (AudioPlayerSessionController, AudioPlayerStateStore) {
        let state = AudioPlayerStateStore()
        let engine = AudioPlaybackEngine(
            loadFileOperation: loader,
            playbackControlOperation: operation,
            sampleRateManager: StubSampleRateManager()
        )
        let controller = AudioPlayerSessionController(
            stateStore: state,
            engine: engine,
            progressTracker: RecordingPlaybackProgressTracker(),
            loadCoordinator: AudioPlayerLoadCoordinator(folderScanner: scanner),
            refreshHardwareInfo: refresh,
            currentVolume: { 1 }
        )
        return (controller, state)
    }

    private func trackURL(_ name: String) -> URL {
        URL(fileURLWithPath: "/tmp/\(name).wav")
    }
}

@MainActor
private final class PlaybackRefreshGate {
    var armed = false
    private(set) var blocked = false
    private var continuation: CheckedContinuation<Void, Never>?

    func refresh() async {
        guard armed else { return }
        armed = false
        blocked = true
        await withCheckedContinuation { continuation = $0 }
    }

    func release() {
        continuation?.resume()
        continuation = nil
    }
}

/// Playback operations are synchronous and invoked by the main-actor engine.
private final class RecordingRegressionPlaybackOperation: PlaybackControlOperationProtocol, @unchecked Sendable {
    private(set) var pauseCount = 0
    private(set) var lastWasAtEnd = false
    private(set) var lastStartTime = 0.0

    func play(player: AVAudioPlayer, audioInfo: AudioInfo, isAtEnd: Bool) throws -> EnginePlaybackState {
        lastWasAtEnd = isAtEnd
        if isAtEnd { player.currentTime = 0 }
        lastStartTime = player.currentTime
        return .playing(audioInfo)
    }

    func pause(player: AVAudioPlayer, audioInfo: AudioInfo) throws -> EnginePlaybackState {
        pauseCount += 1
        return .paused(audioInfo)
    }

    func stop(player: AVAudioPlayer, audioInfo: AudioInfo) -> EnginePlaybackState {
        .ready(audioInfo)
    }
}

private actor GatedFailureLoadOperation: LoadFileOperationProtocol {
    private var continuation: CheckedContinuation<Void, Never>?
    private var blockedWaiters: [CheckedContinuation<Void, Never>] = []

    func execute(from url: URL) async throws -> LoadedAudioData {
        if url.lastPathComponent == "broken.wav" {
            await withCheckedContinuation {
                continuation = $0
                blockedWaiters.forEach { $0.resume() }
                blockedWaiters.removeAll()
            }
            // Simulate I/O that completes with an error despite cancellation.
            throw PlaybackError.loadFailed("I/O failed after replacement")
        }
        return regressionAudioData(url)
    }

    func waitUntilBlocked() async {
        guard continuation == nil else { return }
        await withCheckedContinuation { blockedWaiters.append($0) }
    }

    func release() {
        continuation?.resume()
        continuation = nil
    }
}

private struct DelayedPlaylistLoadOperation: LoadFileOperationProtocol {
    func execute(from url: URL) async throws -> LoadedAudioData {
        if url.lastPathComponent == "02-second.wav" {
            try await Task.sleep(for: .seconds(1))
        }
        return regressionAudioData(url)
    }
}

private struct RefusingSampleRateOperation: SyncSampleRateOperationProtocol {
    func execute(audioInfo: AudioInfo, sampleRateManager: SampleRateManaging) async throws {
        throw SampleRateManagerError.settlingTimedOut(targetRate: audioInfo.sampleRate, currentRate: 44_100)
    }
}

private func regressionAudioData(_ url: URL) -> LoadedAudioData {
    LoadedAudioData(
        data: WaveData.make(frameCount: 44_100 * 20),
        fileName: url.lastPathComponent,
        fileExtension: "wav",
        displayTitle: url.lastPathComponent,
        sampleRate: 44_100,
        duration: 20
    )
}
