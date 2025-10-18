import Foundation
import AVFoundation
import Observation
import Combine

@MainActor
@Observable
final class AudioPlayer: @unchecked Sendable { // Safe: all access serialized on MainActor

    // MARK: - Constants

    private enum Constants {
        static let hardwareSwitchDelay: UInt64 = 500_000_000  // nanoseconds (0.5 seconds)
        static let skipInterval: Double = 10  // seconds
        static let progressUpdateInterval: TimeInterval = 0.1  // seconds
        static let sampleRateUpdateTicks = 20  // timer ticks (2 seconds at 0.1s interval)
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
    private var loadingTask: Task<Void, Never>?
    private var progressUpdateTask: Task<Void, Never>?
    private var timerTickCount = 0

    init(
        sampleRateManager: SampleRateManaging = CoreAudioSampleRateManager()
    ) {
        self.sampleRateManager = sampleRateManager
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

        // Access security-scoped resource
        guard url.startAccessingSecurityScopedResource() else {
            statusMessage = "Error: Cannot access file"
            hasError = true
            isLoading = false
            return
        }

        defer {
            url.stopAccessingSecurityScopedResource()
        }

        // Check cancellation before expensive operations
        guard !Task.isCancelled else {
            isLoading = false
            return
        }

        do {
            // Create AVAudioPlayer - this loads the file into memory
            player = try AVAudioPlayer(contentsOf: url)
            player?.volume = Float(volume)
            player?.prepareToPlay()

            guard !Task.isCancelled else {
                isLoading = false
                return
            }

            // Extract metadata from player
            guard let player = player else {
                throw NSError(domain: "AudioPlayer", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to create player"])
            }

            fileSampleRate = player.format.sampleRate
            currentFileName = url.lastPathComponent
            duration = player.duration
            currentTime = 0

            // Set hardware sample rate
            do {
                try sampleRateManager.setSampleRate(fileSampleRate)
                // Wait longer for hardware to actually switch - some devices need more time
                try await Task.sleep(nanoseconds: Constants.hardwareSwitchDelay)

                guard !Task.isCancelled else {
                    isLoading = false
                    return
                }

                updateHardwareSampleRate()
                statusMessage = "Ready to play at \(Int(fileSampleRate)) Hz"
                hasError = false
                isLoading = false
            } catch {
                statusMessage = "Warning: Could not set sample rate - \(error.localizedDescription)"
                hasError = false // This is a warning, not a critical error
                isLoading = false
                // Still update to show actual hardware rate even if we couldn't set it
                updateHardwareSampleRate()
            }

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
        startProgressUpdates()

        // Update hardware sample rate to ensure display is current
        updateHardwareSampleRate()
        statusMessage = "Playing at \(Int(fileSampleRate)) Hz"
        hasError = false
    }

    private func pause() {
        player?.pause()
        isPlaying = false
        stopProgressUpdates()
        statusMessage = "Paused"
    }

    func stop() {
        player?.stop()
        player?.currentTime = 0
        isPlaying = false
        currentTime = 0
        stopProgressUpdates()
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

    private func startProgressUpdates() {
        stopProgressUpdates() // Ensure we don't have multiple tasks running
        timerTickCount = 0

        progressUpdateTask = Task { @MainActor [weak self] in
            guard let self else { return }

            // Use Timer.publish as an AsyncSequence for modern Swift concurrency
            for await _ in Timer.publish(every: Constants.progressUpdateInterval, on: .main, in: .common).autoconnect().values {
                guard !Task.isCancelled else { break }

                // Update current time from player
                if let player = self.player {
                    self.currentTime = player.currentTime

                    // Check if playback finished naturally
                    if player.currentTime >= self.duration - 0.05 && self.isPlaying {
                        self.handlePlaybackFinished()
                    }
                }

                // Update hardware sample rate periodically
                self.timerTickCount += 1
                if self.timerTickCount >= Constants.sampleRateUpdateTicks {
                    self.updateHardwareSampleRate()
                    self.timerTickCount = 0
                }
            }
        }
    }

    private func stopProgressUpdates() {
        progressUpdateTask?.cancel()
        progressUpdateTask = nil
        timerTickCount = 0
    }

    private func handlePlaybackFinished() {
        isPlaying = false
        currentTime = duration
        stopProgressUpdates()
        statusMessage = "Playback finished"
    }

    private func updateHardwareSampleRate() {
        hardwareSampleRate = sampleRateManager.getCurrentSampleRate() ?? 0
    }
}
