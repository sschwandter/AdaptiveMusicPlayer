import AdaptiveMusicPlayerCore
import Foundation

struct PlayerStatusContext {
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

    func presentReady(_ input: PlayerStatusContext) -> PlayerStatusPresentationOutput {
        presentInfo(message: buildMessage(prefix: readyPrefix(for: input), context: input))
    }

    func presentPlaying(_ input: PlayerStatusContext) -> PlayerStatusPresentationOutput {
        presentInfo(message: buildMessage(prefix: playingPrefix(for: input), context: input))
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

    private func buildMessage(prefix: String, context: PlayerStatusContext) -> String {
        if context.hasSampleRateMismatch {
            return "\(prefix) - \(context.sampleRateStatusDetail)"
        }
        return "\(prefix) at \(SampleRatePresenter.formatSampleRate(context.sampleRate)) on \(context.hardwareDeviceName)"
    }

    private func readyPrefix(for context: PlayerStatusContext) -> String {
        if context.hasPlaylist, let playlistTrackPosition = context.playlistTrackPosition {
            return "Track \(playlistTrackPosition) ready"
        }

        return "Track ready"
    }

    private func playingPrefix(for context: PlayerStatusContext) -> String {
        if context.hasPlaylist, let playlistTrackPosition = context.playlistTrackPosition {
            return "Playing track \(playlistTrackPosition)"
        }

        return "Playing"
    }
}
