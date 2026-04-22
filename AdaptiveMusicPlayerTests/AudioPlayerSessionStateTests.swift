import Foundation
import Testing
@testable import AdaptiveMusicPlayer

@Suite("AudioPlayerSessionState Tests")
@MainActor
struct AudioPlayerSessionStateTests {
    @Test("derived playback facts come from the unified session state")
    func derivedPlaybackFacts() {
        let audioInfo = AudioInfo(
            fileName: "track.wav",
            displayTitle: "Track",
            duration: 123,
            sampleRate: 44_100
        )
        let state = AudioPlayerSessionState(
            playback: .playing(audioInfo),
            activity: .loadingTrack,
            status: StatusPresentationState(kind: .info, message: "Loading"),
            playlist: .init(),
            hardware: HardwarePresentationState(
                deviceName: "Built-in Output",
                currentSampleRate: 48_000,
                supportedSampleRates: [44_100, 48_000]
            ),
            currentTime: 12,
            displayTitlesByTrackURL: [:]
        )

        #expect(state.duration == 123)
        #expect(state.currentFileName == "track.wav")
        #expect(state.currentDisplayTitle == "Track")
        #expect(state.fileSampleRate == 44_100)
        #expect(state.hardwareSampleRate == 48_000)
        #expect(state.hardwareDeviceName == "Built-in Output")
        #expect(state.supportedHardwareSampleRates == [44_100, 48_000])
        #expect(state.isPlaying)
        #expect(state.isLoading)
        #expect(!state.hasError)
        #expect(state.statusMessage == "Loading")
        #expect(state.hasLoadedAudio)
    }

    @Test("recordLoadedTrack stores display titles in the session state")
    func recordLoadedTrack() {
        let audioInfo = AudioInfo(
            fileName: "track.wav",
            displayTitle: "Resolved Title",
            duration: 123,
            sampleRate: 44_100
        )
        let url = URL(fileURLWithPath: "/tmp/track.wav")
        var state = AudioPlayerSessionState()

        state.recordLoadedTrack(audioInfo, for: url)

        #expect(state.displayTitlesByTrackURL[url] == "Resolved Title")
    }
}
