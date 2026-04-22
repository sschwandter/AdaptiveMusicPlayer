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
        sessionController.isStartingPlayback
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
    private let folderScanner: AudioPlaylistFolderScanning
    private let finderItemRevealer: FinderItemRevealing
    private let hardwareMonitor: AudioPlayerHardwareMonitor
    @ObservationIgnored
    private lazy var sessionController: AudioPlayerSessionController = {
        let loadCoordinator = AudioPlayerLoadCoordinator(folderScanner: folderScanner)
        return AudioPlayerSessionController(
            stateStore: stateStore,
            engine: engine,
            progressTracker: progressTracker,
            loadCoordinator: loadCoordinator,
            refreshHardwareInfo: { [hardwareMonitor] in
                await hardwareMonitor.refreshHardwareInfo()
            },
            currentVolume: { [weak self] in
                self?.volume ?? 1
            }
        )
    }()

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
        self.folderScanner = folderScanner
        self.finderItemRevealer = finderItemRevealer
        self.hardwareMonitor = AudioPlayerHardwareMonitor(
            stateStore: stateStore,
            hardwareObserver: hardwareObserver,
            hardwareInfoProvider: hardwareInfoProvider
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
        sessionController.loadFile(url: url, importerDismissalDelay: importerDismissalDelay)
    }

    func loadFolder(url: URL, importerDismissalDelay: Duration = .zero) {
        sessionController.loadFolder(url: url, importerDismissalDelay: importerDismissalDelay)
    }

    /// Report a file selection error from the file picker
    func reportFileSelectionError(_ message: String) {
        sessionController.reportFileSelectionError(message)
    }

    func waitForCurrentLoad() async {
        await sessionController.waitForCurrentActivity()
    }

    func playNextTrack() {
        _ = sessionController.loadAdjacentTrack(next: true, autoplay: true)
    }

    func playPreviousTrack() {
        _ = sessionController.loadAdjacentTrack(next: false, autoplay: true)
    }

    func selectPlaylistTrack(at index: Int) {
        sessionController.selectPlaylistTrack(
            at: index,
            shouldAutoplay: isPlaying || sessionController.isStartingPlayback
        )
    }

    func showCurrentTrackInFinder() {
        guard let currentTrackURL = stateStore.currentTrackURL else { return }
        finderItemRevealer.revealItem(at: currentTrackURL)
    }

    // MARK: - Playback Control

    func togglePlayPause() {
        sessionController.togglePlayPause()
    }

    func stop() {
        sessionController.stop()
    }

    // MARK: - Seeking

    func seek(to time: Double) {
        sessionController.seek(to: time)
    }

    func skipForward() {
        sessionController.skipForward()
    }

    func skipBackward() {
        sessionController.skipBackward()
    }

    // MARK: - Sample Rate Management

    func synchronizeSampleRates() async {
        await sessionController.synchronizeSampleRates()
    }
}
