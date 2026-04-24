import Foundation

@MainActor
final class AudioPlayerLoadCoordinator {
    enum Event {
        case scanningFolderStarted
        case trackLoadingStarted(PlaylistSession)
        case playlistSessionUpdated(PlaylistSession)
        case trackLoaded(
            url: URL,
            audioInfo: AudioInfo,
            autoplayOnSuccess: Bool
        )
        case cancelled
        case failed(PlaybackError)
    }

    private let folderScanner: AudioPlaylistFolderScanning
    private let latestLoad = LatestAsyncRequestCoordinator()

    init(folderScanner: AudioPlaylistFolderScanning = AudioPlaylistFolderScanner()) {
        self.folderScanner = folderScanner
    }

    func waitForCurrentLoad() async {
        await latestLoad.waitForCurrentRun()
    }

    func loadFile(
        url: URL,
        playlistSession: PlaylistSession,
        importerDismissalDelay: Duration = .zero,
        autoplayOnSuccess: Bool = false,
        loadTrack: @escaping @MainActor (URL) async throws -> AudioInfo,
        handleEvent: @escaping @MainActor (Event) async -> Void
    ) {
        startNewLoad(handleEvent: handleEvent) { run in
            await handleEvent(.playlistSessionUpdated(playlistSession))
            await handleEvent(.trackLoadingStarted(playlistSession))

            try await self.waitForImporterDismissal(
                importerDismissalDelay,
                run: run
            )

            let audioInfo = try await loadTrack(url)
            try self.ensureLoadRemainsCurrent(run)
            await handleEvent(
                .trackLoaded(
                    url: url,
                    audioInfo: audioInfo,
                    autoplayOnSuccess: autoplayOnSuccess
                )
            )
        }
    }

    func loadPlaylistTrack(
        playlistSession: PlaylistSession,
        importerDismissalDelay: Duration = .zero,
        autoplayOnSuccess: Bool = false,
        loadTrack: @escaping @MainActor (URL) async throws -> AudioInfo,
        handleEvent: @escaping @MainActor (Event) async -> Void
    ) {
        let trackURL = playlistSession.currentTrackURL

        startNewLoad(handleEvent: handleEvent) { run in
            await handleEvent(.playlistSessionUpdated(playlistSession))
            await handleEvent(.trackLoadingStarted(playlistSession))

            try await self.waitForImporterDismissal(
                importerDismissalDelay,
                run: run
            )

            let audioInfo = try await loadTrack(trackURL)
            try self.ensureLoadRemainsCurrent(run)
            await handleEvent(
                .trackLoaded(
                    url: trackURL,
                    audioInfo: audioInfo,
                    autoplayOnSuccess: autoplayOnSuccess
                )
            )
        }
    }

    func loadFolder(
        url: URL,
        importerDismissalDelay: Duration = .zero,
        loadTrack: @escaping @MainActor (URL) async throws -> AudioInfo,
        handleEvent: @escaping @MainActor (Event) async -> Void
    ) {
        startNewLoad(handleEvent: handleEvent) { run in
            await handleEvent(.scanningFolderStarted)

            try await self.waitForImporterDismissal(
                importerDismissalDelay,
                run: run
            )

            guard let folderAccess = ScopedFolderAccess(folderURL: url) else {
                throw PlaybackError.loadFailed("Cannot access folder")
            }

            let tracks = try await self.scanFolderOffMainActor(url)

            try self.ensureLoadRemainsCurrent(run)

            guard let playlistSession = PlaylistSession.folderPlaylist(
                tracks: tracks,
                folderAccess: folderAccess
            ) else {
                throw PlaybackError.loadFailed("No playable audio files were found in the selected folder.")
            }

            await handleEvent(.playlistSessionUpdated(playlistSession))
            await handleEvent(.trackLoadingStarted(playlistSession))

            let audioInfo = try await loadTrack(playlistSession.currentTrackURL)
            try self.ensureLoadRemainsCurrent(run)
            await handleEvent(
                .trackLoaded(
                    url: playlistSession.currentTrackURL,
                    audioInfo: audioInfo,
                    autoplayOnSuccess: false
                )
            )
        }
    }

    private func startNewLoad(
        handleEvent: @escaping @MainActor (Event) async -> Void,
        operation: @escaping @MainActor (LatestAsyncRequestCoordinator.Run) async throws -> Void
    ) {
        latestLoad.replaceCurrentRun { run in
            do {
                try await operation(run)
            } catch is CancellationError {
                guard run.isCurrent() else { return }
                await handleEvent(.cancelled)
            } catch let error as PlaybackError {
                guard run.isCurrent() else { return }
                await handleEvent(.failed(error))
            } catch {
                guard run.isCurrent() else { return }
                await handleEvent(.failed(.loadFailed(error.localizedDescription)))
            }
        }
    }

    private func waitForImporterDismissal(
        _ delay: Duration,
        run: LatestAsyncRequestCoordinator.Run
    ) async throws {
        guard delay > .zero else { return }

        do {
            try await Task.sleep(for: delay)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw CancellationError()
        }

        try run.ensureCurrent()
    }

    private func ensureLoadRemainsCurrent(_ run: LatestAsyncRequestCoordinator.Run) throws {
        try run.ensureCurrent()
    }

    private func scanFolderOffMainActor(_ url: URL) async throws -> [URL] {
        let folderScanner = self.folderScanner
        let scanTask = Task.detached(priority: .userInitiated) {
            try await folderScanner.scan(folderURL: url)
        }

        return try await withTaskCancellationHandler {
            try await scanTask.value
        } onCancel: {
            scanTask.cancel()
        }
    }
}
