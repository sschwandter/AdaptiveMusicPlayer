import Foundation
import Observation

@MainActor
@Observable
final class AudioPlayerStateStore {
    private(set) var sessionState = AudioPlayerSessionState()

    var currentTime: Double {
        get { sessionState.currentTime }
        set { sessionState.currentTime = newValue }
    }
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
    var playlistSession: PlaylistSession? {
        get { sessionState.playlistSession }
        set { sessionState.playlistSession = newValue }
    }
    var currentTrackURL: URL? { sessionState.currentTrackURL }
    var currentAudioInfo: AudioInfo? { sessionState.currentAudioInfo }

    func recordLoadedTrack(_ audioInfo: AudioInfo, for trackURL: URL) {
        sessionState.recordLoadedTrack(audioInfo, for: trackURL)
    }

    func setHardwareInfo(_ deviceInfo: AudioDeviceInfo?) {
        if let deviceInfo {
            sessionState.hardware = HardwarePresentationState(
                deviceName: deviceInfo.name,
                currentSampleRate: deviceInfo.currentSampleRate,
                supportedSampleRates: deviceInfo.supportedSampleRates
            )
        } else {
            sessionState.hardware = HardwarePresentationState()
        }
    }

    func setLoadingState(_ loadingState: LoadingPresentationState) {
        sessionState.activity = loadingState
    }

    func applyStatusPresentation(_ output: PlayerStatusPresentationOutput) {
        sessionState.activity = output.loading
        sessionState.status = output.status

        if let playbackOverride = output.playbackOverride {
            sessionState.playback = playbackOverride
        }
    }

    func applyScreenStateAction(
        _ action: PlayerScreenStateReducer.Action,
        reducer: PlayerScreenStateReducer
    ) {
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
