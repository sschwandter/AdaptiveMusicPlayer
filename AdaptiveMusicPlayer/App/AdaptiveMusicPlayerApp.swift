import AdaptiveMusicPlayerCore
import SwiftUI

/// With a single `Window` scene, SwiftUI's default is to terminate the app
/// when that window closes, which would end playback. Keep the process alive
/// so the music continues; the user quits explicitly via Cmd+Q.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}

@main
struct AdaptiveMusicPlayerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    // Owned by the app, not the window, so playback continues when the last
    // window closes and a reopened window rebinds to the live session state.
    @State private var player = AudioPlayer()

    var body: some Scene {
        Window("Adaptive Music Player", id: "player") {
            ContentView(player: player)
        }
        .restorationBehavior(.disabled)
        .windowResizability(.contentSize)
        .defaultWindowPlacement { content, context in WindowPlacement(size: content.sizeThatFits(.unspecified)) }
        .windowStyle(.automatic)
        .commands {
            PlaybackCommands()
        }
    }
}
