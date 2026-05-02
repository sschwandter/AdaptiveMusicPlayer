import Foundation

struct AudioPlayerSessionState {
    var playback: PlaybackPresentationState = .idle
    var activity: LoadingPresentationState = .idle
    var status: StatusPresentationState = .init()
    var playlist: PlaylistPresentationState = .init()
    var hardware: HardwarePresentationState = .init()
    var currentTime: Double = 0
    var volume: Double = 1.0
    var isSeeking: Bool = false
    var displayTitlesByTrackURL: [URL: String] = [:]

    var duration: Double { playback.audioInfo?.duration ?? 0 }
    var statusMessage: String { status.message }
    var hasError: Bool { status.kind == .error }
    var currentFileName: String? { playback.audioInfo?.fileName }
    var currentDisplayTitle: String? {
        if let currentTrackURL, let title = displayTitlesByTrackURL[currentTrackURL] {
            return title
        }
        return playback.audioInfo?.displayTitle
    }
    var fileSampleRate: Double { playback.audioInfo?.sampleRate ?? 0 }
    var hardwareSampleRate: Double { hardware.currentSampleRate }
    var hardwareDeviceName: String { hardware.deviceName }
    var supportedHardwareSampleRates: [Double] { hardware.supportedSampleRates }
    var isLoading: Bool { activity.isActive }
    var isPlaying: Bool { playback.isPlaying }
    var playlistSession: PlaylistSession? {
        get { playlist.session }
        set { playlist.session = newValue }
    }
    var currentTrackURL: URL? { playlist.session?.currentTrackURL }
    var currentAudioInfo: AudioInfo? { playback.audioInfo }
    var hasLoadedAudio: Bool { playback.audioInfo != nil }

    mutating func recordLoadedTrack(_ audioInfo: AudioInfo, for trackURL: URL) {
        displayTitlesByTrackURL[trackURL] = audioInfo.displayTitle
    }
}
