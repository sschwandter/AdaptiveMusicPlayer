import Testing
import Foundation
@testable import AdaptiveMusicPlayerCore

@Suite("LoadFileOperation Tests")
struct LoadFileOperationTests {
    @Test("Cancellation after metadata loading is not wrapped as a load failure")
    func cancellationAfterSessionReturnsPreservesCancellation() async {
        let session = GatedAudioSessionManager()
        let operation = LoadFileOperation(sessionManager: session)
        let task = Task {
            try await operation.execute(from: URL(fileURLWithPath: "/tmp/cancelled.wav"))
        }
        await session.waitUntilBlocked()
        task.cancel()
        await session.release()

        do {
            _ = try await task.value
            Issue.record("Expected loading cancellation")
        } catch let error as PlaybackError {
            #expect(error == .loadingCancelled)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }
}

private actor GatedAudioSessionManager: AudioSessionManaging {
    private var continuation: CheckedContinuation<Void, Never>?
    private var blockedWaiters: [CheckedContinuation<Void, Never>] = []

    func loadAudioData(from url: URL) async throws -> LoadedAudioData {
        await withCheckedContinuation {
            continuation = $0
            blockedWaiters.forEach { $0.resume() }
            blockedWaiters.removeAll()
        }
        // Metadata readers may return a fallback title even when cancelled.
        return LoadedAudioData(
            data: Data(),
            fileName: url.lastPathComponent,
            fileExtension: "wav",
            displayTitle: url.lastPathComponent,
            sampleRate: 44_100,
            duration: 1
        )
    }

    func waitUntilBlocked() async {
        guard continuation == nil else { return }
        await withCheckedContinuation { blockedWaiters.append($0) }
    }

    func release() {
        continuation?.resume()
        continuation = nil
    }
}
