import Foundation

/// Loaded audio file data
struct LoadedAudioFile {
    nonisolated let data: Data
    nonisolated let fileName: String
    nonisolated let fileExtension: String
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

        // Directly selected files can grant security-scoped access themselves, while
        // playlist entries discovered under an already-open scoped folder may not.
        let didAccessScopedResource = url.startAccessingSecurityScopedResource()
        defer {
            if didAccessScopedResource {
                url.stopAccessingSecurityScopedResource()
            }
        }

        // Load file data into memory
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            if !didAccessScopedResource {
                throw LoaderError.cannotAccessFile
            }
            throw error
        }

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
