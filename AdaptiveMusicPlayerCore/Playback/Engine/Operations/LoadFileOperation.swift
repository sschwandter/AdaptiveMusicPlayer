import Foundation
import AVFoundation

/// Protocol for loading audio files
public protocol LoadFileOperationProtocol: Sendable {
    /// Load audio file data and metadata from the given URL.
    /// Returns Sendable data only — AVAudioPlayer creation happens on @MainActor.
    /// - Parameter url: URL of the audio file to load
    /// - Returns: LoadedAudioData containing file data and metadata
    /// - Throws: PlaybackError if loading fails
    func execute(from url: URL) async throws -> LoadedAudioData
}

/// Operation for loading audio files
/// Coordinates file access, player creation, and sample rate detection
public final class LoadFileOperation: LoadFileOperationProtocol {

    private let sessionManager: AudioSessionManaging

    public init(sessionManager: AudioSessionManaging = AudioSessionManager()) {
        self.sessionManager = sessionManager
    }

    public func execute(from url: URL) async throws -> LoadedAudioData {
        do {
            let audioData = try await sessionManager.loadAudioData(from: url)

            guard !Task.isCancelled else {
                throw PlaybackError.loadingCancelled
            }

            return audioData

        } catch is CancellationError {
            throw PlaybackError.loadingCancelled
        } catch {
            throw PlaybackError.loadFailed(error.localizedDescription)
        }
    }
}
