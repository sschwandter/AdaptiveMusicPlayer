import Foundation

@MainActor
final class AudioPlayerLoadWorkflow {
    struct Callbacks {
        let cancelPendingPlaybackStart: @MainActor () -> Bool
        let stopProgressTracking: @MainActor () -> Void
        let startPlayback: @MainActor () -> Void
        let currentVolume: @MainActor () -> Double
    }

    private let stateStore: AudioPlayerStateStore
    private let engine: AudioPlaybackEngine
    private let loadCoordinator: AudioPlayerLoadCoordinator
    private let statusPresenter: PlayerStatusPresenter
    private let screenStateReducer: PlayerScreenStateReducer
    private let refreshHardwareInfo: @MainActor () async -> Void

    init(
        stateStore: AudioPlayerStateStore,
        engine: AudioPlaybackEngine,
        loadCoordinator: AudioPlayerLoadCoordinator,
        refreshHardwareInfo: @escaping @MainActor () async -> Void,
        statusPresenter: PlayerStatusPresenter = PlayerStatusPresenter(),
        screenStateReducer: PlayerScreenStateReducer = PlayerScreenStateReducer()
    ) {
        self.stateStore = stateStore
        self.engine = engine
        self.loadCoordinator = loadCoordinator
        self.refreshHardwareInfo = refreshHardwareInfo
        self.statusPresenter = statusPresenter
        self.screenStateReducer = screenStateReducer
    }

    func waitForCurrentLoad() async {
        await loadCoordinator.waitForCurrentLoad()
    }

    func reportFileSelectionError(_ message: String) {
        presentError(.loadFailed(message))
    }

    func loadFile(
        url: URL,
        importerDismissalDelay: Duration = .zero,
        callbacks: Callbacks
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
                await self?.handleLoadEvent(event, callbacks: callbacks)
            }
        )
    }

    func loadFolder(
        url: URL,
        importerDismissalDelay: Duration = .zero,
        callbacks: Callbacks
    ) {
        loadCoordinator.loadFolder(
            url: url,
            importerDismissalDelay: importerDismissalDelay,
            loadTrack: { [engine] trackURL in
                try await engine.loadFile(from: trackURL)
            },
            handleEvent: { [weak self] event in
                await self?.handleLoadEvent(event, callbacks: callbacks)
            }
        )
    }

    @discardableResult
    func loadAdjacentTrack(
        next: Bool,
        autoplay: Bool = false,
        callbacks: Callbacks
    ) -> Bool {
        guard let playlistSession = stateStore.playlistSession else { return false }

        let nextPlaylistSession = next
            ? playlistSession.movingToNextTrack()
            : playlistSession.movingToPreviousTrack()

        guard let nextPlaylistSession else { return false }

        loadPlaylistTrack(
            playlistSession: nextPlaylistSession,
            autoplayOnSuccess: autoplay,
            callbacks: callbacks
        )
        return true
    }

    func selectPlaylistTrack(
        at index: Int,
        shouldAutoplay: Bool,
        callbacks: Callbacks
    ) {
        guard let playlistSession = stateStore.playlistSession,
              playlistSession.currentIndex != index,
              let nextPlaylistSession = playlistSession.movingToTrack(at: index) else { return }

        loadPlaylistTrack(
            playlistSession: nextPlaylistSession,
            autoplayOnSuccess: shouldAutoplay,
            callbacks: callbacks
        )
    }

    private func loadPlaylistTrack(
        playlistSession: PlaylistSession,
        autoplayOnSuccess: Bool,
        callbacks: Callbacks
    ) {
        loadCoordinator.loadPlaylistTrack(
            playlistSession: playlistSession,
            autoplayOnSuccess: autoplayOnSuccess,
            loadTrack: { [engine] trackURL in
                try await engine.loadFile(from: trackURL)
            },
            handleEvent: { [weak self] event in
                await self?.handleLoadEvent(event, callbacks: callbacks)
            }
        )
    }

    private func handleLoadEvent(
        _ event: AudioPlayerLoadCoordinator.Event,
        callbacks: Callbacks
    ) async {
        switch event {
        case .beginLoading(let loadingState, let message):
            beginLoading(
                loadingState: loadingState,
                message: message,
                callbacks: callbacks
            )
        case .playlistSessionUpdated(let playlistSession):
            stateStore.playlistSession = playlistSession
        case .trackLoaded(let url, let audioInfo, let autoplayOnSuccess):
            do {
                try await finishLoadingTrack(
                    from: url,
                    audioInfo: audioInfo,
                    autoplayOnSuccess: autoplayOnSuccess,
                    callbacks: callbacks
                )
            } catch let error as PlaybackError {
                presentError(error)
            } catch {
                presentError(.loadFailed(error.localizedDescription))
            }
        case .cancelled:
            handleLoadCancellation(callbacks: callbacks)
        case .failed(let error):
            presentError(error)
        }
    }

    private func beginLoading(
        loadingState: LoadingPresentationState,
        message: String,
        callbacks: Callbacks
    ) {
        _ = callbacks.cancelPendingPlaybackStart()
        let preservedAudioInfo = engine.beginLoading()
        applyScreenStateAction(.beginLoading(preservedAudioInfo: preservedAudioInfo))
        callbacks.stopProgressTracking()
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
        callbacks: Callbacks
    ) async throws {
        applyScreenStateAction(.ready(audioInfo))
        stateStore.recordLoadedTrack(audioInfo, for: trackURL)

        stateStore.currentTime = 0
        engine.setVolume(callbacks.currentVolume())
        await refreshHardwareInfo()
        showReadyStatus(for: audioInfo)

        if autoplayOnSuccess {
            callbacks.startPlayback()
        }
    }

    private func handleLoadCancellation(callbacks: Callbacks) {
        callbacks.stopProgressTracking()
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

    private func applyStatusPresentation(_ output: PlayerStatusPresentationOutput) {
        stateStore.applyStatusPresentation(output)
    }

    private func presentError(_ error: PlaybackError) {
        applyStatusPresentation(
            statusPresenter.presentError(
                error,
                hasCurrentAudio: stateStore.currentAudioInfo != nil
            )
        )
    }

    private func applyScreenStateAction(_ action: PlayerScreenStateReducer.Action) {
        stateStore.applyScreenStateAction(
            action,
            reducer: screenStateReducer
        )
    }
}
