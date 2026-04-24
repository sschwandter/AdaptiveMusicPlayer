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
    }

    var isStartingPlayback: Bool {
        startupCoordinator.isStartingPlayback
    }

    func waitForCurrentActivity() async {
        await loadCoordinator.waitForCurrentLoad()
        await startupCoordinator.waitForCurrentStartup()
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
            dispatch(.commandIgnored(.notReady))
        case .synchronizeSampleRates:
            Task { @MainActor [weak self] in
                await self?.synchronizeSampleRates()
            }
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
        let audioInfo = engine.stop()
        stopProgressTracking()
        dispatch(.playbackStopped(preservedAudioInfo: audioInfo))
    }

    private func seek(to time: Double) {
        do {
            let newTime = try engine.seek(to: time)
            dispatch(.progressChanged(newTime))
        } catch {
            dispatch(.commandIgnored(.noFileLoaded))
        }
    }

    private func skipForward() {
        do {
            let newTime = try engine.skipForward(from: stateStore.currentTime)
            dispatch(.progressChanged(newTime))
        } catch {
            dispatch(.commandIgnored(.noFileLoaded))
        }
    }

    private func skipBackward() {
        do {
            let newTime = try engine.skipBackward(from: stateStore.currentTime)
            dispatch(.progressChanged(newTime))
        } catch {
            dispatch(.commandIgnored(.noFileLoaded))
        }
    }

    private func synchronizeSampleRates() async {
        do {
            try await engine.synchronizeSampleRates()

            do {
                try await Task.sleep(for: .milliseconds(500))
            } catch {
                return
            }

            await refreshHardwareInfo()

            let sampleRatePresentation = stateStore.sampleRatePresentation(
                isAttemptingPlaybackStart: isStartingPlayback
            )
            if sampleRatePresentation.hasMismatch {
                showError(.sampleRateSyncFailed(sampleRatePresentation.statusDetail))
            } else {
                dispatchStatus(
                    statusPresenter.presentInfo(
                        message: "Hardware sample rate set to \(SampleRatePresenter.formatSampleRate(stateStore.fileSampleRate)) on \(sampleRatePresentation.hardwareDeviceDisplayName)"
                    )
                )
            }
        } catch let error as PlaybackError {
            showError(error)
        } catch {
            showError(.sampleRateSyncFailed(error.localizedDescription))
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
        case .cancelled:
            handleLoadCancellation()
        case .failed(let error):
            showError(error)
        }
    }

    private func beginLoading(phase: AudioPlayerLoadPhase) {
        _ = cancelPendingPlaybackStart()
        let preservedAudioInfo = engine.beginLoading()
        stopProgressTracking()
        dispatch(.loadStarted(preservedAudioInfo: preservedAudioInfo, phase: phase))
    }

    private func finishLoadingTrack(
        from trackURL: URL,
        audioInfo: AudioInfo,
        autoplayOnSuccess: Bool
    ) async throws {
        dispatch(.trackReady(url: trackURL, audioInfo: audioInfo))
        engine.setVolume(currentVolume())
        await refreshHardwareInfo()
        showReadyStatus(for: audioInfo)

        if autoplayOnSuccess {
            startPlayback()
        }
    }

    private func handleLoadCancellation() {
        stopProgressTracking()
        dispatch(.loadingCancelled)
    }

    private func startPlayback() {
        startupCoordinator.startPlayback(
            play: { [engine] in
                try await engine.play()
            },
            handleEvent: { [weak self] event in
                await self?.handlePlaybackStartupEvent(event)
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
            let audioInfo = try engine.pause()
            stopProgressTracking()
            dispatch(.playbackPaused(audioInfo))
        } catch let error as PlaybackError {
            showError(error)
        } catch {
            showError(.notPlaying)
        }
    }

    private func handlePlaybackStartupEvent(_ event: PlaybackStartupCoordinator.Event) async {
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
            let preservedAudioInfo = engine.stop()
            dispatch(.playbackStopped(preservedAudioInfo: preservedAudioInfo))
        }
    }

    private func finishSuccessfulPlaybackStart(audioInfo: AudioInfo) async {
        dispatch(.playbackStarted(audioInfo))
        startProgressTracking()
        await refreshHardwareInfo()
        showPlayingStatus()
    }

    private func startProgressTracking() {
        // Cancel any existing tracking
        stopProgressTracking()

        // Start hardware refresh task (separate from progress tracking)
        hardwareRefreshTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                await self?.refreshHardwareInfo()
                try? await Task.sleep(for: Constants.hardwareRefreshInterval)
            }
        }

        // Forward progress updates as they arrive so the slider stays responsive.
        progressTrackingTask = Task { @MainActor [weak self] in
            guard let self else { return }

            let progressStream = self.engine.trackProgress(
                using: self.progressTracker,
                updateInterval: Constants.progressUpdateInterval
            )

            for await event in progressStream {
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
                    phase: .ready,
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
                    phase: .playing,
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
