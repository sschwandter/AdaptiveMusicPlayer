import AdaptiveMusicPlayerCore
import SwiftUI

/// Window-scoped command actions for the focused player scene.
struct PlaybackCommandActions: Equatable {
    let openFilePicker: () -> Void
    let openFolderPicker: () -> Void
    let togglePlayPause: () -> Void
    let stopPlayback: () -> Void
    let skipForward: () -> Void
    let skipBackward: () -> Void
    let playNextTrack: () -> Void
    let playPreviousTrack: () -> Void
    let canTogglePlayPause: Bool
    let canStopPlayback: Bool
    let canSkipForward: Bool
    let canSkipBackward: Bool
    let canPlayNextTrack: Bool
    let canPlayPreviousTrack: Bool

    // ContentView rebuilds this value on every view update — at 10 Hz during
    // playback — and the main menu is rebuilt whenever the focused value
    // changes. Equality therefore compares only the capability flags: the
    // closures are fresh each time but behaviorally identical (they re-read
    // live view state when invoked), and without this the constant menu
    // rebuilds make open menus flicker and crash AppKit's menu tracking.
    static func == (lhs: PlaybackCommandActions, rhs: PlaybackCommandActions) -> Bool {
        lhs.canTogglePlayPause == rhs.canTogglePlayPause
            && lhs.canStopPlayback == rhs.canStopPlayback
            && lhs.canSkipForward == rhs.canSkipForward
            && lhs.canSkipBackward == rhs.canSkipBackward
            && lhs.canPlayNextTrack == rhs.canPlayNextTrack
            && lhs.canPlayPreviousTrack == rhs.canPlayPreviousTrack
    }
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
