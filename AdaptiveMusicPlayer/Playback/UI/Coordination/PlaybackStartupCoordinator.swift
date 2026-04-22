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

    private let latestStartup = LatestAsyncRequestCoordinator()

    var isStartingPlayback: Bool {
        latestStartup.hasActiveRun
    }

    func waitForCurrentStartup() async {
        await latestStartup.waitForCurrentRun()
    }

    func startPlayback(
        play: @escaping @MainActor () async throws -> AudioInfo,
        handleEvent: @escaping @MainActor (Event) async -> Void
    ) {
        guard latestStartup.startRunIfIdle(operation: { run in

            await handleEvent(.startupBegan)

            do {
                let audioInfo = try await play()

                guard run.isCurrent() else {
                    await handleEvent(.staleStartupFinished)
                    return
                }

                await handleEvent(.startupFinished(audioInfo: audioInfo))
            } catch is CancellationError {
                guard run.isCurrent() else { return }
                await handleEvent(.startupCancelled)
            } catch let error as PlaybackError {
                guard run.isCurrent() else { return }
                await handleEvent(.startupFailed(error))
            } catch {
                guard run.isCurrent() else { return }
                await handleEvent(.startupFailed(.notReady))
            }
        }) else { return }
    }

    @discardableResult
    func cancelStartup() -> Bool {
        latestStartup.cancelCurrentRun()
    }
}
