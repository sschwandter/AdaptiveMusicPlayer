import Foundation
import CoreAudio

protocol AudioHardwareObserving: AnyObject, Sendable {
    nonisolated func startObserving(onChange: @escaping @Sendable () -> Void)
    nonisolated func stopObserving()
}

/// Observes the active output device and its sample-rate-related properties.
final class CoreAudioHardwareObserver: @unchecked Sendable, AudioHardwareObserving {
    private let callbackQueue = DispatchQueue(label: "AdaptiveMusicPlayer.AudioHardwareObserver")

    nonisolated(unsafe) private var onChange: (@Sendable () -> Void)?
    nonisolated(unsafe) private var observedDeviceID: AudioDeviceID?
    nonisolated(unsafe) private var systemListener: AudioObjectPropertyListenerBlock?
    nonisolated(unsafe) private var deviceListener: AudioObjectPropertyListenerBlock?
    nonisolated(unsafe) private var isObserving = false

    nonisolated deinit {
        stopObserving()
    }

    nonisolated func startObserving(onChange: @escaping @Sendable () -> Void) {
        stopObserving()
        self.onChange = onChange

        var systemAddress = Self.defaultOutputDeviceAddress
        let systemListener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            guard let self else { return }
            self.handleDefaultOutputDeviceChange()
        }
        self.systemListener = systemListener

        let status = AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &systemAddress,
            callbackQueue,
            systemListener
        )

        guard status == noErr else {
            self.systemListener = nil
            self.onChange = nil
            return
        }

        isObserving = true
        observedDeviceID = Self.getDefaultAudioDevice()
        registerDeviceListenersIfNeeded()
    }

    nonisolated func stopObserving() {
        if let observedDeviceID {
            unregisterDeviceListeners(for: observedDeviceID)
        }

        if let systemListener {
            var systemAddress = Self.defaultOutputDeviceAddress
            AudioObjectRemovePropertyListenerBlock(
                AudioObjectID(kAudioObjectSystemObject),
                &systemAddress,
                callbackQueue,
                systemListener
            )
        }

        observedDeviceID = nil
        systemListener = nil
        deviceListener = nil
        onChange = nil
        isObserving = false
    }

    nonisolated private func handleDefaultOutputDeviceChange() {
        let newDeviceID = Self.getDefaultAudioDevice()
        let previousDeviceID = observedDeviceID

        if let previousDeviceID, previousDeviceID != newDeviceID {
            unregisterDeviceListeners(for: previousDeviceID)
        }

        observedDeviceID = newDeviceID
        registerDeviceListenersIfNeeded()
        notifyChange()
    }

    nonisolated private func registerDeviceListenersIfNeeded() {
        guard isObserving, let deviceID = observedDeviceID, deviceListener == nil else {
            return
        }

        let listener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            self?.notifyChange()
        }

        var nominalAddress = Self.nominalSampleRateAddress
        let nominalStatus = AudioObjectAddPropertyListenerBlock(
            deviceID,
            &nominalAddress,
            callbackQueue,
            listener
        )

        guard nominalStatus == noErr else {
            return
        }

        var availableRatesAddress = Self.availableNominalSampleRatesAddress
        let availableRatesStatus = AudioObjectAddPropertyListenerBlock(
            deviceID,
            &availableRatesAddress,
            callbackQueue,
            listener
        )

        guard availableRatesStatus == noErr else {
            AudioObjectRemovePropertyListenerBlock(
                deviceID,
                &nominalAddress,
                callbackQueue,
                listener
            )
            return
        }

        deviceListener = listener
    }

    nonisolated private func unregisterDeviceListeners(for deviceID: AudioDeviceID) {
        guard let deviceListener else { return }

        var nominalAddress = Self.nominalSampleRateAddress
        AudioObjectRemovePropertyListenerBlock(
            deviceID,
            &nominalAddress,
            callbackQueue,
            deviceListener
        )

        var availableRatesAddress = Self.availableNominalSampleRatesAddress
        AudioObjectRemovePropertyListenerBlock(
            deviceID,
            &availableRatesAddress,
            callbackQueue,
            deviceListener
        )

        self.deviceListener = nil
    }

    nonisolated private func notifyChange() {
        guard let onChange else { return }
        onChange()
    }

    nonisolated private static var defaultOutputDeviceAddress: AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
    }

    nonisolated private static var nominalSampleRateAddress: AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyNominalSampleRate,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
    }

    nonisolated private static var availableNominalSampleRatesAddress: AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyAvailableNominalSampleRates,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
    }

    nonisolated private static func getDefaultAudioDevice() -> AudioDeviceID? {
        var deviceID = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = defaultOutputDeviceAddress

        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &size,
            &deviceID
        )

        guard status == noErr else {
            return nil
        }

        return deviceID
    }
}
