import Testing
import AVFoundation
@testable import AdaptiveMusicPlayer

@Suite("AudioSessionManager Tests")
@MainActor
struct AudioSessionManagerTests {

    @Test("Metadata title becomes the display title when available")
    func metadataTitleBecomesDisplayTitle() async throws {
        let manager = AudioSessionManager(
            fileLoader: StubAudioFileLoader(fileName: "track.mp3", fileExtension: "mp3"),
            titleReader: StubAudioTitleReader(title: "Tagged Track")
        )

        let session = try await manager.createSession(from: URL(fileURLWithPath: "/tmp/track.mp3"))

        #expect(session.fileName == "track.mp3")
        #expect(session.displayTitle == "Tagged Track")
        #expect(session.player is AVAudioPlayer)
    }

    @Test("Missing metadata title falls back to file name")
    func missingMetadataTitleFallsBackToFileName() async throws {
        let manager = AudioSessionManager(
            fileLoader: StubAudioFileLoader(fileName: "track.mp3", fileExtension: "mp3"),
            titleReader: StubAudioTitleReader(title: nil)
        )

        let session = try await manager.createSession(from: URL(fileURLWithPath: "/tmp/track.mp3"))

        #expect(session.displayTitle == "track.mp3")
    }

    @Test("Blank metadata title falls back to file name")
    func blankMetadataTitleFallsBackToFileName() async throws {
        let manager = AudioSessionManager(
            fileLoader: StubAudioFileLoader(fileName: "track.mp3", fileExtension: "mp3"),
            titleReader: StubAudioTitleReader(title: "   ")
        )

        let session = try await manager.createSession(from: URL(fileURLWithPath: "/tmp/track.mp3"))

        #expect(session.displayTitle == "track.mp3")
    }
}
