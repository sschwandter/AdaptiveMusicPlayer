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

    struct ActivityIndicatorPresentation: Equatable {
        enum Style: Equatable {
            case idle
            case playing
            case sampleRateMatched
            case sampleRateMismatched
            case error
        }

        let title: String
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
        let activityIndicator: ActivityIndicatorPresentation
        let transport: TransportControlsPresentation
        let playlist: PlaylistBrowserPresentation
    }


    // MARK: - Constants

    private enum Constants {
        static let progressUpdateInterval: TimeInterval = 0.1  // seconds
        static let sampleRateTolerance: Double = 1.0  // Hz
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
    var playlistTrackPosition: String? { playlistSession?.positionDescription }
    var playlistTracks: [PlaylistTrackRow] {
        guard let playlistSession else { return [] }

        return playlistSession.playlist.tracks.enumerated().map { index, url in
            PlaylistTrackRow(
                url: url,
                index: index,
                isCurrent: index == playlistSession.currentIndex,
                displayTitle: displayTitlesByTrackURL[url] ?? url.lastPathComponent
            )
        }
    }
    var hasPlaylist: Bool { playlistSession?.trackCount ?? 0 > 1 }
    var canPlayPreviousTrack: Bool { playlistSession?.canMoveToPreviousTrack ?? false }
    var canPlayNextTrack: Bool { playlistSession?.canMoveToNextTrack ?? false }
    var fileSampleRate: Double { screenState.playback.audioInfo?.sampleRate ?? 0 }
    var hardwareSampleRate: Double { screenState.hardware.currentSampleRate }
    var hardwareDeviceName: String { screenState.hardware.deviceName }
    var supportedHardwareSampleRates: [Double] { screenState.hardware.supportedSampleRates }

    var isLoading: Bool { screenState.loading.isActive }

    var isPlaying: Bool { screenState.playback.isPlaying }

    var contentViewState: ContentViewState {
        let hasLoadedFile = currentDisplayTitle != nil
        let transport = TransportControlsPresentation(
            canPlayPreviousTrack: canPlayPreviousTrack && !isLoading,
            canPlayPause: hasLoadedFile && !isLoading,
            canSkip: hasLoadedFile && !isLoading,
            canPlayNextTrack: canPlayNextTrack && !isLoading,
            canStop: hasLoadedFile && !isLoading,
            canAdjustVolume: !isLoading,
            playPauseSymbolName: isPlaying ? "pause.fill" : "play.fill",
            playPauseHelp: isPlaying ? "Pause (Space)" : "Play (Space)"
        )
        let playlist = PlaylistBrowserPresentation(
            isVisible: hasPlaylist && hasLoadedFile,
            positionDescription: playlistTrackPosition,
            tracks: playlistTracks
        )

        return ContentViewState(
            currentTrackTitle: currentDisplayTitle,
            playlistTrackPosition: playlistTrackPosition,
            duration: duration,
            currentTime: currentTime,
            isLoading: isLoading,
            isPlaying: isPlaying,
            hasLoadedFile: hasLoadedFile,
            sliderIsEnabled: hasLoadedFile && !isLoading,
            sliderOpacity: hasLoadedFile ? (isLoading ? 0.7 : 1.0) : 0.45,
            activityIndicator: activityIndicatorPresentation,
            transport: transport,
            playlist: playlist
        )
    }

    var hasSampleRateMismatch: Bool {
        guard fileSampleRate > 0 && hardwareSampleRate > 0 else { return false }
        return abs(fileSampleRate - hardwareSampleRate) > Constants.sampleRateTolerance
    }

    var hardwareDeviceDisplayName: String {
        hardwareDeviceName.isEmpty ? "Unknown output" : hardwareDeviceName
    }

    var supportedHardwareSampleRatesDescription: String {
        guard !supportedHardwareSampleRates.isEmpty else { return "Unavailable" }
        return supportedHardwareSampleRates
            .map(Self.formatSampleRate)
            .joined(separator: ", ")
    }

    var playbackSampleRateBadgeTitle: String {
        guard fileSampleRate > 0 else { return "No File" }
        guard hardwareSampleRate > 0 else { return "Unknown" }
        return Self.formatSampleRate(hardwareSampleRate)
    }

    var activityIndicatorPresentation: ActivityIndicatorPresentation {
        if hasError {
            return ActivityIndicatorPresentation(
                title: "Error",
                iconName: "exclamationmark.triangle.fill",
                helpText: statusMessage.isEmpty ? "Playback error" : statusMessage,
                style: .error
            )
        }

        if fileSampleRate > 0 && hardwareSampleRate > 0 {
            return ActivityIndicatorPresentation(
                title: playbackSampleRateBadgeTitle,
                iconName: hasSampleRateMismatch ? "exclamationmark.triangle.fill" : "waveform.circle.fill",
                helpText: sampleRateStatusDetail,
                style: hasSampleRateMismatch ? .sampleRateMismatched : .sampleRateMatched
            )
        }

        if isPlaying {
            return ActivityIndicatorPresentation(
                title: "Live",
                iconName: "waveform.circle.fill",
                helpText: "Playback in progress",
                style: .playing
            )
        }

        return ActivityIndicatorPresentation(
            title: "Idle",
            iconName: "pause.circle",
            helpText: "Playback is idle",
            style: .idle
        )
    }

    var sampleRateRouteDescription: String {
        let fileRate = fileSampleRate > 0 ? Self.formatSampleRate(fileSampleRate) : "—"
        let hardwareRate = hardwareSampleRate > 0 ? Self.formatSampleRate(hardwareSampleRate) : "—"
        return "\(fileRate) -> \(hardwareRate)"
    }

    var compactSampleRateExplanation: String? {
        guard fileSampleRate > 0 else { return nil }
        guard hardwareSampleRate > 0 else {
            return "Could not read the current hardware sample rate."
        }
        guard hasSampleRateMismatch else { return nil }

        if !deviceSupportsFileSampleRate {
            return "\(hardwareDeviceDisplayName) does not advertise \(Self.formatSampleRate(fileSampleRate))."
        }

        return "\(hardwareDeviceDisplayName) supports \(Self.formatSampleRate(fileSampleRate)), but has not switched yet."
    }

    var showsSupportedRatesHint: Bool {
        fileSampleRate > 0 && (hasSampleRateMismatch || supportedHardwareSampleRates.isEmpty)
    }

    var sampleRateStatusDetail: String {
        guard fileSampleRate > 0 else {
            return "Load a file to compare its sample rate with the active output device."
        }

        let deviceName = hardwareDeviceDisplayName
        guard hardwareSampleRate > 0 else {
            return "Could not read the current sample rate for \(deviceName)."
        }

        if !hasSampleRateMismatch {
            return "Matched on \(deviceName). Playback is running at the file's native rate."
        }

        if !supportedHardwareSampleRates.isEmpty &&
            !Self.sampleRate(fileSampleRate, isWithin: supportedHardwareSampleRates)
        {
            return "\(deviceName) does not advertise support for \(Self.formatSampleRate(fileSampleRate)). Supported rates: \(supportedHardwareSampleRatesDescription)."
        }

        return "\(deviceName) supports \(Self.formatSampleRate(fileSampleRate)), but the hardware is still at \(Self.formatSampleRate(hardwareSampleRate)). Playback will be resampled until the device switches."
    }

    private var deviceSupportsFileSampleRate: Bool {
        !supportedHardwareSampleRates.isEmpty &&
        Self.sampleRate(fileSampleRate, isWithin: supportedHardwareSampleRates)
    }

    // MARK: - Dependencies

    private let engine: AudioPlaybackEngine
    private let progressTracker: PlaybackProgressTracking
    private let hardwareObserver: AudioHardwareObserving
    private let hardwareInfoProvider: AudioHardwareInfoProviding
    private let folderScanner: AudioPlaylistFolderScanning
    private let finderItemRevealer: FinderItemRevealing
    private var loadingTask: Task<Void, Never>?
    private var loadGeneration: Int = 0
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
        self.folderScanner = folderScanner
        self.finderItemRevealer = finderItemRevealer

        hardwareObserver.startObserving { [weak self] in
            Task { @MainActor [weak self] in
                await self?.refreshHardwareInfo()
            }
        }

        Task {
            await refreshHardwareInfo()
        }
    }

    deinit {
        hardwareObserver.stopObserving()
    }

    // MARK: - File Loading

    /// Starts a file load and enters loading state immediately.
    /// A short delay can be requested to let the file importer dismiss first.
    func loadFile(url: URL, importerDismissalDelay: Duration = .zero) {
        playlistSession = PlaylistSession.singleTrack(url)
        loadPlaylistTrack(
            at: 0,
            importerDismissalDelay: importerDismissalDelay
        )
    }

    func loadFolder(url: URL, importerDismissalDelay: Duration = .zero) {
        runLoadTask(loadingState: .scanningFolder, message: "Scanning folder...") { generation in
            try await self.waitForImporterDismissal(
                importerDismissalDelay,
                generation: generation
            )

            guard let folderAccess = ScopedFolderAccess(folderURL: url) else {
                throw PlaybackError.loadFailed("Cannot access folder")
            }

            let tracks = try await Task.detached(priority: .userInitiated) {
                try self.folderScanner.scan(folderURL: url)
            }.value

            try self.ensureLoadRemainsCurrent(generation)

            guard let playlistSession = PlaylistSession.folderPlaylist(
                tracks: tracks,
                folderAccess: folderAccess
            ) else {
                throw PlaybackError.loadFailed("No playable audio files were found in the selected folder.")
            }

            self.playlistSession = playlistSession
            try await self.continueLoadingPreparedTrack(
                from: playlistSession.currentTrackURL,
                generation: generation
            )
        }
    }

    /// Report a file selection error from the file picker
    func reportFileSelectionError(_ message: String) {
        showError(.loadFailed(message))
    }

    func waitForCurrentLoad() async {
        await loadingTask?.value
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
        loadPlaylistTrack(at: index, autoplayOnSuccess: shouldAutoplay)
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
            setStatusMessage("Paused")
            return
        }

        do {
            let audioInfo = try engine.pause()
            transitionToPausedPlayback(audioInfo)
            progressTracker.stopTracking()
            setStatusMessage("Paused")
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
        setStatusMessage("Stopped")
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
                setStatusMessage("Hardware sample rate set to \(Self.formatSampleRate(fileSampleRate)) on \(hardwareDeviceDisplayName)")
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
                    self.setStatusMessage("Playback finished")
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
        with message: String,
        cancelCurrentLoad: Bool = true,
        advanceGeneration: Bool = true
    ) {
        _ = cancelPendingPlaybackStart()
        let preservedAudioInfo = engine.beginLoading()
        transitionToLoadingPlayback(preserving: preservedAudioInfo)
        progressTracker.stopTracking()
        currentTime = 0
        screenState.loading = message == "Scanning folder..." ? .scanningFolder : .loadingTrack
        setStatusMessage(message)

        if cancelCurrentLoad {
            loadingTask?.cancel()
        }
        if advanceGeneration {
            loadGeneration += 1
        }
    }

    private func runLoadTask(
        loadingState: LoadingPresentationState,
        message: String,
        cancelCurrentLoad: Bool = true,
        advanceGeneration: Bool = true,
        operation: @escaping @MainActor (Int) async throws -> Void
    ) {
        beginLoading(
            with: message,
            cancelCurrentLoad: cancelCurrentLoad,
            advanceGeneration: advanceGeneration
        )
        screenState.loading = loadingState

        let generation = loadGeneration
        loadingTask = Task { @MainActor [weak self] in
            guard let self else { return }

            do {
                try await operation(generation)
            } catch is CancellationError {
                self.handleLoadCancellation(generation: generation)
            } catch let error as PlaybackError {
                self.handleLoadFailure(error, generation: generation)
            } catch {
                self.handleLoadFailure(.loadFailed(error.localizedDescription), generation: generation)
            }
        }
    }

    private func loadPlaylistTrack(
        at index: Int,
        importerDismissalDelay: Duration = .zero,
        autoplayOnSuccess: Bool = false
    ) {
        guard let nextPlaylistSession = playlistSession?.movingToTrack(at: index) else { return }
        playlistSession = nextPlaylistSession

        let trackURL = nextPlaylistSession.currentTrackURL
        let loadingMessage = nextPlaylistSession.trackCount > 1
            ? "Loading track \(nextPlaylistSession.positionDescription)..."
            : "Loading file..."
        runLoadTask(loadingState: .loadingTrack, message: loadingMessage) { generation in
            try await self.waitForImporterDismissal(
                importerDismissalDelay,
                generation: generation
            )
            try await self.finishLoadingTrack(
                from: trackURL,
                generation: generation,
                autoplayOnSuccess: autoplayOnSuccess
            )
        }
    }

    private func waitForImporterDismissal(_ delay: Duration, generation: Int) async throws {
        guard delay > .zero else { return }

        do {
            try await Task.sleep(for: delay)
        } catch is CancellationError {
            guard generation == loadGeneration else { throw CancellationError() }
            throw CancellationError()
        } catch {
            throw CancellationError()
        }
    }

    private func finishLoadingTrack(
        from trackURL: URL,
        generation: Int,
        autoplayOnSuccess: Bool = false
    ) async throws {
        let audioInfo = try await engine.loadFile(from: trackURL)
        transitionToReadyPlayback(audioInfo)
        displayTitlesByTrackURL[trackURL] = audioInfo.displayTitle

        try ensureLoadRemainsCurrent(generation)

        currentTime = 0
        engine.setVolume(volume)
        await refreshHardwareInfo()
        showReadyStatus(for: audioInfo)

        if autoplayOnSuccess {
            startPlayback()
        }
    }

    private func continueLoadingPreparedTrack(
        from trackURL: URL,
        generation: Int,
        autoplayOnSuccess: Bool = false
    ) async throws {
        let loadingMessage = playlistSession?.trackCount ?? 0 > 1
            ? "Loading track \(playlistSession?.positionDescription ?? "")..."
            : "Loading file..."

        beginLoading(
            with: loadingMessage,
            cancelCurrentLoad: false,
            advanceGeneration: false
        )
        screenState.loading = .loadingTrack

        try await finishLoadingTrack(
            from: trackURL,
            generation: generation,
            autoplayOnSuccess: autoplayOnSuccess
        )
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

    private func ensureLoadRemainsCurrent(_ generation: Int) throws {
        guard generation == loadGeneration, !Task.isCancelled else {
            throw CancellationError()
        }
    }

    private func handleLoadCancellation(generation: Int) {
        guard generation == loadGeneration else { return }
        setStatusMessage("Loading cancelled")
    }

    private func handleLoadFailure(_ error: PlaybackError, generation: Int) {
        guard generation == loadGeneration else { return }
        showError(error)
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

        self.playlistSession = nextPlaylistSession
        loadPlaylistTrack(at: nextPlaylistSession.currentIndex, autoplayOnSuccess: autoplay)
        return true
    }

    private func showReadyStatus(for audioInfo: AudioInfo) {
        screenState.loading = .idle
        let prefix = playlistSession?.trackCount ?? 0 > 1
            ? "Track \(playlistSession?.positionDescription ?? "") ready"
            : "Ready to play"

        if hasSampleRateMismatch {
            setStatusMessage("\(prefix) — \(sampleRateStatusDetail)")
        } else {
            setStatusMessage("\(prefix) at \(Self.formatSampleRate(audioInfo.sampleRate)) on \(hardwareDeviceDisplayName)")
        }
    }

    private func showPlayingStatus() {
        screenState.loading = .idle
        let prefix = playlistSession?.trackCount ?? 0 > 1
            ? "Playing track \(playlistSession?.positionDescription ?? "")"
            : "Playing"

        if hasSampleRateMismatch {
            setStatusMessage("\(prefix) — \(sampleRateStatusDetail)")
        } else {
            setStatusMessage("\(prefix) at \(Self.formatSampleRate(fileSampleRate)) on \(hardwareDeviceDisplayName)")
        }
    }

    private func showError(_ error: PlaybackError) {
        if currentAudioInfo == nil {
            screenState.playback = .unavailable
        }
        screenState.loading = .failed
        screenState.status = StatusPresentationState(kind: .error, message: error.localizedDescription)
    }

    private func setStatusMessage(_ message: String) {
        if message == "Loading cancelled" {
            screenState.loading = .cancelled
            screenState.status = StatusPresentationState(kind: .info, message: message)
            return
        }

        if screenState.loading.isActive {
            screenState.status = StatusPresentationState(kind: .info, message: message)
            return
        }

        screenState.loading = .idle
        screenState.status = StatusPresentationState(kind: message.isEmpty ? .neutral : .info, message: message)
    }

    private static func formatSampleRate(_ sampleRate: Double) -> String {
        let kilohertz = sampleRate / 1000
        if abs(kilohertz.rounded() - kilohertz) < 0.05 {
            return "\(Int(kilohertz.rounded())) kHz"
        }
        return String(format: "%.1f kHz", kilohertz)
    }

    private static func sampleRate(_ target: Double, isWithin supportedRates: [Double]) -> Bool {
        supportedRates.contains { abs($0 - target) <= Constants.sampleRateTolerance }
    }

    private var currentAudioInfo: AudioInfo? {
        screenState.playback.audioInfo
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
