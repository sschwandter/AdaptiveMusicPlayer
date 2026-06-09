import Testing
import Foundation
@testable import AdaptiveMusicPlayerCore
@testable import AdaptiveMusicPlayer

@Suite("AudioPlayerSessionController Lifecycle Tests")
@MainActor
struct AudioPlayerSessionControllerLifecycleTests {
    @Test("controller deallocates while playback is active")
    func controllerDeallocatesDuringActivePlayback() async throws {
        weak var weakController: AudioPlayerSessionController?

        // Scope the controller in a helper so releasing the last strong
        // reference happens mid-playback, like a window closing during a track.
        func runPlaybackAndReleaseController() async {
            let stateStore = AudioPlayerStateStore()
            let engine = AudioPlaybackEngine(
                loadFileOperation: StubLoadFileOperation(sampleRate: 44_100),
                playbackControlOperation: SucceedingPlaybackControlOperation(),
                sampleRateManager: StubSampleRateManager()
            )
            let controller = AudioPlayerSessionController(
                stateStore: stateStore,
                engine: engine,
                progressTracker: RecordingPlaybackProgressTracker(),
                loadCoordinator: AudioPlayerLoadCoordinator(),
                refreshHardwareInfo: {},
                currentVolume: { 1 }
            )
            weakController = controller

            controller.send(.loadFile(
                url: URL(fileURLWithPath: "/tmp/lifecycle-test.wav"),
                importerDismissalDelay: .zero
            ))
            await controller.waitForCurrentActivity()
            controller.send(.togglePlayPause)
            await controller.waitForCurrentActivity()

            #expect(stateStore.isPlaying)
        }

        await runPlaybackAndReleaseController()

        #expect(weakController == nil)
    }
}
