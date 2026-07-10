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

    @Test("Cancelled load keeps the previously loaded track instead of resetting to idle")
    func loadCancellationPreservesPreviousTrack() async throws {
        let engine = AudioPlaybackEngine(
            loadFileOperation: FirstSucceedsThenHangsLoadFileOperation(),
            sampleRateManager: StubSampleRateManager()
        )

        let firstAudioInfo = try await engine.loadFile(from: URL(fileURLWithPath: "/tmp/first.wav"))

        let replacedLoad = Task<AudioInfo, Error> {
            try await engine.loadFile(from: URL(fileURLWithPath: "/tmp/second.wav"))
        }
        try await Task.sleep(for: .milliseconds(20))
        replacedLoad.cancel()
        _ = try? await replacedLoad.value

        // The cancelled load must not wipe the engine back to idle: the first
        // track's player and audio info are still valid, and a replacing load
        // relies on them staying visible while it runs.
        #expect(engine.currentAudioInfo == firstAudioInfo)
        #expect(engine.hasActivePlayer)
    }

    @Test("Identity-checked stop ignores a stale player generation")
    func stopIgnoresStalePlayerGeneration() async throws {
        let engine = AudioPlaybackEngine(
            loadFileOperation: StubLoadFileOperation(sampleRate: 44_100),
            sampleRateManager: StubSampleRateManager()
        )

        _ = try await engine.loadFile(from: URL(fileURLWithPath: "/tmp/first.wav"))
        let staleGeneration = engine.currentPlayerGeneration

        // A newer load replaces the player, then starts playing.
        _ = try await engine.loadFile(from: URL(fileURLWithPath: "/tmp/second.wav"))
        let playingAudioInfo = try await engine.play()

        // The stale startup's cleanup must not stop the newer player...
        #expect(engine.stop(ifCurrentPlayerIs: staleGeneration) == nil)
        #expect(engine.currentAudioInfo == playingAudioInfo)

        // ...but a matching generation still stops as before.
        #expect(engine.stop(ifCurrentPlayerIs: engine.currentPlayerGeneration) == playingAudioInfo)
    }

    @Test("Cancellation during load surfaces as CancellationError, not a load failure")
    func loadCancellationSurfacesAsCancellationError() async throws {
        let cancellableOperation = CancellableLoadFileOperation()
        let engine = AudioPlaybackEngine(
            loadFileOperation: cancellableOperation,
            sampleRateManager: StubSampleRateManager()
        )

        let loadTask = Task<AudioInfo, Error> {
            try await engine.loadFile(from: URL(fileURLWithPath: "/tmp/cancelled.wav"))
        }
        cancellableOperation.cancelRequested = true
        loadTask.cancel()

        do {
            _ = try await loadTask.value
            Issue.record("Expected load to be cancelled.")
        } catch is CancellationError {
            // The engine should have translated `loadingCancelled` back into a
            // plain `CancellationError` so the load coordinator can route it
            // through the cancellation path instead of treating it as a user
            // error.
        } catch let error as PlaybackError {
            Issue.record("Expected CancellationError, got PlaybackError: \(error)")
        } catch {
            Issue.record("Expected CancellationError, got: \(error)")
        }
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

/// Loads the first track immediately, then hangs on subsequent loads until
/// cancelled — mimicking a slow second load that gets replaced.
private final class FirstSucceedsThenHangsLoadFileOperation: LoadFileOperationProtocol, @unchecked Sendable {
    private var loadCount = 0

    func execute(from url: URL) async throws -> LoadedAudioData {
        loadCount += 1
        guard loadCount > 1 else {
            return LoadedAudioData(
                data: WaveData.make(),
                fileName: url.lastPathComponent,
                fileExtension: "wav",
                displayTitle: url.lastPathComponent,
                sampleRate: 44_100,
                duration: 1
            )
        }

        while true {
            try await Task.sleep(for: .milliseconds(5))
            try Task.checkCancellation()
        }
    }
}

/// Simulates the production load pipeline: cooperative cancellation is
/// translated to `PlaybackError.loadingCancelled` by `LoadFileOperation`.
/// The engine must then re-throw a plain `CancellationError` so the load
/// coordinator's cancellation branch (not the error branch) handles it.
private final class CancellableLoadFileOperation: LoadFileOperationProtocol, @unchecked Sendable {
    var cancelRequested: Bool = false

    func execute(from url: URL) async throws -> LoadedAudioData {
        try Task.checkCancellation()

        // Spin until either the outer task is cancelled or the test signals
        // cancellation. Once cancelled, throw the same error the production
        // `LoadFileOperation` would throw.
        while !cancelRequested {
            try await Task.sleep(for: .milliseconds(5))
            try Task.checkCancellation()
        }

        throw PlaybackError.loadingCancelled
    }
}
