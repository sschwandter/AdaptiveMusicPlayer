import Foundation

/// Protocol for synchronizing hardware sample rate to match audio file
public protocol SyncSampleRateOperationProtocol: Sendable {
    /// Synchronize hardware sample rate to match the current audio file
    /// - Parameters:
    ///   - audioInfo: Audio file information containing the target sample rate
    ///   - sampleRateManager: Manager for hardware sample rate control
    /// - Throws: PlaybackError if sync fails
    func execute(audioInfo: AudioInfo, sampleRateManager: SampleRateManaging) async throws
}

/// Operation for fixing sample rate mismatches
/// Sets hardware sample rate to match the audio file's native rate for bit-perfect playback
public final class SyncSampleRateOperation: SyncSampleRateOperationProtocol {

    public init() {}

    public func execute(audioInfo: AudioInfo, sampleRateManager: SampleRateManaging) async throws {
        try await sampleRateManager.setSampleRate(audioInfo.sampleRate)
    }
}
