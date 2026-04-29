import Testing
@testable import AdaptiveMusicPlayerCore
@testable import AdaptiveMusicPlayer

@MainActor
@Suite("SampleRatePresenter Tests")
struct SampleRatePresenterTests {
    private let presenter = SampleRatePresenter()

    @Test("No file loaded produces idle banner and default status detail")
    func noFileLoaded() {
        let output = presenter.build(
            from: SampleRatePresentationInput(
                fileSampleRate: 0,
                hardwareSampleRate: 44_100,
                hardwareDeviceName: "Test Device",
                supportedHardwareSampleRates: [44_100],
                hasError: false,
                statusMessage: "",
                isPlaying: false,
                isAttemptingPlaybackStart: false
            )
        )

        #expect(output.banner.title == "No File Loaded")
        #expect(output.banner.style == .idle)
        #expect(output.statusDetail == "Load a file to compare its sample rate with the active output device.")
    }

    @Test("Matched hardware produces matched banner")
    func matchedState() {
        let output = presenter.build(
            from: SampleRatePresentationInput(
                fileSampleRate: 44_100,
                hardwareSampleRate: 44_100,
                hardwareDeviceName: "Test Device",
                supportedHardwareSampleRates: [44_100],
                hasError: false,
                statusMessage: "",
                isPlaying: false,
                isAttemptingPlaybackStart: false
            )
        )

        #expect(output.hasMismatch == false)
        #expect(output.banner.title == "Matched")
        #expect(output.banner.detail == "44.1 kHz")
        #expect(output.banner.style == .matched)
    }

    @Test("Supported mismatch stays neutral before playback starts")
    func supportedMismatchBeforePlayback() {
        let output = presenter.build(
            from: SampleRatePresentationInput(
                fileSampleRate: 96_000,
                hardwareSampleRate: 44_100,
                hardwareDeviceName: "Test Device",
                supportedHardwareSampleRates: [44_100, 96_000],
                hasError: false,
                statusMessage: "",
                isPlaying: false,
                isAttemptingPlaybackStart: false
            )
        )

        #expect(output.hasMismatch)
        #expect(output.banner.title == "Ready")
        #expect(output.banner.detail == "96 kHz")
        #expect(output.banner.style == .idle)
    }

    @Test("Supported mismatch during startup shows switching banner")
    func supportedMismatchDuringStartup() {
        let output = presenter.build(
            from: SampleRatePresentationInput(
                fileSampleRate: 96_000,
                hardwareSampleRate: 44_100,
                hardwareDeviceName: "Test Device",
                supportedHardwareSampleRates: [44_100, 96_000],
                hasError: false,
                statusMessage: "",
                isPlaying: false,
                isAttemptingPlaybackStart: true
            )
        )

        #expect(output.banner.title == "Switching")
        #expect(output.banner.detail == "96 kHz -> 44.1 kHz")
        #expect(output.banner.style == .switching)
    }

    @Test("Unsupported mismatch lists supported rates in status detail")
    func unsupportedMismatch() {
        let output = presenter.build(
            from: SampleRatePresentationInput(
                fileSampleRate: 96_000,
                hardwareSampleRate: 44_100,
                hardwareDeviceName: "Test Device",
                supportedHardwareSampleRates: [44_100, 48_000],
                hasError: false,
                statusMessage: "",
                isPlaying: true,
                isAttemptingPlaybackStart: false
            )
        )

        #expect(output.banner.title == "Unsupported Rate")
        #expect(output.banner.style == .unsupported)
        #expect(output.statusDetail.contains("Supported rates: 44.1 kHz, 48 kHz."))
    }

    @Test("Error state overrides banner and help text")
    func errorState() {
        let output = presenter.build(
            from: SampleRatePresentationInput(
                fileSampleRate: 96_000,
                hardwareSampleRate: 44_100,
                hardwareDeviceName: "Test Device",
                supportedHardwareSampleRates: [44_100, 96_000],
                hasError: true,
                statusMessage: "Playback failed",
                isPlaying: false,
                isAttemptingPlaybackStart: false
            )
        )

        #expect(output.banner.title == "Playback Error")
        #expect(output.banner.style == .error)
        #expect(output.banner.helpText == "Playback failed")
    }
}
