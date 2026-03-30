import Testing
import CoreAudio
@testable import AdaptiveMusicPlayer

@Suite("SampleRateManager Tests")
struct SampleRateManagerTests {

    @Test("Nominal sample-rate ranges are treated as ranges")
    func rangeSupportCheck() {
        let ranges = [
            AudioValueRange(mMinimum: 44_100, mMaximum: 192_000)
        ]

        #expect(CoreAudioSampleRateManager.sampleRate(96_000, isSupportedBy: ranges))
        #expect(!CoreAudioSampleRateManager.sampleRate(22_050, isSupportedBy: ranges))
    }

    @Test("Range-backed sample rates expand to common nominal rates")
    func rangeExpansionUsesCommonNominalRates() {
        let discrete = AudioValueRange(mMinimum: 44_100, mMaximum: 44_100)
        let ranged = AudioValueRange(mMinimum: 44_100, mMaximum: 192_000)

        #expect(
            CoreAudioSampleRateManager.expandSupportedRates(from: discrete) == [44_100]
        )
        #expect(
            CoreAudioSampleRateManager.expandSupportedRates(from: ranged)
            == [44_100, 48_000, 88_200, 96_000, 176_400, 192_000]
        )
    }
}
