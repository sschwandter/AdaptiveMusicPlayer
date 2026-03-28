import SwiftUI

@main
struct AdaptiveMusicPlayerApp: App {
    private enum WindowMetrics {
        static let width: CGFloat = 520
        static let minimumHeight: CGFloat = 700
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .defaultSize(width: WindowMetrics.width, height: WindowMetrics.minimumHeight)
        .windowResizability(.contentMinSize)
        .windowStyle(.automatic)
        .commands {
            PlaybackCommands()
        }
    }
}
