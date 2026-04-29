import AdaptiveMusicPlayerCore
import SwiftUI

@main
struct AdaptiveMusicPlayerApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
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
