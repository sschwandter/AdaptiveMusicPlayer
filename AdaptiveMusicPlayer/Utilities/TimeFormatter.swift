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

    nonisolated static func formatRemaining(currentTime: Double, duration: Double) -> String {
        guard duration.isFinite && duration >= 0 else {
            return "-0:00"
        }

        let remaining = max(duration - max(currentTime, 0), 0)
        return "-\(format(remaining))"
    }
}
