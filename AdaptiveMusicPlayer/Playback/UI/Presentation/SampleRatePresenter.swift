import AdaptiveMusicPlayerCore
import Foundation

struct SampleRatePresentationInput {
    let fileSampleRate: Double
    let hardwareSampleRate: Double
    let hardwareDeviceName: String
    let supportedHardwareSampleRates: [Double]
    let hasError: Bool
    let statusMessage: String
    let isPlaying: Bool
    let isAttemptingPlaybackStart: Bool
}

struct SampleRatePresentationOutput {
    let hasMismatch: Bool
    let hardwareDeviceDisplayName: String
    let supportedHardwareSampleRatesDescription: String
    let banner: SampleRateBannerPresentation
    let routeDescription: String
    let compactExplanation: String?
    let showsSupportedRatesHint: Bool
    let statusDetail: String
}

struct SampleRatePresenter {
    func build(from input: SampleRatePresentationInput) -> SampleRatePresentationOutput {
        let hardwareDeviceDisplayName = hardwareDeviceDisplayName(for: input)
        let supportedRatesDescription = supportedHardwareSampleRatesDescription(for: input)
        let hasMismatch = hasSampleRateMismatch(for: input)
        let routeDescription = sampleRateRouteDescription(for: input)
        let statusDetail = sampleRateStatusDetail(
            for: input,
            hardwareDeviceDisplayName: hardwareDeviceDisplayName,
            supportedHardwareSampleRatesDescription: supportedRatesDescription,
            hasMismatch: hasMismatch
        )
        let banner = sampleRateBannerPresentation(
            for: input,
            statusDetail: statusDetail,
            routeDescription: routeDescription,
            hasMismatch: hasMismatch
        )
        let compactExplanation = compactSampleRateExplanation(
            for: input,
            hardwareDeviceDisplayName: hardwareDeviceDisplayName,
            hasMismatch: hasMismatch
        )
        let showsSupportedRatesHint = input.fileSampleRate > 0 &&
            (hasMismatch || input.supportedHardwareSampleRates.isEmpty)

        return SampleRatePresentationOutput(
            hasMismatch: hasMismatch,
            hardwareDeviceDisplayName: hardwareDeviceDisplayName,
            supportedHardwareSampleRatesDescription: supportedRatesDescription,
            banner: banner,
            routeDescription: routeDescription,
            compactExplanation: compactExplanation,
            showsSupportedRatesHint: showsSupportedRatesHint,
            statusDetail: statusDetail
        )
    }

    private func hasSampleRateMismatch(for input: SampleRatePresentationInput) -> Bool {
        guard input.fileSampleRate > 0 && input.hardwareSampleRate > 0 else { return false }
        return abs(input.fileSampleRate - input.hardwareSampleRate) > SampleRateSupport.tolerance
    }

    private func hardwareDeviceDisplayName(for input: SampleRatePresentationInput) -> String {
        input.hardwareDeviceName.isEmpty ? "Unknown output" : input.hardwareDeviceName
    }

    private func supportedHardwareSampleRatesDescription(for input: SampleRatePresentationInput) -> String {
        guard !input.supportedHardwareSampleRates.isEmpty else { return "Unavailable" }
        return input.supportedHardwareSampleRates
            .map(Self.formatSampleRate)
            .joined(separator: ", ")
    }

    private func sampleRateBannerPresentation(
        for input: SampleRatePresentationInput,
        statusDetail: String,
        routeDescription: String,
        hasMismatch: Bool
    ) -> SampleRateBannerPresentation {
        if input.hasError {
            return SampleRateBannerPresentation(
                title: "Playback Error",
                detail: nil,
                iconName: "exclamationmark.triangle.fill",
                helpText: input.statusMessage.isEmpty ? "Playback error" : input.statusMessage,
                style: .error
            )
        }

        guard input.fileSampleRate > 0 else {
            return SampleRateBannerPresentation(
                title: "No File Loaded",
                detail: nil,
                iconName: "waveform",
                helpText: "Load a file to compare its sample rate with the active output device.",
                style: .idle
            )
        }

        guard input.hardwareSampleRate > 0 else {
            return SampleRateBannerPresentation(
                title: "Output Unknown",
                detail: Self.formatSampleRate(input.fileSampleRate),
                iconName: "speaker.slash.fill",
                helpText: statusDetail,
                style: .switching
            )
        }

        if !input.isPlaying && !input.isAttemptingPlaybackStart && hasMismatch {
            return SampleRateBannerPresentation(
                title: "Ready",
                detail: Self.formatSampleRate(input.fileSampleRate),
                iconName: "waveform",
                helpText: "Press play to start playback and sync the output device if needed.",
                style: .idle
            )
        }

        if !hasMismatch {
            return SampleRateBannerPresentation(
                title: "Matched",
                detail: Self.formatSampleRate(input.fileSampleRate),
                iconName: "checkmark.circle.fill",
                helpText: statusDetail,
                style: .matched
            )
        }

        if deviceSupportsFileSampleRate(for: input) {
            return SampleRateBannerPresentation(
                title: "Switching",
                detail: routeDescription,
                iconName: "arrow.triangle.2.circlepath.circle.fill",
                helpText: statusDetail,
                style: .switching
            )
        }

        return SampleRateBannerPresentation(
            title: "Unsupported Rate",
            detail: routeDescription,
            iconName: "exclamationmark.triangle.fill",
            helpText: statusDetail,
            style: .unsupported
        )
    }

    private func sampleRateRouteDescription(for input: SampleRatePresentationInput) -> String {
        let fileRate = input.fileSampleRate > 0 ? Self.formatSampleRate(input.fileSampleRate) : "—"
        let hardwareRate = input.hardwareSampleRate > 0 ? Self.formatSampleRate(input.hardwareSampleRate) : "—"
        return "\(fileRate) -> \(hardwareRate)"
    }

    private func compactSampleRateExplanation(
        for input: SampleRatePresentationInput,
        hardwareDeviceDisplayName: String,
        hasMismatch: Bool
    ) -> String? {
        guard input.fileSampleRate > 0 else { return nil }
        guard input.hardwareSampleRate > 0 else {
            return "Could not read the current hardware sample rate."
        }
        guard hasMismatch else { return nil }

        if !deviceSupportsFileSampleRate(for: input) {
            return "\(hardwareDeviceDisplayName) does not advertise \(Self.formatSampleRate(input.fileSampleRate))."
        }

        return "\(hardwareDeviceDisplayName) supports \(Self.formatSampleRate(input.fileSampleRate)), but has not switched yet."
    }

    private func sampleRateStatusDetail(
        for input: SampleRatePresentationInput,
        hardwareDeviceDisplayName: String,
        supportedHardwareSampleRatesDescription: String,
        hasMismatch: Bool
    ) -> String {
        guard input.fileSampleRate > 0 else {
            return "Load a file to compare its sample rate with the active output device."
        }

        guard input.hardwareSampleRate > 0 else {
            return "Could not read the current sample rate for \(hardwareDeviceDisplayName)."
        }

        if !hasMismatch {
            return "Matched on \(hardwareDeviceDisplayName). Playback is running at the file's native rate."
        }

        if !input.supportedHardwareSampleRates.isEmpty &&
            !Self.sampleRate(input.fileSampleRate, isWithin: input.supportedHardwareSampleRates)
        {
            return "\(hardwareDeviceDisplayName) does not advertise support for \(Self.formatSampleRate(input.fileSampleRate)). Supported rates: \(supportedHardwareSampleRatesDescription)."
        }

        return "\(hardwareDeviceDisplayName) supports \(Self.formatSampleRate(input.fileSampleRate)), but the hardware is still at \(Self.formatSampleRate(input.hardwareSampleRate)). Playback will be resampled until the device switches."
    }

    private func deviceSupportsFileSampleRate(for input: SampleRatePresentationInput) -> Bool {
        !input.supportedHardwareSampleRates.isEmpty &&
        Self.sampleRate(input.fileSampleRate, isWithin: input.supportedHardwareSampleRates)
    }

    static func formatSampleRate(_ sampleRate: Double) -> String {
        let kilohertz = sampleRate / 1000
        if abs(kilohertz.rounded() - kilohertz) < 0.05 {
            return "\(Int(kilohertz.rounded())) kHz"
        }
        return String(format: "%.1f kHz", kilohertz)
    }

    static func sampleRate(_ target: Double, isWithin supportedRates: [Double]) -> Bool {
        supportedRates.contains { abs($0 - target) <= SampleRateSupport.tolerance }
    }
}
