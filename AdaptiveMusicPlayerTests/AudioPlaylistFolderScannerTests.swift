import Testing
import Foundation
@testable import AdaptiveMusicPlayer

@Suite("AudioPlaylistFolderScanner Tests")
struct AudioPlaylistFolderScannerTests {

    @Test("Recursively scans folders, keeps playable files, and sorts by full path")
    func scansRecursivelyAndSortsByPath() throws {
        let rootFolder = try TemporaryFolder.make()
        defer { try? TemporaryFolder.remove(rootFolder) }

        try TemporaryFolder.createSubfolder(named: "z-last", in: rootFolder)
        try TemporaryFolder.createSubfolder(named: "a-first/deeper", in: rootFolder)

        let topLevelPlayable = rootFolder.appending(path: "middle.wav")
        let nestedPlayable = rootFolder.appending(path: "a-first/song.mp3")
        let deepPlayable = rootFolder.appending(path: "a-first/deeper/intro.aiff")
        let ignoredText = rootFolder.appending(path: "notes.txt")
        let hiddenPlayable = rootFolder.appending(path: ".hidden.mp3")

        try TemporaryFolder.writeFile(at: topLevelPlayable)
        try TemporaryFolder.writeFile(at: nestedPlayable)
        try TemporaryFolder.writeFile(at: deepPlayable)
        try TemporaryFolder.writeFile(at: ignoredText)
        try TemporaryFolder.writeFile(at: hiddenPlayable)

        let scanner = AudioPlaylistFolderScanner()

        let result = try scanner.scan(folderURL: rootFolder)

        #expect(result == [deepPlayable, nestedPlayable, topLevelPlayable])
    }

    @Test("Rejects file URLs instead of folders")
    func rejectsNonDirectoryURLs() throws {
        let rootFolder = try TemporaryFolder.make()
        defer { try? TemporaryFolder.remove(rootFolder) }

        let fileURL = rootFolder.appending(path: "track.wav")
        try TemporaryFolder.writeFile(at: fileURL)

        let scanner = AudioPlaylistFolderScanner()

        #expect(throws: AudioPlaylistFolderScannerError.notADirectory(fileURL)) {
            try scanner.scan(folderURL: fileURL)
        }
    }

    @Test("Separates recursion from filtering so selection logic stays unit testable")
    func supportsInjectedEnumerationAndFiltering() throws {
        let rootFolder = try TemporaryFolder.make()
        defer { try? TemporaryFolder.remove(rootFolder) }

        let expectedAudio = rootFolder.appending(path: "disc-1/keep-me.wav")
        let alsoPlayable = rootFolder.appending(path: "disc-2/another-song.mp3")
        let ignoredText = rootFolder.appending(path: "disc-1/readme.txt")
        let enumerator = StubDirectoryTreeEnumerator(urls: [ignoredText, alsoPlayable, expectedAudio])
        let classifier = StubPlayableAudioFileClassifier(playableURLs: [alsoPlayable, expectedAudio])
        let scanner = AudioPlaylistFolderScanner(
            directoryEnumerator: enumerator,
            audioFileClassifier: classifier
        )

        let result = try scanner.scan(folderURL: rootFolder)

        #expect(result == [expectedAudio, alsoPlayable])
    }
}
