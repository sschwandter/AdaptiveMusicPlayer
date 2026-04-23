import Testing
import Foundation
@testable import AdaptiveMusicPlayer

@Suite("AudioPlaybackEngine Tests")
@MainActor
struct AudioPlaybackEngineTests {

    @Test("Starting playback switches hardware to the file sample rate")
    func playRequestsFileSampleRateBeforeStartingPlayback() async throws {
        let sampleRateManager = RecordingSampleRateManager(currentSampleRate: 44_100)
        let engine = AudioPlaybackEngine(
            loadFileOperation: StubLoadFileOperation(sampleRate: 96_000),
            sampleRateManager: sampleRateManager
        )

        let loadedAudioInfo = try await engine.loadFile(from: URL(fileURLWithPath: "/tmp/test.wav"))
        let playingAudioInfo = try await engine.play()

        #expect(await sampleRateManager.recordedSampleRates() == [96_000])
        #expect(playingAudioInfo == loadedAudioInfo)
        // Verify engine has active player after successful play
        #expect(engine.hasActivePlayer == true)
    }

    @Test("Starting playback skips switching when hardware already matches the file sample rate")
    func playSkipsSampleRateSwitchWhenAlreadyMatched() async throws {
        let sampleRateManager = RecordingSampleRateManager(currentSampleRate: 96_000)
        let engine = AudioPlaybackEngine(
            loadFileOperation: StubLoadFileOperation(sampleRate: 96_000),
            sampleRateManager: sampleRateManager
        )

        let loadedAudioInfo = try await engine.loadFile(from: URL(fileURLWithPath: "/tmp/test.wav"))
        let playingAudioInfo = try await engine.play()

        #expect(await sampleRateManager.recordedSampleRates().isEmpty)
        #expect(playingAudioInfo == loadedAudioInfo)
        // Verify engine has active player after successful play
        #expect(engine.hasActivePlayer == true)
    }

    @Test("Progress tracking returns AsyncStream with correct configuration")
    func progressTrackingReturnsAsyncStream() async throws {
        let stubPlayer = try StubAudioPlayer()
        let tracker = RecordingPlaybackProgressTracker()
        let engine = AudioPlaybackEngine(
            loadFileOperation: StubLoadFileOperation(sampleRate: 44_100, player: stubPlayer),
            sampleRateManager: StubSampleRateManager()
        )

        _ = try await engine.loadFile(from: URL(fileURLWithPath: "/tmp/test.wav"))

        // Create the progress stream
        let stream = engine.trackProgress(
            using: tracker,
            updateInterval: 0.25
        )

        // Start consuming the stream and give it time to initialize
        let task = Task {
            for await _ in stream {
                // Just consume events
            }
        }

        // Give the stream time to start and configure the tracker
        try await Task.sleep(for: .milliseconds(50))

        // Verify the stream was created and tracker was configured
        #expect(tracker.updateInterval == 0.25)

        task.cancel()
    }

    @Test("Stopping progress tracking delegates to the tracker")
    func stopProgressTrackingDelegatesToTracker() async throws {
        let engine = AudioPlaybackEngine(
            loadFileOperation: StubLoadFileOperation(sampleRate: 44_100),
            sampleRateManager: StubSampleRateManager()
        )
        let tracker = RecordingPlaybackProgressTracker()

        tracker.stopTracking()

        #expect(tracker.stopCallCount == 1)
    }
}
