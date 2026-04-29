import Foundation
import CoreAudio

@MainActor
public protocol AudioHardwareObserving: AnyObject {
    func startObserving(onChange: @escaping @Sendable () -> Void)
    func stopObserving()
}

public protocol AudioHardwareInfoProviding: Sendable {
    func getCurrentAudioDeviceInfo() async -> AudioDeviceInfo?
}

public struct CoreAudioHardwareInfoProvider: AudioHardwareInfoProviding {
    private let sampleRateManager: SampleRateManaging

    public init(sampleRateManager: SampleRateManaging = CoreAudioSampleRateManager()) {
        self.sampleRateManager = sampleRateManager
    }

    public func getCurrentAudioDeviceInfo() async -> AudioDeviceInfo? {
        await sampleRateManager.getCurrentDeviceInfo()
    }
}

/// Observes the active output device and its sample-rate-related properties.
/// Design:
/// - MainActor owns behavioral state (`onChange`, observed device identity, token references).
/// - `ListenerToken` owns low-level CoreAudio registration and deterministic teardown in `deinit`.
/// - `PropertyChangeDelegate` is a minimal callback bridge that hops onto MainActor.
@MainActor
public final class CoreAudioHardwareObserver: AudioHardwareObserving {
    private let callbackQueue = DispatchQueue(label: "AdaptiveMusicPlayer.AudioHardwareObserver")
    private let hardwareSystem = AudioHardwareSystem.shared

    private var onChange: (@Sendable () -> Void)?
    private var observedDeviceUID: String?
    private var systemToken: ListenerToken?
    private var deviceToken: ListenerToken?

    public init() {}

    public func startObserving(onChange: @escaping @Sendable () -> Void) {
        stopObserving()
        self.onChange = onChange

        let systemToken = ListenerToken(
            object: hardwareSystem,
            properties: [Self.defaultOutputDeviceAddress],
            callbackQueue: callbackQueue,
            delegate: PropertyChangeDelegate(observer: self, event: .defaultOutputDeviceChanged)
        )
        guard let systemToken else {
            self.onChange = nil
            return
        }

        self.systemToken = systemToken
        let defaultDevice = getDefaultAudioDevice()
        observedDeviceUID = defaultDevice.flatMap(Self.deviceUID)
        registerDeviceListenersIfNeeded(for: defaultDevice)
    }

    public func stopObserving() {
        unregisterDeviceListeners()
        systemToken = nil
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
        guard systemToken != nil else {
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
        guard let device, deviceToken == nil, systemToken != nil else {
            return
        }

        deviceToken = ListenerToken(
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
        deviceToken = nil
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

/// RAII-style owner for one CoreAudio listener registration.
/// Keeping this lets teardown happen synchronously in `deinit`,
/// independent of whether the MainActor observer is explicitly stopped.
private final class ListenerToken {
    private let object: AudioHardwareObject
    private let properties: [AudioObjectPropertyAddress]
    private let callbackQueue: DispatchQueue
    private let delegate: PropertyChangeDelegate

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

    deinit {
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

/// Receives CoreAudio property callbacks on the CoreAudio callback queue and
/// forwards them to the MainActor observer, where all state transitions live.
private final class PropertyChangeDelegate: PropertyListenerDelegate, @unchecked Sendable {
    private weak var observer: CoreAudioHardwareObserver?
    private let event: ObserverPropertyChangeEvent

    init(observer: CoreAudioHardwareObserver, event: ObserverPropertyChangeEvent) {
        self.observer = observer
        self.event = event
    }

    func propertiesChanged(properties: [AudioObjectPropertyAddress]) {
        Task { @MainActor [weak self] in
            self?.notifyObserver()
        }
    }

    @MainActor
    private func notifyObserver() {
        observer?.handlePropertyChange(event)
    }
}
