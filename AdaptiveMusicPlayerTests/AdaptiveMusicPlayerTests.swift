import Testing
import AVFoundation
import CoreAudio
@testable import AdaptiveMusicPlayer

@Suite("AudioPlayer Tests")
@MainActor
struct AudioPlayerTests {
    
    @Test("AudioPlayer initializes with default values")
    func initialState() async throws {
        let player = AudioPlayer()
        
        #expect(player.isPlaying == false)
        #expect(player.currentTime == 0)
        #expect(player.duration == 0)
        #expect(player.volume == 1.0)
        #expect(player.currentFileName == nil)
        #expect(player.fileSampleRate == 0)
        // Hardware sample rate is fetched asynchronously off the main thread
        try await Task.sleep(for: .milliseconds(100))
        #expect(player.hardwareSampleRate > 0) // Should get system default
        #expect(player.statusMessage == "")
        #expect(player.hasError == false)
        #expect(player.isLoading == false)
    }
    
    @Test("Volume changes are applied correctly")
    func volumeControl() async throws {
        let player = AudioPlayer()
        
        player.volume = 0.8
        #expect(player.volume == 0.8)
        
        player.volume = 0.0
        #expect(player.volume == 0.0)
        
        player.volume = 1.0
        #expect(player.volume == 1.0)
    }
    
    @Test("Time formatting works correctly")
    func timeFormatting() async throws {
        // Test various time formats using TimeFormatter directly
        #expect(TimeFormatter.format(0) == "0:00")
        #expect(TimeFormatter.format(30) == "0:30")
        #expect(TimeFormatter.format(60) == "1:00")
        #expect(TimeFormatter.format(90) == "1:30")
        #expect(TimeFormatter.format(3661) == "61:01")
    }
    
    @Test("Toggle play/pause with no file loaded")
    func toggleWithoutFile() async throws {
        let player = AudioPlayer()
        
        // Should remain stopped when no file is loaded
        player.togglePlayPause()
        #expect(player.isPlaying == false)
    }
    
    @Test("Stop functionality")
    func stopFunctionality() async throws {
        let player = AudioPlayer()
        
        // Stopping when not playing should be safe
        player.stop()
        #expect(player.isPlaying == false)
        #expect(player.currentTime == 0)
    }
    
    @Test("Skip operations without file")
    func skipWithoutFile() async throws {
        let player = AudioPlayer()
        
        // Should be safe to call skip functions without a file
        player.skipForward()
        player.skipBackward()
        
        #expect(player.currentTime == 0)
        #expect(player.isPlaying == false)
    }
    
    @Test("Seek bounds checking")
    func seekBounds() async throws {
        let player = AudioPlayer()
        
        // Should handle seeking without a file gracefully
        player.seek(to: 10.0)
        #expect(player.currentTime == 0)
        
        player.seek(to: -5.0)
        #expect(player.currentTime == 0)
    }
    
    @Test("Error state management")
    func errorStates() async throws {
        let player = AudioPlayer()

        // Initially no error
        #expect(player.hasError == false)

        // Test loading a non-existent file
        let invalidURL = URL(fileURLWithPath: "/nonexistent/file.mp3")
        await player.loadFile(url: invalidURL)

        // Should have error state
        #expect(player.hasError == true)
        #expect(!player.statusMessage.isEmpty)
    }
}

@Suite("TimeFormatter Tests")
struct TimeFormatterTests {

    @Test("Time string formatting edge cases")
    func timeStringEdgeCases() async throws {
        // Test edge cases using TimeFormatter directly
        #expect(TimeFormatter.format(0.5) == "0:00")
        #expect(TimeFormatter.format(59.9) == "0:59")
        #expect(TimeFormatter.format(3600) == "60:00")
        #expect(TimeFormatter.format(Double.infinity) == "0:00") // Invalid input returns 0:00
        #expect(TimeFormatter.format(-10) == "0:00") // Negative should be handled gracefully
    }
}

@Suite("PlaybackControlUseCase Tests")
@MainActor
struct PlaybackControlUseCaseTests {

    @Test("Playing a finished track rewinds before restarting")
    func playFinishedTrackRewindsToStart() throws {
        let useCase = PlaybackControlUseCase()
        let player = try StubAudioPlayer()
        let audioInfo = AudioInfo(fileName: "test.wav", duration: 1, sampleRate: 44_100)

        player.currentTime = 0.75
        let newState = try useCase.play(player: player, state: .finished(audioInfo))

        #expect(newState == .playing(audioInfo))
        #expect(player.playCallCount == 1)
        #expect(player.currentTime == 0)
    }

    @Test("State does not advance when AVAudioPlayer fails to start")
    func playFailureDoesNotAdvanceState() throws {
        let useCase = PlaybackControlUseCase()
        let player = try StubAudioPlayer(playResult: false)
        let audioInfo = AudioInfo(fileName: "test.wav", duration: 1, sampleRate: 44_100)

        #expect(throws: PlaybackError.playbackStartFailed) {
            try useCase.play(player: player, state: .ready(audioInfo))
        }
        #expect(player.playCallCount == 1)
    }
}

@Suite("SampleRateManager Tests")
struct SampleRateManagerTests {

    @Test("Nominal sample-rate ranges are treated as ranges")
    func rangeSupportCheck() {
        let ranges = [
            AudioValueRange(mMinimum: 44_100, mMaximum: 192_000)
        ]

        #expect(CoreAudioSampleRateManager.sampleRate(96_000, isSupportedBy: ranges))
        #expect(!CoreAudioSampleRateManager.sampleRate(22_050, isSupportedBy: ranges))
    }

    @Test("Range-backed sample rates expand to common nominal rates")
    func rangeExpansionUsesCommonNominalRates() {
        let discrete = AudioValueRange(mMinimum: 44_100, mMaximum: 44_100)
        let ranged = AudioValueRange(mMinimum: 44_100, mMaximum: 192_000)

        #expect(
            CoreAudioSampleRateManager.expandSupportedRates(from: discrete) == [44_100]
        )
        #expect(
            CoreAudioSampleRateManager.expandSupportedRates(from: ranged)
            == [44_100, 48_000, 88_200, 96_000, 176_400, 192_000]
        )
    }
}

@Suite("PlaybackProgressTracker Tests")
@MainActor
struct PlaybackProgressTrackerTests {

    @Test("Ignoring finish callbacks from a previously tracked player")
    func ignoresStaleFinishCallbacks() async throws {
        let tracker = PlaybackProgressTracker()
        let stalePlayer = try StubAudioPlayer()
        let activePlayer = try StubAudioPlayer()
        var finishCount = 0

        tracker.startTracking(
            player: stalePlayer,
            duration: 1,
            updateInterval: 1,
            onProgressUpdate: { _ in },
            onPlaybackFinished: { finishCount += 1 },
            onPeriodicUpdate: {}
        )

        tracker.startTracking(
            player: activePlayer,
            duration: 1,
            updateInterval: 1,
            onProgressUpdate: { _ in },
            onPlaybackFinished: { finishCount += 1 },
            onPeriodicUpdate: {}
        )

        tracker.audioPlayerDidFinishPlaying(stalePlayer, successfully: true)
        try await Task.sleep(for: .milliseconds(10))

        #expect(finishCount == 0)
    }

    @Test("Ignoring unsuccessful finish callbacks")
    func ignoresUnsuccessfulFinishCallbacks() async throws {
        let tracker = PlaybackProgressTracker()
        let player = try StubAudioPlayer()
        var finishCount = 0

        tracker.startTracking(
            player: player,
            duration: 1,
            updateInterval: 1,
            onProgressUpdate: { _ in },
            onPlaybackFinished: { finishCount += 1 },
            onPeriodicUpdate: {}
        )

        tracker.audioPlayerDidFinishPlaying(player, successfully: false)
        try await Task.sleep(for: .milliseconds(10))

        #expect(finishCount == 0)
    }
}

private final class StubAudioPlayer: AVAudioPlayer {
    var playResult: Bool
    var playCallCount = 0

    init(playResult: Bool = true) throws {
        self.playResult = playResult
        try super.init(data: Self.makeWaveData(), fileTypeHint: "wav")
    }

    override func play() -> Bool {
        playCallCount += 1
        return playResult
    }

    override func stop() {
        super.stop()
        currentTime = 0
    }

    private static func makeWaveData() -> Data {
        let sampleRate: UInt32 = 44_100
        let bitsPerSample: UInt16 = 16
        let channels: UInt16 = 1
        let frameCount: UInt32 = 44
        let bytesPerSample = UInt32(bitsPerSample / 8)
        let dataSize = frameCount * UInt32(channels) * bytesPerSample
        let byteRate = sampleRate * UInt32(channels) * bytesPerSample
        let blockAlign = channels * bitsPerSample / 8

        var data = Data()
        data.append("RIFF".data(using: .ascii)!)
        data.appendLE(UInt32(36 + dataSize))
        data.append("WAVE".data(using: .ascii)!)
        data.append("fmt ".data(using: .ascii)!)
        data.appendLE(UInt32(16))
        data.appendLE(UInt16(1))
        data.appendLE(channels)
        data.appendLE(sampleRate)
        data.appendLE(byteRate)
        data.appendLE(blockAlign)
        data.appendLE(bitsPerSample)
        data.append("data".data(using: .ascii)!)
        data.appendLE(dataSize)
        data.append(Data(repeating: 0, count: Int(dataSize)))
        return data
    }
}

private extension Data {
    mutating func appendLE<T: FixedWidthInteger>(_ value: T) {
        var littleEndian = value.littleEndian
        Swift.withUnsafeBytes(of: &littleEndian) { bytes in
            append(bytes.bindMemory(to: UInt8.self))
        }
    }
}
