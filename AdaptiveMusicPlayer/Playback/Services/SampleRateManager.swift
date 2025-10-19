import Foundation
import CoreAudio

/// Protocol for managing audio device sample rates
protocol SampleRateManaging: Sendable {
    /// Get the current hardware sample rate
    /// - Returns: The current sample rate in Hz, or nil if unavailable
    nonisolated func getCurrentSampleRate() -> Double?

    /// Set the hardware sample rate
    /// - Parameter rate: The desired sample rate in Hz
    /// - Throws: Error if the rate is not supported or cannot be set
    nonisolated func setSampleRate(_ rate: Double) throws

    /// Get all supported sample rates for the current device
    /// - Returns: Array of supported sample rates in Hz
    nonisolated func getSupportedSampleRates() -> [Double]
}

/// Core Audio implementation of sample rate management
final class CoreAudioSampleRateManager: SampleRateManaging {

    nonisolated func getCurrentSampleRate() -> Double? {
        guard let deviceID = try? getDefaultAudioDevice() else {
            return nil
        }

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

    nonisolated func setSampleRate(_ rate: Double) throws {
        let deviceID = try getDefaultAudioDevice()

        // Check if sample rate is supported
        let supportedRates = getSupportedSampleRates(deviceID: deviceID)
        guard supportedRates.contains(rate) else {
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
        return getSupportedSampleRates(deviceID: deviceID)
    }

    // MARK: - Private Methods

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

    nonisolated private func getSupportedSampleRates(deviceID: AudioDeviceID) -> [Double] {
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

        return ranges.map { $0.mMinimum }
    }
}
