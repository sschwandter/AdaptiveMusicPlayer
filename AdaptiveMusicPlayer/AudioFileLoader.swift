import Foundation
import AVFoundation

/// Metadata and file reference for a loaded audio file
struct LoadedAudioFile {
    let file: AVAudioFile
    let sampleRate: Double
    let duration: Double
    let lengthSamples: AVAudioFramePosition
    let fileName: String
}

/// Protocol for loading audio files
protocol AudioFileLoading {
    /// Load an audio file from the given URL
    /// - Parameter url: The file URL to load
    /// - Returns: Loaded audio file with metadata
    /// - Throws: Error if file cannot be loaded or accessed
    func load(url: URL) async throws -> LoadedAudioFile
}

/// File loader that handles security-scoped resource access
final class SecurityScopedFileLoader: AudioFileLoading {

    func load(url: URL) async throws -> LoadedAudioFile {
        // Check for cancellation early
        guard !Task.isCancelled else {
            throw CancellationError()
        }

        // Access security-scoped resource
        guard url.startAccessingSecurityScopedResource() else {
            throw LoaderError.cannotAccessFile
        }

        defer {
            url.stopAccessingSecurityScopedResource()
        }

        // Check cancellation before expensive operations
        guard !Task.isCancelled else {
            throw CancellationError()
        }

        // Load audio file
        let file = try AVAudioFile(forReading: url)

        // Check cancellation after loading
        guard !Task.isCancelled else {
            throw CancellationError()
        }

        // Extract metadata
        let format = file.processingFormat
        let sampleRate = format.sampleRate
        let lengthSamples = file.length
        let duration = Double(lengthSamples) / sampleRate
        let fileName = url.lastPathComponent

        return LoadedAudioFile(
            file: file,
            sampleRate: sampleRate,
            duration: duration,
            lengthSamples: lengthSamples,
            fileName: fileName
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
