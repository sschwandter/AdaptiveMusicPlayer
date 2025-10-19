import SwiftUI

@main
struct AdaptiveMusicPlayerApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .windowResizability(.contentSize)
        .windowStyle(.titleBar)
        .commands {
            CommandGroup(after: .newItem) {
                Button("Open Audio File...") {
                    // This will be handled by the ContentView's keyboard shortcut
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
}

// MARK: - Notification Names
extension Notification.Name {
    static let togglePlayPause = Notification.Name("togglePlayPause")
    static let stopPlayback = Notification.Name("stopPlayback")
    static let skipForward = Notification.Name("skipForward")
    static let skipBackward = Notification.Name("skipBackward")
}
