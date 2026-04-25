import Foundation
import AVFoundation

@MainActor
protocol AudioPlaybackBackend: AnyObject {
    var hasLoadedItem: Bool { get }
    var currentAudioInfo: AudioInfo? { get }

    func loadFile(from url: URL) async throws -> AudioInfo
    func play(fromFinishedState: Bool) throws
    func pause() throws
    func stop()
    func seek(to time: Double, audioInfo: AudioInfo) throws -> Double
    func skipForward(from currentTime: Double, audioInfo: AudioInfo) throws -> Double
    func skipBackward(from currentTime: Double, audioInfo: AudioInfo) throws -> Double
    func setVolume(_ volume: Double)
    func makeProgressStream(
        using tracker: PlaybackProgressTracking,
        updateInterval: TimeInterval
    ) -> AsyncStream<ProgressEvent>
}

@MainActor
final class AVAudioPlayerPlaybackBackend: AudioPlaybackBackend {
    private let loadFileOperation: LoadFileOperationProtocol
    private let playbackControlOperation: PlaybackControlOperationProtocol
    private let seekingOperation: SeekingOperationProtocol

    private var player: AVAudioPlayer?
    private var audioInfo: AudioInfo?

    init(
        loadFileOperation: LoadFileOperationProtocol = LoadFileOperation(),
        playbackControlOperation: PlaybackControlOperationProtocol = PlaybackControlOperation(),
        seekingOperation: SeekingOperationProtocol = SeekingOperation()
    ) {
        self.loadFileOperation = loadFileOperation
        self.playbackControlOperation = playbackControlOperation
        self.seekingOperation = seekingOperation
    }

    var hasLoadedItem: Bool { player != nil }
    var currentAudioInfo: AudioInfo? { audioInfo }

    func loadFile(from url: URL) async throws -> AudioInfo {
        let session = try await loadFileOperation.execute(from: url)
        let loadedAudioInfo = AudioInfo(
            fileName: session.fileName,
            displayTitle: session.displayTitle,
            duration: session.duration,
            sampleRate: session.sampleRate
        )

        player = session.player
        audioInfo = loadedAudioInfo
        return loadedAudioInfo
    }

    func play(fromFinishedState: Bool) throws {
        guard let player, let audioInfo else {
            throw PlaybackError.noFileLoaded
        }

        _ = try playbackControlOperation.play(
            player: player,
            audioInfo: audioInfo,
            isAtEnd: fromFinishedState
        )
    }

    func pause() throws {
        guard let player, let audioInfo else {
            throw PlaybackError.noFileLoaded
        }

        _ = try playbackControlOperation.pause(player: player, audioInfo: audioInfo)
    }

    func stop() {
        guard let player, let audioInfo else { return }
        _ = playbackControlOperation.stop(player: player, audioInfo: audioInfo)
    }

    func seek(to time: Double, audioInfo: AudioInfo) throws -> Double {
        guard let player else {
            throw PlaybackError.noFileLoaded
        }

        return try seekingOperation.seek(to: time, player: player, audioInfo: audioInfo)
    }

    func skipForward(from currentTime: Double, audioInfo: AudioInfo) throws -> Double {
        guard let player else {
            throw PlaybackError.noFileLoaded
        }

        return try seekingOperation.skipForward(from: currentTime, player: player, audioInfo: audioInfo)
    }

    func skipBackward(from currentTime: Double, audioInfo: AudioInfo) throws -> Double {
        guard let player else {
            throw PlaybackError.noFileLoaded
        }

        return try seekingOperation.skipBackward(from: currentTime, player: player, audioInfo: audioInfo)
    }

    func setVolume(_ volume: Double) {
        let clampedVolume = max(0, min(volume, 1))
        player?.volume = Float(clampedVolume)
    }

    func makeProgressStream(
        using tracker: PlaybackProgressTracking,
        updateInterval: TimeInterval
    ) -> AsyncStream<ProgressEvent> {
        AsyncStream { continuation in
            let task = Task { @MainActor in
                await tracker.trackProgressStream(
                    player: self.player,
                    updateInterval: updateInterval,
                    continuation: continuation
                )
            }

            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }
}
