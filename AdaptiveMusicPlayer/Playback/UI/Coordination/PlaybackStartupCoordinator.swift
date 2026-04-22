import Foundation

@MainActor
final class PlaybackStartupCoordinator {
    enum Event {
        case startupBegan
        case startupCancelled
        case startupFinished(audioInfo: AudioInfo)
        case startupFailed(PlaybackError)
        case staleStartupFinished
    }

    private var playbackStartupTask: Task<Void, Never>?
    private var activePlaybackStartupGeneration: Int?
    private var playbackStartupGeneration: Int = 0

    var isStartingPlayback: Bool {
        playbackStartupTask != nil
    }

    func waitForCurrentStartup() async {
        await playbackStartupTask?.value
    }

    func startPlayback(
        play: @escaping @MainActor () async throws -> AudioInfo,
        handleEvent: @escaping @MainActor (Event) async -> Void
    ) {
        guard playbackStartupTask == nil else { return }

        playbackStartupGeneration += 1
        let generation = playbackStartupGeneration
        activePlaybackStartupGeneration = generation

        Task { @MainActor in
            await handleEvent(.startupBegan)
        }

        playbackStartupTask = Task { @MainActor [weak self] in
            guard let self else { return }

            defer {
                if self.activePlaybackStartupGeneration == generation {
                    self.activePlaybackStartupGeneration = nil
                    self.playbackStartupTask = nil
                }
            }

            do {
                let audioInfo = try await play()

                guard self.playbackStartupRemainsCurrent(generation) else {
                    await handleEvent(.staleStartupFinished)
                    return
                }

                await handleEvent(.startupFinished(audioInfo: audioInfo))
            } catch is CancellationError {
                guard self.playbackStartupRemainsCurrent(generation) else { return }
                await handleEvent(.startupCancelled)
            } catch let error as PlaybackError {
                guard self.playbackStartupRemainsCurrent(generation) else { return }
                await handleEvent(.startupFailed(error))
            } catch {
                guard self.playbackStartupRemainsCurrent(generation) else { return }
                await handleEvent(.startupFailed(.notReady))
            }
        }
    }

    @discardableResult
    func cancelStartup() -> Bool {
        guard playbackStartupTask != nil else { return false }

        playbackStartupGeneration += 1
        activePlaybackStartupGeneration = nil
        playbackStartupTask?.cancel()
        playbackStartupTask = nil
        return true
    }

    private func playbackStartupRemainsCurrent(_ generation: Int) -> Bool {
        activePlaybackStartupGeneration == generation && !Task.isCancelled
    }
}
