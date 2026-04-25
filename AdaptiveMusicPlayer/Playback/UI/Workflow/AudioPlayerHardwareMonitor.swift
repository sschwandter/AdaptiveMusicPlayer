import Foundation

@MainActor
final class AudioPlayerHardwareMonitor {
    private enum Constants {
        static let refreshDebounceDelay: Duration = .milliseconds(150)
    }

    private let stateStore: AudioPlayerStateStore
    private let hardwareObserver: AudioHardwareObserving
    private let hardwareInfoProvider: AudioHardwareInfoProviding
    private var pendingRefreshTask: Task<Void, Never>?
    private var isObserving = false

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
        isObserving = true
        hardwareObserver.startObserving { [weak self] in
            Task { @MainActor [weak self] in
                self?.scheduleRefresh()
            }
        }
    }

    func stopObserving() {
        isObserving = false
        pendingRefreshTask?.cancel()
        pendingRefreshTask = nil
        hardwareObserver.stopObserving()
    }

    func refreshHardwareInfo() async {
        let deviceInfo = await hardwareInfoProvider.getCurrentAudioDeviceInfo()
        stateStore.dispatch(.hardwareInfoChanged(deviceInfo))
    }

    deinit {
        pendingRefreshTask?.cancel()
    }

    private func scheduleRefresh() {
        guard isObserving else { return }

        pendingRefreshTask?.cancel()
        pendingRefreshTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(for: Constants.refreshDebounceDelay)
            } catch {
                return
            }

            guard let self, self.isObserving else { return }

            await self.refreshHardwareInfo()
            self.pendingRefreshTask = nil
        }
    }
}
