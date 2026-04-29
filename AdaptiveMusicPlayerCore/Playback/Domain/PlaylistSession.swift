import Foundation

public struct PlaylistSession: Sendable {
    public let playlist: PlaybackPlaylist
    public let folderAccess: ScopedFolderAccess?

    public init(playlist: PlaybackPlaylist, folderAccess: ScopedFolderAccess? = nil) {
        self.playlist = playlist
        self.folderAccess = folderAccess
    }

    public static func singleTrack(_ url: URL) -> PlaylistSession? {
        guard let playlist = PlaybackPlaylist(tracks: [url]) else {
            return nil
        }

        return PlaylistSession(playlist: playlist)
    }

    public static func folderPlaylist(
        tracks: [URL],
        folderAccess: ScopedFolderAccess
    ) -> PlaylistSession? {
        guard let playlist = PlaybackPlaylist(tracks: tracks) else {
            return nil
        }

        return PlaylistSession(playlist: playlist, folderAccess: folderAccess)
    }

    public var currentTrackURL: URL {
        playlist.currentTrackURL
    }

    public var positionDescription: String {
        playlist.positionDescription
    }

    public var trackCount: Int {
        playlist.trackCount
    }

    public var canMoveToPreviousTrack: Bool {
        playlist.canMoveToPreviousTrack
    }

    public var canMoveToNextTrack: Bool {
        playlist.canMoveToNextTrack
    }

    public var currentIndex: Int {
        playlist.currentIndex
    }

    public func movingToTrack(at index: Int) -> PlaylistSession? {
        guard let playlist = playlist.playlistByMovingToTrack(at: index) else {
            return nil
        }

        return PlaylistSession(playlist: playlist, folderAccess: folderAccess)
    }

    public func movingToNextTrack() -> PlaylistSession? {
        guard let playlist = playlist.playlistByMovingToNextTrack() else {
            return nil
        }

        return PlaylistSession(playlist: playlist, folderAccess: folderAccess)
    }

    public func movingToPreviousTrack() -> PlaylistSession? {
        guard let playlist = playlist.playlistByMovingToPreviousTrack() else {
            return nil
        }

        return PlaylistSession(playlist: playlist, folderAccess: folderAccess)
    }
}
