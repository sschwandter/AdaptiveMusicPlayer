import Testing
@testable import AdaptiveMusicPlayer

@Suite("PlaybackState Tests")
struct PlaybackStateTests {

    @Test("Loading state preserves prior audio info during transitions")
    func loadingStatePreservesAudioInfo() {
        let audioInfo = AudioInfo(fileName: "track.wav", displayTitle: "Track Title", duration: 42, sampleRate: 44_100)

        #expect(PlaybackState.loading(audioInfo).isLoading == true)
        #expect(PlaybackState.loading(audioInfo).audioInfo == audioInfo)
        #expect(PlaybackState.loading(nil).audioInfo == nil)
    }
}
