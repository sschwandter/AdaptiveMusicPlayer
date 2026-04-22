import Foundation

@MainActor
final class AudioPlayerLoadCoordinator {
    enum Event {
        case beginLoading(
            loadingState: AudioPlayer.LoadingPresentationState,
            message: String
        )
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
    private var loadingTask: Task<Void, Never>?
    private var loadGeneration: Int = 0

    init(folderScanner: AudioPlaylistFolderScanning = AudioPlaylistFolderScanner()) {
        self.folderScanner = folderScanner
    }

    func waitForCurrentLoad() async {
        await loadingTask?.value
    }

    func loadFile(
        url: URL,
        playlistSession: PlaylistSession,
        importerDismissalDelay: Duration = .zero,
        autoplayOnSuccess: Bool = false,
        loadTrack: @escaping @MainActor (URL) async throws -> AudioInfo,
        handleEvent: @escaping @MainActor (Event) async -> Void
    ) {
        startNewLoad(handleEvent: handleEvent) { generation in
            await handleEvent(.playlistSessionUpdated(playlistSession))
            await handleEvent(
                .beginLoading(
                    loadingState: .loadingTrack,
                    message: Self.loadingMessage(for: playlistSession)
                )
            )

            try await self.waitForImporterDismissal(
                importerDismissalDelay,
                generation: generation
            )

            let audioInfo = try await loadTrack(url)
            try self.ensureLoadRemainsCurrent(generation)
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

        startNewLoad(handleEvent: handleEvent) { generation in
            await handleEvent(.playlistSessionUpdated(playlistSession))
            await handleEvent(
                .beginLoading(
                    loadingState: .loadingTrack,
                    message: Self.loadingMessage(for: playlistSession)
                )
            )

            try await self.waitForImporterDismissal(
                importerDismissalDelay,
                generation: generation
            )

            let audioInfo = try await loadTrack(trackURL)
            try self.ensureLoadRemainsCurrent(generation)
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
        startNewLoad(handleEvent: handleEvent) { generation in
            await handleEvent(
                .beginLoading(
                    loadingState: .scanningFolder,
                    message: "Scanning folder..."
                )
            )

            try await self.waitForImporterDismissal(
                importerDismissalDelay,
                generation: generation
            )

            guard let folderAccess = ScopedFolderAccess(folderURL: url) else {
                throw PlaybackError.loadFailed("Cannot access folder")
            }

            let folderScanner = self.folderScanner
            let tracks = try await Task.detached(priority: .userInitiated) {
                try folderScanner.scan(folderURL: url)
            }.value

            try self.ensureLoadRemainsCurrent(generation)

            guard let playlistSession = PlaylistSession.folderPlaylist(
                tracks: tracks,
                folderAccess: folderAccess
            ) else {
                throw PlaybackError.loadFailed("No playable audio files were found in the selected folder.")
            }

            await handleEvent(.playlistSessionUpdated(playlistSession))
            await handleEvent(
                .beginLoading(
                    loadingState: .loadingTrack,
                    message: Self.loadingMessage(for: playlistSession)
                )
            )

            let audioInfo = try await loadTrack(playlistSession.currentTrackURL)
            try self.ensureLoadRemainsCurrent(generation)
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
        operation: @escaping @MainActor (Int) async throws -> Void
    ) {
        loadingTask?.cancel()
        loadGeneration += 1
        let generation = loadGeneration

        loadingTask = Task { @MainActor [weak self] in
            guard let self else { return }

            do {
                try await operation(generation)
            } catch is CancellationError {
                guard generation == self.loadGeneration else { return }
                await handleEvent(.cancelled)
            } catch let error as PlaybackError {
                guard generation == self.loadGeneration else { return }
                await handleEvent(.failed(error))
            } catch {
                guard generation == self.loadGeneration else { return }
                await handleEvent(.failed(.loadFailed(error.localizedDescription)))
            }
        }
    }

    private func waitForImporterDismissal(_ delay: Duration, generation: Int) async throws {
        guard delay > .zero else { return }

        do {
            try await Task.sleep(for: delay)
        } catch is CancellationError {
            guard generation == loadGeneration else { throw CancellationError() }
            throw CancellationError()
        } catch {
            throw CancellationError()
        }
    }

    private func ensureLoadRemainsCurrent(_ generation: Int) throws {
        guard generation == loadGeneration, !Task.isCancelled else {
            throw CancellationError()
        }
    }

    private static func loadingMessage(for playlistSession: PlaylistSession) -> String {
        playlistSession.trackCount > 1
            ? "Loading track \(playlistSession.positionDescription)..."
            : "Loading file..."
    }
}
