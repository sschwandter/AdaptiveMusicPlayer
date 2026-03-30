import Testing
import Foundation
@testable import AdaptiveMusicPlayer

@Suite("PlaylistSession Tests")
struct PlaylistSessionTests {

    @Test("Playlist session moves between tracks while preserving playlist metadata")
    func sessionNavigationPreservesPlaylistContext() throws {
        let tracks = [
            URL(fileURLWithPath: "/tmp/a.wav"),
            URL(fileURLWithPath: "/tmp/b.wav")
        ]
        let playlist = try #require(PlaybackPlaylist(tracks: tracks))
        let session = PlaylistSession(playlist: playlist)

        #expect(session.currentTrackURL == tracks[0])
        #expect(session.positionDescription == "1 of 2")
        #expect(session.canMoveToNextTrack)

        let nextSession = try #require(session.movingToNextTrack())
        #expect(nextSession.currentTrackURL == tracks[1])
        #expect(nextSession.positionDescription == "2 of 2")
        #expect(nextSession.canMoveToPreviousTrack)
    }
}
