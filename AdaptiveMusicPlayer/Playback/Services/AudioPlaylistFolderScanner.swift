import Foundation
import UniformTypeIdentifiers

protocol AudioPlaylistFolderScanning: Sendable {
    nonisolated func scan(folderURL: URL) async throws -> [URL]
}

protocol DirectoryTreeEnumerating: Sendable {
    nonisolated func recursivelyEnumerateFiles(in folderURL: URL) async throws -> [URL]
}

protocol PlayableAudioFileClassifying: Sendable {
    nonisolated func isPlayableFile(at url: URL) -> Bool
}

struct FileManagerDirectoryTreeEnumerator: DirectoryTreeEnumerating {
    nonisolated func recursivelyEnumerateFiles(in folderURL: URL) async throws -> [URL] {
        let resourceKeys: Set<URLResourceKey> = [.isRegularFileKey, .contentTypeKey]
        let options: FileManager.DirectoryEnumerationOptions = [
            .skipsHiddenFiles,
            .skipsPackageDescendants
        ]

        guard let enumerator = FileManager.default.enumerator(
            at: folderURL,
            includingPropertiesForKeys: Array(resourceKeys),
            options: options,
            errorHandler: { _, _ in true }
        ) else {
            throw AudioPlaylistFolderScannerError.cannotEnumerateFolder(folderURL)
        }

        var urls: [URL] = []
        while let fileURL = enumerator.nextObject() as? URL {
            try Task.checkCancellation()
            urls.append(fileURL)
        }
        return urls
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

    nonisolated func scan(folderURL: URL) async throws -> [URL] {
        let resourceValues = try folderURL.resourceValues(forKeys: [.isDirectoryKey])
        guard resourceValues.isDirectory == true else {
            throw AudioPlaylistFolderScannerError.notADirectory(folderURL)
        }

        return try await directoryEnumerator.recursivelyEnumerateFiles(in: folderURL)
            .filter(audioFileClassifier.isPlayableFile(at:))
            .sorted(by: Self.sortByFullPath)
    }

    private nonisolated static func sortByFullPath(lhs: URL, rhs: URL) -> Bool {
        lhs.standardizedFileURL.path.localizedStandardCompare(rhs.standardizedFileURL.path) == .orderedAscending
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
