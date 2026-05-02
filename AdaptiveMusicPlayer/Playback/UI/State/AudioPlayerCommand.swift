import AdaptiveMusicPlayerCore
import Foundation

enum AudioPlayerCommand {
    case loadFile(url: URL, importerDismissalDelay: Duration)
    case loadFolder(url: URL, importerDismissalDelay: Duration)
    case reportFileSelectionError(String)
    case togglePlayPause
    case stop
    case seekStarted
    case seek(to: Double)
    case skipForward
    case skipBackward
    case navigatePlaylist(next: Bool, autoplay: Bool)
    case selectPlaylistTrack(index: Int)
    case revealCurrentTrackInFinder
    case setVolume(Double)
}

