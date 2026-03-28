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
    private var currentStatus: StatusEvent = .stopped

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

    var isLoading: Bool {
        if case .loading = currentStatus { return true }
        return false
    }

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
        stop()
        updateStatus(.loading)
    }

    /// Report a file selection error from the file picker
    func reportFileSelectionError(_ message: String) {
        updateStatus(.error(.loadFailed(message)))
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
                updateStatus(.loadingCancelled)
                return
            }

            do {
                let audioInfo = try await engine.loadFile(from: url)

                // Discard result if a newer load has started
                guard generation == self.loadGeneration else { return }

                guard !Task.isCancelled else {
                    updateStatus(.loadingCancelled)
                    return
                }

                currentTime = 0
                engine.setVolume(volume)
                await updateHardwareSampleRate()
                updateStatus(.ready(audioInfo))

            } catch let error as PlaybackError {
                guard generation == self.loadGeneration else { return }
                updateStatus(.error(error))
            } catch {
                guard generation == self.loadGeneration else { return }
                updateStatus(.error(.loadFailed(error.localizedDescription)))
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
            updateStatus(.playing)
        } catch let error as PlaybackError {
            updateStatus(.error(error))
        } catch {
            updateStatus(.error(.notReady))
        }
    }

    private func pause() {
        do {
            try engine.pause()
            progressTracker.stopTracking()
            updateStatus(.paused)
        } catch let error as PlaybackError {
            updateStatus(.error(error))
        } catch {
            updateStatus(.error(.notPlaying))
        }
    }

    func stop() {
        engine.stop()
        progressTracker.stopTracking()
        currentTime = 0
        updateStatus(.stopped)
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
                updateStatus(.error(.sampleRateSyncFailed(
                    "Hardware stayed at \(Int(hardwareSampleRate)) Hz")))
            } else {
                updateStatus(.sampleRateSynchronized)
            }
        } catch let error as PlaybackError {
            updateStatus(.error(error))
        } catch {
            updateStatus(.error(.sampleRateSyncFailed(error.localizedDescription)))
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
                self.updateStatus(.finished)
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

    /// Update user-facing status derived from engine state and local UI events
    private func updateStatus(_ event: StatusEvent) {
        currentStatus = event

        switch event {
        case .loading:
            statusMessage = "Loading file..."
            hasError = false

        case .ready(let audioInfo):
            if hasSampleRateMismatch {
                statusMessage = "Ready — output at \(Int(hardwareSampleRate)) Hz (file is \(Int(audioInfo.sampleRate)) Hz)"
            } else {
                statusMessage = "Ready to play at \(Int(audioInfo.sampleRate)) Hz"
            }
            hasError = false

        case .playing:
            if hasSampleRateMismatch {
                statusMessage = "Playing at \(Int(hardwareSampleRate)) Hz (resampled from \(Int(fileSampleRate)) Hz)"
            } else {
                statusMessage = "Playing at \(Int(fileSampleRate)) Hz"
            }
            hasError = false

        case .paused:
            statusMessage = "Paused"
            hasError = false

        case .stopped:
            statusMessage = "Stopped"
            hasError = false

        case .finished:
            statusMessage = "Playback finished"
            hasError = false

        case .loadingCancelled:
            statusMessage = "Loading cancelled"
            hasError = false

        case .sampleRateSynchronized:
            statusMessage = "Hardware sample rate set to \(Int(fileSampleRate)) Hz"
            hasError = false

        case .error(let error):
            statusMessage = error.localizedDescription
            hasError = true
        }
    }
}

// MARK: - Status Events

/// Events that trigger status message updates
private enum StatusEvent {
    case loading
    case ready(AudioInfo)
    case playing
    case paused
    case stopped
    case finished
    case loadingCancelled
    case sampleRateSynchronized
    case error(PlaybackError)
}
