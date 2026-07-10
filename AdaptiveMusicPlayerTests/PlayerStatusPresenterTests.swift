import Testing
@testable import AdaptiveMusicPlayerCore
@testable import AdaptiveMusicPlayer

@Suite("PlayerStatusPresenter Tests")
@MainActor
struct PlayerStatusPresenterTests {
    private let presenter = PlayerStatusPresenter()

 @Test("ready status includes route details and clears loading")
    func readyStatus() {
        let output = presenter.presentReady(
            PlayerStatusContext(
                hasPlaylist: false,
                playlistTrackPosition: nil,
                sampleRate: 44_100,
                hardwareDeviceName: "Built-in Output",
                hasSampleRateMismatch: false,
                sampleRateStatusDetail: "Matched"
             )
         )

         #expect(output.loading == .idle)
         #expect(output.status.kind == .info)
         #expect(output.status.message == "Track ready at 44.1 kHz on Built-in Output")
         #expect(output.playbackOverride == nil)
     }

@Test("playing status for playlists includes mismatch detail")
    func playingStatus() {
        let output = presenter.presentPlaying(
            PlayerStatusContext(
                hasPlaylist: true,
                playlistTrackPosition: "2 of 3",
                sampleRate: 48_000,
                hardwareDeviceName: "Studio DAC",
                hasSampleRateMismatch: true,
                sampleRateStatusDetail: "Device is running at 44.1 kHz"
             )
         )

         #expect(output.loading == .idle)
         #expect(output.status.kind == .info)
         #expect(output.status.message == "Playing track 2 of 3 - Device is running at 44.1 kHz")
         #expect(output.playbackOverride == nil)
     }

    @Test("playing status for a single file avoids playlist wording")
    func playingStatusWithoutPlaylist() {
        let output = presenter.presentPlaying(
            PlayerStatusContext(
                hasPlaylist: false,
                playlistTrackPosition: nil,
                sampleRate: 44_100,
                hardwareDeviceName: "Built-in Output",
                hasSampleRateMismatch: false,
                sampleRateStatusDetail: "Matched"
            )
        )

        #expect(output.loading == .idle)
        #expect(output.status.kind == .info)
        #expect(output.status.message == "Playing at 44.1 kHz on Built-in Output")
        #expect(output.playbackOverride == nil)
    }

    @Test("errors without audio force unavailable playback state")
    func errorStatus() {
        let output = presenter.presentError(
            .playbackStartFailed,
            hasCurrentAudio: false
        )

        #expect(output.loading == .failed)
        #expect(output.status.kind == .error)
        #expect(output.status.message == "Failed to start audio playback")
        if case .unavailable? = output.playbackOverride {
            #expect(Bool(true))
        } else {
            Issue.record("Expected playback override to set unavailable state")
        }
    }
}
