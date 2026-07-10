import Foundation
@preconcurrency import AVFoundation

/// Events emitted during playback progress tracking
public enum ProgressEvent: Sendable {
    case progress(Double)  // Current playback time
    case finished          // Playback reached end
}

/// Events emitted by the engine to notify observers of internal changes
public enum EngineEvent: Sendable {
    case stateChanged(EnginePlaybackState)
    case volumeChanged(Double)
}

/// Stateful playback coordinator around AVAudioPlayer
/// Owns playback state and delegates smaller operations to focused operation types
@MainActor
public final class AudioPlaybackEngine {
    private enum Constants {
        static let sampleRateTolerance: Double = 1.0
    }

    // MARK: - Properties

    private var playbackState: EnginePlaybackState = .idle {
        didSet {
            if playbackState != oldValue {
                emit(.stateChanged(playbackState))
            }
        }
    }
    private var player: AVAudioPlayer?
    private var playerGeneration = 0

    public let eventStream: AsyncStream<EngineEvent>
    private let eventContinuation: AsyncStream<EngineEvent>.Continuation

    private func emit(_ event: EngineEvent) {
        eventContinuation.yield(event)
    }

    // MARK: - Internal State Queries (for runtime coordination only)

    /// Returns whether the engine has an active player ready for playback.
    /// This is an internal runtime check, not the authoritative app state.
    public var hasActivePlayer: Bool { player != nil }

    /// Returns the current audio info if a file is loaded.
    public var currentAudioInfo: AudioInfo? { playbackState.audioInfo }

    /// Opaque identity of the currently loaded player. Playback startup
    /// captures this so a stale startup can stop only the player it actually
    /// started, never a newer startup's player. A counter rather than
    /// `ObjectIdentifier` because a deallocated player's address can be reused.
    public var currentPlayerGeneration: Int { playerGeneration }

    // MARK: - Dependencies

    private let loadFileOperation: LoadFileOperationProtocol
    private let playbackControlOperation: PlaybackControlOperationProtocol
    private let seekingOperation: SeekingOperationProtocol
    private let syncSampleRateOperation: SyncSampleRateOperationProtocol
    private let sampleRateManager: SampleRateManaging

    // MARK: - Initialization

    public init(
        loadFileOperation: LoadFileOperationProtocol? = nil,
        playbackControlOperation: PlaybackControlOperationProtocol = PlaybackControlOperation(),
        seekingOperation: SeekingOperationProtocol = SeekingOperation(),
        syncSampleRateOperation: SyncSampleRateOperationProtocol = SyncSampleRateOperation(),
        sampleRateManager: SampleRateManaging = CoreAudioSampleRateManager()
    ) {
        let (stream, continuation) = AsyncStream.makeStream(of: EngineEvent.self)
        self.eventStream = stream
        self.eventContinuation = continuation

        self.sampleRateManager = sampleRateManager
        self.loadFileOperation = loadFileOperation ?? LoadFileOperation(sessionManager: AudioSessionManager())
        self.playbackControlOperation = playbackControlOperation
        self.seekingOperation = seekingOperation
        self.syncSampleRateOperation = syncSampleRateOperation
    }

    // MARK: - File Loading

    /// Move the engine into a loading state before async file work begins.
    public func beginLoading() -> AudioInfo? {
        let preservedAudioInfo = playbackState.audioInfo
        if let player {
            player.stop()
            player.currentTime = 0
        }
        playbackState = .loading(preservedAudioInfo)
        return preservedAudioInfo
    }

    /// Load an audio file and prepare for playback
    public func loadFile(from url: URL) async throws -> AudioInfo {
        playbackState = .loading(playbackState.audioInfo)

        do {
            let audioData = try await loadAudioDataOffMainActor(from: url)

            try Task.checkCancellation()

            // Create AVAudioPlayer on @MainActor from the Sendable audio data.
            // Do not prepare the player yet: playback startup may first switch the
            // hardware sample rate, and preparing before that switch can leave the
            // underlying AudioQueue tied to a stale device configuration.
            let newPlayer = try AVAudioPlayer(data: audioData.data, fileTypeHint: audioData.fileExtension)

            let audioInfo = AudioInfo(
                fileName: audioData.fileName,
                displayTitle: audioData.displayTitle,
                duration: audioData.duration,
                sampleRate: audioData.sampleRate
            )

            player = newPlayer
            playerGeneration += 1
            playbackState = .ready(audioInfo)

            return audioInfo

        } catch is CancellationError {
            // Propagate cooperative cancellation as a plain `CancellationError`
            // so the load coordinator can route it through its cancellation
            // branch. Translating it here into `PlaybackError.loadingCancelled`
            // would cause the controller to show it as a user-facing error.
            playbackState = stateAfterCancelledLoad()
            throw CancellationError()
        } catch let error as PlaybackError {
            // The load pipeline (`LoadFileOperation`) translates inner
            // `CancellationError` into `PlaybackError.loadingCancelled`. Surface
            // that variant as a plain cancellation too, for the same reason as
            // above: the user did not actually fail to load the file, the load
            // was cancelled.
            if case .loadingCancelled = error {
                playbackState = stateAfterCancelledLoad()
                throw CancellationError()
            }
            playbackState = stateAfterFailedLoad(error)
            throw error
        } catch {
            let playbackError = PlaybackError.loadFailed(error.localizedDescription)
            playbackState = stateAfterFailedLoad(playbackError)
            throw playbackError
        }
    }

    private func loadAudioDataOffMainActor(from url: URL) async throws -> LoadedAudioData {
        let loadFileOperation = self.loadFileOperation
        let loadTask = Task.detached(priority: .userInitiated) {
            try await loadFileOperation.execute(from: url)
        }

        return try await withTaskCancellationHandler {
            try await loadTask.value
        } onCancel: {
            loadTask.cancel()
        }
    }

    // MARK: - Playback Control

    /// Start or resume playback
    public func play() async throws -> AudioInfo {
        guard let player = player else {
            throw PlaybackError.noFileLoaded
        }
        guard let requestedAudioInfo = playbackState.audioInfo else {
            throw PlaybackError.noFileLoaded
        }

        let targetSampleRate = requestedAudioInfo.sampleRate
        if targetSampleRate > 0 {
            let currentSampleRate = await getCurrentHardwareSampleRate()
            if currentSampleRate <= 0 ||
                abs(currentSampleRate - targetSampleRate) > Constants.sampleRateTolerance
            {
                do {
                    try await syncSampleRateOperation.execute(audioInfo: requestedAudioInfo, sampleRateManager: sampleRateManager)
                } catch {
                    // Playback should still start even if the device refuses the requested rate.
                }
            }
        }

        try Task.checkCancellation()
        // The re-entrancy check guards against the case where a newer load
        // replaced `self.player` (and/or `playbackState.audioInfo`) while we
        // were awaiting the sample-rate switch. If that happened, this
        // `play()` call refers to a track the user no longer wants, so we
        // bail out with `CancellationError` instead of starting playback on
        // a stale player.
        guard self.player === player, self.playbackState.audioInfo == requestedAudioInfo else {
            throw CancellationError()
        }

        let isAtEnd = if case .finished = playbackState { true } else { false }
        playbackState = try playbackControlOperation.play(player: player, audioInfo: requestedAudioInfo, isAtEnd: isAtEnd)
        return requestedAudioInfo
    }

    /// Pause playback
    public func pause() throws -> AudioInfo {
        guard let player = player else {
            throw PlaybackError.noFileLoaded
        }
        guard let audioInfo = playbackState.audioInfo else {
            throw PlaybackError.noFileLoaded
        }

        playbackState = try playbackControlOperation.pause(player: player, audioInfo: audioInfo)
        return audioInfo
    }

    /// Stop playback and reset to beginning
    public func stop() -> AudioInfo? {
        guard let player = player else { return nil }
        guard let audioInfo = playbackState.audioInfo else { return nil }

        playbackState = playbackControlOperation.stop(player: player, audioInfo: audioInfo)
        return audioInfo
    }

    /// Stop playback only if `generation` still identifies the current player.
    /// Returns nil without touching playback when a newer load has replaced
    /// the player (the replaced player was already stopped by `beginLoading`).
    @discardableResult
    public func stop(ifCurrentPlayerIs generation: Int) -> AudioInfo? {
        guard generation == playerGeneration else { return nil }
        return stop()
    }

    /// Mark playback as finished
    public func markFinished() -> AudioInfo? {
        guard let audioInfo = playbackState.audioInfo else { return nil }
        playbackState = .finished(audioInfo)
        return audioInfo
    }

    // MARK: - Seeking

    /// Seek to a specific time
    /// - Parameter time: Target time in seconds
    /// - Returns: Actual time seeked to (clamped to valid range)
    public func seek(to time: Double) throws -> Double {
        guard let player = player else {
            throw PlaybackError.noFileLoaded
        }
        guard let audioInfo = playbackState.audioInfo else {
            throw PlaybackError.noFileLoaded
        }

        return try seekingOperation.seek(to: time, player: player, audioInfo: audioInfo)
    }

    /// Skip forward by the configured interval
    /// - Parameter currentTime: Current playback time
    /// - Returns: New time after skipping
    public func skipForward(from currentTime: Double) throws -> Double {
        guard let player = player else {
            throw PlaybackError.noFileLoaded
        }
        guard let audioInfo = playbackState.audioInfo else {
            throw PlaybackError.noFileLoaded
        }

        return try seekingOperation.skipForward(from: currentTime, player: player, audioInfo: audioInfo)
    }

    /// Skip backward by the configured interval
    /// - Parameter currentTime: Current playback time
    /// - Returns: New time after skipping
    public func skipBackward(from currentTime: Double) throws -> Double {
        guard let player = player else {
            throw PlaybackError.noFileLoaded
        }
        guard let audioInfo = playbackState.audioInfo else {
            throw PlaybackError.noFileLoaded
        }

        return try seekingOperation.skipBackward(from: currentTime, player: player, audioInfo: audioInfo)
    }

    // MARK: - Volume Control

    /// Set playback volume
    /// - Parameter volume: Volume level (0.0 to 1.0)
    public func setVolume(_ volume: Double) {
        let clampedVolume = max(0, min(volume, 1))
        player?.volume = Float(clampedVolume)
        emit(.volumeChanged(clampedVolume))
    }
    // MARK: - Hardware Info

    /// Get current hardware sample rate
    public func getCurrentHardwareSampleRate() async -> Double {
        await sampleRateManager.getCurrentSampleRate() ?? 0
    }

    /// Get current output-device diagnostics
    public func getCurrentAudioDeviceInfo() async -> AudioDeviceInfo? {
        await sampleRateManager.getCurrentDeviceInfo()
    }

    // MARK: - Progress Tracking

    /// Returns raw progress events for the current playback.
    public func trackProgress(
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

    private func stateAfterFailedLoad(_ error: PlaybackError) -> EnginePlaybackState {
        if let preservedAudioInfo = playbackState.audioInfo, player != nil {
            return .ready(preservedAudioInfo)
        }

        return .error(error)
    }

    /// A cancelled load almost always means a newer load replaced this one.
    /// Dropping to `.idle` here would emit a state change that wipes the
    /// "previous track stays visible while loading" presentation the replacing
    /// load just set up, so restore the preserved track instead. If a newer
    /// load has already moved the engine past `.loading`, leave its state
    /// untouched.
    private func stateAfterCancelledLoad() -> EnginePlaybackState {
        guard case .loading(let preservedAudioInfo) = playbackState else {
            return playbackState
        }

        if let preservedAudioInfo, player != nil {
            return .ready(preservedAudioInfo)
        }

        return .idle
    }
}
