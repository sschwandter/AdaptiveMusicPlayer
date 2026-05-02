import Foundation

struct ContentViewStatePresentationInput {
    let sessionState: AudioPlayerSessionState
    let sampleRateBanner: SampleRateBannerPresentation
}

struct ContentViewStatePresentationOutput {
    let playlistTrackPosition: String?
    let playlistTracks: [PlaylistTrackRow]
    let hasPlaylist: Bool
    let canPlayPreviousTrack: Bool
    let canPlayNextTrack: Bool
    let contentViewState: ContentViewState
}

@MainActor
struct ContentViewStatePresenter {
    func present(input: ContentViewStatePresentationInput) -> ContentViewStatePresentationOutput {
        let playlistTrackPosition = input.sessionState.playlistSession?.positionDescription
        let playlistTracks = playlistTracks(
            playlistSession: input.sessionState.playlistSession,
            displayTitlesByTrackURL: input.sessionState.displayTitlesByTrackURL
        )
        let hasPlaylist = input.sessionState.playlistSession?.trackCount ?? 0 > 1
        let canPlayPreviousTrack = input.sessionState.playlistSession?.canMoveToPreviousTrack ?? false
        let canPlayNextTrack = input.sessionState.playlistSession?.canMoveToNextTrack ?? false
        let isLoading = input.sessionState.isLoading
        let isPlaying = input.sessionState.isPlaying
        let currentTrackTitle = input.sessionState.currentDisplayTitle
        let duration = input.sessionState.duration
        let isSeeking = input.sessionState.isSeeking
        let hasLoadedFile = currentTrackTitle != nil

        let transport = TransportControlsPresentation(
            canPlayPreviousTrack: canPlayPreviousTrack && !isLoading,
            canPlayPause: hasLoadedFile && !isLoading,
            canSkip: hasLoadedFile && !isLoading,
            canPlayNextTrack: canPlayNextTrack && !isLoading,
            canStop: hasLoadedFile && !isLoading,
            canAdjustVolume: !isLoading,
            playPauseSymbolName: isPlaying ? "pause.fill" : "play.fill",
            playPauseHelp: isPlaying ? "Pause (Space)" : "Play (Space)"
        )
        let playlist = PlaylistBrowserPresentation(
            isVisible: hasPlaylist && hasLoadedFile,
            positionDescription: playlistTrackPosition,
            tracks: playlistTracks
        )

        let contentViewState = ContentViewState(
            currentTrackTitle: currentTrackTitle,
            playlistTrackPosition: playlistTrackPosition,
            duration: duration,
            currentTime: input.sessionState.currentTime,
            isSeeking: isSeeking,
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
    ) -> [PlaylistTrackRow] {
        guard let playlistSession else { return [] }

        return playlistSession.playlist.tracks.enumerated().map { index, url in
            PlaylistTrackRow(
                url: url,
                index: index,
                isCurrent: index == playlistSession.currentIndex,
                displayTitle: displayTitlesByTrackURL[url] ?? url.lastPathComponent
            )
        }
    }
}
