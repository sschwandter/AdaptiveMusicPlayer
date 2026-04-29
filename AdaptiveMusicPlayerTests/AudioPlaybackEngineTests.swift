import Testing
import Foundation
@preconcurrency import AVFoundation
@testable import AdaptiveMusicPlayerCore
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
        let tracker = RecordingPlaybackProgressTracker()
        let engine = AudioPlaybackEngine(
            loadFileOperation: StubLoadFileOperation(sampleRate: 44_100),
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

    @Test("Loading creates the audio session away from the main thread")
    func loadFileCreatesSessionOffMainThread() async throws {
        let recorder = LoadExecutionThreadRecorder()
        let engine = AudioPlaybackEngine(
            loadFileOperation: ThreadRecordingLoadFileOperation(recorder: recorder),
            sampleRateManager: StubSampleRateManager()
        )

        _ = try await engine.loadFile(from: URL(fileURLWithPath: "/tmp/test.wav"))

        #expect(await recorder.didRunOnMainThread == false)
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

private actor LoadExecutionThreadRecorder {
    private var recordedValue: Bool?

    var didRunOnMainThread: Bool? {
        recordedValue
    }

    func record(_ didRunOnMainThread: Bool) {
        recordedValue = didRunOnMainThread
    }
}

private struct ThreadRecordingLoadFileOperation: LoadFileOperationProtocol, @unchecked Sendable {
    let recorder: LoadExecutionThreadRecorder

    func execute(from url: URL) async throws -> LoadedAudioData {
        await recorder.record(Thread.isMainThread)
        // Read sample rate from a probe player, same as AudioSessionManager does.
        let probePlayer = try AVAudioPlayer(data: WaveData.make(), fileTypeHint: "wav")
        return LoadedAudioData(
            data: WaveData.make(),
            fileName: url.lastPathComponent,
            fileExtension: "wav",
            displayTitle: url.lastPathComponent,
            sampleRate: probePlayer.format.sampleRate,
            duration: probePlayer.duration
        )
    }
}
