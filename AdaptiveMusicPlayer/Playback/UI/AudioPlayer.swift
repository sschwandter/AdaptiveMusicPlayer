import Foundation
import AVFoundation
import Observation

/// Observable playback view model used by SwiftUI
/// Wraps the engine and maintains additional UI-facing status state
@MainActor
@Observable
final class AudioPlayer: @unchecked Sendable { // Safe: all access serialized on MainActor
    // MARK: - Constants

    private enum Constants {
        static let progressUpdateInterval: TimeInterval = 0.1  // seconds
    }

    // MARK: - Presentation State

    private let stateStore = AudioPlayerStateStore()

    // MARK: - Domain State (exposed to UI)

    var currentTime: Double {
        get { stateStore.currentTime }
        set { stateStore.currentTime = newValue }
    }
    var duration: Double { stateStore.duration }
    var volume: Double = 1 {
        didSet {
            engine.setVolume(volume)
        }
    }
    var statusMessage: String { stateStore.statusMessage }
    var hasError: Bool { stateStore.hasError }
    var currentFileName: String? { stateStore.currentFileName }
    var currentDisplayTitle: String? { stateStore.currentDisplayTitle }
    var fileSampleRate: Double { stateStore.fileSampleRate }
    var hardwareSampleRate: Double { stateStore.hardwareSampleRate }
    var hardwareDeviceName: String { stateStore.hardwareDeviceName }
    var supportedHardwareSampleRates: [Double] { stateStore.supportedHardwareSampleRates }

    var isLoading: Bool { stateStore.isLoading }

    var isPlaying: Bool { stateStore.isPlaying }

    private var isAttemptingPlaybackStart: Bool {
        startupCoordinator.isStartingPlayback
    }

    private var sampleRatePresentation: SampleRatePresentationOutput {
        stateStore.sampleRatePresentation(
            isAttemptingPlaybackStart: isAttemptingPlaybackStart
        )
    }

    private var contentViewPresentation: ContentViewStatePresentationOutput {
        stateStore.contentViewPresentation(
            sampleRateBanner: sampleRateBannerPresentation
        )
    }

    private let statusPresenter = PlayerStatusPresenter()

    var playlistTrackPosition: String? { contentViewPresentation.playlistTrackPosition }
    var playlistTracks: [PlaylistTrackRow] { contentViewPresentation.playlistTracks }
    var hasPlaylist: Bool { contentViewPresentation.hasPlaylist }
    var canPlayPreviousTrack: Bool { contentViewPresentation.canPlayPreviousTrack }
    var canPlayNextTrack: Bool { contentViewPresentation.canPlayNextTrack }

    var contentViewState: ContentViewState {
        contentViewPresentation.contentViewState
    }

    var hasSampleRateMismatch: Bool {
        sampleRatePresentation.hasMismatch
    }

    var hardwareDeviceDisplayName: String {
        sampleRatePresentation.hardwareDeviceDisplayName
    }

    var supportedHardwareSampleRatesDescription: String {
        sampleRatePresentation.supportedHardwareSampleRatesDescription
    }

    var sampleRateBannerPresentation: SampleRateBannerPresentation {
        sampleRatePresentation.banner
    }

    var sampleRateRouteDescription: String {
        sampleRatePresentation.routeDescription
    }

    var compactSampleRateExplanation: String? {
        sampleRatePresentation.compactExplanation
    }

    var showsSupportedRatesHint: Bool {
        sampleRatePresentation.showsSupportedRatesHint
    }

    var sampleRateStatusDetail: String {
        sampleRatePresentation.statusDetail
    }

    // MARK: - Dependencies

    private let engine: AudioPlaybackEngine
    private let progressTracker: PlaybackProgressTracking
    private let hardwareObserver: AudioHardwareObserving
    private let hardwareInfoProvider: AudioHardwareInfoProviding
    private let finderItemRevealer: FinderItemRevealing
    private let loadWorkflow: AudioPlayerLoadWorkflow
    private let startupCoordinator = PlaybackStartupCoordinator()
    private let screenStateReducer = PlayerScreenStateReducer()
    private var playlistSession: PlaylistSession? {
        get { stateStore.playlistSession }
        set { stateStore.playlistSession = newValue }
    }

    // MARK: - Initialization

    init(
        engine: AudioPlaybackEngine = AudioPlaybackEngine(),
        progressTracker: PlaybackProgressTracking = PlaybackProgressTracker(),
        hardwareObserver: AudioHardwareObserving = CoreAudioHardwareObserver(),
        hardwareInfoProvider: AudioHardwareInfoProviding = CoreAudioHardwareInfoProvider(),
        folderScanner: AudioPlaylistFolderScanning = AudioPlaylistFolderScanner(),
        finderItemRevealer: FinderItemRevealing = FinderItemRevealer()
    ) {
        self.engine = engine
        self.progressTracker = progressTracker
        self.hardwareObserver = hardwareObserver
        self.hardwareInfoProvider = hardwareInfoProvider
        self.finderItemRevealer = finderItemRevealer
        let loadCoordinator = AudioPlayerLoadCoordinator(folderScanner: folderScanner)
        self.loadWorkflow = AudioPlayerLoadWorkflow(
            stateStore: stateStore,
            engine: engine,
            loadCoordinator: loadCoordinator,
            hardwareInfoProvider: hardwareInfoProvider
        )

        hardwareObserver.startObserving { [weak self] in
            Task { @MainActor [weak self] in
                await self?.refreshHardwareInfo()
            }
        }

        Task {
            await refreshHardwareInfo()
        }
    }

    // MARK: - File Loading

    /// Starts a file load and enters loading state immediately.
    /// A short delay can be requested to let the file importer dismiss first.
    func loadFile(url: URL, importerDismissalDelay: Duration = .zero) {
        loadWorkflow.loadFile(
            url: url,
            importerDismissalDelay: importerDismissalDelay,
            handleError: { [weak self] error in self?.showError(error) },
            cancelPendingPlaybackStart: { [weak self] in self?.cancelPendingPlaybackStart() ?? false },
            stopProgressTracking: { [weak self] in self?.stopProgressTracking() },
            startPlayback: { [weak self] in self?.startPlayback() },
            currentVolume: { [weak self] in self?.volume ?? 1 }
        )
    }

    func loadFolder(url: URL, importerDismissalDelay: Duration = .zero) {
        loadWorkflow.loadFolder(
            url: url,
            importerDismissalDelay: importerDismissalDelay,
            handleError: { [weak self] error in self?.showError(error) },
            cancelPendingPlaybackStart: { [weak self] in self?.cancelPendingPlaybackStart() ?? false },
            stopProgressTracking: { [weak self] in self?.stopProgressTracking() },
            startPlayback: { [weak self] in self?.startPlayback() },
            currentVolume: { [weak self] in self?.volume ?? 1 }
        )
    }

    /// Report a file selection error from the file picker
    func reportFileSelectionError(_ message: String) {
        showError(.loadFailed(message))
    }

    func waitForCurrentLoad() async {
        await loadWorkflow.waitForCurrentLoad()
        await startupCoordinator.waitForCurrentStartup()
    }

    func playNextTrack() {
        _ = loadWorkflow.loadAdjacentTrack(
            next: true,
            autoplay: true,
            handleError: { [weak self] error in self?.showError(error) },
            cancelPendingPlaybackStart: { [weak self] in self?.cancelPendingPlaybackStart() ?? false },
            stopProgressTracking: { [weak self] in self?.stopProgressTracking() },
            startPlayback: { [weak self] in self?.startPlayback() },
            currentVolume: { [weak self] in self?.volume ?? 1 }
        )
    }

    func playPreviousTrack() {
        _ = loadWorkflow.loadAdjacentTrack(
            next: false,
            autoplay: true,
            handleError: { [weak self] error in self?.showError(error) },
            cancelPendingPlaybackStart: { [weak self] in self?.cancelPendingPlaybackStart() ?? false },
            stopProgressTracking: { [weak self] in self?.stopProgressTracking() },
            startPlayback: { [weak self] in self?.startPlayback() },
            currentVolume: { [weak self] in self?.volume ?? 1 }
        )
    }

    func selectPlaylistTrack(at index: Int) {
        let shouldAutoplay = isPlaying || startupCoordinator.isStartingPlayback
        loadWorkflow.selectPlaylistTrack(
            at: index,
            shouldAutoplay: shouldAutoplay,
            handleError: { [weak self] error in self?.showError(error) },
            cancelPendingPlaybackStart: { [weak self] in self?.cancelPendingPlaybackStart() ?? false },
            stopProgressTracking: { [weak self] in self?.stopProgressTracking() },
            startPlayback: { [weak self] in self?.startPlayback() },
            currentVolume: { [weak self] in self?.volume ?? 1 }
        )
    }

    func showCurrentTrackInFinder() {
        guard let currentTrackURL = playlistSession?.currentTrackURL else { return }
        finderItemRevealer.revealItem(at: currentTrackURL)
    }

    // MARK: - Playback Control

    func togglePlayPause() {
        if isPlaying || startupCoordinator.isStartingPlayback {
            pause()
        } else {
            startPlayback()
        }
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
            currentTime = 0
        }
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

    func stop() {
        _ = cancelPendingPlaybackStart()
        let audioInfo = engine.stop()
        applyScreenStateAction(.stopped(preservedAudioInfo: audioInfo))
        stopProgressTracking()
        currentTime = 0
        applyStatusPresentation(statusPresenter.presentInfo(message: "Stopped"))
    }

    // MARK: - Seeking

    func seek(to time: Double) {
        do {
            let newTime = try engine.seek(to: time)
            currentTime = newTime
        } catch {
            // Silently fail for seek - don't show error to user
        }
    }

    func skipForward() {
        do {
            let newTime = try engine.skipForward(from: currentTime)
            currentTime = newTime
        } catch {
            // Silently fail for skip - don't show error to user
        }
    }

    func skipBackward() {
        do {
            let newTime = try engine.skipBackward(from: currentTime)
            currentTime = newTime
        } catch {
            // Silently fail for skip - don't show error to user
        }
    }

    // MARK: - Sample Rate Management

    func synchronizeSampleRates() async {
        do {
            // Core Audio operations run on background thread via async
            try await engine.synchronizeSampleRates()

            // Wait for hardware to stabilize, then refresh (still needed for hardware settling)
            do {
                try await Task.sleep(for: .milliseconds(500))
            } catch is CancellationError {
                return
            } catch {
                return
            }

            // Back on MainActor after await - safe to update UI
            await refreshHardwareInfo()

            // Verify the switch actually took effect
            if hasSampleRateMismatch {
                showError(.sampleRateSyncFailed(sampleRateStatusDetail))
            } else {
                applyStatusPresentation(
                    statusPresenter.presentInfo(
                        message: "Hardware sample rate set to \(SampleRatePresenter.formatSampleRate(fileSampleRate)) on \(hardwareDeviceDisplayName)"
                    )
                )
            }
        } catch let error as PlaybackError {
            showError(error)
        } catch {
            showError(.sampleRateSyncFailed(error.localizedDescription))
        }
    }

    // MARK: - Progress Tracking

    private func startProgressTracking() {
        engine.startProgressTracking(
            using: progressTracker,
            updateInterval: Constants.progressUpdateInterval,
            onProgressUpdate: { [weak self] time in
                self?.currentTime = time
            },
            onPlaybackFinished: { [weak self] in
                guard let self else { return }
                if !self.loadWorkflow.loadAdjacentTrack(
                    next: true,
                    autoplay: true,
                    handleError: { [weak self] error in self?.showError(error) },
                    cancelPendingPlaybackStart: { [weak self] in self?.cancelPendingPlaybackStart() ?? false },
                    stopProgressTracking: { [weak self] in self?.stopProgressTracking() },
                    startPlayback: { [weak self] in self?.startPlayback() },
                    currentVolume: { [weak self] in self?.volume ?? 1 }
                ) {
                    let audioInfo = self.engine.markFinished()
                    self.applyScreenStateAction(.finished(audioInfo))
                    self.currentTime = self.duration
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

    // MARK: - Private Methods

    private func refreshHardwareInfo() async {
        let deviceInfo = await hardwareInfoProvider.getCurrentAudioDeviceInfo()
        stateStore.setHardwareInfo(deviceInfo)
    }

    private func cancelPendingPlaybackStart() -> Bool {
        let cancelled = startupCoordinator.cancelStartup()
        if cancelled {
            stopProgressTracking()
        }
        return cancelled
    }

    private func finishSuccessfulPlaybackStart(audioInfo: AudioInfo) async {
        applyScreenStateAction(.playing(audioInfo))
        startProgressTracking()
        await refreshHardwareInfo()
        showPlayingStatus()
    }

    private func showPlayingStatus() {
        applyStatusPresentation(
            statusPresenter.presentPlaying(
                PlayerStatusPlayingInput(
                    hasPlaylist: playlistSession?.trackCount ?? 0 > 1,
                    playlistTrackPosition: playlistSession?.positionDescription,
                    sampleRate: fileSampleRate,
                    hardwareDeviceName: hardwareDeviceDisplayName,
                    hasSampleRateMismatch: hasSampleRateMismatch,
                    sampleRateStatusDetail: sampleRateStatusDetail
                )
            )
        )
    }

    private func showError(_ error: PlaybackError) {
        applyStatusPresentation(
            statusPresenter.presentError(
                error,
                hasCurrentAudio: currentAudioInfo != nil
            )
        )
    }

    private var currentAudioInfo: AudioInfo? {
        stateStore.currentAudioInfo
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
