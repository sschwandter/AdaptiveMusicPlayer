import Foundation

struct TimeFormatter {
    nonisolated static func format(_ time: Double) -> String {
        guard time.isFinite && time >= 0 else {
            return "0:00"
        }

        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}
