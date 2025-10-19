import Foundation

/// Protocol for synchronizing hardware sample rate to match audio file
protocol SyncSampleRateUseCaseProtocol: Sendable {
    /// Synchronize hardware sample rate to match the current audio file
    /// - Parameters:
    ///   - state: Current playback state (must have audioInfo)
    ///   - sampleRateManager: Manager for hardware sample rate control
    /// - Throws: PlaybackError if no file is loaded or sync fails
    func execute(state: PlaybackState, sampleRateManager: SampleRateManaging) throws
}

/// Use case for fixing sample rate mismatches
/// Sets hardware sample rate to match the audio file's native rate for bit-perfect playback
final class SyncSampleRateUseCase: SyncSampleRateUseCaseProtocol {

    func execute(state: PlaybackState, sampleRateManager: SampleRateManaging) throws {
        guard let audioInfo = state.audioInfo else {
            throw PlaybackError.noFileLoaded
        }

        try sampleRateManager.setSampleRate(audioInfo.sampleRate)
    }
}
