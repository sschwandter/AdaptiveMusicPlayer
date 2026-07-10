import Testing
import Foundation
@testable import AdaptiveMusicPlayerCore
@testable import AdaptiveMusicPlayer

@MainActor
@Suite("ContentViewStatePresenter Tests")
struct ContentViewStatePresenterTests {
    private let presenter = ContentViewStatePresenter()

    @Test("Unloaded state disables transport and hides playlist")
    func unloadedState() {
        let output = presenter.present(
            input: ContentViewStatePresentationInput(
                sessionState: AudioPlayerSessionState(),
                sampleRateBanner: idleBanner
            )
        )

        #expect(output.playlist.tracks.isEmpty)
        #expect(output.currentTrackTitle == nil)
        #expect(output.sliderIsEnabled == false)
        #expect(output.sliderOpacity == 0.45)
        #expect(output.transport.canPlayPause == false)
        #expect(output.playlist.isVisible == false)
    }

    @Test("Single loaded track enables transport and keeps playlist hidden")
    func singleTrackState() {
        let audioInfo = AudioInfo(fileName: "track.wav", displayTitle: "Track", duration: 120, sampleRate: 44_100)
        let output = presenter.present(
            input: ContentViewStatePresentationInput(
                sessionState: AudioPlayerSessionState(
                    playback: .ready(audioInfo),
                    activity: .idle,
                    status: .init(),
                    playlist: PlaylistPresentationState(
                        session: PlaylistSession.singleTrack(URL(fileURLWithPath: "/tmp/track.wav"))
                    ),
                    hardware: .init(),
                    currentTime: 12,
                    displayTitlesByTrackURL: [:]
                ),
                sampleRateBanner: idleBanner
            )
        )

        #expect(output.currentTrackTitle == "Track")
        #expect(output.duration == 120)
        #expect(output.currentTime == 12)
        #expect(output.sliderIsEnabled == true)
        #expect(output.transport.canPlayPause == true)
        #expect(output.playlist.isVisible == false)
    }

    @Test("Playlist state maps rows and navigation flags")
    func playlistState() {
        let firstURL = URL(fileURLWithPath: "/tmp/album/01-first.wav")
        let secondURL = URL(fileURLWithPath: "/tmp/album/02-second.wav")
        let playlistSession = PlaylistSession(
            playlist: PlaybackPlaylist(tracks: [firstURL, secondURL], currentIndex: 1)!
        )
        let audioInfo = AudioInfo(fileName: "02-second.wav", displayTitle: "Finale", duration: 180, sampleRate: 48_000)
        let output = presenter.present(
            input: ContentViewStatePresentationInput(
                sessionState: AudioPlayerSessionState(
                    playback: .ready(audioInfo),
                    activity: .idle,
                    status: .init(),
                    playlist: PlaylistPresentationState(session: playlistSession),
                    hardware: .init(),
                    currentTime: 30,
                    displayTitlesByTrackURL: [secondURL: "Finale"]
                ),
                sampleRateBanner: idleBanner
            )
        )

        #expect(output.playlistTrackPosition == "2 of 2")
        #expect(output.playlist.positionDescription == "2 of 2")
        #expect(output.playlist.tracks.count == 2)
        #expect(output.playlist.tracks.first?.title == "01-first.wav")
        #expect(output.playlist.tracks.last?.title == "Finale")
        #expect(output.playlist.tracks.last?.isCurrent == true)
        #expect(output.playlist.isVisible == true)
        #expect(output.transport.canPlayPreviousTrack == true)
        #expect(output.transport.canPlayNextTrack == false)
    }

    @Test("Loading state disables transport and dims slider")
    func loadingState() {
        let audioInfo = AudioInfo(fileName: "track.wav", displayTitle: "Track", duration: 120, sampleRate: 44_100)
        let output = presenter.present(
            input: ContentViewStatePresentationInput(
                sessionState: AudioPlayerSessionState(
                    playback: .ready(audioInfo),
                    activity: .loadingTrack,
                    status: .init(),
                    playlist: PlaylistPresentationState(
                        session: PlaylistSession.singleTrack(URL(fileURLWithPath: "/tmp/track.wav"))
                    ),
                    hardware: .init(),
                    currentTime: 0,
                    displayTitlesByTrackURL: [:]
                ),
                sampleRateBanner: idleBanner
            )
        )

        #expect(output.isLoading == true)
        #expect(output.sliderIsEnabled == false)
        #expect(output.sliderOpacity == 0.7)
        #expect(output.transport.canPlayPause == false)
        #expect(output.transport.canAdjustVolume == false)
    }

    @Test("Playing state switches play pause symbol")
    func playingState() {
        let audioInfo = AudioInfo(fileName: "track.wav", displayTitle: "Track", duration: 120, sampleRate: 44_100)
        let output = presenter.present(
            input: ContentViewStatePresentationInput(
                sessionState: AudioPlayerSessionState(
                    playback: .playing(audioInfo),
                    activity: .idle,
                    status: .init(),
                    playlist: PlaylistPresentationState(
                        session: PlaylistSession.singleTrack(URL(fileURLWithPath: "/tmp/track.wav"))
                    ),
                    hardware: .init(),
                    currentTime: 40,
                    displayTitlesByTrackURL: [:]
                ),
                sampleRateBanner: idleBanner
            )
        )

        #expect(output.isPlaying == true)
        #expect(output.transport.playPauseSymbolName == "pause.fill")
        #expect(output.transport.playPauseHelp == "Pause (Space)")
    }

    private var idleBanner: SampleRateBannerPresentation {
        SampleRateBannerPresentation(
            title: "No File Loaded",
            detail: nil,
            iconName: "waveform",
            helpText: "",
            style: .idle
        )
    }
}
