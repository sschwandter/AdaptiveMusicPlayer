import Foundation
import AVFoundation
import Observation

/// ViewModel for audio playback
/// Translates domain logic to presentation state
@MainActor
@Observable
final class AudioPlayer: @unchecked Sendable { // Safe: all access serialized on MainActor

    // MARK: - Constants

    private enum Constants {
        static let progressUpdateInterval: TimeInterval = 0.1  // seconds
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
        return fileSampleRate != hardwareSampleRate
    }

    // MARK: - Dependencies

    private let engine: AudioPlaybackEngine
    private let progressTracker: PlaybackProgressTracking
    private var loadingTask: Task<Void, Never>?

    // MARK: - Initialization

    init(
        engine: AudioPlaybackEngine = AudioPlaybackEngine(),
        progressTracker: PlaybackProgressTracking = PlaybackProgressTracker()
    ) {
        self.engine = engine
        self.progressTracker = progressTracker
        updateHardwareSampleRate()
    }

    // MARK: - File Loading

    /// Set loading state immediately (synchronous)
    /// Called from UI before async file loading begins
    func setLoadingState() {
        stop()
        updateStatus(.loading)
    }

    func loadFile(url: URL) async {
        // Loading state already set by caller (setLoadingState())

        // Cancel any existing load operation
        loadingTask?.cancel()

        loadingTask = Task {
            guard !Task.isCancelled else {
                updateStatus(.loadingCancelled)
                return
            }

            do {
                let audioInfo = try await engine.loadFile(from: url)

                guard !Task.isCancelled else {
                    updateStatus(.loadingCancelled)
                    return
                }

                currentTime = 0
                engine.setVolume(volume)
                updateHardwareSampleRate()
                updateStatus(.ready(audioInfo))

            } catch let error as PlaybackError {
                updateStatus(.error(error))
            } catch {
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
            updateHardwareSampleRate()
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

    func synchronizeSampleRates() {
        do {
            try engine.synchronizeSampleRates()

            // Wait for hardware to switch, then refresh
            Task {
                try? await Task.sleep(for: .milliseconds(500))
                updateHardwareSampleRate()
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
                self?.updateHardwareSampleRate()
            }
        )
    }

    // MARK: - Private Methods

    private func updateHardwareSampleRate() {
        hardwareSampleRate = engine.getCurrentHardwareSampleRate()
    }

    /// Update presentation state based on domain state
    private func updateStatus(_ event: StatusEvent) {
        currentStatus = event

        switch event {
        case .loading:
            statusMessage = "Loading file..."
            hasError = false

        case .ready(let audioInfo):
            statusMessage = "Ready to play at \(Int(audioInfo.sampleRate)) Hz"
            hasError = false

        case .playing:
            if hasSampleRateMismatch {
                statusMessage = "Playing at \(Int(fileSampleRate)) Hz (hardware resampling from \(Int(hardwareSampleRate)) Hz)"
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
            statusMessage = error.localizedDescription ?? "An error occurred"
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
