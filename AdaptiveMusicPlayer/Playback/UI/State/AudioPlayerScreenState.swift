struct PlayerScreenState {
    var playback: PlaybackPresentationState = .idle
    var loading: LoadingPresentationState = .idle
    var status: StatusPresentationState = .init()
    var playlist: PlaylistPresentationState = .init()
    var hardware: HardwarePresentationState = .init()
}
