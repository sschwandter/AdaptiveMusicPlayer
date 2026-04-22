import Foundation

struct PlayerStatusReadyInput {
    let hasPlaylist: Bool
    let playlistTrackPosition: String?
    let sampleRate: Double
    let hardwareDeviceName: String
    let hasSampleRateMismatch: Bool
    let sampleRateStatusDetail: String
}

struct PlayerStatusPlayingInput {
    let hasPlaylist: Bool
    let playlistTrackPosition: String?
    let sampleRate: Double
    let hardwareDeviceName: String
    let hasSampleRateMismatch: Bool
    let sampleRateStatusDetail: String
}

struct PlayerStatusPresentationOutput {
    let loading: LoadingPresentationState
    let status: StatusPresentationState
    let playbackOverride: PlaybackPresentationState?
}

@MainActor
struct PlayerStatusPresenter {
    func presentLoading(
        state: LoadingPresentationState,
        message: String
    ) -> PlayerStatusPresentationOutput {
        PlayerStatusPresentationOutput(
            loading: state,
            status: StatusPresentationState(kind: .info, message: message),
            playbackOverride: nil
        )
    }

    func presentInfo(
        message: String,
        loading: LoadingPresentationState = .idle
    ) -> PlayerStatusPresentationOutput {
        PlayerStatusPresentationOutput(
            loading: loading,
            status: StatusPresentationState(
                kind: message.isEmpty ? .neutral : .info,
                message: message
            ),
            playbackOverride: nil
        )
    }

    func presentReady(_ input: PlayerStatusReadyInput) -> PlayerStatusPresentationOutput {
        presentInfo(message: playbackMessage(prefix: readyPrefix(for: input), input: input))
    }

    func presentPlaying(_ input: PlayerStatusPlayingInput) -> PlayerStatusPresentationOutput {
        presentInfo(message: playbackMessage(prefix: playingPrefix(for: input), input: input))
    }

    func presentError(
        _ error: PlaybackError,
        hasCurrentAudio: Bool
    ) -> PlayerStatusPresentationOutput {
        PlayerStatusPresentationOutput(
            loading: .failed,
            status: StatusPresentationState(
                kind: .error,
                message: error.localizedDescription
            ),
            playbackOverride: hasCurrentAudio ? nil : .unavailable
        )
    }

    private func readyPrefix(for input: PlayerStatusReadyInput) -> String {
        input.hasPlaylist ? "Track \(input.playlistTrackPosition ?? "") ready" : "Ready to play"
    }

    private func playingPrefix(for input: PlayerStatusPlayingInput) -> String {
        input.hasPlaylist ? "Playing track \(input.playlistTrackPosition ?? "")" : "Playing"
    }

    private func playbackMessage(
        prefix: String,
        input: PlayerStatusReadyInput
    ) -> String {
        if input.hasSampleRateMismatch {
            return "\(prefix) - \(input.sampleRateStatusDetail)"
        }

        return "\(prefix) at \(SampleRatePresenter.formatSampleRate(input.sampleRate)) on \(input.hardwareDeviceName)"
    }

    private func playbackMessage(
        prefix: String,
        input: PlayerStatusPlayingInput
    ) -> String {
        if input.hasSampleRateMismatch {
            return "\(prefix) - \(input.sampleRateStatusDetail)"
        }

        return "\(prefix) at \(SampleRatePresenter.formatSampleRate(input.sampleRate)) on \(input.hardwareDeviceName)"
    }
}
