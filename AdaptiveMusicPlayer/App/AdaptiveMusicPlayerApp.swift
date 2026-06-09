import AdaptiveMusicPlayerCore
import SwiftUI

@main
struct AdaptiveMusicPlayerApp: App {
    // Owned by the app, not the window, so playback continues when the last
    // window closes and a reopened window rebinds to the live session state.
    @State private var player = AudioPlayer()

    var body: some Scene {
        WindowGroup {
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
