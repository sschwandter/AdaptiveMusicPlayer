import Foundation

// MARK: - Domain State

/// Represents the engine's runtime state for audio playback.
/// This is an internal state used by AudioPlaybackEngine for runtime coordination,
/// not the authoritative app-level state which is AudioPlayerSessionState.
public enum EnginePlaybackState: Equatable, Sendable {
    case idle
    case loading(AudioInfo?)
    case ready(AudioInfo)
    case playing(AudioInfo)
    case paused(AudioInfo)
    case finished(AudioInfo)
    case error(PlaybackError)

    // MARK: - State Queries

    public var isPlaying: Bool {
        if case .playing = self { return true }
        return false
    }

    public var isPaused: Bool {
        if case .paused = self { return true }
        return false
    }

    public var isLoading: Bool {
        if case .loading = self { return true }
        return false
    }

    public var hasError: Bool {
        if case .error = self { return true }
        return false
    }

    public var audioInfo: AudioInfo? {
        switch self {
        case .loading(let info):
            return info
        case .ready(let info), .playing(let info), .paused(let info), .finished(let info):
            return info
        case .idle, .error:
            return nil
        }
    }

    // MARK: - State Transitions

    public var canPlay: Bool {
        switch self {
        case .ready, .paused, .finished:
            return true
        case .idle, .loading, .playing, .error:
            return false
        }
    }

    public var canPause: Bool {
        if case .playing = self { return true }
        return false
    }

    public var canSeek: Bool {
        switch self {
        case .ready, .playing, .paused, .finished:
            return true
        case .idle, .loading, .error:
            return false
        }
    }
}

// MARK: - Domain Data

/// Audio file information with business rules
public struct AudioInfo: Equatable, Sendable {
    public let fileName: String
    public let displayTitle: String
    public let duration: Double
    public let sampleRate: Double

    public init(
        fileName: String,
        displayTitle: String,
        duration: Double,
        sampleRate: Double
    ) {
        self.fileName = fileName
        self.displayTitle = displayTitle
        self.duration = duration
        self.sampleRate = sampleRate
    }

    // MARK: - Business Rules

    /// Clamp seek time to valid range [0, duration]
    public func clampSeekTime(_ time: Double) -> Double {
        max(0, min(time, duration))
    }

    /// Calculate valid skip forward time
    public func skipForward(from currentTime: Double, by interval: Double) -> Double {
        clampSeekTime(currentTime + interval)
    }

    /// Calculate valid skip backward time
    public func skipBackward(from currentTime: Double, by interval: Double) -> Double {
        clampSeekTime(currentTime - interval)
    }
}

// MARK: - Domain Errors

/// Errors that can occur in the playback domain
public enum PlaybackError: LocalizedError, Equatable {
    case notReady
    case noFileLoaded
    case alreadyPlaying
    case notPlaying
    case playbackStartFailed
    case loadingCancelled
    case loadFailed(String)
    case sampleRateSyncFailed(String)

    public var errorDescription: String? {
        switch self {
        case .notReady:
            return "Audio player is not ready"
        case .noFileLoaded:
            return "No audio file loaded"
        case .alreadyPlaying:
            return "Audio is already playing"
        case .notPlaying:
            return "Audio is not playing"
        case .playbackStartFailed:
            return "Failed to start audio playback"
        case .loadingCancelled:
            return "Loading cancelled"
        case .loadFailed(let message):
            return "Error loading file: \(message)"
        case .sampleRateSyncFailed(let message):
            return "Failed to set sample rate: \(message)"
        }
    }
}
