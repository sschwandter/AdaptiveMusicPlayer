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
            PlaybackCommands()
        }
    }
}
