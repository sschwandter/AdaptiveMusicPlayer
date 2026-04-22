import Foundation
import AVFoundation
import Observation

/// Observable playback view model used by SwiftUI
/// Wraps the engine and maintains additional UI-facing status state
@MainActor
@Observable
final class AudioPlayer: @unchecked Sendable { // Safe: all access serialized on MainActor
    struct PlayerScreenState {
        var playback: PlaybackPresentationState = .idle
        var loading: LoadingPresentationState = .idle
        var status: StatusPresentationState = .init()
        var playlist: PlaylistPresentationState = .init()
        var hardware: HardwarePresentationState = .init()
    }

    enum PlaybackPresentationState {
        case idle
        case ready(AudioInfo)
        case playing(AudioInfo)
        case paused(AudioInfo)
        case finished(AudioInfo)
        case unavailable

        var audioInfo: AudioInfo? {
            switch self {
            case .ready(let info), .playing(let info), .paused(let info), .finished(let info):
                return info
            case .idle, .unavailable:
                return nil
            }
        }

        var isPlaying: Bool {
            if case .playing = self { return true }
            return false
        }
    }

    enum LoadingPresentationState {
        case idle
        case scanningFolder
        case loadingTrack
        case startingPlayback
        case cancelled
        case failed

        var isActive: Bool {
            switch self {
            case .scanningFolder, .loadingTrack:
                return true
            case .idle, .startingPlayback, .cancelled, .failed:
                return false
            }
        }
    }

    struct StatusPresentationState {
        enum Kind {
            case neutral
            case info
            case error
        }

        var kind: Kind = .neutral
        var message: String = ""
    }

    struct PlaylistPresentationState {
        var session: PlaylistSession?
    }

    struct HardwarePresentationState {
        var deviceName: String = ""
        var currentSampleRate: Double = 0
        var supportedSampleRates: [Double] = []
    }

    struct SampleRateBannerPresentation: Equatable {
        enum Style: Equatable {
            case idle
            case matched
            case switching
            case unsupported
            case error
        }

        let title: String
        let detail: String?
        let iconName: String
        let helpText: String
        let style: Style
    }

    struct PlaylistTrackRow: Identifiable, Equatable {
        let url: URL
        let index: Int
        let isCurrent: Bool
        let displayTitle: String

        var id: URL { url }
        var title: String { displayTitle }
        var subtitle: String { url.deletingLastPathComponent().lastPathComponent }
    }

    struct TransportControlsPresentation {
        let canPlayPreviousTrack: Bool
        let canPlayPause: Bool
        let canSkip: Bool
        let canPlayNextTrack: Bool
        let canStop: Bool
        let canAdjustVolume: Bool
        let playPauseSymbolName: String
        let playPauseHelp: String
    }

    struct PlaylistBrowserPresentation {
        let isVisible: Bool
        let positionDescription: String?
        let tracks: [PlaylistTrackRow]
    }

    struct ContentViewState {
        let currentTrackTitle: String?
        let playlistTrackPosition: String?
        let duration: Double
        let currentTime: Double
        let isLoading: Bool
        let isPlaying: Bool
        let hasLoadedFile: Bool
        let sliderIsEnabled: Bool
        let sliderOpacity: Double
        let sampleRateBanner: SampleRateBannerPresentation
        let transport: TransportControlsPresentation
        let playlist: PlaylistBrowserPresentation
    }


    // MARK: - Constants

    private enum Constants {
        static let progressUpdateInterval: TimeInterval = 0.1  // seconds
    }

    // MARK: - Presentation State

    private var screenState = PlayerScreenState()

    // MARK: - Domain State (exposed to UI)

    var currentTime: Double = 0
    var duration: Double { screenState.playback.audioInfo?.duration ?? 0 }
    var volume: Double = 1 {
        didSet {
            engine.setVolume(volume)
        }
    }
    var statusMessage: String { screenState.status.message }
    var hasError: Bool { screenState.status.kind == .error }
    var currentFileName: String? { screenState.playback.audioInfo?.fileName }
    var currentDisplayTitle: String? { screenState.playback.audioInfo?.displayTitle }
    var fileSampleRate: Double { screenState.playback.audioInfo?.sampleRate ?? 0 }
    var hardwareSampleRate: Double { screenState.hardware.currentSampleRate }
    var hardwareDeviceName: String { screenState.hardware.deviceName }
    var supportedHardwareSampleRates: [Double] { screenState.hardware.supportedSampleRates }

    var isLoading: Bool { screenState.loading.isActive }

    var isPlaying: Bool { screenState.playback.isPlaying }

    private var isAttemptingPlaybackStart: Bool {
        playbackStartupTask != nil
    }

    private var sampleRatePresentation: SampleRatePresentationOutput {
        SampleRatePresenter().build(
            from: SampleRatePresentationInput(
                fileSampleRate: fileSampleRate,
                hardwareSampleRate: hardwareSampleRate,
                hardwareDeviceName: hardwareDeviceName,
                supportedHardwareSampleRates: supportedHardwareSampleRates,
                hasError: hasError,
                statusMessage: statusMessage,
                isPlaying: isPlaying,
                isAttemptingPlaybackStart: isAttemptingPlaybackStart
            )
        )
    }

    private var contentViewPresentation: ContentViewStatePresentationOutput {
        ContentViewStatePresenter().present(
            input: ContentViewStatePresentationInput(
                playback: screenState.playback,
                loading: screenState.loading,
                currentTime: currentTime,
                playlistSession: playlistSession,
                displayTitlesByTrackURL: displayTitlesByTrackURL,
                sampleRateBanner: sampleRateBannerPresentation
            )
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
    private let loadCoordinator: AudioPlayerLoadCoordinator
    private var playbackStartupTask: Task<Void, Never>?
    private var activePlaybackStartupGeneration: Int?
    private var playbackStartupGeneration: Int = 0
    private var displayTitlesByTrackURL: [URL: String] = [:]
    private var playlistSession: PlaylistSession? {
        get { screenState.playlist.session }
        set { screenState.playlist.session = newValue }
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
        self.loadCoordinator = AudioPlayerLoadCoordinator(folderScanner: folderScanner)

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

    /// Report a file selection error from the file picker
    func reportFileSelectionError(_ message: String) {
        showError(.loadFailed(message))
    }

    func waitForCurrentLoad() async {
        await loadCoordinator.waitForCurrentLoad()
        await playbackStartupTask?.value
    }

    func playNextTrack() {
        moveToAdjacentTrack(next: true, autoplay: true)
    }

    func playPreviousTrack() {
        moveToAdjacentTrack(next: false, autoplay: true)
    }

    func selectPlaylistTrack(at index: Int) {
        let shouldAutoplay = isPlaying || playbackStartupTask != nil
        guard let playlistSession, playlistSession.currentIndex != index else { return }
        guard let nextPlaylistSession = playlistSession.movingToTrack(at: index) else { return }

        loadCoordinator.loadPlaylistTrack(
            playlistSession: nextPlaylistSession,
            autoplayOnSuccess: shouldAutoplay,
            loadTrack: { [engine] trackURL in
                try await engine.loadFile(from: trackURL)
            },
            handleEvent: { [weak self] event in
                await self?.handleLoadEvent(event)
            }
        )
    }

    func showCurrentTrackInFinder() {
        guard let currentTrackURL = playlistSession?.currentTrackURL else { return }
        finderItemRevealer.revealItem(at: currentTrackURL)
    }

    // MARK: - Playback Control

    func togglePlayPause() {
        if isPlaying || playbackStartupTask != nil {
            pause()
        } else {
            startPlayback()
        }
    }

    private func startPlayback() {
        guard playbackStartupTask == nil else { return }

        playbackStartupGeneration += 1
        let generation = playbackStartupGeneration
        activePlaybackStartupGeneration = generation
        screenState.loading = .startingPlayback
        playbackStartupTask = Task { @MainActor [weak self] in
            await self?.play(generation: generation)
        }
    }

    private func play(generation: Int) async {
        defer {
            if activePlaybackStartupGeneration == generation {
                activePlaybackStartupGeneration = nil
                playbackStartupTask = nil
            }
        }

        do {
            let audioInfo = try await engine.play()

            try await finishSuccessfulPlaybackStart(generation: generation, audioInfo: audioInfo)
        } catch is CancellationError {
            handlePlaybackStartupCancellation(generation: generation)
        } catch let error as PlaybackError {
            handlePlaybackStartupFailure(error, generation: generation)
        } catch {
            handlePlaybackStartupFailure(.notReady, generation: generation)
        }
    }

    private func pause() {
        if cancelPendingPlaybackStart() {
            progressTracker.stopTracking()
            applyStatusPresentation(statusPresenter.presentInfo(message: "Paused"))
            return
        }

        do {
            let audioInfo = try engine.pause()
            transitionToPausedPlayback(audioInfo)
            progressTracker.stopTracking()
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
        transitionToStoppedPlayback(preserving: audioInfo)
        progressTracker.stopTracking()
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
        guard let player = engine.getPlayer() else { return }

        progressTracker.startTracking(
            player: player,
            duration: duration,
            updateInterval: Constants.progressUpdateInterval,
            onProgressUpdate: { [weak self] time in
                self?.currentTime = time
            },
            onPlaybackFinished: { [weak self] in
                guard let self else { return }
                if !self.moveToAdjacentTrack(next: true, autoplay: true) {
                    let audioInfo = self.engine.markFinished()
                    self.transitionToFinishedPlayback(audioInfo)
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

    // MARK: - Private Methods

    private func refreshHardwareInfo() async {
        if let deviceInfo = await hardwareInfoProvider.getCurrentAudioDeviceInfo() {
            screenState.hardware = HardwarePresentationState(
                deviceName: deviceInfo.name,
                currentSampleRate: deviceInfo.currentSampleRate,
                supportedSampleRates: deviceInfo.supportedSampleRates
            )
        } else {
            screenState.hardware = HardwarePresentationState()
        }
    }

    private func beginLoading(
        loadingState: LoadingPresentationState,
        with message: String
    ) {
        _ = cancelPendingPlaybackStart()
        let preservedAudioInfo = engine.beginLoading()
        transitionToLoadingPlayback(preserving: preservedAudioInfo)
        progressTracker.stopTracking()
        currentTime = 0
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
        autoplayOnSuccess: Bool = false
    ) async throws {
        transitionToReadyPlayback(audioInfo)
        displayTitlesByTrackURL[trackURL] = audioInfo.displayTitle

        currentTime = 0
        engine.setVolume(volume)
        await refreshHardwareInfo()
        showReadyStatus(for: audioInfo)

        if autoplayOnSuccess {
            startPlayback()
        }
    }

    private func cancelPendingPlaybackStart() -> Bool {
        guard playbackStartupTask != nil else { return false }

        playbackStartupGeneration += 1
        activePlaybackStartupGeneration = nil
        playbackStartupTask?.cancel()
        playbackStartupTask = nil
        return true
    }

    private func playbackStartupRemainsCurrent(_ generation: Int) -> Bool {
        activePlaybackStartupGeneration == generation && !Task.isCancelled
    }

    private func handleLoadCancellation() {
        applyStatusPresentation(
            statusPresenter.presentInfo(
                message: "Loading cancelled",
                loading: .cancelled
            )
        )
    }

    private func finishSuccessfulPlaybackStart(generation: Int, audioInfo: AudioInfo) async throws {
        guard playbackStartupRemainsCurrent(generation) else {
            let preservedAudioInfo = engine.stop()
            transitionToStoppedPlayback(preserving: preservedAudioInfo)
            currentTime = 0
            return
        }

        transitionToPlayingPlayback(audioInfo)
        startProgressTracking()
        await refreshHardwareInfo()
        showPlayingStatus()
    }

    private func handlePlaybackStartupCancellation(generation: Int) {
        guard playbackStartupRemainsCurrent(generation) else { return }
        screenState.loading = .idle
    }

    private func handlePlaybackStartupFailure(_ error: PlaybackError, generation: Int) {
        guard playbackStartupRemainsCurrent(generation) else { return }
        showError(error)
    }

    @discardableResult
    private func moveToAdjacentTrack(next: Bool, autoplay: Bool = false) -> Bool {
        guard let playlistSession else { return false }

        let nextPlaylistSession = next
            ? playlistSession.movingToNextTrack()
            : playlistSession.movingToPreviousTrack()

        guard let nextPlaylistSession else { return false }

        loadCoordinator.loadPlaylistTrack(
            playlistSession: nextPlaylistSession,
            autoplayOnSuccess: autoplay,
            loadTrack: { [engine] trackURL in
                try await engine.loadFile(from: trackURL)
            },
            handleEvent: { [weak self] event in
                await self?.handleLoadEvent(event)
            }
        )
        return true
    }

    private func handleLoadEvent(_ event: AudioPlayerLoadCoordinator.Event) async {
        switch event {
        case .beginLoading(let loadingState, let message):
            beginLoading(loadingState: loadingState, with: message)
        case .playlistSessionUpdated(let playlistSession):
            self.playlistSession = playlistSession
        case .trackLoaded(let url, let audioInfo, let autoplayOnSuccess):
            do {
                try await finishLoadingTrack(
                    from: url,
                    audioInfo: audioInfo,
                    autoplayOnSuccess: autoplayOnSuccess
                )
            } catch let error as PlaybackError {
                showError(error)
            } catch {
                showError(.loadFailed(error.localizedDescription))
            }
        case .cancelled:
            handleLoadCancellation()
        case .failed(let error):
            showError(error)
        }
    }

    private func showReadyStatus(for audioInfo: AudioInfo) {
        applyStatusPresentation(
            statusPresenter.presentReady(
                PlayerStatusReadyInput(
                    hasPlaylist: playlistSession?.trackCount ?? 0 > 1,
                    playlistTrackPosition: playlistSession?.positionDescription,
                    sampleRate: audioInfo.sampleRate,
                    hardwareDeviceName: hardwareDeviceDisplayName,
                    hasSampleRateMismatch: hasSampleRateMismatch,
                    sampleRateStatusDetail: sampleRateStatusDetail
                )
            )
        )
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
        screenState.playback.audioInfo
    }

    private func applyStatusPresentation(_ output: PlayerStatusPresentationOutput) {
        screenState.loading = output.loading
        screenState.status = output.status

        if let playbackOverride = output.playbackOverride {
            screenState.playback = playbackOverride
        }
    }

    private func transitionToLoadingPlayback(preserving audioInfo: AudioInfo?) {
        if let audioInfo {
            screenState.playback = .ready(audioInfo)
        } else if let currentAudioInfo {
            screenState.playback = .ready(currentAudioInfo)
        } else {
            screenState.playback = .idle
        }
    }

    private func transitionToReadyPlayback(_ audioInfo: AudioInfo) {
        screenState.playback = .ready(audioInfo)
    }

    private func transitionToPlayingPlayback(_ audioInfo: AudioInfo) {
        screenState.playback = .playing(audioInfo)
    }

    private func transitionToPausedPlayback(_ audioInfo: AudioInfo) {
        screenState.playback = .paused(audioInfo)
    }

    private func transitionToStoppedPlayback(preserving audioInfo: AudioInfo?) {
        if let audioInfo {
            screenState.playback = .ready(audioInfo)
            return
        }
        guard let currentAudioInfo else {
            screenState.playback = .idle
            return
        }
        screenState.playback = .ready(currentAudioInfo)
    }

    private func transitionToFinishedPlayback(_ audioInfo: AudioInfo?) {
        if let audioInfo {
            screenState.playback = .finished(audioInfo)
        }
    }
}
