import Foundation

public struct PlaybackPlaylist: Equatable, Sendable {
    public let tracks: [URL]
    public private(set) var currentIndex: Int

    public init?(tracks: [URL], currentIndex: Int = 0) {
        guard !tracks.isEmpty, tracks.indices.contains(currentIndex) else {
            return nil
        }

        self.tracks = tracks
        self.currentIndex = currentIndex
    }

    public var currentTrackURL: URL {
        tracks[currentIndex]
    }

    public var currentTrackNumber: Int {
        currentIndex + 1
    }

    public var trackCount: Int {
        tracks.count
    }

    public var canMoveToPreviousTrack: Bool {
        currentIndex > 0
    }

    public var canMoveToNextTrack: Bool {
        currentIndex < tracks.index(before: tracks.endIndex)
    }

    public var positionDescription: String {
        "\(currentTrackNumber) of \(trackCount)"
    }

    public func playlistByMovingToTrack(at index: Int) -> PlaybackPlaylist? {
        PlaybackPlaylist(tracks: tracks, currentIndex: index)
    }

    public func playlistByMovingToNextTrack() -> PlaybackPlaylist? {
        playlistByMovingToTrack(at: currentIndex + 1)
    }

    public func playlistByMovingToPreviousTrack() -> PlaybackPlaylist? {
        playlistByMovingToTrack(at: currentIndex - 1)
    }
}
