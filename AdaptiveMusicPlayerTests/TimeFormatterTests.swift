import Testing
@testable import AdaptiveMusicPlayerCore
@testable import AdaptiveMusicPlayer

@Suite("TimeFormatter Tests")
struct TimeFormatterTests {

    @Test("Time string formatting edge cases")
    func timeStringEdgeCases() async throws {
        #expect(TimeFormatter.format(0.5) == "0:00")
        #expect(TimeFormatter.format(59.9) == "0:59")
        #expect(TimeFormatter.format(3600) == "60:00")
        #expect(TimeFormatter.format(Double.infinity) == "0:00")
        #expect(TimeFormatter.format(-10) == "0:00")
    }

    @Test("Remaining time formatting")
    func remainingTimeFormatting() async throws {
        #expect(TimeFormatter.formatRemaining(currentTime: 0, duration: 125) == "-2:05")
        #expect(TimeFormatter.formatRemaining(currentTime: 65, duration: 125) == "-1:00")
        #expect(TimeFormatter.formatRemaining(currentTime: 200, duration: 125) == "-0:00")
        #expect(TimeFormatter.formatRemaining(currentTime: -5, duration: 125) == "-2:05")
        #expect(TimeFormatter.formatRemaining(currentTime: 10, duration: Double.infinity) == "-0:00")
    }
}
