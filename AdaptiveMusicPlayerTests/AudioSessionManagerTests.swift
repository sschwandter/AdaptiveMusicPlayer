import Testing
import AVFoundation
@testable import AdaptiveMusicPlayerCore
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

        let audioData = try await manager.loadAudioData(from: URL(fileURLWithPath: "/tmp/track.mp3"))

        #expect(audioData.fileName == "track.mp3")
        #expect(audioData.displayTitle == "Tagged Track")
        #expect(audioData.fileExtension == "mp3")
    }

    @Test("Missing metadata title falls back to file name")
    func missingMetadataTitleFallsBackToFileName() async throws {
        let manager = AudioSessionManager(
            fileLoader: StubAudioFileLoader(fileName: "track.mp3", fileExtension: "mp3"),
            titleReader: StubAudioTitleReader(title: nil)
        )

        let audioData = try await manager.loadAudioData(from: URL(fileURLWithPath: "/tmp/track.mp3"))

        #expect(audioData.displayTitle == "track.mp3")
    }

    @Test("Blank metadata title falls back to file name")
    func blankMetadataTitleFallsBackToFileName() async throws {
        let manager = AudioSessionManager(
            fileLoader: StubAudioFileLoader(fileName: "track.mp3", fileExtension: "mp3"),
            titleReader: StubAudioTitleReader(title: "   ")
        )

        let audioData = try await manager.loadAudioData(from: URL(fileURLWithPath: "/tmp/track.mp3"))

        #expect(audioData.displayTitle == "track.mp3")
    }
}
