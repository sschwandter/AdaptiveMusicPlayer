import Foundation
import AVFoundation

/// Protocol for loading audio files
protocol LoadFileOperationProtocol: Sendable {
    /// Load an audio file and prepare it for playback
    /// - Parameter url: URL of the audio file to load
    /// - Returns: AudioSession containing player and metadata
    /// - Throws: PlaybackError if loading fails
    nonisolated func execute(from url: URL) async throws -> AudioSession
}

/// Operation for loading audio files
/// Coordinates file access, player creation, and sample rate detection
final class LoadFileOperation: LoadFileOperationProtocol {

    private let sessionManager: AudioSessionManaging

    init(sessionManager: AudioSessionManaging = AudioSessionManager()) {
        self.sessionManager = sessionManager
    }

    nonisolated func execute(from url: URL) async throws -> AudioSession {
        do {
            let session = try await sessionManager.createSession(from: url)

            guard !Task.isCancelled else {
                throw PlaybackError.loadingCancelled
            }

            return session

        } catch is CancellationError {
            throw PlaybackError.loadingCancelled
        } catch {
            throw PlaybackError.loadFailed(error.localizedDescription)
        }
    }
}
