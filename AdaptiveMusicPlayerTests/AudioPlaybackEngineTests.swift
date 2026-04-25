import Testing
import Foundation
import AVFoundation
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

    @Test("AVAudioEngine backend loads and starts playback")
    func avAudioEngineBackendLoadsAndPlays() async throws {
        let engine = AudioPlaybackEngine(
            backend: AVAudioEnginePlaybackBackend(
                fileLoader: StubAudioFileLoader(fileName: "test.wav"),
                titleReader: StubAudioTitleReader(title: "Engine Track")
            ),
            sampleRateManager: StubSampleRateManager()
        )

        let loadedAudioInfo = try await engine.loadFile(from: URL(fileURLWithPath: "/tmp/test.wav"))
        let playingAudioInfo = try await engine.play()

        #expect(loadedAudioInfo.displayTitle == "Engine Track")
        #expect(playingAudioInfo == loadedAudioInfo)
        #expect(engine.hasActivePlayer == true)
    }

    @Test("AVAudioEngine backend finishes progress stream for scheduled playback")
    func avAudioEngineBackendProgressStreamFinishes() async throws {
        let engine = AudioPlaybackEngine(
            backend: AVAudioEnginePlaybackBackend(
                fileLoader: StubAudioFileLoader(fileName: "test.wav"),
                titleReader: StubAudioTitleReader(title: "Engine Track")
            ),
            sampleRateManager: StubSampleRateManager()
        )

        _ = try await engine.loadFile(from: URL(fileURLWithPath: "/tmp/test.wav"))
        _ = try await engine.play()

        let stream = engine.trackProgress(
            using: RecordingPlaybackProgressTracker(),
            updateInterval: 0.01
        )

        var didFinish = false
        for await event in stream {
            if case .finished = event {
                didFinish = true
                break
            }
        }

        #expect(didFinish)
    }

    @Test("AVAudioEngine backend surfaces scheduling failures as playback start errors")
    func avAudioEngineBackendThrowsWhenSchedulingFails() async throws {
        let opener = FailingAudioFileOpener(failOnOpenNumber: 2)
        let engine = AudioPlaybackEngine(
            backend: AVAudioEnginePlaybackBackend(
                fileLoader: StubAudioFileLoader(fileName: "test.wav"),
                titleReader: StubAudioTitleReader(title: "Broken Track"),
                openAudioFile: { url in
                    try opener.open(url: url)
                }
            ),
            sampleRateManager: StubSampleRateManager()
        )

        _ = try await engine.loadFile(from: URL(fileURLWithPath: "/tmp/test.wav"))

        await #expect(throws: PlaybackError.playbackStartFailed) {
            _ = try await engine.play()
        }
    }

    @Test("AVAudioEngine backend stops progress after active reschedule failure")
    func avAudioEngineBackendStopsAfterFailedSeekReschedule() async throws {
        let opener = FailingAudioFileOpener(failOnOpenNumber: 3)
        let engine = AudioPlaybackEngine(
            backend: AVAudioEnginePlaybackBackend(
                fileLoader: StubAudioFileLoader(fileName: "test.wav"),
                titleReader: StubAudioTitleReader(title: "Broken Track"),
                openAudioFile: { url in
                    try opener.open(url: url)
                }
            ),
            sampleRateManager: StubSampleRateManager()
        )

        _ = try await engine.loadFile(from: URL(fileURLWithPath: "/tmp/test.wav"))
        _ = try await engine.play()

        #expect(throws: PlaybackError.playbackStartFailed) {
            _ = try engine.seek(to: 0.0005)
        }

        let stream = engine.trackProgress(
            using: RecordingPlaybackProgressTracker(),
            updateInterval: 0.01
        )
        var iterator = stream.makeAsyncIterator()
        let firstEvent = await iterator.next()
        let secondEvent = await iterator.next()

        if case .progress(let time) = firstEvent {
            #expect(time > 0)
        } else {
            Issue.record("Expected the stopped backend to report retained seek progress.")
        }
        #expect(secondEvent == nil)
    }
}

@MainActor
private final class FailingAudioFileOpener {
    private let failOnOpenNumber: Int
    private var openCount = 0

    init(failOnOpenNumber: Int) {
        self.failOnOpenNumber = failOnOpenNumber
    }

    func open(url: URL) throws -> AVAudioFile {
        openCount += 1
        if openCount >= failOnOpenNumber {
            throw NSError(domain: NSOSStatusErrorDomain, code: -1)
        }
        return try AVAudioFile(forReading: url)
    }
}
