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
        static let sampleRateTolerance: Double = 1.0  // Hz
    }

    // MARK: - Presentation State

    var statusMessage: String = ""
    var hasError: Bool = false

    // MARK: - Domain State (exposed to UI)

    var currentTime: Double = 0
    var duration: Double { engine.state.audioInfo?.duration ?? 0 }
    var volume: Double = 1 {
        didSet {
            engine.setVolume(volume)
        }
    }
    var currentFileName: String? { engine.state.audioInfo?.fileName }
    var playlistTrackPosition: String? { playlistSession?.positionDescription }
    var hasPlaylist: Bool { playlistSession?.trackCount ?? 0 > 1 }
    var canPlayPreviousTrack: Bool { playlistSession?.canMoveToPreviousTrack ?? false }
    var canPlayNextTrack: Bool { playlistSession?.canMoveToNextTrack ?? false }
    var fileSampleRate: Double { engine.state.audioInfo?.sampleRate ?? 0 }
    var hardwareSampleRate: Double = 0
    var hardwareDeviceName: String = ""
    var supportedHardwareSampleRates: [Double] = []

    var isLoading: Bool { engine.state.isLoading }

    var isPlaying: Bool { engine.state.isPlaying }

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

    var sampleRateBadgeTitle: String {
        guard fileSampleRate > 0 else { return "No File" }
        guard hardwareSampleRate > 0 else { return "Unknown" }
        if !hasSampleRateMismatch { return "Matched" }
        if !deviceSupportsFileSampleRate { return "Unsupported" }
        return "Resampling"
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
    private let folderScanner: AudioPlaylistFolderScanning
    private var loadingTask: Task<Void, Never>?
    private var loadGeneration: Int = 0
    private var playlistSession: PlaylistSession?
    private var playlistScanWarningSummary: String?

    // MARK: - Initialization

    init(
        engine: AudioPlaybackEngine = AudioPlaybackEngine(),
        progressTracker: PlaybackProgressTracking = PlaybackProgressTracker(),
        hardwareObserver: AudioHardwareObserving = CoreAudioHardwareObserver(),
        folderScanner: AudioPlaylistFolderScanning = AudioPlaylistFolderScanner()
    ) {
        self.engine = engine
        self.progressTracker = progressTracker
        self.hardwareObserver = hardwareObserver
        self.folderScanner = folderScanner

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
        playlistScanWarningSummary = nil
        playlistSession = PlaylistSession.singleTrack(url)
        loadPlaylistTrack(at: 0, importerDismissalDelay: importerDismissalDelay)
    }

    func loadFolder(url: URL, importerDismissalDelay: Duration = .zero) {
        beginLoading(with: "Scanning folder...")

        loadingTask = Task {
            let generation = self.loadGeneration

            do {
                try await self.waitForImporterDismissal(
                    importerDismissalDelay,
                    generation: generation
                )

                guard let folderAccess = ScopedFolderAccess(folderURL: url) else {
                    throw PlaybackError.loadFailed("Cannot access folder")
                }

                let scanResult = try await Task.detached(priority: .userInitiated) {
                    try self.folderScanner.scan(folderURL: url)
                }.value

                guard generation == self.loadGeneration else { return }
                guard !Task.isCancelled else {
                    self.setStatusMessage("Loading cancelled")
                    return
                }

                guard let playlistSession = PlaylistSession.folderPlaylist(
                    tracks: scanResult.files,
                    folderAccess: folderAccess
                ) else {
                    self.showError(.loadFailed("No playable audio files were found in the selected folder."))
                    return
                }

                self.playlistScanWarningSummary = scanResult.warningSummary
                self.playlistSession = playlistSession
                self.loadPlaylistTrack(at: playlistSession.currentIndex)
                await self.loadingTask?.value
            } catch is CancellationError {
                guard generation == self.loadGeneration else { return }
                self.setStatusMessage("Loading cancelled")
            } catch let error as PlaybackError {
                guard generation == self.loadGeneration else { return }
                self.showError(error)
            } catch {
                guard generation == self.loadGeneration else { return }
                self.showError(.loadFailed(error.localizedDescription))
            }
        }
    }

    /// Report a file selection error from the file picker
    func reportFileSelectionError(_ message: String) {
        showError(.loadFailed(message))
    }

    func waitForCurrentLoad() async {
        await loadingTask?.value
    }

    func playNextTrack() {
        moveToAdjacentTrack(next: true, autoplay: true)
    }

    func playPreviousTrack() {
        moveToAdjacentTrack(next: false, autoplay: true)
    }

    // MARK: - Playback Control

    func togglePlayPause() {
        if isPlaying {
            pause()
        } else {
            play()
        }
    }

    private func play() {
        do {
            try engine.play()
            startProgressTracking()
            Task {
                await refreshHardwareInfo()
            }
            showPlayingStatus()
        } catch let error as PlaybackError {
            showError(error)
        } catch {
            showError(.notReady)
        }
    }

    private func pause() {
        do {
            try engine.pause()
            progressTracker.stopTracking()
            setStatusMessage("Paused")
        } catch let error as PlaybackError {
            showError(error)
        } catch {
            showError(.notPlaying)
        }
    }

    func stop() {
        engine.stop()
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
                    self.engine.markFinished()
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
        if let deviceInfo = await engine.getCurrentAudioDeviceInfo() {
            hardwareDeviceName = deviceInfo.name
            hardwareSampleRate = deviceInfo.currentSampleRate
            supportedHardwareSampleRates = deviceInfo.supportedSampleRates
        } else {
            hardwareDeviceName = ""
            hardwareSampleRate = await engine.getCurrentHardwareSampleRate()
            supportedHardwareSampleRates = []
        }
    }

    private func beginLoading(with message: String) {
        engine.beginLoading()
        progressTracker.stopTracking()
        currentTime = 0
        setStatusMessage(message)

        loadingTask?.cancel()
        loadGeneration += 1
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
        beginLoading(with: loadingMessage)

        loadingTask = Task {
            let generation = self.loadGeneration

            do {
                try await self.waitForImporterDismissal(
                    importerDismissalDelay,
                    generation: generation
                )

                let audioInfo = try await self.engine.loadFile(from: trackURL)

                guard generation == self.loadGeneration else { return }
                guard !Task.isCancelled else {
                    self.setStatusMessage("Loading cancelled")
                    return
                }

                self.currentTime = 0
                self.engine.setVolume(self.volume)
                await self.refreshHardwareInfo()
                self.showReadyStatus(for: audioInfo)

                if autoplayOnSuccess {
                    self.play()
                }
            } catch is CancellationError {
                guard generation == self.loadGeneration else { return }
                self.setStatusMessage("Loading cancelled")
            } catch let error as PlaybackError {
                guard generation == self.loadGeneration else { return }
                self.showError(error)
            } catch {
                guard generation == self.loadGeneration else { return }
                self.showError(.loadFailed(error.localizedDescription))
            }
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
        let prefix = playlistSession?.trackCount ?? 0 > 1
            ? "Track \(playlistSession?.positionDescription ?? "") ready"
            : "Ready to play"
        let warningSuffix = playlistScanWarningSuffix

        if hasSampleRateMismatch {
            setStatusMessage("\(prefix) — \(sampleRateStatusDetail)\(warningSuffix)")
        } else {
            setStatusMessage("\(prefix) at \(Self.formatSampleRate(audioInfo.sampleRate)) on \(hardwareDeviceDisplayName)\(warningSuffix)")
        }
    }

    private func showPlayingStatus() {
        let prefix = playlistSession?.trackCount ?? 0 > 1
            ? "Playing track \(playlistSession?.positionDescription ?? "")"
            : "Playing"
        let warningSuffix = playlistScanWarningSuffix

        if hasSampleRateMismatch {
            setStatusMessage("\(prefix) — \(sampleRateStatusDetail)\(warningSuffix)")
        } else {
            setStatusMessage("\(prefix) at \(Self.formatSampleRate(fileSampleRate)) on \(hardwareDeviceDisplayName)\(warningSuffix)")
        }
    }

    private func showError(_ error: PlaybackError) {
        statusMessage = error.localizedDescription
        hasError = true
    }

    private func setStatusMessage(_ message: String) {
        statusMessage = message
        hasError = false
    }

    private var playlistScanWarningSuffix: String {
        guard let playlistScanWarningSummary else { return "" }
        return " \(playlistScanWarningSummary)"
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
}
