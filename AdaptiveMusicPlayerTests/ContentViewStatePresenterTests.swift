import Testing
import Foundation
@testable import AdaptiveMusicPlayer

@MainActor
@Suite("ContentViewStatePresenter Tests")
struct ContentViewStatePresenterTests {
    private let presenter = ContentViewStatePresenter()

    @Test("Unloaded state disables transport and hides playlist")
    func unloadedState() {
        let output = presenter.present(
            input: ContentViewStatePresentationInput(
                playback: .idle,
                loading: .idle,
                currentTime: 0,
                playlistSession: nil,
                displayTitlesByTrackURL: [:],
                sampleRateBanner: idleBanner
            )
        )

        #expect(output.playlistTracks.isEmpty)
        #expect(output.hasPlaylist == false)
        #expect(output.contentViewState.currentTrackTitle == nil)
        #expect(output.contentViewState.sliderIsEnabled == false)
        #expect(output.contentViewState.sliderOpacity == 0.45)
        #expect(output.contentViewState.transport.canPlayPause == false)
        #expect(output.contentViewState.playlist.isVisible == false)
    }

    @Test("Single loaded track enables transport and keeps playlist hidden")
    func singleTrackState() {
        let audioInfo = AudioInfo(fileName: "track.wav", displayTitle: "Track", duration: 120, sampleRate: 44_100)
        let output = presenter.present(
            input: ContentViewStatePresentationInput(
                playback: .ready(audioInfo),
                loading: .idle,
                currentTime: 12,
                playlistSession: PlaylistSession.singleTrack(URL(fileURLWithPath: "/tmp/track.wav")),
                displayTitlesByTrackURL: [:],
                sampleRateBanner: idleBanner
            )
        )

        #expect(output.contentViewState.currentTrackTitle == "Track")
        #expect(output.contentViewState.duration == 120)
        #expect(output.contentViewState.currentTime == 12)
        #expect(output.contentViewState.sliderIsEnabled == true)
        #expect(output.contentViewState.transport.canPlayPause == true)
        #expect(output.contentViewState.playlist.isVisible == false)
        #expect(output.hasPlaylist == false)
    }

    @Test("Playlist state maps rows and navigation flags")
    func playlistState() {
        let firstURL = URL(fileURLWithPath: "/tmp/album/01-first.wav")
        let secondURL = URL(fileURLWithPath: "/tmp/album/02-second.wav")
        let playlistSession = PlaylistSession(
            playlist: PlaybackPlaylist(tracks: [firstURL, secondURL], currentIndex: 1)!,
            folderAccess: nil
        )
        let audioInfo = AudioInfo(fileName: "02-second.wav", displayTitle: "Finale", duration: 180, sampleRate: 48_000)
        let output = presenter.present(
            input: ContentViewStatePresentationInput(
                playback: .ready(audioInfo),
                loading: .idle,
                currentTime: 30,
                playlistSession: playlistSession,
                displayTitlesByTrackURL: [secondURL: "Finale"],
                sampleRateBanner: idleBanner
            )
        )

        #expect(output.playlistTrackPosition == "2 of 2")
        #expect(output.playlistTracks.count == 2)
        #expect(output.playlistTracks.first?.title == "01-first.wav")
        #expect(output.playlistTracks.last?.title == "Finale")
        #expect(output.playlistTracks.last?.isCurrent == true)
        #expect(output.hasPlaylist == true)
        #expect(output.canPlayPreviousTrack == true)
        #expect(output.canPlayNextTrack == false)
        #expect(output.contentViewState.playlist.isVisible == true)
        #expect(output.contentViewState.transport.canPlayPreviousTrack == true)
        #expect(output.contentViewState.transport.canPlayNextTrack == false)
    }

    @Test("Loading state disables transport and dims slider")
    func loadingState() {
        let audioInfo = AudioInfo(fileName: "track.wav", displayTitle: "Track", duration: 120, sampleRate: 44_100)
        let output = presenter.present(
            input: ContentViewStatePresentationInput(
                playback: .ready(audioInfo),
                loading: .loadingTrack,
                currentTime: 0,
                playlistSession: PlaylistSession.singleTrack(URL(fileURLWithPath: "/tmp/track.wav")),
                displayTitlesByTrackURL: [:],
                sampleRateBanner: idleBanner
            )
        )

        #expect(output.contentViewState.isLoading == true)
        #expect(output.contentViewState.sliderIsEnabled == false)
        #expect(output.contentViewState.sliderOpacity == 0.7)
        #expect(output.contentViewState.transport.canPlayPause == false)
        #expect(output.contentViewState.transport.canAdjustVolume == false)
    }

    @Test("Playing state switches play pause symbol")
    func playingState() {
        let audioInfo = AudioInfo(fileName: "track.wav", displayTitle: "Track", duration: 120, sampleRate: 44_100)
        let output = presenter.present(
            input: ContentViewStatePresentationInput(
                playback: .playing(audioInfo),
                loading: .idle,
                currentTime: 40,
                playlistSession: PlaylistSession.singleTrack(URL(fileURLWithPath: "/tmp/track.wav")),
                displayTitlesByTrackURL: [:],
                sampleRateBanner: idleBanner
            )
        )

        #expect(output.contentViewState.isPlaying == true)
        #expect(output.contentViewState.transport.playPauseSymbolName == "pause.fill")
        #expect(output.contentViewState.transport.playPauseHelp == "Pause (Space)")
    }

    private var idleBanner: AudioPlayer.SampleRateBannerPresentation {
        AudioPlayer.SampleRateBannerPresentation(
            title: "No File Loaded",
            detail: nil,
            iconName: "waveform",
            helpText: "",
            style: .idle
        )
    }
}
