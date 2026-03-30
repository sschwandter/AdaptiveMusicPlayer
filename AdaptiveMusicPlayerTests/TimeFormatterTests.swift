import Testing
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
}
