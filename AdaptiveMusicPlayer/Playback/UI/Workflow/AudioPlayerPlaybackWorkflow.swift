import Foundation

@MainActor
final class AudioPlayerPlaybackWorkflow {
    private enum Constants {
        static let progressUpdateInterval: TimeInterval = 0.1
    }

    private let stateStore: AudioPlayerStateStore
    private let engine: AudioPlaybackEngine
    private let progressTracker: PlaybackProgressTracking
    private let startupCoordinator: PlaybackStartupCoordinator
    private let statusPresenter: PlayerStatusPresenter
    private let screenStateReducer: PlayerScreenStateReducer
    private let refreshHardwareInfo: @MainActor () async -> Void

    init(
        stateStore: AudioPlayerStateStore,
        engine: AudioPlaybackEngine,
        progressTracker: PlaybackProgressTracking,
        refreshHardwareInfo: @escaping @MainActor () async -> Void,
        startupCoordinator: PlaybackStartupCoordinator = PlaybackStartupCoordinator(),
        statusPresenter: PlayerStatusPresenter = PlayerStatusPresenter(),
        screenStateReducer: PlayerScreenStateReducer = PlayerScreenStateReducer()
    ) {
        self.stateStore = stateStore
        self.engine = engine
        self.progressTracker = progressTracker
        self.refreshHardwareInfo = refreshHardwareInfo
        self.startupCoordinator = startupCoordinator
        self.statusPresenter = statusPresenter
        self.screenStateReducer = screenStateReducer
    }

    var isStartingPlayback: Bool {
        startupCoordinator.isStartingPlayback
    }

    func waitForCurrentStartup() async {
        await startupCoordinator.waitForCurrentStartup()
    }

    func togglePlayPause(
        loadAdjacentTrack: @escaping @MainActor (_ next: Bool, _ autoplay: Bool) -> Bool
    ) {
        if stateStore.isPlaying || isStartingPlayback {
            pause()
        } else {
            startPlayback(loadAdjacentTrack: loadAdjacentTrack)
        }
    }

    func startPlayback(
        loadAdjacentTrack: @escaping @MainActor (_ next: Bool, _ autoplay: Bool) -> Bool
    ) {
        startupCoordinator.startPlayback(
            play: { [engine] in
                try await engine.play()
            },
            handleEvent: { [weak self] event in
                await self?.handlePlaybackStartupEvent(
                    event,
                    loadAdjacentTrack: loadAdjacentTrack
                )
            }
        )
    }

    func pause() {
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
            // Silently fail for seek - don't show error to user
        }
    }

    func skipForward() {
        do {
            let newTime = try engine.skipForward(from: stateStore.currentTime)
            stateStore.currentTime = newTime
        } catch {
            // Silently fail for skip - don't show error to user
        }
    }

    func skipBackward() {
        do {
            let newTime = try engine.skipBackward(from: stateStore.currentTime)
            stateStore.currentTime = newTime
        } catch {
            // Silently fail for skip - don't show error to user
        }
    }

    func synchronizeSampleRates() async {
        do {
            try await engine.synchronizeSampleRates()

            do {
                try await Task.sleep(for: .milliseconds(500))
            } catch is CancellationError {
                return
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

    private func handlePlaybackStartupEvent(
        _ event: PlaybackStartupCoordinator.Event,
        loadAdjacentTrack: @escaping @MainActor (_ next: Bool, _ autoplay: Bool) -> Bool
    ) async {
        switch event {
        case .startupBegan:
            stateStore.setLoadingState(.startingPlayback)
        case .startupCancelled:
            stateStore.setLoadingState(.idle)
        case .startupFinished(let audioInfo):
            await finishSuccessfulPlaybackStart(
                audioInfo: audioInfo,
                loadAdjacentTrack: loadAdjacentTrack
            )
        case .startupFailed(let error):
            showError(error)
        case .staleStartupFinished:
            let preservedAudioInfo = engine.stop()
            applyScreenStateAction(.stopped(preservedAudioInfo: preservedAudioInfo))
            stateStore.currentTime = 0
        }
    }

    private func finishSuccessfulPlaybackStart(
        audioInfo: AudioInfo,
        loadAdjacentTrack: @escaping @MainActor (_ next: Bool, _ autoplay: Bool) -> Bool
    ) async {
        applyScreenStateAction(.playing(audioInfo))
        startProgressTracking(loadAdjacentTrack: loadAdjacentTrack)
        await refreshHardwareInfo()
        showPlayingStatus()
    }

    private func startProgressTracking(
        loadAdjacentTrack: @escaping @MainActor (_ next: Bool, _ autoplay: Bool) -> Bool
    ) {
        engine.startProgressTracking(
            using: progressTracker,
            updateInterval: Constants.progressUpdateInterval,
            onProgressUpdate: { [weak self] time in
                self?.stateStore.currentTime = time
            },
            onPlaybackFinished: { [weak self] in
                guard let self else { return }
                if !loadAdjacentTrack(true, true) {
                    let audioInfo = self.engine.markFinished()
                    self.applyScreenStateAction(.finished(audioInfo))
                    self.stateStore.currentTime = self.stateStore.duration
                    self.applyStatusPresentation(
                        self.statusPresenter.presentInfo(message: "Playback finished")
                    )
                }
            },
            onPeriodicUpdate: { [weak self] in
                Task {
                    await self?.refreshHardwareInfo()
                }
            }
        )
    }

    private func stopProgressTracking() {
        engine.stopProgressTracking(using: progressTracker)
    }
    private func showPlayingStatus() {
        let sampleRatePresentation = stateStore.sampleRatePresentation(
            isAttemptingPlaybackStart: isStartingPlayback
        )
        applyStatusPresentation(
            statusPresenter.presentPlaying(
                PlayerStatusPlayingInput(
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

    private func applyScreenStateAction(_ action: PlayerScreenStateReducer.Action) {
        stateStore.applyScreenStateAction(
            action,
            reducer: screenStateReducer
        )
    }
}
