import Testing
import AVFoundation
import Foundation
@testable import AdaptiveMusicPlayer

final class StubAudioPlayer: AVAudioPlayer {
    var playResult: Bool
    var playCallCount = 0

    init(playResult: Bool = true) throws {
        self.playResult = playResult
        try super.init(data: WaveData.make(), fileTypeHint: "wav")
    }

    override func play() -> Bool {
        playCallCount += 1
        return playResult
    }

    override func stop() {
        super.stop()
        currentTime = 0
    }
}

final class StubAudioHardwareObserver: AudioHardwareObserving {
    nonisolated func startObserving(onChange: @escaping @Sendable () -> Void) {}
    nonisolated func stopObserving() {}
}

struct StubAudioHardwareInfoProvider: AudioHardwareInfoProviding {
    let deviceInfo: AudioDeviceInfo?

    init(deviceInfo: AudioDeviceInfo? = AudioDeviceInfo(
        name: "Test Device",
        currentSampleRate: 44_100,
        supportedSampleRates: [44_100]
    )) {
        self.deviceInfo = deviceInfo
    }

    func getCurrentAudioDeviceInfo() async -> AudioDeviceInfo? {
        deviceInfo
    }
}

struct StubSampleRateManager: SampleRateManaging {
    nonisolated func getCurrentSampleRate() -> Double? { 44_100 }
    nonisolated func getCurrentOutputDeviceName() -> String? { "Test Device" }
    nonisolated func setSampleRate(_ rate: Double) throws {}
    nonisolated func getSupportedSampleRates() -> [Double] { [44_100] }
    nonisolated func getCurrentDeviceInfo() -> AudioDeviceInfo? {
        AudioDeviceInfo(name: "Test Device", currentSampleRate: 44_100, supportedSampleRates: [44_100])
    }
}

final class RecordingSampleRateManager: SampleRateManaging, @unchecked Sendable {
    let currentSampleRate: Double
    private(set) var requestedSampleRates: [Double] = []

    init(currentSampleRate: Double) {
        self.currentSampleRate = currentSampleRate
    }

    nonisolated func getCurrentSampleRate() -> Double? { currentSampleRate }
    nonisolated func getCurrentOutputDeviceName() -> String? { "Test Device" }
    func setSampleRate(_ rate: Double) throws {
        requestedSampleRates.append(rate)
    }
    nonisolated func getSupportedSampleRates() -> [Double] { [44_100, 96_000] }
    nonisolated func getCurrentDeviceInfo() -> AudioDeviceInfo? {
        AudioDeviceInfo(name: "Test Device", currentSampleRate: currentSampleRate, supportedSampleRates: [44_100, 96_000])
    }
}

struct StubLoadFileUseCase: LoadFileUseCaseProtocol, @unchecked Sendable {
    let sampleRate: Double
    let player: AVAudioPlayer
    let displayTitle: String?

    init(sampleRate: Double, player: AVAudioPlayer? = nil, displayTitle: String? = nil) {
        self.sampleRate = sampleRate
        self.player = player ?? (try! StubAudioPlayer())
        self.displayTitle = displayTitle
    }

    func execute(from url: URL) async throws -> AudioSession {
        AudioSession(
            player: player,
            fileName: url.lastPathComponent,
            displayTitle: displayTitle ?? url.lastPathComponent,
            sampleRate: sampleRate,
            duration: 1
        )
    }
}

struct RoutingStubLoadFileUseCase: LoadFileUseCaseProtocol, @unchecked Sendable {
    let sessionsByURL: [URL: AudioSession]

    init(sessionsByURL: [URL: AudioSession]) {
        self.sessionsByURL = Dictionary(
            uniqueKeysWithValues: sessionsByURL.map { (canonicalTestFileURL($0.key), $0.value) }
        )
    }

    func execute(from url: URL) async throws -> AudioSession {
        guard let session = sessionsByURL[canonicalTestFileURL(url)] else {
            throw PlaybackError.loadFailed("Missing stub session for \(url.path)")
        }
        return session
    }
}

struct DelayedSyncSampleRateUseCase: SyncSampleRateUseCaseProtocol {
    let delay: Duration

    func execute(state: PlaybackState, sampleRateManager: SampleRateManaging) async throws {
        try await Task.sleep(for: delay)
        try Task.checkCancellation()
        guard let audioInfo = state.audioInfo else {
            throw PlaybackError.noFileLoaded
        }
        try sampleRateManager.setSampleRate(audioInfo.sampleRate)
    }
}

struct DelayedFolderScanner: AudioPlaylistFolderScanning {
    let delay: TimeInterval
    let tracks: [URL]

    nonisolated func scan(folderURL: URL) throws -> [URL] {
        Thread.sleep(forTimeInterval: delay)
        return tracks
    }
}

struct StubAudioFileLoader: AudioFileLoading {
    let data: Data
    let fileName: String
    let fileExtension: String

    init(data: Data = WaveData.make(), fileName: String, fileExtension: String = "wav") {
        self.data = data
        self.fileName = fileName
        self.fileExtension = fileExtension
    }

    func load(url: URL) async throws -> LoadedAudioFile {
        LoadedAudioFile(data: data, fileName: fileName, fileExtension: fileExtension)
    }
}

struct StubAudioTitleReader: AudioTitleReading {
    let title: String?

    func readDisplayTitle(from url: URL, fallbackFileName: String) async -> String {
        guard let title else { return fallbackFileName }
        return title
    }
}
