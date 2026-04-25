import Foundation
import AVFoundation

@MainActor
final class AVAudioEnginePlaybackBackend: AudioPlaybackBackend {
    typealias AudioFileOpener = @MainActor (URL) throws -> AVAudioFile

    private let fileLoader: AudioFileLoading
    private let titleReader: AudioTitleReading
    private let fileManager: FileManager
    private let openAudioFile: AudioFileOpener

    private let engine = AVAudioEngine()
    private let playerNode = AVAudioPlayerNode()

    private var audioInfo: AudioInfo?
    private var tempFileURL: URL?
    private var scheduledFile: AVAudioFile?
    private var currentFrame: AVAudioFramePosition = 0
    private var scheduledStartFrame: AVAudioFramePosition = 0
    private var isPlaying = false
    private var scheduleGeneration = 0

    init(
        fileLoader: AudioFileLoading = SecurityScopedFileLoader(),
        titleReader: AudioTitleReading = AVAssetAudioTitleReader(),
        fileManager: FileManager = .default,
        openAudioFile: @escaping AudioFileOpener = { try AVAudioFile(forReading: $0) }
    ) {
        self.fileLoader = fileLoader
        self.titleReader = titleReader
        self.fileManager = fileManager
        self.openAudioFile = openAudioFile

        engine.attach(playerNode)
        engine.connect(playerNode, to: engine.mainMixerNode, format: nil)
        engine.prepare()
    }

    var hasLoadedItem: Bool { audioInfo != nil }
    var currentAudioInfo: AudioInfo? { audioInfo }

    func loadFile(from url: URL) async throws -> AudioInfo {
        stop()
        try removeTemporaryFile()

        let loadedFile = try await fileLoader.load(url: url)
        guard !Task.isCancelled else { throw CancellationError() }

        let tempURL = temporaryFileURL(forExtension: loadedFile.fileExtension)
        try loadedFile.data.write(to: tempURL, options: .atomic)

        let audioFile = try openAudioFile(tempURL)
        let sampleRate = audioFile.processingFormat.sampleRate
        let duration = sampleRate > 0 ? Double(audioFile.length) / sampleRate : 0
        let rawDisplayTitle = await titleReader.readDisplayTitle(
            from: url,
            fallbackFileName: loadedFile.fileName
        )

        let loadedAudioInfo = AudioInfo(
            fileName: loadedFile.fileName,
            displayTitle: Self.normalizedDisplayTitle(rawDisplayTitle, fallback: loadedFile.fileName),
            duration: duration,
            sampleRate: sampleRate
        )

        tempFileURL = tempURL
        scheduledFile = nil
        currentFrame = 0
        scheduledStartFrame = 0
        isPlaying = false
        audioInfo = loadedAudioInfo
        playerNode.volume = 1

        return loadedAudioInfo
    }

    func play(fromFinishedState: Bool) throws {
        guard let audioInfo else {
            throw PlaybackError.noFileLoaded
        }

        if fromFinishedState {
            currentFrame = 0
        }

        if !engine.isRunning {
            try engine.start()
        }

        try schedulePlayback(from: currentFrame, audioInfo: audioInfo)
        playerNode.play()
        isPlaying = true
    }

    func pause() throws {
        guard audioInfo != nil else {
            throw PlaybackError.noFileLoaded
        }

        updateCurrentFrameFromPlaybackClock()
        playerNode.pause()
        isPlaying = false
    }

    func stop() {
        scheduleGeneration += 1
        playerNode.stop()
        isPlaying = false
        currentFrame = 0
        scheduledStartFrame = 0
        scheduledFile = nil
    }

    func seek(to time: Double, audioInfo: AudioInfo) throws -> Double {
        let clampedTime = audioInfo.clampSeekTime(time)
        currentFrame = framePosition(for: clampedTime, sampleRate: audioInfo.sampleRate)

        guard isPlaying else {
            return clampedTime
        }

        try play(fromFinishedState: false)
        return clampedTime
    }

    func skipForward(from currentTime: Double, audioInfo: AudioInfo) throws -> Double {
        let newTime = audioInfo.skipForward(from: currentTime, by: 10)
        return try seek(to: newTime, audioInfo: audioInfo)
    }

    func skipBackward(from currentTime: Double, audioInfo: AudioInfo) throws -> Double {
        let newTime = audioInfo.skipBackward(from: currentTime, by: 10)
        return try seek(to: newTime, audioInfo: audioInfo)
    }

    func setVolume(_ volume: Double) {
        let clampedVolume = max(0, min(volume, 1))
        playerNode.volume = Float(clampedVolume)
    }

    func makeProgressStream(
        using tracker: PlaybackProgressTracking,
        updateInterval: TimeInterval
    ) -> AsyncStream<ProgressEvent> {
        _ = tracker
        let intervalNanoseconds = UInt64(max(updateInterval, 0.01) * 1_000_000_000)

        return AsyncStream { continuation in
            let generation = scheduleGeneration

            let task = Task { @MainActor [weak self] in
                guard let self else {
                    continuation.finish()
                    return
                }

                while !Task.isCancelled {
                    if generation != self.scheduleGeneration {
                        continuation.finish()
                        return
                    }

                    continuation.yield(.progress(self.currentTime))

                    if self.hasReachedEnd {
                        continuation.yield(.finished)
                        continuation.finish()
                        return
                    }

                    guard self.isPlaying else {
                        continuation.finish()
                        return
                    }

                    try? await Task.sleep(nanoseconds: intervalNanoseconds)
                }

                continuation.finish()
            }

            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    private var currentTime: Double {
        guard let audioInfo else { return 0 }

        let frame = min(currentPlaybackFrame, totalFrameCount(for: audioInfo))
        return min(Double(frame) / audioInfo.sampleRate, audioInfo.duration)
    }

    private var hasReachedEnd: Bool {
        guard let audioInfo else { return false }
        return currentPlaybackFrame >= totalFrameCount(for: audioInfo)
    }

    private var currentPlaybackFrame: AVAudioFramePosition {
        guard isPlaying,
              let nodeTime = playerNode.lastRenderTime,
              let playerTime = playerNode.playerTime(forNodeTime: nodeTime),
              let audioInfo else {
            return currentFrame
        }

        let elapsedFrames = AVAudioFramePosition(playerTime.sampleTime)
        return min(scheduledStartFrame + elapsedFrames, totalFrameCount(for: audioInfo))
    }

    private func schedulePlayback(from frame: AVAudioFramePosition, audioInfo: AudioInfo) throws {
        guard let tempFileURL else {
            throw PlaybackError.noFileLoaded
        }

        playerNode.stop()
        scheduleGeneration += 1

        do {
            let audioFile = try openAudioFile(tempFileURL)
            let remainingFrames = max(audioFile.length - frame, 0)
            let frameCount = AVAudioFrameCount(min(remainingFrames, AVAudioFramePosition(UInt32.max)))

            scheduledFile = audioFile
            scheduledStartFrame = frame
            if frameCount == 0 {
                currentFrame = totalFrameCount(for: audioInfo)
                isPlaying = false
                return
            }

            let generation = scheduleGeneration
            audioFile.framePosition = frame
            playerNode.scheduleSegment(
                audioFile,
                startingFrame: frame,
                frameCount: frameCount,
                at: nil
            ) { [weak self] in
                Task { @MainActor in
                    guard let self, generation == self.scheduleGeneration, let audioInfo = self.audioInfo else { return }
                    self.currentFrame = self.totalFrameCount(for: audioInfo)
                    self.isPlaying = false
                    self.scheduledStartFrame = self.currentFrame
                }
            }
        } catch {
            scheduledFile = nil
            scheduledStartFrame = frame
            isPlaying = false
            throw PlaybackError.playbackStartFailed
        }
    }

    private func updateCurrentFrameFromPlaybackClock() {
        currentFrame = currentPlaybackFrame
        scheduledStartFrame = currentFrame
    }

    private func framePosition(for time: Double, sampleRate: Double) -> AVAudioFramePosition {
        AVAudioFramePosition((time * sampleRate).rounded(.down))
    }

    private func totalFrameCount(for audioInfo: AudioInfo) -> AVAudioFramePosition {
        framePosition(for: audioInfo.duration, sampleRate: audioInfo.sampleRate)
    }

    private func temporaryFileURL(forExtension fileExtension: String) -> URL {
        let ext = fileExtension.isEmpty ? "tmp" : fileExtension
        return fileManager.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(ext)
    }

    private func removeTemporaryFile() throws {
        if let tempFileURL {
            try? fileManager.removeItem(at: tempFileURL)
            self.tempFileURL = nil
        }
    }

    private static func normalizedDisplayTitle(_ title: String?, fallback: String) -> String {
        guard let trimmedTitle = title?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmedTitle.isEmpty else {
            return fallback
        }
        return trimmedTitle
    }
}
