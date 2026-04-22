import Foundation

struct ContentViewStatePresentationInput {
    let playback: AudioPlayer.PlaybackPresentationState
    let loading: AudioPlayer.LoadingPresentationState
    let currentTime: Double
    let playlistSession: PlaylistSession?
    let displayTitlesByTrackURL: [URL: String]
    let sampleRateBanner: AudioPlayer.SampleRateBannerPresentation
}

struct ContentViewStatePresentationOutput {
    let playlistTrackPosition: String?
    let playlistTracks: [AudioPlayer.PlaylistTrackRow]
    let hasPlaylist: Bool
    let canPlayPreviousTrack: Bool
    let canPlayNextTrack: Bool
    let contentViewState: AudioPlayer.ContentViewState
}

@MainActor
struct ContentViewStatePresenter {
    func present(input: ContentViewStatePresentationInput) -> ContentViewStatePresentationOutput {
        let playlistTrackPosition = input.playlistSession?.positionDescription
        let playlistTracks = playlistTracks(
            playlistSession: input.playlistSession,
            displayTitlesByTrackURL: input.displayTitlesByTrackURL
        )
        let hasPlaylist = input.playlistSession?.trackCount ?? 0 > 1
        let canPlayPreviousTrack = input.playlistSession?.canMoveToPreviousTrack ?? false
        let canPlayNextTrack = input.playlistSession?.canMoveToNextTrack ?? false
        let isLoading = input.loading.isActive
        let isPlaying = input.playback.isPlaying
        let currentTrackTitle = input.playback.audioInfo?.displayTitle
        let duration = input.playback.audioInfo?.duration ?? 0
        let hasLoadedFile = currentTrackTitle != nil

        let transport = AudioPlayer.TransportControlsPresentation(
            canPlayPreviousTrack: canPlayPreviousTrack && !isLoading,
            canPlayPause: hasLoadedFile && !isLoading,
            canSkip: hasLoadedFile && !isLoading,
            canPlayNextTrack: canPlayNextTrack && !isLoading,
            canStop: hasLoadedFile && !isLoading,
            canAdjustVolume: !isLoading,
            playPauseSymbolName: isPlaying ? "pause.fill" : "play.fill",
            playPauseHelp: isPlaying ? "Pause (Space)" : "Play (Space)"
        )
        let playlist = AudioPlayer.PlaylistBrowserPresentation(
            isVisible: hasPlaylist && hasLoadedFile,
            positionDescription: playlistTrackPosition,
            tracks: playlistTracks
        )

        let contentViewState = AudioPlayer.ContentViewState(
            currentTrackTitle: currentTrackTitle,
            playlistTrackPosition: playlistTrackPosition,
            duration: duration,
            currentTime: input.currentTime,
            isLoading: isLoading,
            isPlaying: isPlaying,
            hasLoadedFile: hasLoadedFile,
            sliderIsEnabled: hasLoadedFile && !isLoading,
            sliderOpacity: hasLoadedFile ? (isLoading ? 0.7 : 1.0) : 0.45,
            sampleRateBanner: input.sampleRateBanner,
            transport: transport,
            playlist: playlist
        )

        return ContentViewStatePresentationOutput(
            playlistTrackPosition: playlistTrackPosition,
            playlistTracks: playlistTracks,
            hasPlaylist: hasPlaylist,
            canPlayPreviousTrack: canPlayPreviousTrack,
            canPlayNextTrack: canPlayNextTrack,
            contentViewState: contentViewState
        )
    }

    private func playlistTracks(
        playlistSession: PlaylistSession?,
        displayTitlesByTrackURL: [URL: String]
    ) -> [AudioPlayer.PlaylistTrackRow] {
        guard let playlistSession else { return [] }

        return playlistSession.playlist.tracks.enumerated().map { index, url in
            AudioPlayer.PlaylistTrackRow(
                url: url,
                index: index,
                isCurrent: index == playlistSession.currentIndex,
                displayTitle: displayTitlesByTrackURL[url] ?? url.lastPathComponent
            )
        }
    }
}
