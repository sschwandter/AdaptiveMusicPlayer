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

    func startObserving() {
        hardwareObserver.startObserving { [weak self] in
            Task { @MainActor [weak self] in
                await self?.refreshHardwareInfo()
            }
        }
    }

    func refreshHardwareInfo() async {
        let deviceInfo = await hardwareInfoProvider.getCurrentAudioDeviceInfo()
        stateStore.dispatch(.hardwareInfoChanged(deviceInfo))
    }
}
