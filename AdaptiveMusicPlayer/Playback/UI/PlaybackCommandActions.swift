import SwiftUI

/// Window-scoped command actions for the focused player scene.
struct PlaybackCommandActions {
    let openFilePicker: () -> Void
    let openFolderPicker: () -> Void
    let togglePlayPause: () -> Void
    let stopPlayback: () -> Void
    let skipForward: () -> Void
    let skipBackward: () -> Void
    let playNextTrack: () -> Void
    let playPreviousTrack: () -> Void
    let canControlPlayback: Bool
    let canNavigatePlaylist: Bool
}

private struct PlaybackCommandActionsKey: FocusedValueKey {
    typealias Value = PlaybackCommandActions
}

extension FocusedValues {
    var playbackCommandActions: PlaybackCommandActions? {
        get { self[PlaybackCommandActionsKey.self] }
        set { self[PlaybackCommandActionsKey.self] = newValue }
    }
}
