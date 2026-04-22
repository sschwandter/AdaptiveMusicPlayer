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
            loadFileUseCase: StubLoadFileUseCase(sampleRate: 96_000),
            sampleRateManager: sampleRateManager
        )

        let loadedAudioInfo = try await engine.loadFile(from: URL(fileURLWithPath: "/tmp/test.wav"))
        let playingAudioInfo = try await engine.play()

        #expect(await sampleRateManager.recordedSampleRates() == [96_000])
        #expect(playingAudioInfo == loadedAudioInfo)
        #expect(engine.state.isPlaying == true)
    }

    @Test("Starting playback skips switching when hardware already matches the file sample rate")
    func playSkipsSampleRateSwitchWhenAlreadyMatched() async throws {
        let sampleRateManager = RecordingSampleRateManager(currentSampleRate: 96_000)
        let engine = AudioPlaybackEngine(
            loadFileUseCase: StubLoadFileUseCase(sampleRate: 96_000),
            sampleRateManager: sampleRateManager
        )

        let loadedAudioInfo = try await engine.loadFile(from: URL(fileURLWithPath: "/tmp/test.wav"))
        let playingAudioInfo = try await engine.play()

        #expect(await sampleRateManager.recordedSampleRates().isEmpty)
        #expect(playingAudioInfo == loadedAudioInfo)
        #expect(engine.state.isPlaying == true)
    }

    @Test("Progress tracking stays behind the engine boundary")
    func progressTrackingUsesLoadedPlayerWithoutExposingIt() async throws {
        let stubPlayer = try StubAudioPlayer()
        let tracker = RecordingPlaybackProgressTracker()
        let engine = AudioPlaybackEngine(
            loadFileUseCase: StubLoadFileUseCase(sampleRate: 44_100, player: stubPlayer),
            sampleRateManager: StubSampleRateManager()
        )

        _ = try await engine.loadFile(from: URL(fileURLWithPath: "/tmp/test.wav"))

        engine.startProgressTracking(
            using: tracker,
            updateInterval: 0.25,
            onProgressUpdate: { _ in },
            onPlaybackFinished: {},
            onPeriodicUpdate: {}
        )

        #expect(tracker.trackedPlayer === stubPlayer)
        #expect(tracker.updateInterval == 0.25)
    }

    @Test("Stopping progress tracking delegates to the tracker")
    func stopProgressTrackingDelegatesToTracker() async throws {
        let engine = AudioPlaybackEngine(
            loadFileUseCase: StubLoadFileUseCase(sampleRate: 44_100),
            sampleRateManager: StubSampleRateManager()
        )
        let tracker = RecordingPlaybackProgressTracker()

        engine.stopProgressTracking(using: tracker)

        #expect(tracker.stopCallCount == 1)
    }
}
