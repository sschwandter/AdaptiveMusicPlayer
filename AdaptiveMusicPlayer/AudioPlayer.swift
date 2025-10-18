import Foundation
import AVFoundation
import CoreAudio
import Observation
import Combine

@MainActor
@Observable
final class AudioPlayer: @unchecked Sendable { // Safe: all access serialized on MainActor

    // MARK: - Constants

    private enum Constants {
        static let hardwareSwitchDelay: UInt64 = 500_000_000  // nanoseconds (0.5 seconds)
        static let skipInterval: Double = 10  // seconds
        static let timerInterval: TimeInterval = 0.1  // seconds
        static let timeUpdateThreshold: Double = 0.05  // seconds
        static let sampleRateUpdateTicks = 20  // timer ticks (2 seconds at 0.1s interval)
    }

    // MARK: - Public Properties

    var isPlaying = false
    var currentTime: Double = 0
    var duration: Double = 0
    var volume: Double = 1 {
        didSet {
            audioEngine.mainMixerNode.outputVolume = Float(volume)
        }
    }
    var currentFileName: String?
    var fileSampleRate: Double = 0
    var hardwareSampleRate: Double = 0
    var statusMessage: String = ""
    var hasError: Bool = false
    var isLoading: Bool = false
    
    private let audioEngine = AVAudioEngine()
    private let playerNode = AVAudioPlayerNode()
    private var audioFile: AVAudioFile?
    private var playbackUpdateTask: Task<Void, Never>?
    private var audioLengthSamples: AVAudioFramePosition = 0
    private var sampleRate: Double = 0
    private var loadingTask: Task<Void, Never>?
    private var segmentStartFrame: AVAudioFramePosition = 0  // Track offset for timer calculations
    private var playbackSessionID: Int = 0  // Increment on each seek/play to track which playback session is current
    private var isPaused: Bool = false  // Track if we're paused (vs stopped) to support pause/resume
    
    init() {
        setupAudioEngine()
        updateHardwareSampleRate()
    }

    // Note: No explicit deinit needed - Task cancellation happens automatically
    // when the AudioPlayer is deallocated. Tasks are structured concurrency primitives
    // that handle their own cleanup.
    
    private func setupAudioEngine() {
        audioEngine.attach(playerNode)
        audioEngine.connect(playerNode, to: audioEngine.mainMixerNode, format: nil)
        audioEngine.mainMixerNode.outputVolume = Float(volume)
        // Don't start engine yet - will start when playing
    }

    private func ensureEngineStarted() {
        guard !audioEngine.isRunning else { return }

        do {
            try audioEngine.start()
        } catch {
            statusMessage = "Error starting audio engine: \(error.localizedDescription)"
            hasError = true
        }
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
        audioFile = nil
        isLoading = true
        statusMessage = "Loading file..."
        hasError = false

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
            // Load audio file
            let file = try AVAudioFile(forReading: url)

            guard !Task.isCancelled else {
                isLoading = false
                return
            }

            audioFile = file

            let format = file.processingFormat
            sampleRate = format.sampleRate
            audioLengthSamples = file.length

            fileSampleRate = sampleRate
            currentFileName = url.lastPathComponent
            duration = Double(audioLengthSamples) / sampleRate
            currentTime = 0

            // Set hardware sample rate
            do {
                try setSystemSampleRate(sampleRate)
                // Wait longer for hardware to actually switch - some devices need more time
                try await Task.sleep(nanoseconds: Constants.hardwareSwitchDelay)

                guard !Task.isCancelled else {
                    isLoading = false
                    return
                }

                updateHardwareSampleRate()
                statusMessage = "Ready to play at \(Int(sampleRate)) Hz"
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
            audioFile = nil
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
        guard let file = audioFile else {
            statusMessage = "No audio file loaded"
            hasError = true
            return
        }

        // Ensure audio engine is started
        ensureEngineStarted()
        guard !hasError else { return }

        // Only schedule audio if we're not resuming from pause
        // When paused, the audio is already scheduled and playerNode.play() will resume
        if !isPaused {
            scheduleFileWithCompletion(file)
            segmentStartFrame = 0  // Playing from beginning
        }

        isPaused = false  // Clear paused state when playing
        playerNode.play()
        isPlaying = true
        startTimer()

        // Update hardware sample rate to ensure display is current
        updateHardwareSampleRate()
        statusMessage = "Playing at \(Int(fileSampleRate)) Hz"
        hasError = false
    }
    
    private func pause() {
        playerNode.pause()
        isPlaying = false
        isPaused = true  // Mark as paused to enable resume
        stopTimer()
        statusMessage = "Paused"
    }
    
    func stop() {
        playerNode.stop()
        isPlaying = false
        isPaused = false  // Clear paused state when stopping
        currentTime = 0
        stopTimer()
        statusMessage = "Stopped"
    }
    
    private func performSeek(to time: Double, wasPlaying: Bool) {
        guard let file = audioFile else { return }

        playerNode.stop()
        stopTimer()
        isPaused = false  // Clear paused state since we're rescheduling

        let seekTime = max(0, min(time, duration))
        let startFrame = AVAudioFramePosition(seekTime * sampleRate)
        let frameCount = AVAudioFrameCount(audioLengthSamples - startFrame)

        if frameCount > 0 {
            // Schedule segment with session tracking
            scheduleSegmentWithCompletion(file, startingFrame: startFrame, frameCount: frameCount)

            segmentStartFrame = startFrame  // Track offset for timer
            currentTime = seekTime

            if wasPlaying {
                ensureEngineStarted()
                guard !hasError else { return }
                playerNode.play()
                isPlaying = true
                startTimer()
            } else {
                // If we weren't playing, restore paused state so next play will resume
                isPaused = true
            }
        }
    }

    func seek(to time: Double) {
        performSeek(to: time, wasPlaying: isPlaying)
    }
    
    func skipForward() {
        let newTime = min(currentTime + Constants.skipInterval, duration)
        performSeek(to: newTime, wasPlaying: isPlaying)
    }

    func skipBackward() {
        let newTime = max(currentTime - Constants.skipInterval, 0)
        performSeek(to: newTime, wasPlaying: isPlaying)
    }

    private func handlePlaybackFinished(sessionID: Int) {
        // Only handle completion if this matches the current playback session
        // This prevents stale completion handlers from old seeks/plays from interfering
        guard sessionID == playbackSessionID else { return }

        isPlaying = false
        currentTime = duration
        stopTimer()
        statusMessage = "Playback finished"
    }

    // MARK: - Private Methods

    /// Helper to schedule full file playback with session-tracked completion handler
    private func scheduleFileWithCompletion(_ file: AVAudioFile) {
        playbackSessionID += 1
        let currentSessionID = playbackSessionID

        playerNode.scheduleFile(file, at: nil) { [weak self] in
            guard let self else { return }
            Task { @MainActor in
                self.handlePlaybackFinished(sessionID: currentSessionID)
            }
        }
    }

    /// Helper to schedule audio segment with session-tracked completion handler
    private func scheduleSegmentWithCompletion(_ file: AVAudioFile, startingFrame: AVAudioFramePosition, frameCount: AVAudioFrameCount) {
        playbackSessionID += 1
        let currentSessionID = playbackSessionID

        playerNode.scheduleSegment(file, startingFrame: startingFrame, frameCount: frameCount, at: nil) { [weak self] in
            guard let self else { return }
            Task { @MainActor in
                self.handlePlaybackFinished(sessionID: currentSessionID)
            }
        }
    }
    
    private var timerTickCount = 0

    private func startTimer() {
        stopTimer() // Ensure we don't have multiple tasks running
        timerTickCount = 0

        playbackUpdateTask = Task { @MainActor [weak self] in
            guard let self else { return }

            // Use Timer.publish as an AsyncSequence for modern Swift concurrency
            for await _ in Timer.publish(every: Constants.timerInterval, on: .main, in: .common).autoconnect().values {
                guard !Task.isCancelled else { break }

                // Update playback time
                if let nodeTime = self.playerNode.lastRenderTime,
                   let playerTime = self.playerNode.playerTime(forNodeTime: nodeTime) {
                    // Add segment offset since playerTime is relative to segment start
                    let currentFrame = Double(self.segmentStartFrame + playerTime.sampleTime)
                    let newTime = currentFrame / self.sampleRate
                    if abs(newTime - self.currentTime) > Constants.timeUpdateThreshold {
                        self.currentTime = min(newTime, self.duration)
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

    private func stopTimer() {
        playbackUpdateTask?.cancel()
        playbackUpdateTask = nil
        timerTickCount = 0
    }
    
    private func getDefaultAudioDevice() throws -> AudioDeviceID {
        var deviceID = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)

        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &size,
            &deviceID
        )

        guard status == noErr else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status), userInfo: [
                NSLocalizedDescriptionKey: "Failed to get audio device"
            ])
        }

        return deviceID
    }

    private func setSystemSampleRate(_ sampleRate: Double) throws {
        let deviceID = try getDefaultAudioDevice()
        
        // Check if sample rate is supported
        let supportedRates = getSupportedSampleRates(deviceID: deviceID)
        guard supportedRates.contains(sampleRate) else {
            throw NSError(domain: "AudioPlayer", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "Sample rate \(Int(sampleRate)) Hz not supported by device"
            ])
        }

        // Set sample rate
        var nominalSampleRate = sampleRate
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyNominalSampleRate,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        let status = AudioObjectSetPropertyData(
            deviceID,
            &address,
            0,
            nil,
            UInt32(MemoryLayout<Double>.size),
            &nominalSampleRate
        )

        guard status == noErr else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status), userInfo: [
                NSLocalizedDescriptionKey: "Failed to set sample rate"
            ])
        }
    }
    
    private func getSupportedSampleRates(deviceID: AudioDeviceID) -> [Double] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyAvailableNominalSampleRates,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(deviceID, &address, 0, nil, &size) == noErr else {
            return []
        }
        
        let count = Int(size) / MemoryLayout<AudioValueRange>.size
        var ranges = [AudioValueRange](repeating: AudioValueRange(), count: count)
        
        guard AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &ranges) == noErr else {
            return []
        }
        
        return ranges.map { $0.mMinimum }
    }
    
    private func updateHardwareSampleRate() {
        guard let deviceID = try? getDefaultAudioDevice() else {
            return
        }

        var sampleRate: Double = 0
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyNominalSampleRate,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size = UInt32(MemoryLayout<Double>.size)
        
        guard AudioObjectGetPropertyData(
            deviceID,
            &address,
            0,
            nil,
            &size,
            &sampleRate
        ) == noErr else {
            return
        }
        
        hardwareSampleRate = sampleRate
    }
}
