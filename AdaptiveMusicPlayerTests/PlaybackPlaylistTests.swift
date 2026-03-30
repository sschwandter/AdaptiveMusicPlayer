import Testing
import Foundation
@testable import AdaptiveMusicPlayer

@Suite("PlaybackPlaylist Tests")
struct PlaybackPlaylistTests {

    @Test("Playlist tracks move forward and backward safely")
    func playlistNavigation() throws {
        let tracks = [
            URL(fileURLWithPath: "/tmp/a.wav"),
            URL(fileURLWithPath: "/tmp/b.wav"),
            URL(fileURLWithPath: "/tmp/c.wav")
        ]

        let firstPlaylist = try #require(PlaybackPlaylist(tracks: tracks))
        #expect(firstPlaylist.currentTrackURL == tracks[0])
        #expect(firstPlaylist.canMoveToPreviousTrack == false)
        #expect(firstPlaylist.canMoveToNextTrack == true)
        #expect(firstPlaylist.positionDescription == "1 of 3")

        let secondPlaylist = try #require(firstPlaylist.playlistByMovingToNextTrack())
        #expect(secondPlaylist.currentTrackURL == tracks[1])
        #expect(secondPlaylist.canMoveToPreviousTrack == true)
        #expect(secondPlaylist.canMoveToNextTrack == true)

        let thirdPlaylist = try #require(secondPlaylist.playlistByMovingToNextTrack())
        #expect(thirdPlaylist.currentTrackURL == tracks[2])
        #expect(thirdPlaylist.canMoveToNextTrack == false)
        #expect(thirdPlaylist.playlistByMovingToNextTrack() == nil)
        #expect(try #require(thirdPlaylist.playlistByMovingToPreviousTrack()).currentTrackURL == tracks[1])
    }

    @Test("Playlist rejects empty track lists")
    func rejectsEmptyPlaylists() {
        #expect(PlaybackPlaylist(tracks: []) == nil)
    }
}
