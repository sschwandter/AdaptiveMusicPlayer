import Foundation

final class ScopedFolderAccess: @unchecked Sendable {
    let folderURL: URL
    private let usesSecurityScope: Bool

    init?(folderURL: URL) {
        let didStartScopedAccess = folderURL.startAccessingSecurityScopedResource()
        let isReadableDirectory = (try? folderURL.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
            && FileManager.default.isReadableFile(atPath: folderURL.path)

        guard didStartScopedAccess || isReadableDirectory else {
            return nil
        }

        self.folderURL = folderURL
        self.usesSecurityScope = didStartScopedAccess
    }

    deinit {
        if usesSecurityScope {
            folderURL.stopAccessingSecurityScopedResource()
        }
    }
}
