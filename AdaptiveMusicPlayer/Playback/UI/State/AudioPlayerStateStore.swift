import Foundation
import Observation

@MainActor
@Observable
final class AudioPlayerStateStore {
    private(set) var screenState = PlayerScreenState()
    var currentTime: Double = 0
    var displayTitlesByTrackURL: [URL: String] = [:]

    var duration: Double { screenState.playback.audioInfo?.duration ?? 0 }
    var statusMessage: String { screenState.status.message }
    var hasError: Bool { screenState.status.kind == .error }
    var currentFileName: String? { screenState.playback.audioInfo?.fileName }
    var currentDisplayTitle: String? { screenState.playback.audioInfo?.displayTitle }
    var fileSampleRate: Double { screenState.playback.audioInfo?.sampleRate ?? 0 }
    var hardwareSampleRate: Double { screenState.hardware.currentSampleRate }
    var hardwareDeviceName: String { screenState.hardware.deviceName }
    var supportedHardwareSampleRates: [Double] { screenState.hardware.supportedSampleRates }
    var isLoading: Bool { screenState.loading.isActive }
    var isPlaying: Bool { screenState.playback.isPlaying }
    var playlistSession: PlaylistSession? {
        get { screenState.playlist.session }
        set { screenState.playlist.session = newValue }
    }
    var currentAudioInfo: AudioInfo? { screenState.playback.audioInfo }

    func recordLoadedTrack(_ audioInfo: AudioInfo, for trackURL: URL) {
        displayTitlesByTrackURL[trackURL] = audioInfo.displayTitle
    }

    func setHardwareInfo(_ deviceInfo: AudioDeviceInfo?) {
        if let deviceInfo {
            screenState.hardware = HardwarePresentationState(
                deviceName: deviceInfo.name,
                currentSampleRate: deviceInfo.currentSampleRate,
                supportedSampleRates: deviceInfo.supportedSampleRates
            )
        } else {
            screenState.hardware = HardwarePresentationState()
        }
    }

    func setLoadingState(_ loadingState: LoadingPresentationState) {
        screenState.loading = loadingState
    }

    func applyStatusPresentation(_ output: PlayerStatusPresentationOutput) {
        screenState.loading = output.loading
        screenState.status = output.status

        if let playbackOverride = output.playbackOverride {
            screenState.playback = playbackOverride
        }
    }

    func applyScreenStateAction(
        _ action: PlayerScreenStateReducer.Action,
        reducer: PlayerScreenStateReducer
    ) {
        screenState = reducer.reduce(
            state: screenState,
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
                playback: screenState.playback,
                loading: screenState.loading,
                currentTime: currentTime,
                playlistSession: playlistSession,
                displayTitlesByTrackURL: displayTitlesByTrackURL,
                sampleRateBanner: sampleRateBanner
            )
        )
    }
}
