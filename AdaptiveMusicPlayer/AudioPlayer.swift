import Foundation
import AVFoundation
import Observation
import Combine

@MainActor
@Observable
final class AudioPlayer: @unchecked Sendable { // Safe: all access serialized on MainActor

    // MARK: - Constants

    private enum Constants {
        static let skipInterval: Double = 10  // seconds
        static let progressUpdateInterval: TimeInterval = 0.1  // seconds
    }

    // MARK: - Public Properties

    var currentTime: Double = 0
    var duration: Double = 0
    var volume: Double = 1 {
        didSet {
            player?.volume = Float(volume)
        }
    }
    var currentFileName: String?
    var fileSampleRate: Double = 0
    var hardwareSampleRate: Double = 0
    var statusMessage: String = ""
    var hasError: Bool = false
    var isLoading: Bool = false
    var isPlaying: Bool = false

    private var player: AVAudioPlayer?
    private let sampleRateManager: SampleRateManaging
    private let sessionManager: AudioSessionManaging
    private let progressTracker: PlaybackProgressTracking
    private var loadingTask: Task<Void, Never>?

    init(
        sampleRateManager: SampleRateManaging = CoreAudioSampleRateManager(),
        sessionManager: AudioSessionManaging = AudioSessionManager(),
        progressTracker: PlaybackProgressTracking = PlaybackProgressTracker()
    ) {
        self.sampleRateManager = sampleRateManager
        self.sessionManager = sessionManager
        self.progressTracker = progressTracker
        updateHardwareSampleRate()
    }

    func loadFile(url: URL) async {
        // Cancel any existing load operation
        loadingTask?.cancel()

        loadingTask = Task {
            await loadFileAsync(url: url)
        }

        await loadingTask?.value
    }

    private func loadFileAsync(url: URL) async {
        // Check for cancellation early
        guard !Task.isCancelled else { return }

        // Stop playback and clear the old file first
        stop()
        player = nil
        isLoading = true
        statusMessage = "Loading file..."
        hasError = false

        do {
            // Create audio session (handles file loading, player creation, hardware config)
            let session = try await sessionManager.createSession(from: url)

            guard !Task.isCancelled else {
                isLoading = false
                return
            }

            // Update all state from session
            player = session.player
            player?.volume = Float(volume)
            fileSampleRate = session.sampleRate
            currentFileName = session.fileName
            duration = session.duration
            currentTime = 0

            // Update hardware sample rate display
            updateHardwareSampleRate()
            statusMessage = "Ready to play at \(Int(fileSampleRate)) Hz"
            hasError = false
            isLoading = false

        } catch is CancellationError {
            statusMessage = "Loading cancelled"
            isLoading = false
        } catch {
            statusMessage = "Error loading file: \(error.localizedDescription)"
            hasError = true
            isLoading = false
            currentFileName = nil
            fileSampleRate = 0
            player = nil
        }
    }

    func togglePlayPause() {
        if isPlaying {
            pause()
        } else {
            play()
        }
    }

    private func play() {
        guard let player = player else {
            statusMessage = "No audio file loaded"
            hasError = true
            return
        }

        player.play()
        isPlaying = true

        // Start tracking playback progress
        progressTracker.startTracking(
            player: player,
            duration: duration,
            updateInterval: Constants.progressUpdateInterval,
            onProgressUpdate: { [weak self] time in
                self?.currentTime = time
            },
            onPlaybackFinished: { [weak self] in
                guard let self else { return }
                self.isPlaying = false
                self.currentTime = self.duration
                self.statusMessage = "Playback finished"
            },
            onPeriodicUpdate: { [weak self] in
                self?.updateHardwareSampleRate()
            }
        )

        // Update hardware sample rate to ensure display is current
        updateHardwareSampleRate()
        statusMessage = "Playing at \(Int(fileSampleRate)) Hz"
        hasError = false
    }

    private func pause() {
        player?.pause()
        isPlaying = false
        progressTracker.stopTracking()
        statusMessage = "Paused"
    }

    func stop() {
        player?.stop()
        player?.currentTime = 0
        isPlaying = false
        currentTime = 0
        progressTracker.stopTracking()
        statusMessage = "Stopped"
    }

    func seek(to time: Double) {
        guard let player = player else { return }

        let seekTime = max(0, min(time, duration))
        player.currentTime = seekTime
        currentTime = seekTime
    }

    func skipForward() {
        let newTime = min(currentTime + Constants.skipInterval, duration)
        seek(to: newTime)
    }

    func skipBackward() {
        let newTime = max(currentTime - Constants.skipInterval, 0)
        seek(to: newTime)
    }

    // MARK: - Private Methods

    private func updateHardwareSampleRate() {
        hardwareSampleRate = sampleRateManager.getCurrentSampleRate() ?? 0
    }
}
