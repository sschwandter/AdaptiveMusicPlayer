import AdaptiveMusicPlayerCore
import Foundation

@MainActor
final class AudioPlayerSessionController {
    private enum Constants {
        static let progressUpdateInterval: TimeInterval = 0.1
        static let hardwareRefreshInterval: Duration = .seconds(5)
    }

    private let stateStore: AudioPlayerStateStore
    private let engine: AudioPlaybackEngine
    private let progressTracker: PlaybackProgressTracking
    private let loadCoordinator: AudioPlayerLoadCoordinator
    private let startupCoordinator: PlaybackStartupCoordinator
    private let statusPresenter: PlayerStatusPresenter
    private let refreshHardwareInfo: @MainActor () async -> Void
    private let currentVolume: @MainActor () -> Double

    // AsyncStream progress tracking tasks
    private var progressTrackingTask: Task<Void, Never>?
    private var hardwareRefreshTask: Task<Void, Never>?
    private var engineSubscriptionTask: Task<Void, Never>?

    init(
        stateStore: AudioPlayerStateStore,
        engine: AudioPlaybackEngine,
        progressTracker: PlaybackProgressTracking,
        loadCoordinator: AudioPlayerLoadCoordinator,
        startupCoordinator: PlaybackStartupCoordinator = PlaybackStartupCoordinator(),
        refreshHardwareInfo: @escaping @MainActor () async -> Void,
        currentVolume: @escaping @MainActor () -> Double,
        statusPresenter: PlayerStatusPresenter = PlayerStatusPresenter()
    ) {
        self.stateStore = stateStore
        self.engine = engine
        self.progressTracker = progressTracker
        self.loadCoordinator = loadCoordinator
        self.startupCoordinator = startupCoordinator
        self.refreshHardwareInfo = refreshHardwareInfo
        self.currentVolume = currentVolume
        self.statusPresenter = statusPresenter

        startEngineSubscription()
    }

    var isStartingPlayback: Bool {
        startupCoordinator.isStartingPlayback
    }

    func waitForCurrentActivity() async {
        await loadCoordinator.waitForCurrentLoad()
        await startupCoordinator.waitForCurrentStartup()
    }

    deinit {
        engineSubscriptionTask?.cancel()
        progressTrackingTask?.cancel()
        hardwareRefreshTask?.cancel()
    }

    private func startEngineSubscription() {
        engineSubscriptionTask?.cancel()
        // Capture the stream by value so the long-lived consumer task does not
        // retain the controller. Re-acquire `self` weakly each iteration so that
        // once the controller is released the loop exits and the task completes.
        let eventStream = engine.eventStream
        engineSubscriptionTask = Task { @MainActor [weak self] in
            for await event in eventStream {
                guard let self else { return }
                self.dispatch(.engineEventReceived(event))
            }
        }
    }

    func send(_ command: AudioPlayerCommand) {
        switch command {
        case .loadFile(let url, let importerDismissalDelay):
            loadFile(url: url, importerDismissalDelay: importerDismissalDelay)
        case .loadFolder(let url, let importerDismissalDelay):
            loadFolder(url: url, importerDismissalDelay: importerDismissalDelay)
        case .reportFileSelectionError(let message):
            showError(.loadFailed(message))
        case .togglePlayPause:
            togglePlayPause()
        case .stop:
            stop()
        case .seekStarted:
            dispatch(.seekStarted)
        case .seek(let time):
            seek(to: time)
        case .skipForward:
            skipForward()
        case .skipBackward:
            skipBackward()
        case .navigatePlaylist(let next, let autoplay):
            _ = loadAdjacentTrack(next: next, autoplay: autoplay)
        case .selectPlaylistTrack(let index):
            selectPlaylistTrack(
                at: index,
                shouldAutoplay: stateStore.isPlaying || isStartingPlayback
            )
        case .revealCurrentTrackInFinder:
            // Handled entirely by AudioPlayer before reaching the controller;
            // it never owns playback state, so there is nothing to do here.
            break
        case .setVolume(let volume):
            engine.setVolume(volume)
        }
    }

    private func loadFile(url: URL, importerDismissalDelay: Duration) {
        guard let playlistSession = PlaylistSession.singleTrack(url) else { return }

        loadCoordinator.loadFile(
            url: url,
            playlistSession: playlistSession,
            importerDismissalDelay: importerDismissalDelay,
            loadTrack: { [engine] trackURL in
                try await engine.loadFile(from: trackURL)
            },
            handleEvent: { [weak self] event in
                await self?.handleLoadEvent(event)
            }
        )
    }

    private func loadFolder(url: URL, importerDismissalDelay: Duration) {
        loadCoordinator.loadFolder(
            url: url,
            importerDismissalDelay: importerDismissalDelay,
            loadTrack: { [engine] trackURL in
                try await engine.loadFile(from: trackURL)
            },
            handleEvent: { [weak self] event in
                await self?.handleLoadEvent(event)
            }
        )
    }

    @discardableResult
    private func loadAdjacentTrack(next: Bool, autoplay: Bool = false) -> Bool {
        guard let playlistSession = stateStore.playlistSession else { return false }

        let nextPlaylistSession = next
            ? playlistSession.movingToNextTrack()
            : playlistSession.movingToPreviousTrack()

        guard let nextPlaylistSession else { return false }

        loadPlaylistTrack(
            playlistSession: nextPlaylistSession,
            autoplayOnSuccess: autoplay
        )
        return true
    }

    private func selectPlaylistTrack(at index: Int, shouldAutoplay: Bool) {
        guard let playlistSession = stateStore.playlistSession,
              playlistSession.currentIndex != index,
              let nextPlaylistSession = playlistSession.movingToTrack(at: index) else { return }

        loadPlaylistTrack(
            playlistSession: nextPlaylistSession,
            autoplayOnSuccess: shouldAutoplay
        )
    }

    private func togglePlayPause() {
        if stateStore.isPlaying || isStartingPlayback {
            pause()
        } else {
            startPlayback()
        }
    }

    private func stop() {
        _ = cancelPendingPlaybackStart()
        let stoppedAudioInfo = engine.stop()
        stopProgressTracking()
        dispatch(.playbackStopped(preservedAudioInfo: stoppedAudioInfo))
    }

    private func seek(to time: Double) {
        dispatch(.seekStarted)
        do {
            let newTime = try engine.seek(to: time)
            dispatch(.seekFinished(newTime))
        } catch let error as PlaybackError {
            dispatch(.commandIgnored(error))
        } catch {
            assertionFailure("Unexpected error from engine.seek(to:): \(error)")
        }
    }

    private func skipForward() {
        dispatch(.seekStarted)
        do {
            let newTime = try engine.skipForward(from: stateStore.currentTime)
            dispatch(.seekFinished(newTime))
        } catch let error as PlaybackError {
            dispatch(.commandIgnored(error))
        } catch {
            assertionFailure("Unexpected error from engine.skipForward(from:): \(error)")
        }
    }

    private func skipBackward() {
        dispatch(.seekStarted)
        do {
            let newTime = try engine.skipBackward(from: stateStore.currentTime)
            dispatch(.seekFinished(newTime))
        } catch let error as PlaybackError {
            dispatch(.commandIgnored(error))
        } catch {
            assertionFailure("Unexpected error from engine.skipBackward(from:): \(error)")
        }
    }

    @discardableResult
    func cancelPendingPlaybackStart() -> Bool {
        let cancelled = startupCoordinator.cancelStartup()
        if cancelled {
            stopProgressTracking()
        }
        return cancelled
    }

    private func loadPlaylistTrack(
        playlistSession: PlaylistSession,
        autoplayOnSuccess: Bool
    ) {
        loadCoordinator.loadPlaylistTrack(
            playlistSession: playlistSession,
            autoplayOnSuccess: autoplayOnSuccess,
            loadTrack: { [engine] trackURL in
                try await engine.loadFile(from: trackURL)
            },
            handleEvent: { [weak self] event in
                await self?.handleLoadEvent(event)
            }
        )
    }

    private func handleLoadEvent(_ event: AudioPlayerLoadCoordinator.Event) async {
        switch event {
        case .scanningFolderStarted:
            beginLoading(phase: .scanningFolder)
        case .trackLoadingStarted(let playlistSession):
            beginLoading(phase: .loadingTrack(playlistSession))
        case .playlistSessionUpdated(let playlistSession):
            dispatch(.playlistSessionUpdated(playlistSession))
        case .trackLoaded(let url, let audioInfo, let autoplayOnSuccess):
            do {
                try await finishLoadingTrack(
                    from: url,
                    audioInfo: audioInfo,
                    autoplayOnSuccess: autoplayOnSuccess
                )
            } catch let error as PlaybackError {
                showError(error)
            } catch {
                showError(.loadFailed(error.localizedDescription))
            }
        case .failed(let error):
            showError(error)
        }
    }

    private func beginLoading(phase: AudioPlayerLoadPhase) {
        _ = cancelPendingPlaybackStart()
        _ = engine.beginLoading()
        stopProgressTracking()
        dispatch(.loadStarted(preservedAudioInfo: engine.currentAudioInfo, phase: phase))
    }

    private func finishLoadingTrack(
        from trackURL: URL,
        audioInfo: AudioInfo,
        autoplayOnSuccess: Bool
    ) async throws {
        dispatch(.trackReady(url: trackURL, audioInfo: audioInfo))
        engine.setVolume(currentVolume())
        await refreshHardwareInfo()

        // A newer load can replace this one while awaiting the hardware
        // refresh; the load coordinator cancels this run's task when that
        // happens. Bail out so a stale load cannot publish ready status over
        // the newer load's progress — or worse, start playback of a track the
        // user has already moved past via an uncancelled startup task.
        guard !Task.isCancelled else { return }

        showReadyStatus(for: audioInfo)

        if autoplayOnSuccess {
            startPlayback()
        }
    }

    private func startPlayback() {
        // Shared between this startup's two closures so the stale-cleanup
        // path knows which player this startup actually started. Captured
        // inside `play` (not here) because a load can replace the player
        // between scheduling the startup and `engine.play()` running;
        // `play()`'s own identity guard makes the pre-play read authoritative.
        let startedPlayer = StartedPlayerGeneration()
        startupCoordinator.startPlayback(
            play: { [engine] in
                startedPlayer.value = engine.currentPlayerGeneration
                return try await engine.play()
            },
            handleEvent: { [weak self] event in
                await self?.handlePlaybackStartupEvent(event, startedPlayer: startedPlayer.value)
            }
        )
    }

    private func pause() {
        if cancelPendingPlaybackStart() {
            stopProgressTracking()
            dispatchStatus(statusPresenter.presentInfo(message: "Paused"))
            return
        }

        do {
            _ = try engine.pause()
            stopProgressTracking()
        } catch let error as PlaybackError {
            showError(error)
        } catch {
            // `engine.pause()` is contractually expected to throw only
            // `PlaybackError`. Treat any other thrown value as a programming
            // error rather than remapping it to a misleading "not playing"
            // user-facing message.
            assertionFailure("Unexpected error from engine.pause(): \(error)")
        }
    }

    private func handlePlaybackStartupEvent(
        _ event: PlaybackStartupCoordinator.Event,
        startedPlayer: Int?
    ) async {
        switch event {
        case .startupBegan:
            dispatch(.playbackStarting)
        case .startupCancelled:
            dispatch(.playbackStartCancelled)
        case .startupFinished(let audioInfo):
            await finishSuccessfulPlaybackStart(audioInfo: audioInfo)
        case .startupFailed(let error):
            showError(error)
        case .staleStartupFinished:
            // `engine.play()` returned successfully but the user has already
            // moved on (e.g. they hit stop or started a different track).
            // Stop the player this startup started so audio does not keep
            // playing behind the controller's back — but only if it is still
            // the engine's current player. If a newer load replaced it, that
            // load already stopped it, and an unconditional stop would kill
            // the newer startup's playback instead.
            if let startedPlayer {
                engine.stop(ifCurrentPlayerIs: startedPlayer)
            }
        }
    }

    private func finishSuccessfulPlaybackStart(audioInfo: AudioInfo) async {
        startPlaybackLifetimeTasks()
        await refreshHardwareInfo()
        showPlayingStatus()
    }

    /// Begin the long-lived tasks that should run only while playback is
    /// actively running. The matching `stopPlaybackLifetimeTasks()` must be
    /// called on every exit from the playing state so background work cannot
    /// leak.
    private func startPlaybackLifetimeTasks() {
        stopPlaybackLifetimeTasks()

        // The hardware refresh task is owned by the playback lifetime because
        // mismatches between the file and the output device are most useful to
        // surface while audio is actually playing. It is intentionally separate
        // from progress tracking so its lifetime is named in the call sites.
        hardwareRefreshTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                await self?.refreshHardwareInfo()
                try? await Task.sleep(for: Constants.hardwareRefreshInterval)
            }
        }

        // Forward progress updates as they arrive so the slider stays responsive.
        // Like the engine subscription, capture the stream by value and
        // re-acquire `self` weakly per event: a strong capture here would keep
        // the controller (and the playing engine) alive after the owning view
        // is gone, so playback would outlive its window.
        let progressStream = engine.trackProgress(
            using: progressTracker,
            updateInterval: Constants.progressUpdateInterval
        )
        progressTrackingTask = Task { @MainActor [weak self] in
            for await event in progressStream {
                guard let self else { return }

                switch event {
                case .progress(let time):
                    self.dispatch(.progressChanged(time))

                case .finished:
                    await self.handlePlaybackFinished()
                }
            }
        }
    }

    private func stopProgressTracking() {
        stopPlaybackLifetimeTasks()
    }

    private func stopPlaybackLifetimeTasks() {
        progressTrackingTask?.cancel()
        progressTrackingTask = nil
        hardwareRefreshTask?.cancel()
        hardwareRefreshTask = nil
        progressTracker.stopTracking()
    }

    private func handlePlaybackFinished() async {
        stopProgressTracking()
        if !loadAdjacentTrack(next: true, autoplay: true) {
            let audioInfo = engine.markFinished()
            dispatch(.playbackFinished(audioInfo))
        }
    }

    private func showReadyStatus(for audioInfo: AudioInfo) {
        let sampleRatePresentation = stateStore.sampleRatePresentation(
            isAttemptingPlaybackStart: false
        )
        dispatchStatus(
            statusPresenter.presentReady(
                PlayerStatusContext(
                    hasPlaylist: stateStore.playlistSession?.trackCount ?? 0 > 1,
                    playlistTrackPosition: stateStore.playlistSession?.positionDescription,
                    sampleRate: audioInfo.sampleRate,
                    hardwareDeviceName: sampleRatePresentation.hardwareDeviceDisplayName,
                    hasSampleRateMismatch: sampleRatePresentation.hasMismatch,
                    sampleRateStatusDetail: sampleRatePresentation.statusDetail
                )
            )
        )
    }

    private func showPlayingStatus() {
        let sampleRatePresentation = stateStore.sampleRatePresentation(
            isAttemptingPlaybackStart: isStartingPlayback
        )
        dispatchStatus(
            statusPresenter.presentPlaying(
                PlayerStatusContext(
                    hasPlaylist: stateStore.playlistSession?.trackCount ?? 0 > 1,
                    playlistTrackPosition: stateStore.playlistSession?.positionDescription,
                    sampleRate: stateStore.fileSampleRate,
                    hardwareDeviceName: sampleRatePresentation.hardwareDeviceDisplayName,
                    hasSampleRateMismatch: sampleRatePresentation.hasMismatch,
                    sampleRateStatusDetail: sampleRatePresentation.statusDetail
                )
            )
        )
    }

    private func showError(_ error: PlaybackError) {
        dispatchStatus(
            statusPresenter.presentError(
                error,
                hasCurrentAudio: stateStore.currentAudioInfo != nil
            )
        )
    }

    private func dispatchStatus(_ output: PlayerStatusPresentationOutput) {
        dispatch(.statusPresented(output))
    }

    private func dispatch(_ action: AudioPlayerAction) {
        stateStore.dispatch(action)
    }
}

/// Mutable box shared between one startup's `play` and `handleEvent` closures
/// (a plain captured `var` is rejected: `@MainActor` closures are Sendable).
@MainActor
private final class StartedPlayerGeneration {
    var value: Int?
}
