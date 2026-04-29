import AppKit
import Foundation

public protocol FinderItemRevealing: Sendable {
    func revealItem(at url: URL)
}

public struct FinderItemRevealer: FinderItemRevealing {
    public init() {}

    public func revealItem(at url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
}
