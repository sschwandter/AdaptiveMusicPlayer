import AdaptiveMusicPlayerCore
import Foundation

enum AudioPlayerLoadPhase {
    case scanningFolder
    case loadingTrack(PlaylistSession)
}

enum AudioPlayerAction {
    case loadStarted(preservedAudioInfo: AudioInfo?, phase: AudioPlayerLoadPhase)
    case playlistSessionUpdated(PlaylistSession)
    case trackReady(url: URL, audioInfo: AudioInfo)
    case loadingCancelled
    case playbackStarting
    case playbackStartCancelled
    case playbackStarted(AudioInfo)
    case playbackPaused(AudioInfo)
    case playbackStopped(preservedAudioInfo: AudioInfo?)
    case playbackFinished(AudioInfo?)
    case progressChanged(Double)
    case hardwareInfoChanged(AudioDeviceInfo?)
    case statusPresented(PlayerStatusPresentationOutput)
    case playbackFailed(PlaybackError)
    case commandIgnored(PlaybackError)
}

struct AudioPlayerSessionReducer {
    func reduce(
        state: AudioPlayerSessionState,
        action: AudioPlayerAction
    ) -> AudioPlayerSessionState {
        var nextState = state

        switch action {
        case .loadStarted(let preservedAudioInfo, let phase):
            nextState.playback = loadingPlaybackState(
                preservedAudioInfo: preservedAudioInfo,
                currentPlayback: state.playback
            )
            nextState.currentTime = 0
            applyLoadingPhase(phase, to: &nextState)

        case .playlistSessionUpdated(let playlistSession):
            nextState.playlistSession = playlistSession

        case .trackReady(let url, let audioInfo):
            nextState.playback = .ready(audioInfo)
            nextState.currentTime = 0
            nextState.recordLoadedTrack(audioInfo, for: url)

        case .loadingCancelled:
            nextState.currentTime = 0
            nextState.activity = .cancelled
            nextState.status = StatusPresentationState(
                kind: .info,
                message: "Loading cancelled"
            )

        case .playbackStarting:
            nextState.activity = .startingPlayback

        case .playbackStartCancelled:
            nextState.activity = .idle

        case .playbackStarted(let audioInfo):
            nextState.playback = .playing(audioInfo)

        case .playbackPaused(let audioInfo):
            nextState.playback = .paused(audioInfo)
            nextState.activity = .idle
            nextState.status = StatusPresentationState(
                kind: .info,
                message: "Paused"
            )

        case .playbackStopped(let preservedAudioInfo):
            nextState.playback = stoppedPlaybackState(
                preservedAudioInfo: preservedAudioInfo,
                currentPlayback: state.playback
            )
            nextState.currentTime = 0
            nextState.activity = .idle
            nextState.status = StatusPresentationState(
                kind: .info,
                message: "Stopped"
            )

        case .playbackFinished(let audioInfo):
            if let audioInfo {
                nextState.playback = .finished(audioInfo)
            }
            nextState.currentTime = nextState.duration
            nextState.activity = .idle
            nextState.status = StatusPresentationState(
                kind: .info,
                message: "Playback finished"
            )

        case .progressChanged(let currentTime):
            nextState.currentTime = currentTime

        case .hardwareInfoChanged(let deviceInfo):
            if let deviceInfo {
                nextState.hardware = HardwarePresentationState(
                    deviceName: deviceInfo.name,
                    currentSampleRate: deviceInfo.currentSampleRate,
                    supportedSampleRates: deviceInfo.supportedSampleRates
                )
            } else {
                nextState.hardware = HardwarePresentationState()
            }

        case .statusPresented(let output):
            nextState.activity = output.loading
            nextState.status = output.status

            if let playbackOverride = output.playbackOverride {
                nextState.playback = playbackOverride
            }

        case .playbackFailed(let error):
            nextState.activity = .failed
            nextState.status = StatusPresentationState(
                kind: .error,
                message: error.localizedDescription
            )
            if nextState.currentAudioInfo == nil {
                nextState.playback = .unavailable
            }

        case .commandIgnored:
            break
        }

        return nextState
    }

    private func applyLoadingPhase(
        _ phase: AudioPlayerLoadPhase,
        to state: inout AudioPlayerSessionState
    ) {
        switch phase {
        case .scanningFolder:
            state.activity = .scanningFolder
            state.status = StatusPresentationState(
                kind: .info,
                message: "Scanning folder..."
            )
        case .loadingTrack(let playlistSession):
            state.activity = .loadingTrack
            state.status = StatusPresentationState(
                kind: .info,
                message: Self.loadingMessage(for: playlistSession)
            )
        }
    }

    private static func loadingMessage(for playlistSession: PlaylistSession) -> String {
        playlistSession.trackCount > 1
            ? "Loading track \(playlistSession.positionDescription)..."
            : "Loading file..."
    }

    private func loadingPlaybackState(
        preservedAudioInfo: AudioInfo?,
        currentPlayback: PlaybackPresentationState
    ) -> PlaybackPresentationState {
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
        currentPlayback: PlaybackPresentationState
    ) -> PlaybackPresentationState {
        if let preservedAudioInfo {
            return .ready(preservedAudioInfo)
        }

        guard let currentAudioInfo = currentPlayback.audioInfo else {
            return .idle
        }

        return .ready(currentAudioInfo)
    }
}

