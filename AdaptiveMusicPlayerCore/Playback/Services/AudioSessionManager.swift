import Foundation
@preconcurrency import AVFoundation

/// Sendable metadata produced by async file loading.
/// Crosses the concurrency boundary from the background load task to @MainActor.
/// AVAudioPlayer is created separately on @MainActor from this data.
public struct LoadedAudioData: Sendable {
    public let data: Data
    public let fileName: String
    public let fileExtension: String
    public let displayTitle: String
    public let sampleRate: Double
    public let duration: Double

    public init(
        data: Data,
        fileName: String,
        fileExtension: String,
        displayTitle: String,
        sampleRate: Double,
        duration: Double
    ) {
        self.data = data
        self.fileName = fileName
        self.fileExtension = fileExtension
        self.displayTitle = displayTitle
        self.sampleRate = sampleRate
        self.duration = duration
    }
}

/// A fully prepared playback session: Sendable metadata plus the AVAudioPlayer
/// created on @MainActor. Never crosses an isolation boundary.
public struct AudioSession {
    public let player: AVAudioPlayer
    public let audioData: LoadedAudioData

    public var fileName: String { audioData.fileName }
    public var displayTitle: String { audioData.displayTitle }
    public var sampleRate: Double { audioData.sampleRate }
    public var duration: Double { audioData.duration }

    public init(player: AVAudioPlayer, audioData: LoadedAudioData) {
        self.player = player
        self.audioData = audioData
    }

}

public protocol AudioTitleReading: Sendable {
    func readDisplayTitle(from url: URL, fallbackFileName: String) async -> String
}

public struct AVAssetAudioTitleReader: AudioTitleReading {
    public init() {}

    public func readDisplayTitle(from url: URL, fallbackFileName: String) async -> String {
        let asset = AVURLAsset(url: url)
        do {
            let metadata = try await asset.load(.commonMetadata)
            return try await titleFromCommonMetadata(metadata) ?? fallbackFileName
        } catch {
            return fallbackFileName
        }
    }

    private func titleFromCommonMetadata(_ metadataItems: [AVMetadataItem]) async throws -> String? {
        if let item = AVMetadataItem.metadataItems(
            from: metadataItems,
            filteredByIdentifier: .commonIdentifierTitle
        ).first {
            return try await item.load(.stringValue)
        }

        if let item = metadataItems.first(where: { $0.commonKey?.rawValue == "title" }) {
            return try await item.load(.stringValue)
        }

        return nil
    }
}

/// Protocol for loading audio file data and metadata.
/// Returns Sendable data only — AVAudioPlayer creation happens on @MainActor.
public protocol AudioSessionManaging: Sendable {
    /// Load audio file data and extract metadata from the given URL.
    /// - Parameter url: The file URL to load
    /// - Returns: Sendable audio data ready for player creation on @MainActor
    /// - Throws: Error if the file cannot be loaded or read
    func loadAudioData(from url: URL) async throws -> LoadedAudioData
}

/// Manages audio session creation by coordinating file loading, player creation, and metadata extraction
public final class AudioSessionManager: AudioSessionManaging {

    // MARK: - Properties

    private let fileLoader: AudioFileLoading
    private let titleReader: AudioTitleReading

    // MARK: - Initialization

    public init(
        fileLoader: AudioFileLoading = SecurityScopedFileLoader(),
        titleReader: AudioTitleReading = AVAssetAudioTitleReader()
    ) {
        self.fileLoader = fileLoader
        self.titleReader = titleReader
    }

    // MARK: - Public Methods

    public func loadAudioData(from url: URL) async throws -> LoadedAudioData {
        // 1. Load audio file data
        let loadedFile = try await fileLoader.load(url: url)
        guard !Task.isCancelled else { throw CancellationError() }

        // 2. Create a temporary player to read sample rate and duration from the data.
        //    This player is discarded; the caller creates the definitive player on @MainActor.
        let probePlayer = try AVAudioPlayer(data: loadedFile.data, fileTypeHint: loadedFile.fileExtension)
        let sampleRate = probePlayer.format.sampleRate
        let duration = probePlayer.duration

        // 3. Extract title metadata
        let rawDisplayTitle = await titleReader.readDisplayTitle(
            from: url,
            fallbackFileName: loadedFile.fileName
        )
        let displayTitle = Self.normalizedDisplayTitle(rawDisplayTitle, fallback: loadedFile.fileName)

        // 4. Return Sendable data only — player creation happens on @MainActor
        return LoadedAudioData(
            data: loadedFile.data,
            fileName: loadedFile.fileName,
            fileExtension: loadedFile.fileExtension,
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
