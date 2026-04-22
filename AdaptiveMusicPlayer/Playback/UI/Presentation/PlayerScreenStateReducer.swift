import Foundation

struct PlayerScreenStateReducer {
    enum Action {
        case beginLoading(preservedAudioInfo: AudioInfo?)
        case ready(AudioInfo)
        case playing(AudioInfo)
        case paused(AudioInfo)
        case stopped(preservedAudioInfo: AudioInfo?)
        case finished(AudioInfo?)
    }

    func reduce(
        state: AudioPlayer.PlayerScreenState,
        action: Action
    ) -> AudioPlayer.PlayerScreenState {
        var nextState = state

        switch action {
        case .beginLoading(let preservedAudioInfo):
            nextState.playback = loadingPlaybackState(
                preservedAudioInfo: preservedAudioInfo,
                currentPlayback: state.playback
            )
        case .ready(let audioInfo):
            nextState.playback = .ready(audioInfo)
        case .playing(let audioInfo):
            nextState.playback = .playing(audioInfo)
        case .paused(let audioInfo):
            nextState.playback = .paused(audioInfo)
        case .stopped(let preservedAudioInfo):
            nextState.playback = stoppedPlaybackState(
                preservedAudioInfo: preservedAudioInfo,
                currentPlayback: state.playback
            )
        case .finished(let audioInfo):
            if let audioInfo {
                nextState.playback = .finished(audioInfo)
            }
        }

        return nextState
    }

    private func loadingPlaybackState(
        preservedAudioInfo: AudioInfo?,
        currentPlayback: AudioPlayer.PlaybackPresentationState
    ) -> AudioPlayer.PlaybackPresentationState {
        if let preservedAudioInfo {
            return .ready(preservedAudioInfo)
        }

        if let currentAudioInfo = currentPlayback.audioInfo {
            return .ready(currentAudioInfo)
        }

        return .idle
    }

    private func stoppedPlaybackState(
        preservedAudioInfo: AudioInfo?,
        currentPlayback: AudioPlayer.PlaybackPresentationState
    ) -> AudioPlayer.PlaybackPresentationState {
        if let preservedAudioInfo {
            return .ready(preservedAudioInfo)
        }

        guard let currentAudioInfo = currentPlayback.audioInfo else {
            return .idle
        }

        return .ready(currentAudioInfo)
    }
}
