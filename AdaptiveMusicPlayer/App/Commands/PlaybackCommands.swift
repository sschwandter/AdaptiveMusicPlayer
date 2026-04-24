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
            .disabled(actions?.canTogglePlayPause != true)

            Button("Stop") {
                actions?.stopPlayback()
            }
            .keyboardShortcut(".", modifiers: .command)
            .disabled(actions?.canStopPlayback != true)

            Divider()

            Button("Skip Backward") {
                actions?.skipBackward()
            }
            .keyboardShortcut(.leftArrow, modifiers: [])
            .disabled(actions?.canSkipBackward != true)

            Button("Skip Forward") {
                actions?.skipForward()
            }
            .keyboardShortcut(.rightArrow, modifiers: [])
            .disabled(actions?.canSkipForward != true)

            Divider()

            Button("Previous Track") {
                actions?.playPreviousTrack()
            }
            .keyboardShortcut(.leftArrow, modifiers: .command)
            .disabled(actions?.canPlayPreviousTrack != true)

            Button("Next Track") {
                actions?.playNextTrack()
            }
            .keyboardShortcut(.rightArrow, modifiers: .command)
            .disabled(actions?.canPlayNextTrack != true)
        }
    }
}
