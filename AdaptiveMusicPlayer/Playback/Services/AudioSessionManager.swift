import Foundation
import AVFoundation

/// Represents a complete audio playback session
@MainActor
struct AudioSession {
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
    @MainActor
    func createSession(from url: URL) async throws -> AudioSession
}

/// Manages audio session creation by coordinating file loading, player creation, and hardware configuration
final class AudioSessionManager: AudioSessionManaging {

    // MARK: - Constants

    private enum Constants {
        static let hardwareSwitchDelay: UInt64 = 500_000_000  // nanoseconds (0.5 seconds)
    }

    // MARK: - Properties

    private let fileLoader: AudioFileLoading
    private let sampleRateManager: SampleRateManaging

    // MARK: - Initialization

    init(
        fileLoader: AudioFileLoading = SecurityScopedFileLoader(),
        sampleRateManager: SampleRateManaging = CoreAudioSampleRateManager()
    ) {
        self.fileLoader = fileLoader
        self.sampleRateManager = sampleRateManager
    }

    // MARK: - Public Methods

    @MainActor
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

        // 4. Configure hardware sample rate (best effort - don't fail if unsupported)
        do {
            try sampleRateManager.setSampleRate(sampleRate)
            // Wait for hardware to actually switch
            try await Task.sleep(nanoseconds: Constants.hardwareSwitchDelay)
            guard !Task.isCancelled else { throw CancellationError() }
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            // Hardware sample rate configuration is optional
            // Continue even if it fails - playback will work with resampling
        }

        // 5. Return complete session
        return AudioSession(
            player: player,
            fileName: loadedFile.fileName,
            sampleRate: sampleRate,
            duration: duration
        )
    }
}
