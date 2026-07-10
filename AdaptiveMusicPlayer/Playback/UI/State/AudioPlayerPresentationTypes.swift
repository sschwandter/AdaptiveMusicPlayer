import AdaptiveMusicPlayerCore
import Foundation

enum PlaybackPresentationState {
    case idle
    case ready(AudioInfo)
    case playing(AudioInfo)
    case paused(AudioInfo)
    case finished(AudioInfo)
    case unavailable

    var audioInfo: AudioInfo? {
        switch self {
        case .ready(let info), .playing(let info), .paused(let info), .finished(let info):
            return info
        case .idle, .unavailable:
            return nil
        }
    }

    var isPlaying: Bool {
        if case .playing = self { return true }
        return false
    }
}

enum LoadingPresentationState: Equatable {
    case idle
    case scanningFolder
    case loadingTrack
    case startingPlayback
    case failed

    var isActive: Bool {
        switch self {
        case .scanningFolder, .loadingTrack:
            return true
        case .idle, .startingPlayback, .failed:
            return false
        }
    }
}

struct StatusPresentationState {
    enum Kind {
        case neutral
        case info
        case error
    }

    var kind: Kind = .neutral
    var message: String = ""
}

struct PlaylistPresentationState {
    var session: PlaylistSession?
}

struct HardwarePresentationState {
    var deviceName: String = ""
    var currentSampleRate: Double = 0
    var supportedSampleRates: [Double] = []
}

struct SampleRateBannerPresentation: Equatable {
    enum Style: Equatable {
        case idle
        case matched
        case switching
        case unsupported
        case error
    }

    let title: String
    let detail: String?
    let iconName: String
    let helpText: String
    let style: Style
}

struct PlaylistTrackRow: Identifiable, Equatable {
    let url: URL
    let index: Int
    let isCurrent: Bool
    let displayTitle: String

    var id: URL { url }
    var title: String { displayTitle }
    var subtitle: String { url.deletingLastPathComponent().lastPathComponent }
}

struct TransportControlsPresentation {
    let canPlayPreviousTrack: Bool
    let canPlayPause: Bool
    let canSkip: Bool
    let canPlayNextTrack: Bool
    let canStop: Bool
    let canAdjustVolume: Bool
    let playPauseSymbolName: String
    let playPauseHelp: String
}

struct PlaylistBrowserPresentation {
    let isVisible: Bool
    let positionDescription: String?
    let tracks: [PlaylistTrackRow]
}

struct ContentViewState {
    let currentTrackTitle: String?
    let playlistTrackPosition: String?
    let duration: Double
    let currentTime: Double
    let isSeeking: Bool
    let isLoading: Bool
    let isPlaying: Bool
    let hasLoadedFile: Bool
    let sliderIsEnabled: Bool
    let sliderOpacity: Double
    let sampleRateBanner: SampleRateBannerPresentation
    let transport: TransportControlsPresentation
    let playlist: PlaylistBrowserPresentation
}
