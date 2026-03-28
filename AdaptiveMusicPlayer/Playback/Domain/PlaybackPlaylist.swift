import Foundation

struct PlaybackPlaylist: Equatable, Sendable {
    let tracks: [URL]
    private(set) var currentIndex: Int

    nonisolated init?(tracks: [URL], currentIndex: Int = 0) {
        guard !tracks.isEmpty, tracks.indices.contains(currentIndex) else {
            return nil
        }

        self.tracks = tracks
        self.currentIndex = currentIndex
    }

    nonisolated var currentTrackURL: URL {
        tracks[currentIndex]
    }

    nonisolated var currentTrackNumber: Int {
        currentIndex + 1
    }

    nonisolated var trackCount: Int {
        tracks.count
    }

    nonisolated var canMoveToPreviousTrack: Bool {
        currentIndex > 0
    }

    nonisolated var canMoveToNextTrack: Bool {
        currentIndex < tracks.index(before: tracks.endIndex)
    }

    nonisolated var positionDescription: String {
        "\(currentTrackNumber) of \(trackCount)"
    }

    nonisolated func playlistByMovingToTrack(at index: Int) -> PlaybackPlaylist? {
        PlaybackPlaylist(tracks: tracks, currentIndex: index)
    }

    nonisolated func playlistByMovingToNextTrack() -> PlaybackPlaylist? {
        playlistByMovingToTrack(at: currentIndex + 1)
    }

    nonisolated func playlistByMovingToPreviousTrack() -> PlaybackPlaylist? {
        playlistByMovingToTrack(at: currentIndex - 1)
    }
}
