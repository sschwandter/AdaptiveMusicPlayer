import AdaptiveMusicPlayerCore
import Foundation

@MainActor
final class LatestAsyncRequestCoordinator {
    struct Run {
        fileprivate let generation: Int
        private let isCurrentCheck: @MainActor () -> Bool

        fileprivate init(
            generation: Int,
            isCurrentCheck: @escaping @MainActor () -> Bool
        ) {
            self.generation = generation
            self.isCurrentCheck = isCurrentCheck
        }

        @MainActor
        func isCurrent() -> Bool {
            isCurrentCheck() && !Task.isCancelled
        }

        @MainActor
        func ensureCurrent() throws {
            guard isCurrent() else {
                throw CancellationError()
            }
        }
    }

    private var task: Task<Void, Never>?
    private var activeGeneration: Int?
    private var generation: Int = 0

    var hasActiveRun: Bool {
        task != nil
    }

    func waitForCurrentRun() async {
        await task?.value
    }

    @discardableResult
    func cancelCurrentRun() -> Bool {
        guard task != nil else { return false }

        generation += 1
        activeGeneration = nil
        task?.cancel()
        task = nil
        return true
    }

    func replaceCurrentRun(
        operation: @escaping @MainActor (Run) async -> Void
    ) {
        _ = cancelCurrentRun()
        startRun(operation: operation)
    }

    @discardableResult
    func startRunIfIdle(
        operation: @escaping @MainActor (Run) async -> Void
    ) -> Bool {
        guard task == nil else { return false }
        startRun(operation: operation)
        return true
    }

    private func startRun(
        operation: @escaping @MainActor (Run) async -> Void
    ) {
        generation += 1
        let runGeneration = generation
        activeGeneration = runGeneration

        let run = Run(
            generation: runGeneration,
            isCurrentCheck: { [weak self] in
                self?.activeGeneration == runGeneration
            }
        )

        task = Task { @MainActor [weak self] in
            guard let self else { return }

            defer {
                if self.activeGeneration == runGeneration {
                    self.activeGeneration = nil
                    self.task = nil
                }
            }

            await operation(run)
        }
    }
}
