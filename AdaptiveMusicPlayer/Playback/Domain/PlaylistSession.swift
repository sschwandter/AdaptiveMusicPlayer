import Foundation

struct PlaylistSession: Sendable {
    let playlist: PlaybackPlaylist
    let folderAccess: ScopedFolderAccess?

    nonisolated init(playlist: PlaybackPlaylist, folderAccess: ScopedFolderAccess? = nil) {
        self.playlist = playlist
        self.folderAccess = folderAccess
    }

    nonisolated static func singleTrack(_ url: URL) -> PlaylistSession? {
        guard let playlist = PlaybackPlaylist(tracks: [url]) else {
            return nil
        }

        return PlaylistSession(playlist: playlist)
    }

    nonisolated static func folderPlaylist(
        tracks: [URL],
        folderAccess: ScopedFolderAccess
    ) -> PlaylistSession? {
        guard let playlist = PlaybackPlaylist(tracks: tracks) else {
            return nil
        }

        return PlaylistSession(playlist: playlist, folderAccess: folderAccess)
    }

    nonisolated var currentTrackURL: URL {
        playlist.currentTrackURL
    }

    nonisolated var positionDescription: String {
        playlist.positionDescription
    }

    nonisolated var trackCount: Int {
        playlist.trackCount
    }

    nonisolated var canMoveToPreviousTrack: Bool {
        playlist.canMoveToPreviousTrack
    }

    nonisolated var canMoveToNextTrack: Bool {
        playlist.canMoveToNextTrack
    }

    nonisolated var currentIndex: Int {
        playlist.currentIndex
    }

    nonisolated func movingToTrack(at index: Int) -> PlaylistSession? {
        guard let playlist = playlist.playlistByMovingToTrack(at: index) else {
            return nil
        }

        return PlaylistSession(playlist: playlist, folderAccess: folderAccess)
    }

    nonisolated func movingToNextTrack() -> PlaylistSession? {
        guard let playlist = playlist.playlistByMovingToNextTrack() else {
            return nil
        }

        return PlaylistSession(playlist: playlist, folderAccess: folderAccess)
    }

    nonisolated func movingToPreviousTrack() -> PlaylistSession? {
        guard let playlist = playlist.playlistByMovingToPreviousTrack() else {
            return nil
        }

        return PlaylistSession(playlist: playlist, folderAccess: folderAccess)
    }
}
