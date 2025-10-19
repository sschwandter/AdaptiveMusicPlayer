import SwiftUI

/// Menu commands for playback control
/// Provides keyboard shortcuts and menu items for audio playback operations
struct PlaybackCommands: Commands {
    var body: some Commands {
        CommandGroup(after: .newItem) {
            Button("Open Audio File...") {
                NotificationCenter.default.post(name: .openFilePicker, object: nil)
            }
            .keyboardShortcut("o", modifiers: .command)
        }

        CommandGroup(replacing: .textEditing) {
            Button("Play/Pause") {
                NotificationCenter.default.post(name: .togglePlayPause, object: nil)
            }
            .keyboardShortcut(.space, modifiers: [])

            Button("Stop") {
                NotificationCenter.default.post(name: .stopPlayback, object: nil)
            }
            .keyboardShortcut(".", modifiers: .command)

            Divider()

            Button("Skip Backward") {
                NotificationCenter.default.post(name: .skipBackward, object: nil)
            }
            .keyboardShortcut(.leftArrow, modifiers: [])

            Button("Skip Forward") {
                NotificationCenter.default.post(name: .skipForward, object: nil)
            }
            .keyboardShortcut(.rightArrow, modifiers: [])
        }
    }
}
