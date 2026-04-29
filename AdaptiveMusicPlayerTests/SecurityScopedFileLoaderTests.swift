import Testing
import Foundation
@testable import AdaptiveMusicPlayerCore
@testable import AdaptiveMusicPlayer

@Suite("SecurityScopedFileLoader Tests")
struct SecurityScopedFileLoaderTests {

    @Test("Loads regular file URLs even when no direct scoped access is granted")
    func loadsUnscopedReadableFile() async throws {
        let rootFolder = try TemporaryFolder.make()
        defer { try? TemporaryFolder.remove(rootFolder) }

        let fileURL = rootFolder.appending(path: "track.wav")
        let contents = Data("audio".utf8)
        try TemporaryFolder.writeFile(at: fileURL, contents: contents)

        let loader = SecurityScopedFileLoader()
        let loadedFile = try await loader.load(url: fileURL)

        #expect(loadedFile.data == contents)
        #expect(loadedFile.fileName == "track.wav")
        #expect(loadedFile.fileExtension == "wav")
    }
}
