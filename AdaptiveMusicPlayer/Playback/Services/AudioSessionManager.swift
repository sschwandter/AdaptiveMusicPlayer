import Foundation
import AVFoundation

/// Represents a complete audio playback session
/// @unchecked because AVAudioPlayer is not Sendable, but the session is created
/// on a background thread and then consumed exclusively on @MainActor.
struct AudioSession: @unchecked Sendable {
    let player: AVAudioPlayer
    let fileName: String
    let displayTitle: String
    let sampleRate: Double
    let duration: Double
}

protocol AudioTitleReading: Sendable {
    func readDisplayTitle(from url: URL, fallbackFileName: String) async -> String
}

struct AVAssetAudioTitleReader: AudioTitleReading {
    func readDisplayTitle(from url: URL, fallbackFileName: String) async -> String {
        let asset = AVURLAsset(url: url)
        return titleFromCommonMetadata(asset.commonMetadata) ?? fallbackFileName
    }

    private func titleFromCommonMetadata(_ metadataItems: [AVMetadataItem]) -> String? {
        if let item = AVMetadataItem.metadataItems(
            from: metadataItems,
            filteredByIdentifier: .commonIdentifierTitle
        ).first {
            return item.stringValue
        }

        if let item = metadataItems.first(where: { $0.commonKey?.rawValue == "title" }) {
            return item.stringValue
        }

        return nil
    }
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
    private let titleReader: AudioTitleReading

    // MARK: - Initialization

    init(
        fileLoader: AudioFileLoading = SecurityScopedFileLoader(),
        titleReader: AudioTitleReading = AVAssetAudioTitleReader()
    ) {
        self.fileLoader = fileLoader
        self.titleReader = titleReader
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
        let rawDisplayTitle = await titleReader.readDisplayTitle(
            from: url,
            fallbackFileName: loadedFile.fileName
        )
        let displayTitle = Self.normalizedDisplayTitle(rawDisplayTitle, fallback: loadedFile.fileName)

        // 4. Return complete session
        return AudioSession(
            player: player,
            fileName: loadedFile.fileName,
            displayTitle: displayTitle,
            sampleRate: sampleRate,
            duration: duration
        )
    }

    private static func normalizedDisplayTitle(_ title: String?, fallback: String) -> String {
        guard let trimmedTitle = title?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmedTitle.isEmpty else {
            return fallback
        }
        return trimmedTitle
    }
}
