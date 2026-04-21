import Testing
import Foundation
@testable import AdaptiveMusicPlayer

private final class StopCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0

    func increment() {
        lock.lock()
        value += 1
        lock.unlock()
    }

    func currentValue() -> Int {
        lock.lock()
        defer { lock.unlock() }
        return value
    }
}

@Suite("Scoped Folder Access Tests")
struct ScopedFolderAccessTests {

    @Test("Accepts readable directory without requiring security-scoped access")
    @MainActor
    func acceptsReadableDirectoryWithoutScope() throws {
        let folderURL = URL(fileURLWithPath: "/tmp/folder", isDirectory: true)
        let stopCounter = StopCounter()

        let access = ScopedFolderAccess(
            folderURL: folderURL,
            startAccessing: { _ in false },
            isReadableDirectory: { _ in true },
            stopAccessing: { _ in stopCounter.increment() }
        )

        #expect(access != nil)
        #expect(access?.folderURL == folderURL)
        #expect(stopCounter.currentValue() == 0)
    }

    @Test("Rejects non-directory URLs even when security-scoped access starts")
    @MainActor
    func rejectsNonDirectoryEvenWhenScopedAccessStarts() throws {
        let fileURL = URL(fileURLWithPath: "/tmp/file.wav")
        let stopCounter = StopCounter()

        let access = ScopedFolderAccess(
            folderURL: fileURL,
            startAccessing: { _ in true },
            isReadableDirectory: { _ in false },
            stopAccessing: { _ in stopCounter.increment() }
        )

        #expect(access == nil)
        #expect(stopCounter.currentValue() == 1)
    }

    @Test("Stops security-scoped access when accepted scoped folder is released")
    @MainActor
    func stopsScopedAccessOnDeinitForAcceptedFolder() throws {
        let folderURL = URL(fileURLWithPath: "/tmp/scoped-folder", isDirectory: true)
        let stopCounter = StopCounter()

        var access: ScopedFolderAccess? = ScopedFolderAccess(
            folderURL: folderURL,
            startAccessing: { _ in true },
            isReadableDirectory: { _ in true },
            stopAccessing: { _ in stopCounter.increment() }
        )

        #expect(access != nil)
        #expect(stopCounter.currentValue() == 0)
        access = nil
        #expect(stopCounter.currentValue() == 1)
    }
}
