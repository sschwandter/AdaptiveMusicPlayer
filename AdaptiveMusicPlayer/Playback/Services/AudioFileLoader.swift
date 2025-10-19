import Foundation

/// Loaded audio file data
struct LoadedAudioFile {
    let data: Data
    let fileName: String
    let fileExtension: String
}

/// Protocol for loading audio files
protocol AudioFileLoading: Sendable {
    /// Load an audio file from the given URL
    /// - Parameter url: The file URL to load
    /// - Returns: Loaded audio file data
    /// - Throws: Error if file cannot be loaded or accessed
    func load(url: URL) async throws -> LoadedAudioFile
}

/// File loader that handles security-scoped resource access
final class SecurityScopedFileLoader: AudioFileLoading {

    nonisolated func load(url: URL) async throws -> LoadedAudioFile {
        // Check cancellation before starting
        guard !Task.isCancelled else {
            throw CancellationError()
        }

        // Access security-scoped resource
        guard url.startAccessingSecurityScopedResource() else {
            throw LoaderError.cannotAccessFile
        }
        defer { url.stopAccessingSecurityScopedResource() }

        // Load file data into memory
        let data = try Data(contentsOf: url)

        // Check cancellation after expensive operation
        guard !Task.isCancelled else {
            throw CancellationError()
        }

        return LoadedAudioFile(
            data: data,
            fileName: url.lastPathComponent,
            fileExtension: url.pathExtension
        )
    }

    // MARK: - Error Types

    enum LoaderError: LocalizedError {
        case cannotAccessFile

        var errorDescription: String? {
            switch self {
            case .cannotAccessFile:
                return "Cannot access file"
            }
        }
    }
}
