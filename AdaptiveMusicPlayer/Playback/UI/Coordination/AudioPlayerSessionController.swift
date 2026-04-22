import Foundation
import AsyncAlgorithms

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
    private let screenStateReducer: PlayerScreenStateReducer
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
        statusPresenter: PlayerStatusPresenter = PlayerStatusPresenter(),
        screenStateReducer: PlayerScreenStateReducer = PlayerScreenStateReducer()
    ) {
        self.stateStore = stateStore
        self.engine = engine
        self.progressTracker = progressTracker
        self.loadCoordinator = loadCoordinator
        self.startupCoordinator = startupCoordinator
        self.refreshHardwareInfo = refreshHardwareInfo
        self.currentVolume = currentVolume
        self.statusPresenter = statusPresenter
        self.screenStateReducer = screenStateReducer
    }

    var isStartingPlayback: Bool {
        startupCoordinator.isStartingPlayback
    }

    func waitForCurrentActivity() async {
        await loadCoordinator.waitForCurrentLoad()
        await startupCoordinator.waitForCurrentStartup()
    }

    func reportFileSelectionError(_ message: String) {
        presentError(.loadFailed(message))
    }

    func loadFile(url: URL, importerDismissalDelay: Duration = .zero) {
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

    func loadFolder(url: URL, importerDismissalDelay: Duration = .zero) {
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
    func loadAdjacentTrack(next: Bool, autoplay: Bool = false) -> Bool {
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

    func selectPlaylistTrack(at index: Int, shouldAutoplay: Bool) {
        guard let playlistSession = stateStore.playlistSession,
              playlistSession.currentIndex != index,
              let nextPlaylistSession = playlistSession.movingToTrack(at: index) else { return }

        loadPlaylistTrack(
            playlistSession: nextPlaylistSession,
            autoplayOnSuccess: shouldAutoplay
        )
    }

    func togglePlayPause() {
        if stateStore.isPlaying || isStartingPlayback {
            pause()
        } else {
            startPlayback()
        }
    }

    func stop() {
        _ = cancelPendingPlaybackStart()
        let audioInfo = engine.stop()
        applyScreenStateAction(.stopped(preservedAudioInfo: audioInfo))
        stopProgressTracking()
        stateStore.currentTime = 0
        applyStatusPresentation(statusPresenter.presentInfo(message: "Stopped"))
    }

    func seek(to time: Double) {
        do {
            let newTime = try engine.seek(to: time)
            stateStore.currentTime = newTime
        } catch {
        }
    }

    func skipForward() {
        do {
            let newTime = try engine.skipForward(from: stateStore.currentTime)
            stateStore.currentTime = newTime
        } catch {
        }
    }

    func skipBackward() {
        do {
            let newTime = try engine.skipBackward(from: stateStore.currentTime)
            stateStore.currentTime = newTime
        } catch {
        }
    }

    func synchronizeSampleRates() async {
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
                applyStatusPresentation(
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
        case .beginLoading(let loadingState, let message):
            beginLoading(
                loadingState: loadingState,
                message: message
            )
        case .playlistSessionUpdated(let playlistSession):
            stateStore.playlistSession = playlistSession
        case .trackLoaded(let url, let audioInfo, let autoplayOnSuccess):
            do {
                try await finishLoadingTrack(
                    from: url,
                    audioInfo: audioInfo,
                    autoplayOnSuccess: autoplayOnSuccess
                )
            } catch let error as PlaybackError {
                presentError(error)
            } catch {
                presentError(.loadFailed(error.localizedDescription))
            }
        case .cancelled:
            handleLoadCancellation()
        case .failed(let error):
            presentError(error)
        }
    }

    private func beginLoading(
        loadingState: LoadingPresentationState,
        message: String
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
        autoplayOnSuccess: Bool
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

    private func handleLoadCancellation() {
        stopProgressTracking()
        stateStore.currentTime = 0
        applyStatusPresentation(
            statusPresenter.presentInfo(
                message: "Loading cancelled",
                loading: .cancelled
            )
        )
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
            applyStatusPresentation(statusPresenter.presentInfo(message: "Paused"))
            return
        }

        do {
            let audioInfo = try engine.pause()
            applyScreenStateAction(.paused(audioInfo))
            stopProgressTracking()
            applyStatusPresentation(statusPresenter.presentInfo(message: "Paused"))
        } catch let error as PlaybackError {
            showError(error)
        } catch {
            showError(.notPlaying)
        }
    }

    private func handlePlaybackStartupEvent(_ event: PlaybackStartupCoordinator.Event) async {
        switch event {
        case .startupBegan:
            stateStore.setLoadingState(.startingPlayback)
        case .startupCancelled:
            stateStore.setLoadingState(.idle)
        case .startupFinished(let audioInfo):
            await finishSuccessfulPlaybackStart(audioInfo: audioInfo)
        case .startupFailed(let error):
            showError(error)
        case .staleStartupFinished:
            let preservedAudioInfo = engine.stop()
            applyScreenStateAction(.stopped(preservedAudioInfo: preservedAudioInfo))
            stateStore.currentTime = 0
        }
    }

    private func finishSuccessfulPlaybackStart(audioInfo: AudioInfo) async {
        applyScreenStateAction(.playing(audioInfo))
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

        // Start progress tracking with debounced updates using AsyncAlgorithms
        progressTrackingTask = Task { @MainActor [weak self] in
            guard let self else { return }

            // Use debounced progress stream for UI efficiency (500ms debounce)
            let progressStream = self.engine.trackProgressDebounced(
                using: self.progressTracker,
                updateInterval: Constants.progressUpdateInterval,
                debounceInterval: .milliseconds(500)
            )

            for await event in progressStream {
                switch event {
                case .progress(let time):
                    self.stateStore.currentTime = time

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
        if !loadAdjacentTrack(next: true, autoplay: true) {
            let audioInfo = engine.markFinished()
            applyScreenStateAction(.finished(audioInfo))
            stateStore.currentTime = stateStore.duration
            applyStatusPresentation(
                statusPresenter.presentInfo(message: "Playback finished")
            )
        }
    }

private func showReadyStatus(for audioInfo: AudioInfo) {
        let sampleRatePresentation = stateStore.sampleRatePresentation(
            isAttemptingPlaybackStart: false
         )
        applyStatusPresentation(
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
        applyStatusPresentation(
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
        applyStatusPresentation(
            statusPresenter.presentError(
                error,
                hasCurrentAudio: stateStore.currentAudioInfo != nil
            )
        )
    }

    private func applyStatusPresentation(_ output: PlayerStatusPresentationOutput) {
        stateStore.applyStatusPresentation(output)
    }

    private func presentError(_ error: PlaybackError) {
        showError(error)
    }

    private func applyScreenStateAction(_ action: PlayerScreenStateReducer.Action) {
        stateStore.applyScreenStateAction(action, reducer: screenStateReducer)
    }
}
