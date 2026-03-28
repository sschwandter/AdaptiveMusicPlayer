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

    nonisolated func getCurrentSampleRate() -> Double? {
        guard let deviceID = try? getDefaultAudioDevice() else {
            return nil
        }
        return getCurrentSampleRate(deviceID: deviceID)
    }

    nonisolated func getCurrentOutputDeviceName() -> String? {
        guard let deviceID = try? getDefaultAudioDevice() else {
            return nil
        }
        return getDeviceName(deviceID: deviceID)
    }

    nonisolated func setSampleRate(_ rate: Double) throws {
        let deviceID = try getDefaultAudioDevice()

        // Check if sample rate is supported
        let supportedRanges = getSupportedSampleRateRanges(deviceID: deviceID)
        guard Self.sampleRate(rate, isSupportedBy: supportedRanges) else {
            throw NSError(domain: "SampleRateManager", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "Sample rate \(Int(rate)) Hz not supported by device"
            ])
        }

        // Set sample rate
        var nominalSampleRate = rate
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyNominalSampleRate,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        let status = AudioObjectSetPropertyData(
            deviceID,
            &address,
            0,
            nil,
            UInt32(MemoryLayout<Double>.size),
            &nominalSampleRate
        )

        guard status == noErr else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status), userInfo: [
                NSLocalizedDescriptionKey: "Failed to set sample rate"
            ])
        }
    }

    nonisolated func getSupportedSampleRates() -> [Double] {
        guard let deviceID = try? getDefaultAudioDevice() else {
            return []
        }
        return getSupportedSampleRateRanges(deviceID: deviceID).flatMap(Self.expandSupportedRates(from:))
    }

    nonisolated func getCurrentDeviceInfo() -> AudioDeviceInfo? {
        guard let deviceID = try? getDefaultAudioDevice() else {
            return nil
        }
        guard
            let name = getDeviceName(deviceID: deviceID),
            let currentSampleRate = getCurrentSampleRate(deviceID: deviceID)
        else {
            return nil
        }

        let supportedRates = getSupportedSampleRateRanges(deviceID: deviceID)
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

    nonisolated private func getDefaultAudioDevice() throws -> AudioDeviceID {
        var deviceID = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)

        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &size,
            &deviceID
        )

        guard status == noErr else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status), userInfo: [
                NSLocalizedDescriptionKey: "Failed to get audio device"
            ])
        }

        return deviceID
    }

    nonisolated private func getSupportedSampleRateRanges(deviceID: AudioDeviceID) -> [AudioValueRange] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyAvailableNominalSampleRates,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(deviceID, &address, 0, nil, &size) == noErr else {
            return []
        }

        let count = Int(size) / MemoryLayout<AudioValueRange>.size
        var ranges = [AudioValueRange](repeating: AudioValueRange(), count: count)

        guard AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &ranges) == noErr else {
            return []
        }

        return ranges
    }

    nonisolated private func getCurrentSampleRate(deviceID: AudioDeviceID) -> Double? {
        var sampleRate: Double = 0
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyNominalSampleRate,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size = UInt32(MemoryLayout<Double>.size)

        guard AudioObjectGetPropertyData(
            deviceID,
            &address,
            0,
            nil,
            &size,
            &sampleRate
        ) == noErr else {
            return nil
        }

        return sampleRate
    }

    nonisolated private func getDeviceName(deviceID: AudioDeviceID) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioObjectPropertyName,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var name: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)

        let status = AudioObjectGetPropertyData(
            deviceID,
            &address,
            0,
            nil,
            &size,
            &name
        )

        guard status == noErr else {
            return nil
        }

        return name?.takeUnretainedValue() as String?
    }
}
