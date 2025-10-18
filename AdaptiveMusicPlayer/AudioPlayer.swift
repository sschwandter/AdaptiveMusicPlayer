import Foundation
import AVFoundation
import CoreAudio
import Combine

@MainActor
class AudioPlayer: ObservableObject {
    @Published var isPlaying = false
    @Published var currentTime: Double = 0
    @Published var duration: Double = 0
    @Published var volume: Double = 0.5 {
        didSet {
            audioEngine.mainMixerNode.outputVolume = Float(volume)
        }
    }
    @Published var currentFileName: String?
    @Published var fileSampleRate: Double = 0
    @Published var hardwareSampleRate: Double = 0
    @Published var statusMessage: String = ""
    @Published var hasError: Bool = false
    @Published var isLoading: Bool = false
    
    private let audioEngine = AVAudioEngine()
    private let playerNode = AVAudioPlayerNode()
    private var audioFile: AVAudioFile?
    private var timer: Timer?
    private var currentFileURL: URL?
    private var audioLengthSamples: AVAudioFramePosition = 0
    private var sampleRate: Double = 0
    private var wasPlayingBeforeInterruption: Bool = false
    
    init() {
        setupAudioEngine()
        updateHardwareSampleRate()
    }

    deinit {
        Task { @MainActor in
            stopTimer()
        }
    }
    
    private func setupAudioEngine() {
        audioEngine.attach(playerNode)
        audioEngine.connect(playerNode, to: audioEngine.mainMixerNode, format: nil)
        audioEngine.mainMixerNode.outputVolume = Float(volume)
        
        do {
            try audioEngine.start()
        } catch {
            statusMessage = "Error starting audio engine: \(error.localizedDescription)"
            hasError = true
        }
    }
    
    func loadFile(url: URL) {
        Task {
            await loadFileAsync(url: url)
        }
    }
    
    private func loadFileAsync(url: URL) async {
        stop()
        
        await MainActor.run {
            isLoading = true
            statusMessage = "Loading file..."
            hasError = false
        }
        
        guard url.startAccessingSecurityScopedResource() else {
            await MainActor.run {
                statusMessage = "Error: Cannot access file"
                hasError = true
                isLoading = false
            }
            return
        }
        
        defer {
            url.stopAccessingSecurityScopedResource()
        }
        
        currentFileURL = url
        
        do {
            // Load audio file
            let file = try AVAudioFile(forReading: url)
            audioFile = file
            
            let format = file.processingFormat
            sampleRate = format.sampleRate
            audioLengthSamples = file.length
            
            await MainActor.run {
                fileSampleRate = sampleRate
                currentFileName = url.lastPathComponent
                duration = Double(audioLengthSamples) / sampleRate
                currentTime = 0
            }
            
            // Set hardware sample rate
            do {
                try setSystemSampleRate(sampleRate)
                try await Task.sleep(nanoseconds: 200_000_000) // 0.2 second delay
                updateHardwareSampleRate()
                await MainActor.run {
                    statusMessage = "Ready to play at \(Int(sampleRate)) Hz"
                    hasError = false
                    isLoading = false
                }
            } catch {
                await MainActor.run {
                    statusMessage = "Warning: Could not set sample rate - \(error.localizedDescription)"
                    hasError = false // This is a warning, not a critical error
                    isLoading = false
                }
            }
            
        } catch {
            await MainActor.run {
                statusMessage = "Error loading file: \(error.localizedDescription)"
                hasError = true
                isLoading = false
                currentFileName = nil
                fileSampleRate = 0
                audioFile = nil
            }
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
        
        if !audioEngine.isRunning {
            do {
                try audioEngine.start()
            } catch {
                statusMessage = "Error starting audio engine: \(error.localizedDescription)"
                hasError = true
                return
            }
        }
        
        // Schedule file for playback
        playerNode.scheduleFile(file, at: nil) { [weak self] in
            Task { @MainActor in
                self?.handlePlaybackFinished()
            }
        }
        
        playerNode.play()
        isPlaying = true
        startTimer()
        statusMessage = "Playing at \(Int(fileSampleRate)) Hz"
        hasError = false
    }
    
    private func pause() {
        playerNode.pause()
        isPlaying = false
        stopTimer()
        statusMessage = "Paused"
    }
    
    func stop() {
        playerNode.stop()
        isPlaying = false
        currentTime = 0
        stopTimer()
        statusMessage = "Stopped"
        
        // Reschedule file for next play
        if let file = audioFile {
            playerNode.scheduleFile(file, at: nil, completionHandler: nil)
        }
    }
    
    func seek(to time: Double) {
        guard let file = audioFile else { return }
        let wasPlaying = isPlaying
        
        playerNode.stop()
        
        let seekTime = max(0, min(time, duration))
        let startFrame = AVAudioFramePosition(seekTime * sampleRate)
        let frameCount = AVAudioFrameCount(audioLengthSamples - startFrame)
        
        if frameCount > 0 {
            playerNode.scheduleSegment(file, startingFrame: startFrame, frameCount: frameCount, at: nil) { [weak self] in
                Task { @MainActor in
                    self?.handlePlaybackFinished()
                }
            }
            
            currentTime = seekTime
            
            if wasPlaying {
                playerNode.play()
            }
        }
    }
    
    func skipForward() {
        guard let file = audioFile else { return }
        let wasPlaying = isPlaying
        
        playerNode.stop()
        
        let newTime = min(currentTime + 10, duration)
        let startFrame = AVAudioFramePosition(newTime * sampleRate)
        let frameCount = AVAudioFrameCount(audioLengthSamples - startFrame)
        
        if frameCount > 0 {
            playerNode.scheduleSegment(file, startingFrame: startFrame, frameCount: frameCount, at: nil) { [weak self] in
                Task { @MainActor in
                    self?.handlePlaybackFinished()
                }
            }
            
            if wasPlaying {
                playerNode.play()
            }
            currentTime = newTime
        }
    }
    
    func skipBackward() {
        guard let file = audioFile else { return }
        let wasPlaying = isPlaying
        
        playerNode.stop()
        
        let newTime = max(currentTime - 10, 0)
        let startFrame = AVAudioFramePosition(newTime * sampleRate)
        let frameCount = AVAudioFrameCount(audioLengthSamples - startFrame)
        
        playerNode.scheduleSegment(file, startingFrame: startFrame, frameCount: frameCount, at: nil) { [weak self] in
            Task { @MainActor in
                self?.handlePlaybackFinished()
            }
        }
        
        if wasPlaying {
            playerNode.play()
        }
        currentTime = newTime
    }
    
    private func handlePlaybackFinished() {
        isPlaying = false
        currentTime = duration
        stopTimer()
        statusMessage = "Playback finished"
    }
    
    // MARK: - Private Methods
    
    private func startTimer() {
        stopTimer() // Ensure we don't have multiple timers
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            Task { @MainActor in
                if let nodeTime = self.playerNode.lastRenderTime,
                   let playerTime = self.playerNode.playerTime(forNodeTime: nodeTime) {
                    let currentFrame = Double(playerTime.sampleTime)
                    let newTime = currentFrame / self.sampleRate
                    if abs(newTime - self.currentTime) > 0.05 { // Only update if significant change
                        self.currentTime = min(newTime, self.duration)
                    }
                }
            }
        }
    }
    
    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }
    
    private func setSystemSampleRate(_ sampleRate: Double) throws {
        var deviceID = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        var status = AudioObjectGetPropertyData(
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
        
        // Check if sample rate is supported
        let supportedRates = getSupportedSampleRates(deviceID: deviceID)
        guard supportedRates.contains(sampleRate) else {
            throw NSError(domain: "AudioPlayer", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "Sample rate \(Int(sampleRate)) Hz not supported by device"
            ])
        }
        
        // Set sample rate
        var nominalSampleRate = sampleRate
        address.mSelector = kAudioDevicePropertyNominalSampleRate
        address.mScope = kAudioObjectPropertyScopeGlobal
        
        status = AudioObjectSetPropertyData(
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
        var deviceID = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &size,
            &deviceID
        ) == noErr else {
            return
        }
        
        var sampleRate: Double = 0
        address.mSelector = kAudioDevicePropertyNominalSampleRate
        size = UInt32(MemoryLayout<Double>.size)
        
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
