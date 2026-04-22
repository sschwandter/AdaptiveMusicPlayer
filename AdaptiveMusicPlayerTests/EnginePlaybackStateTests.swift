import Testing
@testable import AdaptiveMusicPlayer

@Suite("EnginePlaybackState Tests")
struct EnginePlaybackStateTests {

    @Test("Loading state preserves prior audio info during transitions")
    func loadingStatePreservesAudioInfo() {
        let audioInfo = AudioInfo(fileName: "track.wav", displayTitle: "Track Title", duration: 42, sampleRate: 44_100)

        #expect(EnginePlaybackState.loading(audioInfo).isLoading == true)
        #expect(EnginePlaybackState.loading(audioInfo).audioInfo == audioInfo)
        #expect(EnginePlaybackState.loading(nil).audioInfo == nil)
    }
}
