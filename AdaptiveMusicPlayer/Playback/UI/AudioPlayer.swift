import Foundation
import AVFoundation
import Observation

/// Observable playback view model used by SwiftUI
/// Wraps the engine and maintains additional UI-facing status state
@MainActor
@Observable
final class AudioPlayer: @unchecked Sendable { // Safe: all access serialized on MainActor
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
        playbackWorkflow.isStartingPlayback
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
    private let finderItemRevealer: FinderItemRevealing
    private let hardwareMonitor: AudioPlayerHardwareMonitor
    private let loadWorkflow: AudioPlayerLoadWorkflow
    private let playbackWorkflow: AudioPlayerPlaybackWorkflow
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
        self.finderItemRevealer = finderItemRevealer
        self.hardwareMonitor = AudioPlayerHardwareMonitor(
            stateStore: stateStore,
            hardwareObserver: hardwareObserver,
            hardwareInfoProvider: hardwareInfoProvider
        )
        let loadCoordinator = AudioPlayerLoadCoordinator(folderScanner: folderScanner)
        self.loadWorkflow = AudioPlayerLoadWorkflow(
            stateStore: stateStore,
            engine: engine,
            loadCoordinator: loadCoordinator,
            refreshHardwareInfo: { [hardwareMonitor] in
                await hardwareMonitor.refreshHardwareInfo()
            }
        )
        self.playbackWorkflow = AudioPlayerPlaybackWorkflow(
            stateStore: stateStore,
            engine: engine,
            progressTracker: progressTracker,
            refreshHardwareInfo: { [hardwareMonitor] in
                await hardwareMonitor.refreshHardwareInfo()
            }
        )

        hardwareMonitor.startObserving()

        Task { @MainActor [hardwareMonitor] in
            await hardwareMonitor.refreshHardwareInfo()
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
            cancelPendingPlaybackStart: { [weak self] in self?.playbackWorkflow.cancelPendingPlaybackStart() ?? false },
            stopProgressTracking: { [weak self] in self?.playbackWorkflowStopProgressTracking() },
            startPlayback: { [weak self] in self?.playbackWorkflowStartPlayback() },
            currentVolume: { [weak self] in self?.volume ?? 1 }
        )
    }

    func loadFolder(url: URL, importerDismissalDelay: Duration = .zero) {
        loadWorkflow.loadFolder(
            url: url,
            importerDismissalDelay: importerDismissalDelay,
            handleError: { [weak self] error in self?.showError(error) },
            cancelPendingPlaybackStart: { [weak self] in self?.playbackWorkflow.cancelPendingPlaybackStart() ?? false },
            stopProgressTracking: { [weak self] in self?.playbackWorkflowStopProgressTracking() },
            startPlayback: { [weak self] in self?.playbackWorkflowStartPlayback() },
            currentVolume: { [weak self] in self?.volume ?? 1 }
        )
    }

    /// Report a file selection error from the file picker
    func reportFileSelectionError(_ message: String) {
        showError(.loadFailed(message))
    }

    func waitForCurrentLoad() async {
        await loadWorkflow.waitForCurrentLoad()
        await playbackWorkflow.waitForCurrentStartup()
    }

    func playNextTrack() {
        _ = loadWorkflow.loadAdjacentTrack(
            next: true,
            autoplay: true,
            handleError: { [weak self] error in self?.showError(error) },
            cancelPendingPlaybackStart: { [weak self] in self?.playbackWorkflow.cancelPendingPlaybackStart() ?? false },
            stopProgressTracking: { [weak self] in self?.playbackWorkflowStopProgressTracking() },
            startPlayback: { [weak self] in self?.playbackWorkflowStartPlayback() },
            currentVolume: { [weak self] in self?.volume ?? 1 }
        )
    }

    func playPreviousTrack() {
        _ = loadWorkflow.loadAdjacentTrack(
            next: false,
            autoplay: true,
            handleError: { [weak self] error in self?.showError(error) },
            cancelPendingPlaybackStart: { [weak self] in self?.playbackWorkflow.cancelPendingPlaybackStart() ?? false },
            stopProgressTracking: { [weak self] in self?.playbackWorkflowStopProgressTracking() },
            startPlayback: { [weak self] in self?.playbackWorkflowStartPlayback() },
            currentVolume: { [weak self] in self?.volume ?? 1 }
        )
    }

    func selectPlaylistTrack(at index: Int) {
        let shouldAutoplay = isPlaying || playbackWorkflow.isStartingPlayback
        loadWorkflow.selectPlaylistTrack(
            at: index,
            shouldAutoplay: shouldAutoplay,
            handleError: { [weak self] error in self?.playbackWorkflowShowError(error) },
            cancelPendingPlaybackStart: { [weak self] in self?.playbackWorkflow.cancelPendingPlaybackStart() ?? false },
            stopProgressTracking: { [weak self] in self?.playbackWorkflowStopProgressTracking() },
            startPlayback: { [weak self] in self?.playbackWorkflowStartPlayback() },
            currentVolume: { [weak self] in self?.volume ?? 1 }
        )
    }

    func showCurrentTrackInFinder() {
        guard let currentTrackURL = playlistSession?.currentTrackURL else { return }
        finderItemRevealer.revealItem(at: currentTrackURL)
    }

    // MARK: - Playback Control

    func togglePlayPause() {
        playbackWorkflow.togglePlayPause(loadAdjacentTrack: loadAdjacentTrack)
    }

    private func playbackWorkflowStartPlayback() {
        playbackWorkflow.startPlayback(loadAdjacentTrack: loadAdjacentTrack)
    }

    private func loadAdjacentTrack(next: Bool, autoplay: Bool) -> Bool {
        loadWorkflow.loadAdjacentTrack(
            next: next,
            autoplay: autoplay,
            handleError: { [weak self] error in self?.playbackWorkflowShowError(error) },
            cancelPendingPlaybackStart: { [weak self] in self?.playbackWorkflow.cancelPendingPlaybackStart() ?? false },
            stopProgressTracking: { [weak self] in self?.playbackWorkflowStopProgressTracking() },
            startPlayback: { [weak self] in self?.playbackWorkflowStartPlayback() },
            currentVolume: { [weak self] in self?.volume ?? 1 }
        )
    }

    func stop() {
        playbackWorkflow.stop()
    }

    // MARK: - Seeking

    func seek(to time: Double) {
        playbackWorkflow.seek(to: time)
    }

    func skipForward() {
        playbackWorkflow.skipForward()
    }

    func skipBackward() {
        playbackWorkflow.skipBackward()
    }

    // MARK: - Sample Rate Management

    func synchronizeSampleRates() async {
        await playbackWorkflow.synchronizeSampleRates()
    }
    // MARK: - Private Methods

    private func playbackWorkflowStopProgressTracking() {
        engine.stopProgressTracking(using: progressTracker)
    }

    private func playbackWorkflowShowError(_ error: PlaybackError) {
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

    private func showError(_ error: PlaybackError) {
        playbackWorkflowShowError(error)
    }

    private func applyStatusPresentation(_ output: PlayerStatusPresentationOutput) {
        stateStore.applyStatusPresentation(output)
    }
}
