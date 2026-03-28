import SwiftUI

/// Menu commands for playback control
/// Provides keyboard shortcuts and menu items for the focused player window
struct PlaybackCommands: Commands {
    @FocusedValue(\.playbackCommandActions) private var actions

    var body: some Commands {
        CommandGroup(after: .newItem) {
            Button("Open Audio File...") {
                actions?.openFilePicker()
            }
            .keyboardShortcut("o", modifiers: .command)
            .disabled(actions == nil)

            Button("Open Folder...") {
                actions?.openFolderPicker()
            }
            .keyboardShortcut("o", modifiers: [.command, .shift])
            .disabled(actions == nil)
        }

        CommandGroup(replacing: .textEditing) {
            Button("Play/Pause") {
                actions?.togglePlayPause()
            }
            .keyboardShortcut(.space, modifiers: [])
            .disabled(actions?.canControlPlayback != true)

            Button("Stop") {
                actions?.stopPlayback()
            }
            .keyboardShortcut(".", modifiers: .command)
            .disabled(actions?.canControlPlayback != true)

            Divider()

            Button("Skip Backward") {
                actions?.skipBackward()
            }
            .keyboardShortcut(.leftArrow, modifiers: [])
            .disabled(actions?.canControlPlayback != true)

            Button("Skip Forward") {
                actions?.skipForward()
            }
            .keyboardShortcut(.rightArrow, modifiers: [])
            .disabled(actions?.canControlPlayback != true)

            Divider()

            Button("Previous Track") {
                actions?.playPreviousTrack()
            }
            .keyboardShortcut(.leftArrow, modifiers: .command)
            .disabled(actions?.canNavigatePlaylist != true)

            Button("Next Track") {
                actions?.playNextTrack()
            }
            .keyboardShortcut(.rightArrow, modifiers: .command)
            .disabled(actions?.canNavigatePlaylist != true)
        }
    }
}
