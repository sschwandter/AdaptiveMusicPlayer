import Testing
import CoreAudio
@testable import AdaptiveMusicPlayerCore
@testable import AdaptiveMusicPlayer

@Suite("SampleRateManager Tests")
struct SampleRateManagerTests {

    @Test("Nominal sample-rate ranges are treated as ranges")
    func rangeSupportCheck() {
        let ranges = [
            AudioValueRange(mMinimum: 44_100, mMaximum: 192_000)
        ]

        #expect(SampleRateSupport.isSupported(96_000, by: ranges))
        #expect(!SampleRateSupport.isSupported(22_050, by: ranges))
    }

    @Test("Range-backed sample rates expand to common nominal rates")
    func rangeExpansionUsesCommonNominalRates() {
        let discrete = AudioValueRange(mMinimum: 44_100, mMaximum: 44_100)
        let ranged = AudioValueRange(mMinimum: 44_100, mMaximum: 192_000)

        #expect(
            SampleRateSupport.expandRates(from: discrete) == [44_100]
        )
        #expect(
            SampleRateSupport.expandRates(from: ranged)
                == [44_100, 48_000, 88_200, 96_000, 176_400, 192_000]
        )
    }

    @Test("SampleRateSupport matches within tolerance")
    func sampleRateMatchesWithinTolerance() {
        #expect(SampleRateSupport.matches(44_100.0, 44_100.8))
        #expect(SampleRateSupport.matches(96_000.5, 96_000.0))
        #expect(!SampleRateSupport.matches(44_100.0, 44_102.0))
    }

    @Test("SampleRateManagerError descriptions format rates correctly")
    func sampleRateManagerErrorDescriptions() {
        #expect(
            SampleRateManagerError.unsupportedSampleRate(rate: 44_100.4).errorDescription
                == "Sample rate 44100 Hz not supported by device"
        )
        #expect(
            SampleRateManagerError.noDefaultOutputDevice.errorDescription
                == "No default output device available"
        )
        #expect(
            SampleRateManagerError.settlingTimedOut(targetRate: 96_000, currentRate: 44_100).errorDescription
                == "Sample rate did not settle at 96000 Hz (currently 44100 Hz)"
        )
        #expect(
            SampleRateManagerError.settlingTimedOut(targetRate: 96_000, currentRate: nil).errorDescription
                == "Sample rate did not settle at 96000 Hz"
        )
    }

    @Test("SampleRateSettling returns immediately when rate already matches")
    func immediateSettlingReturnsWithoutSleeping() async throws {
        var queryCount = 0
        try await SampleRateSettling.waitForSampleRateToSettle(
            targetRate: 96_000,
            timeout: .milliseconds(500),
            pollInterval: .milliseconds(10)
        ) {
            queryCount += 1
            return 96_000
        }
        #expect(queryCount == 1)
    }

    @Test("SampleRateSettling accepts rates within tolerance")
    func settlingWithinTolerance() async throws {
        try await SampleRateSettling.waitForSampleRateToSettle(
            targetRate: 96_000,
            timeout: .milliseconds(500),
            pollInterval: .milliseconds(10)
        ) {
            95_999.5
        }
    }

    @Test("SampleRateSettling succeeds after rate settles on subsequent poll")
    func settlingAfterMultiplePolls() async throws {
        var queryCount = 0
        try await SampleRateSettling.waitForSampleRateToSettle(
            targetRate: 96_000,
            timeout: .milliseconds(500),
            pollInterval: .milliseconds(5)
        ) {
            queryCount += 1
            return queryCount >= 3 ? 96_000 : 44_100
        }
        #expect(queryCount >= 3)
    }

    @Test("SampleRateSettling throws typed error on timeout with latest observed rate")
    func settlingTimeoutThrowsTypedError() async {
        do {
            try await SampleRateSettling.waitForSampleRateToSettle(
                targetRate: 96_000,
                timeout: .milliseconds(15),
                pollInterval: .milliseconds(5)
            ) {
                44_100
            }
            Issue.record("Expected timeout error was not thrown")
        } catch let error as SampleRateManagerError {
            #expect(error == .settlingTimedOut(targetRate: 96_000, currentRate: 44_100))
        } catch {
            Issue.record("Unexpected error type thrown: \(error)")
        }
    }

    @Test("SampleRateSettling throws typed error without stale rate when latest query returns nil")
    func settlingTimeoutWithoutStaleRate() async {
        do {
            try await SampleRateSettling.waitForSampleRateToSettle(
                targetRate: 96_000,
                timeout: .milliseconds(15),
                pollInterval: .milliseconds(5)
            ) {
                nil
            }
            Issue.record("Expected timeout error was not thrown")
        } catch let error as SampleRateManagerError {
            #expect(error == .settlingTimedOut(targetRate: 96_000, currentRate: nil))
        } catch {
            Issue.record("Unexpected error type thrown: \(error)")
        }
    }

    @Test("SampleRateSettling propagates Task cancellation")
    func settlingRespectsTaskCancellation() async {
        let task = Task {
            try await SampleRateSettling.waitForSampleRateToSettle(
                targetRate: 96_000,
                timeout: .seconds(5),
                pollInterval: .milliseconds(10)
            ) {
                44_100
            }
        }
        task.cancel()
        do {
            try await task.value
            Issue.record("Expected CancellationError was not thrown")
        } catch is CancellationError {
            // Expected
        } catch {
            Issue.record("Unexpected error type thrown: \(error)")
        }
    }
}

