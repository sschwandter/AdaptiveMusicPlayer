import Testing
import AVFoundation
@testable import AdaptiveMusicPlayerCore
@testable import AdaptiveMusicPlayer

@Suite("PlaybackControlOperation Tests")
@MainActor
struct PlaybackControlOperationTests {

    @Test("Playing a finished track rewinds before restarting")
    func playFinishedTrackRewindsToStart() throws {
        let useCase = PlaybackControlOperation()
        let player = try StubAudioPlayer()
        let audioInfo = AudioInfo(fileName: "test.wav", displayTitle: "Test Track", duration: 1, sampleRate: 44_100)

        player.currentTime = 0.75
        // Pass isAtEnd=true to simulate playing from finished state
        let newState = try useCase.play(player: player, audioInfo: audioInfo, isAtEnd: true)

        #expect(newState == .playing(audioInfo))
        #expect(player.playCallCount == 1)
        #expect(player.currentTime == 0)
    }

    @Test("State does not advance when AVAudioPlayer fails to start")
    func playFailureDoesNotAdvanceState() throws {
        let useCase = PlaybackControlOperation()
        let player = try StubAudioPlayer(playResult: false)
        let audioInfo = AudioInfo(fileName: "test.wav", displayTitle: "Test Track", duration: 1, sampleRate: 44_100)

        #expect(throws: PlaybackError.playbackStartFailed) {
            try useCase.play(player: player, audioInfo: audioInfo, isAtEnd: false)
        }
        #expect(player.playCallCount == 1)
    }
}
