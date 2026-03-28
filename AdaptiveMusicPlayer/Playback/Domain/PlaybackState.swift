import Foundation

// MARK: - Domain State

/// Represents the domain state of audio playback
enum PlaybackState: Equatable {
    case idle
    case loading(AudioInfo?)
    case ready(AudioInfo)
    case playing(AudioInfo)
    case paused(AudioInfo)
    case finished(AudioInfo)
    case error(PlaybackError)

    // MARK: - State Queries

    nonisolated var isPlaying: Bool {
        if case .playing = self { return true }
        return false
    }

    nonisolated var isPaused: Bool {
        if case .paused = self { return true }
        return false
    }

    nonisolated var isLoading: Bool {
        if case .loading = self { return true }
        return false
    }

    nonisolated var hasError: Bool {
        if case .error = self { return true }
        return false
    }

    nonisolated var audioInfo: AudioInfo? {
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

    nonisolated var canPlay: Bool {
        switch self {
        case .ready, .paused, .finished:
            return true
        case .idle, .loading, .playing, .error:
            return false
        }
    }

    nonisolated var canPause: Bool {
        if case .playing = self { return true }
        return false
    }

    nonisolated var canSeek: Bool {
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
struct AudioInfo: Equatable {
    nonisolated let fileName: String
    nonisolated let duration: Double
    nonisolated let sampleRate: Double

    // MARK: - Business Rules

    /// Clamp seek time to valid range [0, duration]
    nonisolated func clampSeekTime(_ time: Double) -> Double {
        max(0, min(time, duration))
    }

    /// Calculate valid skip forward time
    nonisolated func skipForward(from currentTime: Double, by interval: Double) -> Double {
        clampSeekTime(currentTime + interval)
    }

    /// Calculate valid skip backward time
    nonisolated func skipBackward(from currentTime: Double, by interval: Double) -> Double {
        clampSeekTime(currentTime - interval)
    }
}

// MARK: - Domain Errors

/// Errors that can occur in the playback domain
enum PlaybackError: LocalizedError, Equatable {
    case notReady
    case noFileLoaded
    case alreadyPlaying
    case notPlaying
    case playbackStartFailed
    case loadingCancelled
    case loadFailed(String)
    case sampleRateSyncFailed(String)

    var errorDescription: String? {
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
