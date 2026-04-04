import AppKit
import Foundation

protocol FinderItemRevealing: Sendable {
    func revealItem(at url: URL)
}

struct FinderItemRevealer: FinderItemRevealing {
    func revealItem(at url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
}
