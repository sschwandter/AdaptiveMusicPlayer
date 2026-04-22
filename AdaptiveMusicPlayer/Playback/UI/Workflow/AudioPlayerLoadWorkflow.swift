import Foundation

@MainActor
final class AudioPlayerLoadWorkflow {
    private let stateStore: AudioPlayerStateStore
    private let engine: AudioPlaybackEngine
    private let loadCoordinator: AudioPlayerLoadCoordinator
    private let hardwareInfoProvider: AudioHardwareInfoProviding
    private let statusPresenter: PlayerStatusPresenter
    private let screenStateReducer: PlayerScreenStateReducer

    init(
        stateStore: AudioPlayerStateStore,
        engine: AudioPlaybackEngine,
        loadCoordinator: AudioPlayerLoadCoordinator,
        hardwareInfoProvider: AudioHardwareInfoProviding,
        statusPresenter: PlayerStatusPresenter = PlayerStatusPresenter(),
        screenStateReducer: PlayerScreenStateReducer = PlayerScreenStateReducer()
    ) {
        self.stateStore = stateStore
        self.engine = engine
        self.loadCoordinator = loadCoordinator
        self.hardwareInfoProvider = hardwareInfoProvider
        self.statusPresenter = statusPresenter
        self.screenStateReducer = screenStateReducer
    }

    func waitForCurrentLoad() async {
        await loadCoordinator.waitForCurrentLoad()
    }

    func loadFile(
        url: URL,
        importerDismissalDelay: Duration = .zero,
        handleError: @escaping @MainActor (PlaybackError) -> Void,
        cancelPendingPlaybackStart: @escaping @MainActor () -> Bool,
        stopProgressTracking: @escaping @MainActor () -> Void,
        startPlayback: @escaping @MainActor () -> Void,
        currentVolume: @escaping @MainActor () -> Double
    ) {
        guard let playlistSession = PlaylistSession.singleTrack(url) else { return }

        loadCoordinator.loadFile(
            url: url,
            playlistSession: playlistSession,
            importerDismissalDelay: importerDismissalDelay,
            loadTrack: { [engine] trackURL in
                try await engine.loadFile(from: trackURL)
            },
            handleEvent: { [weak self] event in
                await self?.handleLoadEvent(
                    event,
                    handleError: handleError,
                    cancelPendingPlaybackStart: cancelPendingPlaybackStart,
                    stopProgressTracking: stopProgressTracking,
                    startPlayback: startPlayback,
                    currentVolume: currentVolume
                )
            }
        )
    }

    func loadFolder(
        url: URL,
        importerDismissalDelay: Duration = .zero,
        handleError: @escaping @MainActor (PlaybackError) -> Void,
        cancelPendingPlaybackStart: @escaping @MainActor () -> Bool,
        stopProgressTracking: @escaping @MainActor () -> Void,
        startPlayback: @escaping @MainActor () -> Void,
        currentVolume: @escaping @MainActor () -> Double
    ) {
        loadCoordinator.loadFolder(
            url: url,
            importerDismissalDelay: importerDismissalDelay,
            loadTrack: { [engine] trackURL in
                try await engine.loadFile(from: trackURL)
            },
            handleEvent: { [weak self] event in
                await self?.handleLoadEvent(
                    event,
                    handleError: handleError,
                    cancelPendingPlaybackStart: cancelPendingPlaybackStart,
                    stopProgressTracking: stopProgressTracking,
                    startPlayback: startPlayback,
                    currentVolume: currentVolume
                )
            }
        )
    }

    @discardableResult
    func loadAdjacentTrack(
        next: Bool,
        autoplay: Bool = false,
        handleError: @escaping @MainActor (PlaybackError) -> Void,
        cancelPendingPlaybackStart: @escaping @MainActor () -> Bool,
        stopProgressTracking: @escaping @MainActor () -> Void,
        startPlayback: @escaping @MainActor () -> Void,
        currentVolume: @escaping @MainActor () -> Double
    ) -> Bool {
        guard let playlistSession = stateStore.playlistSession else { return false }

        let nextPlaylistSession = next
            ? playlistSession.movingToNextTrack()
            : playlistSession.movingToPreviousTrack()

        guard let nextPlaylistSession else { return false }

        loadPlaylistTrack(
            playlistSession: nextPlaylistSession,
            autoplayOnSuccess: autoplay,
            handleError: handleError,
            cancelPendingPlaybackStart: cancelPendingPlaybackStart,
            stopProgressTracking: stopProgressTracking,
            startPlayback: startPlayback,
            currentVolume: currentVolume
        )
        return true
    }

    func selectPlaylistTrack(
        at index: Int,
        shouldAutoplay: Bool,
        handleError: @escaping @MainActor (PlaybackError) -> Void,
        cancelPendingPlaybackStart: @escaping @MainActor () -> Bool,
        stopProgressTracking: @escaping @MainActor () -> Void,
        startPlayback: @escaping @MainActor () -> Void,
        currentVolume: @escaping @MainActor () -> Double
    ) {
        guard let playlistSession = stateStore.playlistSession,
              playlistSession.currentIndex != index,
              let nextPlaylistSession = playlistSession.movingToTrack(at: index) else { return }

        loadPlaylistTrack(
            playlistSession: nextPlaylistSession,
            autoplayOnSuccess: shouldAutoplay,
            handleError: handleError,
            cancelPendingPlaybackStart: cancelPendingPlaybackStart,
            stopProgressTracking: stopProgressTracking,
            startPlayback: startPlayback,
            currentVolume: currentVolume
        )
    }

    private func loadPlaylistTrack(
        playlistSession: PlaylistSession,
        autoplayOnSuccess: Bool,
        handleError: @escaping @MainActor (PlaybackError) -> Void,
        cancelPendingPlaybackStart: @escaping @MainActor () -> Bool,
        stopProgressTracking: @escaping @MainActor () -> Void,
        startPlayback: @escaping @MainActor () -> Void,
        currentVolume: @escaping @MainActor () -> Double
    ) {
        loadCoordinator.loadPlaylistTrack(
            playlistSession: playlistSession,
            autoplayOnSuccess: autoplayOnSuccess,
            loadTrack: { [engine] trackURL in
                try await engine.loadFile(from: trackURL)
            },
            handleEvent: { [weak self] event in
                await self?.handleLoadEvent(
                    event,
                    handleError: handleError,
                    cancelPendingPlaybackStart: cancelPendingPlaybackStart,
                    stopProgressTracking: stopProgressTracking,
                    startPlayback: startPlayback,
                    currentVolume: currentVolume
                )
            }
        )
    }

    private func handleLoadEvent(
        _ event: AudioPlayerLoadCoordinator.Event,
        handleError: @escaping @MainActor (PlaybackError) -> Void,
        cancelPendingPlaybackStart: @escaping @MainActor () -> Bool,
        stopProgressTracking: @escaping @MainActor () -> Void,
        startPlayback: @escaping @MainActor () -> Void,
        currentVolume: @escaping @MainActor () -> Double
    ) async {
        switch event {
        case .beginLoading(let loadingState, let message):
            beginLoading(
                loadingState: loadingState,
                message: message,
                cancelPendingPlaybackStart: cancelPendingPlaybackStart,
                stopProgressTracking: stopProgressTracking
            )
        case .playlistSessionUpdated(let playlistSession):
            stateStore.playlistSession = playlistSession
        case .trackLoaded(let url, let audioInfo, let autoplayOnSuccess):
            do {
                try await finishLoadingTrack(
                    from: url,
                    audioInfo: audioInfo,
                    autoplayOnSuccess: autoplayOnSuccess,
                    startPlayback: startPlayback,
                    currentVolume: currentVolume
                )
            } catch let error as PlaybackError {
                handleError(error)
            } catch {
                handleError(.loadFailed(error.localizedDescription))
            }
        case .cancelled:
            handleLoadCancellation(stopProgressTracking: stopProgressTracking)
        case .failed(let error):
            handleError(error)
        }
    }

    private func beginLoading(
        loadingState: LoadingPresentationState,
        message: String,
        cancelPendingPlaybackStart: @escaping @MainActor () -> Bool,
        stopProgressTracking: @escaping @MainActor () -> Void
    ) {
        _ = cancelPendingPlaybackStart()
        let preservedAudioInfo = engine.beginLoading()
        applyScreenStateAction(.beginLoading(preservedAudioInfo: preservedAudioInfo))
        stopProgressTracking()
        stateStore.currentTime = 0
        applyStatusPresentation(
            statusPresenter.presentLoading(
                state: loadingState,
                message: message
            )
        )
    }

    private func finishLoadingTrack(
        from trackURL: URL,
        audioInfo: AudioInfo,
        autoplayOnSuccess: Bool,
        startPlayback: @escaping @MainActor () -> Void,
        currentVolume: @escaping @MainActor () -> Double
    ) async throws {
        applyScreenStateAction(.ready(audioInfo))
        stateStore.recordLoadedTrack(audioInfo, for: trackURL)

        stateStore.currentTime = 0
        engine.setVolume(currentVolume())
        await refreshHardwareInfo()
        showReadyStatus(for: audioInfo)

        if autoplayOnSuccess {
            startPlayback()
        }
    }

    private func handleLoadCancellation(
        stopProgressTracking: @escaping @MainActor () -> Void
    ) {
        stopProgressTracking()
        stateStore.currentTime = 0
        applyStatusPresentation(
            statusPresenter.presentInfo(
                message: "Loading cancelled",
                loading: .cancelled
            )
        )
    }

    private func showReadyStatus(for audioInfo: AudioInfo) {
        let sampleRatePresentation = stateStore.sampleRatePresentation(
            isAttemptingPlaybackStart: false
        )
        applyStatusPresentation(
            statusPresenter.presentReady(
                PlayerStatusReadyInput(
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

    private func refreshHardwareInfo() async {
        let deviceInfo = await hardwareInfoProvider.getCurrentAudioDeviceInfo()
        stateStore.setHardwareInfo(deviceInfo)
    }

    private func applyStatusPresentation(_ output: PlayerStatusPresentationOutput) {
        stateStore.applyStatusPresentation(output)
    }

    private func applyScreenStateAction(_ action: PlayerScreenStateReducer.Action) {
        stateStore.applyScreenStateAction(
            action,
            reducer: screenStateReducer
        )
    }
}
