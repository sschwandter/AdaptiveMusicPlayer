import Foundation
import AVFoundation

/// Represents a complete audio playback session
/// @unchecked because AVAudioPlayer is not Sendable, but the session is created
/// on a background thread and then consumed exclusively on @MainActor.
struct AudioSession: @unchecked Sendable {
    let player: AVAudioPlayer
    let fileName: String
    let sampleRate: Double
    let duration: Double
}

/// Protocol for managing audio session creation
protocol AudioSessionManaging: Sendable {
    /// Create a new audio session from a URL
    /// - Parameter url: The file URL to load
    /// - Returns: Complete audio session ready for playback
    /// - Throws: Error if session cannot be created
    func createSession(from url: URL) async throws -> AudioSession
}

/// Manages audio session creation by coordinating file loading, player creation, and metadata extraction
final class AudioSessionManager: AudioSessionManaging {

    // MARK: - Properties

    private let fileLoader: AudioFileLoading

    // MARK: - Initialization

    init(fileLoader: AudioFileLoading = SecurityScopedFileLoader()) {
        self.fileLoader = fileLoader
    }

    // MARK: - Public Methods

    func createSession(from url: URL) async throws -> AudioSession {
        // 1. Load audio file data
        let loadedFile = try await fileLoader.load(url: url)
        guard !Task.isCancelled else { throw CancellationError() }

        // 2. Create AVAudioPlayer from data
        let player = try AVAudioPlayer(data: loadedFile.data, fileTypeHint: loadedFile.fileExtension)
        player.prepareToPlay()

        // 3. Extract metadata
        let sampleRate = player.format.sampleRate
        let duration = player.duration

        // 4. Return complete session
        return AudioSession(
            player: player,
            fileName: loadedFile.fileName,
            sampleRate: sampleRate,
            duration: duration
        )
    }
}
