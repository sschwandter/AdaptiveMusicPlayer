import AdaptiveMusicPlayerCore
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
        case failed(PlaybackError)
    }

    private let folderScanner: AudioPlaylistFolderScanning
    private let audioFileClassifier: PlayableAudioFileClassifying
    private let latestLoad = LatestAsyncRequestCoordinator()

    init(
        folderScanner: AudioPlaylistFolderScanning = AudioPlaylistFolderScanner(),
        audioFileClassifier: PlayableAudioFileClassifying = UTTypeAudioFileClassifier()
    ) {
        self.folderScanner = folderScanner
        self.audioFileClassifier = audioFileClassifier
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
                folderAccesses: [folderAccess]
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

    /// Load drag & dropped files and/or folders as one combined playlist.
    /// Folders are scanned like a folder load; loose files are kept if
    /// playable. No importer dismissal delay — there is no picker to dismiss.
    func loadDroppedItems(
        urls: [URL],
        loadTrack: @escaping @MainActor (URL) async throws -> AudioInfo,
        handleEvent: @escaping @MainActor (Event) async -> Void
    ) {
        startNewLoad(handleEvent: handleEvent) { run in
            await handleEvent(.scanningFolderStarted)

            // `ScopedFolderAccess`'s failable init rejects anything that is
            // not a readable directory, so it doubles as the partition
            // between dropped folders and loose files.
            var folderAccesses: [ScopedFolderAccess] = []
            var looseFiles: [URL] = []
            for url in urls {
                if let folderAccess = ScopedFolderAccess(folderURL: url) {
                    folderAccesses.append(folderAccess)
                } else {
                    looseFiles.append(url)
                }
            }

            var tracks: [URL] = []
            // ponytail: sequential scans; drops carry a handful of folders.
            for folderAccess in folderAccesses {
                tracks += try await self.scanFolderOffMainActor(folderAccess.folderURL)
            }
            tracks += looseFiles.filter { self.isPlayableWithTransientScope($0) }
            tracks.sort(by: AudioPlaylistFolderScanner.sortByFullPath)

            try self.ensureLoadRemainsCurrent(run)

            guard let playlistSession = PlaylistSession.folderPlaylist(
                tracks: tracks,
                folderAccesses: folderAccesses
            ) else {
                throw PlaybackError.loadFailed("No playable audio files were found in the dropped items.")
            }

            await handleEvent(.playlistSessionUpdated(playlistSession))
            await handleEvent(.trackLoadingStarted(playlistSession))

            let audioInfo = try await loadTrack(playlistSession.currentTrackURL)
            try self.ensureLoadRemainsCurrent(run)
            await handleEvent(
                .trackLoaded(
                    url: playlistSession.currentTrackURL,
                    audioInfo: audioInfo,
                    autoplayOnSuccess: true
                )
            )
        }
    }

    /// The classifier reads resource values from disk, which needs the
    /// dropped file's own security scope in the sandboxed app (a no-op for
    /// URLs that are readable without one).
    private func isPlayableWithTransientScope(_ url: URL) -> Bool {
        let didAccessScopedResource = url.startAccessingSecurityScopedResource()
        defer {
            if didAccessScopedResource {
                url.stopAccessingSecurityScopedResource()
            }
        }

        return audioFileClassifier.isPlayableFile(at: url)
    }

    private func startNewLoad(
        handleEvent: @escaping @MainActor (Event) async -> Void,
        operation: @escaping @MainActor (LatestAsyncRequestCoordinator.Run) async throws -> Void
    ) {
        latestLoad.replaceCurrentRun { run in
            do {
                try await operation(run)
            } catch is CancellationError {
                // A cancelled load always means a newer request replaced this
                // run: every cancellation path also bumps the coordinator's
                // generation, so there is no current-run cancellation to
                // report — the replacing load owns the UI now.
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
