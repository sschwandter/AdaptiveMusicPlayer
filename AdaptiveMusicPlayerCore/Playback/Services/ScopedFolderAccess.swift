import Foundation

public final class ScopedFolderAccess: @unchecked Sendable {
    public let folderURL: URL
    private let usesSecurityScope: Bool
    private let stopAccessing: @Sendable (URL) -> Void

    public convenience init?(folderURL: URL) {
        self.init(
            folderURL: folderURL,
            startAccessing: { $0.startAccessingSecurityScopedResource() },
            isReadableDirectory: { url in
                (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
                    && FileManager.default.isReadableFile(atPath: url.path)
            },
            stopAccessing: { $0.stopAccessingSecurityScopedResource() }
        )
    }

    public init?(
        folderURL: URL,
        startAccessing: @Sendable (URL) -> Bool,
        isReadableDirectory: @Sendable (URL) -> Bool,
        stopAccessing: @escaping @Sendable (URL) -> Void
    ) {
        let didStartScopedAccess = startAccessing(folderURL)
        let isReadableDirectory = isReadableDirectory(folderURL)

        guard isReadableDirectory else {
            if didStartScopedAccess {
                stopAccessing(folderURL)
            }
            return nil
        }

        self.folderURL = folderURL
        self.usesSecurityScope = didStartScopedAccess
        self.stopAccessing = stopAccessing
    }

    deinit {
        if usesSecurityScope {
            stopAccessing(folderURL)
        }
    }
}
