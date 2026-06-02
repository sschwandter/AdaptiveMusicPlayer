import AdaptiveMusicPlayerCore
import Foundation

@MainActor
final class AudioPlayerHardwareMonitor {
    private let stateStore: AudioPlayerStateStore
    private let hardwareObserver: AudioHardwareObserving
    private let hardwareInfoProvider: AudioHardwareInfoProviding

    init(
        stateStore: AudioPlayerStateStore,
        hardwareObserver: AudioHardwareObserving,
        hardwareInfoProvider: AudioHardwareInfoProviding
    ) {
        self.stateStore = stateStore
        self.hardwareObserver = hardwareObserver
        self.hardwareInfoProvider = hardwareInfoProvider
    }

    /// Begin observing hardware changes.
    ///
    /// When `initialRefresh` is `true`, the monitor performs one refresh
    /// immediately after subscribing so the UI does not have to remember to
    /// call `refreshHardwareInfo()` itself. This keeps the "start observing
    /// and seed initial state" responsibility in one place.
    func startObserving(initialRefresh: Bool = true) {
        hardwareObserver.startObserving { [weak self] in
            Task { @MainActor [weak self] in
                await self?.refreshHardwareInfo()
            }
        }

        guard initialRefresh else { return }
        Task { @MainActor [weak self] in
            await self?.refreshHardwareInfo()
        }
    }

    func refreshHardwareInfo() async {
        let deviceInfo = await hardwareInfoProvider.getCurrentAudioDeviceInfo()
        stateStore.dispatch(.hardwareInfoChanged(deviceInfo))
    }
}
