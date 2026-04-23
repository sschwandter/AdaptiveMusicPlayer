import Foundation
import Observation

@MainActor
@Observable
final class AudioPlayerStateStore {
    private(set) var sessionState = AudioPlayerSessionState()
    private let reducer: AudioPlayerSessionReducer

    init(reducer: AudioPlayerSessionReducer = AudioPlayerSessionReducer()) {
        self.reducer = reducer
    }

    var currentTime: Double { sessionState.currentTime }
    var duration: Double { sessionState.duration }
    var statusMessage: String { sessionState.statusMessage }
    var hasError: Bool { sessionState.hasError }
    var currentFileName: String? { sessionState.currentFileName }
    var currentDisplayTitle: String? { sessionState.currentDisplayTitle }
    var fileSampleRate: Double { sessionState.fileSampleRate }
    var hardwareSampleRate: Double { sessionState.hardwareSampleRate }
    var hardwareDeviceName: String { sessionState.hardwareDeviceName }
    var supportedHardwareSampleRates: [Double] { sessionState.supportedHardwareSampleRates }
    var isLoading: Bool { sessionState.isLoading }
    var isPlaying: Bool { sessionState.isPlaying }
    var playlistSession: PlaylistSession? { sessionState.playlistSession }
    var currentTrackURL: URL? { sessionState.currentTrackURL }
    var currentAudioInfo: AudioInfo? { sessionState.currentAudioInfo }

    func dispatch(_ action: AudioPlayerAction) {
        sessionState = reducer.reduce(
            state: sessionState,
            action: action
        )
    }

    func sampleRatePresentation(
        isAttemptingPlaybackStart: Bool
    ) -> SampleRatePresentationOutput {
        SampleRatePresenter().build(
            from: SampleRatePresentationInput(
                fileSampleRate: fileSampleRate,
                hardwareSampleRate: hardwareSampleRate,
                hardwareDeviceName: hardwareDeviceName,
                supportedHardwareSampleRates: supportedHardwareSampleRates,
                hasError: hasError,
                statusMessage: statusMessage,
                isPlaying: isPlaying,
                isAttemptingPlaybackStart: isAttemptingPlaybackStart
            )
        )
    }

    func contentViewPresentation(
        sampleRateBanner: SampleRateBannerPresentation
    ) -> ContentViewStatePresentationOutput {
        ContentViewStatePresenter().present(
            input: ContentViewStatePresentationInput(
                sessionState: sessionState,
                sampleRateBanner: sampleRateBanner
            )
        )
    }
}
