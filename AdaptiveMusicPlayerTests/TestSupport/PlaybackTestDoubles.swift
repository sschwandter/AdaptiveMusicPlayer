import Testing
import AVFoundation
import Foundation
@testable import AdaptiveMusicPlayerCore
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

@MainActor
final class StubAudioHardwareObserver: AudioHardwareObserving {
    func startObserving(onChange: @escaping @Sendable () -> Void) {}
    func stopObserving() {}
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

actor StubSampleRateManager: SampleRateManaging {
    func getCurrentSampleRate() async -> Double? { 44_100 }
    func getCurrentOutputDeviceName() async -> String? { "Test Device" }
    func setSampleRate(_ rate: Double) async throws {}
    func getSupportedSampleRates() async -> [Double] { [44_100] }
    func getCurrentDeviceInfo() async -> AudioDeviceInfo? {
        AudioDeviceInfo(name: "Test Device", currentSampleRate: 44_100, supportedSampleRates: [44_100])
    }
}

actor RecordingSampleRateManager: SampleRateManaging {
    let currentSampleRate: Double
    private var requestedSampleRates: [Double] = []

    init(currentSampleRate: Double) {
        self.currentSampleRate = currentSampleRate
    }

    func getCurrentSampleRate() async -> Double? { currentSampleRate }
    func getCurrentOutputDeviceName() async -> String? { "Test Device" }
    func setSampleRate(_ rate: Double) async throws {
        requestedSampleRates.append(rate)
    }
    func getSupportedSampleRates() async -> [Double] { [44_100, 96_000] }
    func getCurrentDeviceInfo() async -> AudioDeviceInfo? {
        AudioDeviceInfo(name: "Test Device", currentSampleRate: currentSampleRate, supportedSampleRates: [44_100, 96_000])
    }

    func recordedSampleRates() -> [Double] {
        requestedSampleRates
    }
}

final class RecordingFinderItemRevealer: FinderItemRevealing, @unchecked Sendable {
    private(set) var revealedURLs: [URL] = []

    func revealItem(at url: URL) {
        revealedURLs.append(url)
    }
}

@MainActor
final class RecordingPlaybackProgressTracker: PlaybackProgressTracking {
    private(set) var trackedPlayer: AVAudioPlayer?
    private(set) var updateInterval: TimeInterval?
    private(set) var stopCallCount = 0
    private(set) var streamContinuation: AsyncStream<ProgressEvent>.Continuation?

    func startTracking(
        player: AVAudioPlayer,
        updateInterval: TimeInterval,
        onProgressUpdate: @escaping (Double) -> Void,
        onPlaybackFinished: @escaping () -> Void,
        onPeriodicUpdate: @escaping () -> Void
    ) {
        trackedPlayer = player
        self.updateInterval = updateInterval
    }

    func stopTracking() {
        stopCallCount += 1
    }

    func trackProgressStream(
        player: AVAudioPlayer?,
        updateInterval: TimeInterval,
        continuation: AsyncStream<ProgressEvent>.Continuation
    ) async {
        trackedPlayer = player
        self.updateInterval = updateInterval
        streamContinuation = continuation
        
        // Keep the stream alive until cancelled
        while !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(100))
        }
        
        continuation.finish()
    }
}

struct StubLoadFileOperation: LoadFileOperationProtocol, @unchecked Sendable {
    let sampleRate: Double
    let displayTitle: String?

    init(sampleRate: Double, player: AVAudioPlayer? = nil, displayTitle: String? = nil) {
        self.sampleRate = sampleRate
        self.displayTitle = displayTitle
    }

    func execute(from url: URL) async throws -> LoadedAudioData {
        LoadedAudioData(
            data: WaveData.make(),
            fileName: url.lastPathComponent,
            fileExtension: url.pathExtension.isEmpty ? "wav" : url.pathExtension,
            displayTitle: displayTitle ?? url.lastPathComponent,
            sampleRate: sampleRate,
            duration: 1
        )
    }
}

struct RoutingStubLoadFileOperation: LoadFileOperationProtocol, @unchecked Sendable {
    let dataByURL: [URL: LoadedAudioData]

    init(sessionsByURL: [URL: AudioSession]) {
        self.dataByURL = Dictionary(
            uniqueKeysWithValues: sessionsByURL.map { url, session in
                (canonicalTestFileURL(url), LoadedAudioData(
                    data: WaveData.make(),
                    fileName: session.fileName,
                    fileExtension: "wav",
                    displayTitle: session.displayTitle,
                    sampleRate: session.sampleRate,
                    duration: session.duration
                ))
            }
        )
    }

    func execute(from url: URL) async throws -> LoadedAudioData {
        guard let data = dataByURL[canonicalTestFileURL(url)] else {
            throw PlaybackError.loadFailed("Missing stub data for \(url.path)")
        }
        return data
    }
}

struct FailingPlaybackControlOperation: PlaybackControlOperationProtocol {
    func play(player: AVAudioPlayer, audioInfo: AudioInfo, isAtEnd: Bool) throws -> EnginePlaybackState {
        throw PlaybackError.playbackStartFailed
    }
    func pause(player: AVAudioPlayer, audioInfo: AudioInfo) throws -> EnginePlaybackState {
        throw PlaybackError.notPlaying
    }
    func stop(player: AVAudioPlayer, audioInfo: AudioInfo) -> EnginePlaybackState {
        .ready(audioInfo)
    }
}

struct DelayedSyncSampleRateOperation: SyncSampleRateOperationProtocol {
    let delay: Duration

    func execute(audioInfo: AudioInfo, sampleRateManager: SampleRateManaging) async throws {
        try await Task.sleep(for: delay)
        try Task.checkCancellation()
        try await sampleRateManager.setSampleRate(audioInfo.sampleRate)
    }
}

struct DelayedFolderScanner: AudioPlaylistFolderScanning {
    let delay: TimeInterval
    let tracks: [URL]

    func scan(folderURL: URL) async throws -> [URL] {
        try await Task.sleep(for: .seconds(delay))
        try Task.checkCancellation()
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
