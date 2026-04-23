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

    // MARK: - Commands

    func send(_ command: AudioPlayerCommand) {
        if case .revealCurrentTrackInFinder = command {
            guard let currentTrackURL = stateStore.currentTrackURL else { return }
            finderItemRevealer.revealItem(at: currentTrackURL)
            return
        }

        sessionController.send(command)
    }

    func waitForCurrentLoad() async {
        await sessionController.waitForCurrentActivity()
    }
}
