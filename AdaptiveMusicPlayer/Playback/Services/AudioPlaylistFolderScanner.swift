import Foundation
import UniformTypeIdentifiers

protocol AudioPlaylistFolderScanning: Sendable {
    nonisolated func scan(folderURL: URL) throws -> AudioPlaylistFolderScanResult
}

protocol DirectoryTreeEnumerating: Sendable {
    nonisolated func recursivelyEnumerateFiles(in folderURL: URL) throws -> DirectoryTreeEnumerationResult
}

protocol PlayableAudioFileClassifying: Sendable {
    nonisolated func isPlayableFile(at url: URL) -> Bool
}

struct FileManagerDirectoryTreeEnumerator: DirectoryTreeEnumerating {
    nonisolated func recursivelyEnumerateFiles(in folderURL: URL) throws -> DirectoryTreeEnumerationResult {
        let resourceKeys: Set<URLResourceKey> = [.isRegularFileKey, .contentTypeKey]
        let options: FileManager.DirectoryEnumerationOptions = [
            .skipsHiddenFiles,
            .skipsPackageDescendants
        ]
        var warnings: [AudioPlaylistFolderScanWarning] = []

        guard let enumerator = FileManager.default.enumerator(
            at: folderURL,
            includingPropertiesForKeys: Array(resourceKeys),
            options: options,
            errorHandler: { url, error in
                warnings.append(
                    AudioPlaylistFolderScanWarning(
                        path: url.path,
                        message: error.localizedDescription
                    )
                )
                return true
            }
        ) else {
            throw AudioPlaylistFolderScannerError.cannotEnumerateFolder(folderURL)
        }

        var urls: [URL] = []
        for case let fileURL as URL in enumerator {
            urls.append(fileURL)
        }
        return DirectoryTreeEnumerationResult(urls: urls, warnings: warnings)
    }
}

struct UTTypeAudioFileClassifier: PlayableAudioFileClassifying {
    nonisolated func isPlayableFile(at url: URL) -> Bool {
        guard let resourceValues = try? url.resourceValues(forKeys: [.isRegularFileKey, .contentTypeKey]),
              resourceValues.isRegularFile == true else {
            return false
        }

        if let contentType = resourceValues.contentType {
            return contentType.conforms(to: .audio)
        }

        guard let contentType = UTType(filenameExtension: url.pathExtension) else {
            return false
        }

        return contentType.conforms(to: .audio)
    }
}

struct AudioPlaylistFolderScanner: AudioPlaylistFolderScanning {
    private let directoryEnumerator: DirectoryTreeEnumerating
    private let audioFileClassifier: PlayableAudioFileClassifying

    nonisolated init(
        directoryEnumerator: DirectoryTreeEnumerating = FileManagerDirectoryTreeEnumerator(),
        audioFileClassifier: PlayableAudioFileClassifying = UTTypeAudioFileClassifier()
    ) {
        self.directoryEnumerator = directoryEnumerator
        self.audioFileClassifier = audioFileClassifier
    }

    nonisolated func scan(folderURL: URL) throws -> AudioPlaylistFolderScanResult {
        let resourceValues = try folderURL.resourceValues(forKeys: [.isDirectoryKey])
        guard resourceValues.isDirectory == true else {
            throw AudioPlaylistFolderScannerError.notADirectory(folderURL)
        }

        let enumeration = try directoryEnumerator.recursivelyEnumerateFiles(in: folderURL)
        let files = enumeration.urls
            .filter(audioFileClassifier.isPlayableFile(at:))
            .sorted(by: Self.sortByFullPath)

        return AudioPlaylistFolderScanResult(files: files, warnings: enumeration.warnings)
    }

    private nonisolated static func sortByFullPath(lhs: URL, rhs: URL) -> Bool {
        lhs.standardizedFileURL.path.localizedStandardCompare(rhs.standardizedFileURL.path) == .orderedAscending
    }
}

struct DirectoryTreeEnumerationResult: Sendable, Equatable {
    nonisolated let urls: [URL]
    nonisolated let warnings: [AudioPlaylistFolderScanWarning]

    nonisolated static func == (lhs: DirectoryTreeEnumerationResult, rhs: DirectoryTreeEnumerationResult) -> Bool {
        lhs.urls == rhs.urls && lhs.warnings == rhs.warnings
    }
}

struct AudioPlaylistFolderScanResult: Sendable, Equatable {
    nonisolated let files: [URL]
    nonisolated let warnings: [AudioPlaylistFolderScanWarning]

    nonisolated var warningSummary: String? {
        guard !warnings.isEmpty else { return nil }
        let itemLabel = warnings.count == 1 ? "item" : "items"
        return "Skipped \(warnings.count) unreadable \(itemLabel) while scanning the folder."
    }

    nonisolated static func == (lhs: AudioPlaylistFolderScanResult, rhs: AudioPlaylistFolderScanResult) -> Bool {
        lhs.files == rhs.files && lhs.warnings == rhs.warnings
    }
}

struct AudioPlaylistFolderScanWarning: Sendable, Equatable {
    nonisolated let path: String
    nonisolated let message: String

    nonisolated static func == (lhs: AudioPlaylistFolderScanWarning, rhs: AudioPlaylistFolderScanWarning) -> Bool {
        lhs.path == rhs.path && lhs.message == rhs.message
    }
}

enum AudioPlaylistFolderScannerError: LocalizedError, Equatable {
    case notADirectory(URL)
    case cannotEnumerateFolder(URL)

    var errorDescription: String? {
        switch self {
        case .notADirectory(let url):
            return "\(url.lastPathComponent) is not a folder."
        case .cannotEnumerateFolder(let url):
            return "Could not scan folder \(url.lastPathComponent)."
        }
    }
}
