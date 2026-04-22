import Foundation
import Observation

/// Observable playback view model used by SwiftUI
/// Wraps the engine and maintains additional UI-facing status state
/// @MainActor ensures all UI updates happen on main thread.
/// Implicitly Sendable in Swift 6 due to @MainActor.
@MainActor
@Observable
final class AudioPlayer {
    // MARK: - Presentation State

    private let stateStore = AudioPlayerStateStore()

// MARK: - Domain State (exposed to UI)

var volume: Double = 1 {
        didSet {
            engine.setVolume(volume)
         }
     }

private var isAttemptingPlaybackStart: Bool {
        sessionController.isStartingPlayback
     }

private var contentViewPresentation: ContentViewStatePresentationOutput {
        stateStore.contentViewPresentation(
            sampleRateBanner: sampleRateBannerPresentation
         )
     }

var contentViewState: ContentViewState {
        contentViewPresentation.contentViewState
     }

var sampleRateBannerPresentation: SampleRateBannerPresentation {
        sampleRatePresentation.banner
     }

private var sampleRatePresentation: SampleRatePresentationOutput {
        stateStore.sampleRatePresentation(
            isAttemptingPlaybackStart: isAttemptingPlaybackStart
         )
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

        // Task inherits @MainActor from surrounding context
        Task {
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
            shouldAutoplay: contentViewState.isPlaying || sessionController.isStartingPlayback
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
