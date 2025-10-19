import Foundation

/// Notification names for playback events
/// Used to communicate between app-level commands and ContentView
extension Notification.Name {
    static let openFilePicker = Notification.Name("openFilePicker")
    static let togglePlayPause = Notification.Name("togglePlayPause")
    static let stopPlayback = Notification.Name("stopPlayback")
    static let skipForward = Notification.Name("skipForward")
    static let skipBackward = Notification.Name("skipBackward")
}
