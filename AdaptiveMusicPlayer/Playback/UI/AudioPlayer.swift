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
    var fileSampleRate: Double { engine.state.audioInfo?.sampleRate ?? 0 }
    var hardwareSampleRate: Double = 0

    var isLoading: Bool { engine.state.isLoading }

    var isPlaying: Bool { engine.state.isPlaying }

    var hasSampleRateMismatch: Bool {
        guard fileSampleRate > 0 && hardwareSampleRate > 0 else { return false }
        return abs(fileSampleRate - hardwareSampleRate) > Constants.sampleRateTolerance
    }

    // MARK: - Dependencies

    private let engine: AudioPlaybackEngine
    private let progressTracker: PlaybackProgressTracking
    private var loadingTask: Task<Void, Never>?
    private var loadGeneration: Int = 0

    // MARK: - Initialization

    init(
        engine: AudioPlaybackEngine = AudioPlaybackEngine(),
        progressTracker: PlaybackProgressTracking = PlaybackProgressTracker()
    ) {
        self.engine = engine
        self.progressTracker = progressTracker
        Task {
            await updateHardwareSampleRate()
        }
    }

    // MARK: - File Loading

    /// Set loading state immediately (synchronous)
    /// Called from UI before async file loading begins
    func setLoadingState() {
        engine.beginLoading()
        progressTracker.stopTracking()
        currentTime = 0
        setStatusMessage("Loading file...")
    }

    /// Report a file selection error from the file picker
    func reportFileSelectionError(_ message: String) {
        showError(.loadFailed(message))
    }

    func loadFile(url: URL) async {
        // Loading state already set by caller (setLoadingState())

        // Cancel any existing load operation
        loadingTask?.cancel()
        loadGeneration += 1
        let generation = loadGeneration

        loadingTask = Task {
            guard !Task.isCancelled else {
                guard generation == self.loadGeneration else { return }
                setStatusMessage("Loading cancelled")
                return
            }

            do {
                let audioInfo = try await engine.loadFile(from: url)

                // Discard result if a newer load has started
                guard generation == self.loadGeneration else { return }

                guard !Task.isCancelled else {
                    setStatusMessage("Loading cancelled")
                    return
                }

                currentTime = 0
                engine.setVolume(volume)
                await updateHardwareSampleRate()
                showReadyStatus(for: audioInfo)

            } catch let error as PlaybackError {
                guard generation == self.loadGeneration else { return }
                showError(error)
            } catch {
                guard generation == self.loadGeneration else { return }
                showError(.loadFailed(error.localizedDescription))
            }
        }

        await loadingTask?.value
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
                await updateHardwareSampleRate()
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
            await updateHardwareSampleRate()

            // Verify the switch actually took effect
            if hasSampleRateMismatch {
                showError(.sampleRateSyncFailed(
                    "Hardware stayed at \(Int(hardwareSampleRate)) Hz"))
            } else {
                setStatusMessage("Hardware sample rate set to \(Int(fileSampleRate)) Hz")
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
                self.engine.markFinished()
                self.currentTime = self.duration
                self.setStatusMessage("Playback finished")
            },
            onPeriodicUpdate: { [weak self] in
                Task {
                    await self?.updateHardwareSampleRate()
                }
            }
        )
    }

    // MARK: - Private Methods

    private func updateHardwareSampleRate() async {
        hardwareSampleRate = await engine.getCurrentHardwareSampleRate()
    }

    private func showReadyStatus(for audioInfo: AudioInfo) {
        if hasSampleRateMismatch {
            setStatusMessage("Ready — output at \(Int(hardwareSampleRate)) Hz (file is \(Int(audioInfo.sampleRate)) Hz)")
        } else {
            setStatusMessage("Ready to play at \(Int(audioInfo.sampleRate)) Hz")
        }
    }

    private func showPlayingStatus() {
        if hasSampleRateMismatch {
            setStatusMessage("Playing at \(Int(hardwareSampleRate)) Hz (resampled from \(Int(fileSampleRate)) Hz)")
        } else {
            setStatusMessage("Playing at \(Int(fileSampleRate)) Hz")
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
}
