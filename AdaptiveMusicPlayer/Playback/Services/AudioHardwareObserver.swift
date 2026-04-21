import Foundation
import CoreAudio

@MainActor
protocol AudioHardwareObserving: AnyObject {
    func startObserving(onChange: @escaping @Sendable () -> Void)
    func stopObserving()
}

protocol AudioHardwareInfoProviding: Sendable {
    func getCurrentAudioDeviceInfo() async -> AudioDeviceInfo?
}

struct CoreAudioHardwareInfoProvider: AudioHardwareInfoProviding {
    private let sampleRateManager: SampleRateManaging

    init(sampleRateManager: SampleRateManaging = CoreAudioSampleRateManager()) {
        self.sampleRateManager = sampleRateManager
    }

    func getCurrentAudioDeviceInfo() async -> AudioDeviceInfo? {
        await sampleRateManager.getCurrentDeviceInfo()
    }
}

/// Observes the active output device and its sample-rate-related properties.
@MainActor
final class CoreAudioHardwareObserver: AudioHardwareObserving {
    private let callbackQueue = DispatchQueue(label: "AdaptiveMusicPlayer.AudioHardwareObserver")
    private let hardwareSystem = AudioHardwareSystem.shared

    private var onChange: (@Sendable () -> Void)?
    private var observedDeviceUID: String?
    private var systemRegistration: PropertyListenerRegistration?
    private var deviceRegistration: PropertyListenerRegistration?

    func startObserving(onChange: @escaping @Sendable () -> Void) {
        stopObserving()
        self.onChange = onChange

        let systemRegistration = PropertyListenerRegistration(
            object: hardwareSystem,
            properties: [Self.defaultOutputDeviceAddress],
            callbackQueue: callbackQueue,
            delegate: PropertyChangeDelegate(observer: self, event: .defaultOutputDeviceChanged)
        )
        guard let systemRegistration else {
            self.onChange = nil
            return
        }

        self.systemRegistration = systemRegistration
        let defaultDevice = getDefaultAudioDevice()
        observedDeviceUID = defaultDevice.flatMap(Self.deviceUID)
        registerDeviceListenersIfNeeded(for: defaultDevice)
    }

    func stopObserving() {
        unregisterDeviceListeners()
        systemRegistration?.tearDown()
        systemRegistration = nil
        observedDeviceUID = nil
        onChange = nil
    }

    fileprivate func handlePropertyChange(_ event: ObserverPropertyChangeEvent) {
        switch event {
        case .defaultOutputDeviceChanged:
            handleDefaultOutputDeviceChange()
        case .devicePropertiesChanged:
            notifyChange()
        }
    }

    private func handleDefaultOutputDeviceChange() {
        guard systemRegistration != nil else {
            return
        }

        let defaultDevice = getDefaultAudioDevice()
        let newDeviceUID = defaultDevice.flatMap(Self.deviceUID)

        if observedDeviceUID != newDeviceUID {
            unregisterDeviceListeners()
        }
        observedDeviceUID = newDeviceUID
        registerDeviceListenersIfNeeded(for: defaultDevice)
        notifyChange()
    }

    private func registerDeviceListenersIfNeeded(for device: AudioHardwareDevice?) {
        guard let device, deviceRegistration == nil, systemRegistration != nil else {
            return
        }

        deviceRegistration = PropertyListenerRegistration(
            object: device,
            properties: [
                Self.nominalSampleRateAddress,
                Self.availableNominalSampleRatesAddress
            ],
            callbackQueue: callbackQueue,
            delegate: PropertyChangeDelegate(observer: self, event: .devicePropertiesChanged)
        )
    }

    private func unregisterDeviceListeners() {
        deviceRegistration?.tearDown()
        deviceRegistration = nil
    }

    private func notifyChange() {
        onChange?()
    }

    private static var defaultOutputDeviceAddress: AudioObjectPropertyAddress {
        PropertyAddress(kAudioHardwarePropertyDefaultOutputDevice)
    }

    private static var nominalSampleRateAddress: AudioObjectPropertyAddress {
        PropertyAddress(kAudioDevicePropertyNominalSampleRate)
    }

    private static var availableNominalSampleRatesAddress: AudioObjectPropertyAddress {
        PropertyAddress(kAudioDevicePropertyAvailableNominalSampleRates)
    }

    private func getDefaultAudioDevice() -> AudioHardwareDevice? {
        do {
            return try hardwareSystem.defaultOutputDevice
        } catch {
            return nil
        }
    }

    private static func deviceUID(_ device: AudioHardwareDevice) -> String? {
        try? device.uid
    }
}

private enum ObserverPropertyChangeEvent: Sendable {
    case defaultOutputDeviceChanged
    case devicePropertiesChanged
}

private final class PropertyListenerRegistration {
    private let object: AudioHardwareObject
    private let properties: [AudioObjectPropertyAddress]
    private let callbackQueue: DispatchQueue
    private let delegate: PropertyChangeDelegate
    private var isTornDown = false

    init?(
        object: AudioHardwareObject,
        properties: [AudioObjectPropertyAddress],
        callbackQueue: DispatchQueue,
        delegate: PropertyChangeDelegate
    ) {
        self.object = object
        self.properties = properties
        self.callbackQueue = callbackQueue
        self.delegate = delegate

        var delegates = object.delegates
        delegates.append(delegate)
        object.delegates = delegates

        do {
            try object.addListener(forProperties: properties, dispatchQueue: callbackQueue)
        } catch {
            Self.remove(delegate: delegate, from: object)
            return nil
        }
    }

    func tearDown() {
        guard !isTornDown else {
            return
        }

        isTornDown = true
        try? object.removeListener(forProperties: properties, dispatchQueue: callbackQueue)
        Self.remove(delegate: delegate, from: object)
    }

    private static func remove(delegate: PropertyChangeDelegate, from object: AudioHardwareObject) {
        var delegates = object.delegates
        delegates.removeAll { existing in
            guard let existing = existing as? PropertyChangeDelegate else { return false }
            return existing === delegate
        }
        object.delegates = delegates
    }
}

private final class PropertyChangeDelegate: PropertyListenerDelegate, @unchecked Sendable {
    private weak var observer: CoreAudioHardwareObserver?
    private let event: ObserverPropertyChangeEvent

    init(observer: CoreAudioHardwareObserver, event: ObserverPropertyChangeEvent) {
        self.observer = observer
        self.event = event
    }

    nonisolated func propertiesChanged(properties: [AudioObjectPropertyAddress]) {
        Task { @MainActor [weak self] in
            self?.notifyObserver()
        }
    }

    @MainActor
    private func notifyObserver() {
        observer?.handlePropertyChange(event)
    }
}
