import Foundation
import Testing
@testable import AdaptiveMusicPlayer

@Suite("LatestAsyncRequestCoordinator Tests", .serialized)
@MainActor
struct LatestAsyncRequestCoordinatorTests {
    @Test("replaceCurrentRun keeps only the latest run current")
    func replaceCurrentRun() async throws {
        let coordinator = LatestAsyncRequestCoordinator()
        let recorder = LatestRunRecorder()

        coordinator.replaceCurrentRun { run in
            await recorder.record("first-start")
            do {
                try await Task.sleep(for: .milliseconds(150))
            } catch is CancellationError {
                await recorder.record("first-cancelled")
            } catch {
            }

            if run.isCurrent() {
                await recorder.record("first-current")
            } else {
                await recorder.record("first-stale")
            }
        }

        coordinator.replaceCurrentRun { run in
            await recorder.record("second-start")
            if run.isCurrent() {
                await recorder.record("second-current")
            }
        }

        await coordinator.waitForCurrentRun()
        try await Task.sleep(for: .milliseconds(200))

        #expect(await recorder.events() == [
            "first-start",
            "second-start",
            "second-current",
            "first-cancelled",
            "first-stale"
        ])
    }

    @Test("startRunIfIdle refuses a second run while one is active")
    func startRunIfIdle() async throws {
        let coordinator = LatestAsyncRequestCoordinator()
        let recorder = LatestRunRecorder()

        #expect(coordinator.startRunIfIdle { _ in
            await recorder.record("first")
            do {
                try await Task.sleep(for: .milliseconds(150))
            } catch {
            }
        })

        #expect(!coordinator.startRunIfIdle { _ in
            await recorder.record("second")
        })

        await coordinator.waitForCurrentRun()

        #expect(await recorder.events() == ["first"])
    }

    @Test("cancelCurrentRun clears active state")
    func cancelCurrentRun() async throws {
        let coordinator = LatestAsyncRequestCoordinator()
        let recorder = LatestRunRecorder()

        _ = coordinator.startRunIfIdle { run in
            await recorder.record("started")
            do {
                try await Task.sleep(for: .milliseconds(150))
            } catch is CancellationError {
                await recorder.record("cancelled")
            } catch {
            }

            #expect(!run.isCurrent())
        }

        #expect(coordinator.hasActiveRun)
        #expect(coordinator.cancelCurrentRun())
        #expect(!coordinator.hasActiveRun)
        #expect(!coordinator.cancelCurrentRun())

        await coordinator.waitForCurrentRun()
        try await Task.sleep(for: .milliseconds(50))

        #expect(await recorder.events() == ["started", "cancelled"])
    }
}

actor LatestRunRecorder {
    private var storage: [String] = []

    func record(_ event: String) {
        storage.append(event)
    }

    func events() -> [String] {
        storage
    }
}
