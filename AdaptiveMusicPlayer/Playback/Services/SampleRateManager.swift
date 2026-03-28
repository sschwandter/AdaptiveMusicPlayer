import Foundation
import CoreAudio

struct AudioDeviceInfo: Sendable, Equatable {
    let name: String
    let currentSampleRate: Double
    let supportedSampleRates: [Double]
}

/// Protocol for managing audio device sample rates
protocol SampleRateManaging: Sendable {
    /// Get the current hardware sample rate
    /// - Returns: The current sample rate in Hz, or nil if unavailable
    nonisolated func getCurrentSampleRate() -> Double?

    /// Get the active output device name
    /// - Returns: Human-readable device name, or nil if unavailable
    nonisolated func getCurrentOutputDeviceName() -> String?

    /// Set the hardware sample rate
    /// - Parameter rate: The desired sample rate in Hz
    /// - Throws: Error if the rate is not supported or cannot be set
    nonisolated func setSampleRate(_ rate: Double) throws

    /// Get all supported sample rates for the current device
    /// - Returns: Array of supported sample rates in Hz
    nonisolated func getSupportedSampleRates() -> [Double]

    /// Get current output device details in one query
    /// - Returns: Device information, or nil if unavailable
    nonisolated func getCurrentDeviceInfo() -> AudioDeviceInfo?
}

/// Core Audio implementation of sample rate management
final class CoreAudioSampleRateManager: SampleRateManaging {
    nonisolated private let hardwareSystem = AudioHardwareSystem.shared

    nonisolated func getCurrentSampleRate() -> Double? {
        guard let device = try? getDefaultAudioDevice() else {
            return nil
        }
        return try? device.nominalSampleRate
    }

    nonisolated func getCurrentOutputDeviceName() -> String? {
        guard let device = try? getDefaultAudioDevice() else {
            return nil
        }
        return try? device.name
    }

    nonisolated func setSampleRate(_ rate: Double) throws {
        let device = try getDefaultAudioDevice()

        // Check if sample rate is supported
        let supportedRanges = try device.availableNominalSampleRates
        guard Self.sampleRate(rate, isSupportedBy: supportedRanges) else {
            throw NSError(domain: "SampleRateManager", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "Sample rate \(Int(rate)) Hz not supported by device"
            ])
        }

        try device.setNominalSampleRate(rate)
    }

    nonisolated func getSupportedSampleRates() -> [Double] {
        guard let device = try? getDefaultAudioDevice() else {
            return []
        }
        let ranges = (try? device.availableNominalSampleRates) ?? []
        return ranges.flatMap(Self.expandSupportedRates(from:))
    }

    nonisolated func getCurrentDeviceInfo() -> AudioDeviceInfo? {
        guard let device = try? getDefaultAudioDevice() else {
            return nil
        }
        guard
            let name = try? device.name,
            let currentSampleRate = try? device.nominalSampleRate
        else {
            return nil
        }

        let supportedRates = ((try? device.availableNominalSampleRates) ?? [])
            .flatMap(Self.expandSupportedRates(from:))

        return AudioDeviceInfo(
            name: name,
            currentSampleRate: currentSampleRate,
            supportedSampleRates: Array(Set(supportedRates)).sorted()
        )
    }

    // MARK: - Private Methods

    nonisolated static func sampleRate(_ rate: Double, isSupportedBy ranges: [AudioValueRange]) -> Bool {
        ranges.contains { range in
            rate >= range.mMinimum && rate <= range.mMaximum
        }
    }

    nonisolated static func expandSupportedRates(from range: AudioValueRange) -> [Double] {
        guard range.mMaximum >= range.mMinimum else { return [] }
        guard range.mMinimum != range.mMaximum else { return [range.mMinimum] }

        let commonRates = [44_100, 48_000, 88_200, 96_000, 176_400, 192_000].map(Double.init)
        let inRangeCommonRates = commonRates.filter { sampleRate($0, isSupportedBy: [range]) }

        if !inRangeCommonRates.isEmpty {
            return inRangeCommonRates
        }

        return [range.mMinimum, range.mMaximum]
    }

    nonisolated private func getDefaultAudioDevice() throws -> AudioHardwareDevice {
        guard let device = try hardwareSystem.defaultOutputDevice else {
            throw NSError(domain: "SampleRateManager", code: 2, userInfo: [
                NSLocalizedDescriptionKey: "No default output device available"
            ])
        }
        return device
    }
}
