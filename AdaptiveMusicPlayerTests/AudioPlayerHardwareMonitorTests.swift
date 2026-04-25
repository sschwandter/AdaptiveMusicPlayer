import Testing
import Foundation
@testable import AdaptiveMusicPlayer

@Suite("AudioPlayerHardwareMonitor Tests")
@MainActor
struct AudioPlayerHardwareMonitorTests {
    @Test("observer callback bursts are coalesced into one hardware refresh")
    func coalescesObserverRefreshBursts() async throws {
        let stateStore = AudioPlayerStateStore()
        let observer = RecordingAudioHardwareObserver()
        let provider = CountingAudioHardwareInfoProvider(
            deviceInfo: AudioDeviceInfo(
                name: "Burst DAC",
                currentSampleRate: 48_000,
                supportedSampleRates: [44_100, 48_000]
            )
        )
        let monitor = AudioPlayerHardwareMonitor(
            stateStore: stateStore,
            hardwareObserver: observer,
            hardwareInfoProvider: provider
        )

        monitor.startObserving()

        observer.triggerChange()
        observer.triggerChange()
        observer.triggerChange()

        try await waitUntil(timeout: .milliseconds(500)) {
            await provider.refreshCount() == 1
        }

        #expect(await provider.refreshCount() == 1)
        #expect(stateStore.hardwareDeviceName == "Burst DAC")
        #expect(stateStore.hardwareSampleRate == 48_000)
    }

    @Test("stopping observation cancels a pending debounced refresh")
    func stopObservingCancelsPendingRefresh() async throws {
        let stateStore = AudioPlayerStateStore()
        let observer = RecordingAudioHardwareObserver()
        let provider = CountingAudioHardwareInfoProvider(
            deviceInfo: AudioDeviceInfo(
                name: "Quiet DAC",
                currentSampleRate: 44_100,
                supportedSampleRates: [44_100]
            )
        )
        let monitor = AudioPlayerHardwareMonitor(
            stateStore: stateStore,
            hardwareObserver: observer,
            hardwareInfoProvider: provider
        )

        monitor.startObserving()
        observer.triggerChange()
        monitor.stopObserving()

        try await Task.sleep(for: .milliseconds(250))

        #expect(await provider.refreshCount() == 0)
        #expect(stateStore.hardwareDeviceName.isEmpty)
    }
}

@MainActor
private final class RecordingAudioHardwareObserver: AudioHardwareObserving {
    private var onChange: (@Sendable () -> Void)?

    func startObserving(onChange: @escaping @Sendable () -> Void) {
        self.onChange = onChange
    }

    func stopObserving() {
        onChange = nil
    }

    func triggerChange() {
        onChange?()
    }
}

private actor CountingAudioHardwareInfoProvider: AudioHardwareInfoProviding {
    private let deviceInfo: AudioDeviceInfo?
    private var count = 0

    init(deviceInfo: AudioDeviceInfo?) {
        self.deviceInfo = deviceInfo
    }

    func getCurrentAudioDeviceInfo() async -> AudioDeviceInfo? {
        count += 1
        return deviceInfo
    }

    func refreshCount() -> Int {
        count
    }
}

@MainActor
private func waitUntil(
    timeout: Duration,
    condition: @escaping () async -> Bool
) async throws {
    let deadline = ContinuousClock.now + timeout

    while !(await condition()) {
        if ContinuousClock.now >= deadline {
            Issue.record("Timed out waiting for condition.")
            return
        }

        try await Task.sleep(for: .milliseconds(10))
    }
}
