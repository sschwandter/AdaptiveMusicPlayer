import Foundation
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
    @ObservationIgnored
    private lazy var loadAdjacentTrackAction: @MainActor (Bool, Bool) -> Bool = { [weak self] next, autoplay in
        guard let self else { return false }

        return self.loadWorkflow.loadAdjacentTrack(
            next: next,
            autoplay: autoplay,
            callbacks: self.loadWorkflowCallbacks
        )
    }
    @ObservationIgnored
    private lazy var loadWorkflowCallbacks = AudioPlayerLoadWorkflow.Callbacks(
        cancelPendingPlaybackStart: { [weak self] in
            self?.playbackWorkflow.cancelPendingPlaybackStart() ?? false
        },
        stopProgressTracking: { [engine, progressTracker] in
            engine.stopProgressTracking(using: progressTracker)
        },
        startPlayback: { [weak self] in
            guard let self else { return }
            self.playbackWorkflow.startPlayback(loadAdjacentTrack: self.loadAdjacentTrackAction)
        },
        currentVolume: { [weak self] in
            self?.volume ?? 1
        }
    )

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
            callbacks: loadWorkflowCallbacks
        )
    }

    func loadFolder(url: URL, importerDismissalDelay: Duration = .zero) {
        loadWorkflow.loadFolder(
            url: url,
            importerDismissalDelay: importerDismissalDelay,
            callbacks: loadWorkflowCallbacks
        )
    }

    /// Report a file selection error from the file picker
    func reportFileSelectionError(_ message: String) {
        loadWorkflow.reportFileSelectionError(message)
    }

    func waitForCurrentLoad() async {
        await loadWorkflow.waitForCurrentLoad()
        await playbackWorkflow.waitForCurrentStartup()
    }

    func playNextTrack() {
        _ = loadAdjacentTrackAction(true, true)
    }

    func playPreviousTrack() {
        _ = loadAdjacentTrackAction(false, true)
    }

    func selectPlaylistTrack(at index: Int) {
        loadWorkflow.selectPlaylistTrack(
            at: index,
            shouldAutoplay: isPlaying || playbackWorkflow.isStartingPlayback,
            callbacks: loadWorkflowCallbacks
        )
    }

    func showCurrentTrackInFinder() {
        guard let currentTrackURL = stateStore.currentTrackURL else { return }
        finderItemRevealer.revealItem(at: currentTrackURL)
    }

    // MARK: - Playback Control

    func togglePlayPause() {
        playbackWorkflow.togglePlayPause(loadAdjacentTrack: loadAdjacentTrackAction)
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
}
