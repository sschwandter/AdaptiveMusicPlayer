import Foundation
import CoreAudio

public struct AudioDeviceInfo: Sendable, Equatable {
    public let name: String
    public let currentSampleRate: Double
    public let supportedSampleRates: [Double]

    public init(name: String, currentSampleRate: Double, supportedSampleRates: [Double]) {
        self.name = name
        self.currentSampleRate = currentSampleRate
        self.supportedSampleRates = supportedSampleRates
    }
}

public enum SampleRateSupport {
    public static func isSupported(_ rate: Double, by ranges: [AudioValueRange]) -> Bool {
        ranges.contains { range in
            rate >= range.mMinimum && rate <= range.mMaximum
        }
    }

    public static func expandRates(from range: AudioValueRange) -> [Double] {
        guard range.mMaximum >= range.mMinimum else { return [] }
        guard range.mMinimum != range.mMaximum else { return [range.mMinimum] }

        let commonRates = [44_100, 48_000, 88_200, 96_000, 176_400, 192_000].map(Double.init)
        let inRangeCommonRates = commonRates.filter { isSupported($0, by: [range]) }

        if !inRangeCommonRates.isEmpty {
            return inRangeCommonRates
        }

        return [range.mMinimum, range.mMaximum]
    }

    /// Expand device-reported ranges into a deduplicated, sorted rate list —
    /// the one contract every supported-rates query returns.
    public static func normalizedRates(from ranges: [AudioValueRange]) -> [Double] {
        Array(Set(ranges.flatMap(expandRates(from:)))).sorted()
    }
}

/// Protocol for managing audio device sample rates
public protocol SampleRateManaging: Sendable {
    /// Get the current hardware sample rate
    /// - Returns: The current sample rate in Hz, or nil if unavailable
    func getCurrentSampleRate() async -> Double?

    /// Get the active output device name
    /// - Returns: Human-readable device name, or nil if unavailable
    func getCurrentOutputDeviceName() async -> String?

    /// Set the hardware sample rate
    /// - Parameter rate: The desired sample rate in Hz
    /// - Throws: Error if the rate is not supported or cannot be set
    func setSampleRate(_ rate: Double) async throws

    /// Get all supported sample rates for the current device
    /// - Returns: Array of supported sample rates in Hz
    func getSupportedSampleRates() async -> [Double]

    /// Get current output device details in one query
    /// - Returns: Device information, or nil if unavailable
    func getCurrentDeviceInfo() async -> AudioDeviceInfo?
}

/// Core Audio implementation of sample rate management
public actor CoreAudioSampleRateManager: SampleRateManaging {
    private enum Constants {
        static let sampleRateTolerance: Double = 1.0
        static let settlePollInterval: Duration = .milliseconds(50)
        static let settleTimeout: Duration = .milliseconds(750)
    }

    private let hardwareSystem = AudioHardwareSystem.shared

    public init() {}

    public func getCurrentSampleRate() async -> Double? {
        guard let device = try? getDefaultAudioDevice() else {
            return nil
        }
        return try? device.nominalSampleRate
    }

    public func getCurrentOutputDeviceName() async -> String? {
        guard let device = try? getDefaultAudioDevice() else {
            return nil
        }
        return try? device.name
    }

    public func setSampleRate(_ rate: Double) async throws {
        let device = try getDefaultAudioDevice()

        // Check if sample rate is supported
        let supportedRanges = try device.availableNominalSampleRates
        guard SampleRateSupport.isSupported(rate, by: supportedRanges) else {
            throw NSError(domain: "SampleRateManager", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "Sample rate \(Int(rate)) Hz not supported by device"
            ])
        }

        try device.setNominalSampleRate(rate)
        try await waitForSampleRateToSettle(rate, on: device)
    }

    public func getSupportedSampleRates() async -> [Double] {
        guard let device = try? getDefaultAudioDevice() else {
            return []
        }
        let ranges = (try? device.availableNominalSampleRates) ?? []
        return SampleRateSupport.normalizedRates(from: ranges)
    }

    public func getCurrentDeviceInfo() async -> AudioDeviceInfo? {
        guard let device = try? getDefaultAudioDevice() else {
            return nil
        }
        guard
            let name = try? device.name,
            let currentSampleRate = try? device.nominalSampleRate
        else {
            return nil
        }

        let supportedRates = SampleRateSupport.normalizedRates(
            from: (try? device.availableNominalSampleRates) ?? []
        )

        return AudioDeviceInfo(
            name: name,
            currentSampleRate: currentSampleRate,
            supportedSampleRates: supportedRates
        )
    }

    // MARK: - Private Methods

    private func getDefaultAudioDevice() throws -> AudioHardwareDevice {
        guard let device = try hardwareSystem.defaultOutputDevice else {
            throw NSError(domain: "SampleRateManager", code: 2, userInfo: [
                NSLocalizedDescriptionKey: "No default output device available"
            ])
        }
        return device
    }

    private func waitForSampleRateToSettle(_ targetRate: Double, on device: AudioHardwareDevice) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: Constants.settleTimeout)

        while true {
            try Task.checkCancellation()

            if let currentRate = try? device.nominalSampleRate,
               abs(currentRate - targetRate) <= Constants.sampleRateTolerance {
                return
            }

            guard clock.now < deadline else {
                throw NSError(domain: "SampleRateManager", code: 3, userInfo: [
                    NSLocalizedDescriptionKey: "Sample rate did not settle at \(Int(targetRate)) Hz"
                ])
            }

            try await Task.sleep(for: Constants.settlePollInterval)
        }
    }
}
