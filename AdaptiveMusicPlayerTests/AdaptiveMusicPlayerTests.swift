import Testing
import AVFoundation
import CoreAudio
import Foundation
@testable import AdaptiveMusicPlayer

@Suite("AudioPlayer Tests", .serialized)
@MainActor
struct AudioPlayerTests {
    
    @Test("AudioPlayer initializes with default values")
    func initialState() async throws {
        let player = AudioPlayer()
        
        #expect(player.isPlaying == false)
        #expect(player.currentTime == 0)
        #expect(player.duration == 0)
        #expect(player.volume == 1.0)
        #expect(player.currentFileName == nil)
        #expect(player.fileSampleRate == 0)
        // Hardware sample rate is fetched asynchronously off the main thread
        try await Task.sleep(for: .milliseconds(100))
        #expect(player.hardwareSampleRate > 0) // Should get system default
        #expect(!player.hardwareDeviceDisplayName.isEmpty)
        #expect(!player.sampleRateStatusDetail.isEmpty)
        #expect(player.statusMessage == "")
        #expect(player.hasError == false)
        #expect(player.isLoading == false)
    }
    
    @Test("Volume changes are applied correctly")
    func volumeControl() async throws {
        let player = AudioPlayer()
        
        player.volume = 0.8
        #expect(player.volume == 0.8)
        
        player.volume = 0.0
        #expect(player.volume == 0.0)
        
        player.volume = 1.0
        #expect(player.volume == 1.0)
    }
    
    @Test("Time formatting works correctly")
    func timeFormatting() async throws {
        // Test various time formats using TimeFormatter directly
        #expect(TimeFormatter.format(0) == "0:00")
        #expect(TimeFormatter.format(30) == "0:30")
        #expect(TimeFormatter.format(60) == "1:00")
        #expect(TimeFormatter.format(90) == "1:30")
        #expect(TimeFormatter.format(3661) == "61:01")
    }
    
    @Test("Toggle play/pause with no file loaded")
    func toggleWithoutFile() async throws {
        let player = AudioPlayer()
        
        // Should remain stopped when no file is loaded
        player.togglePlayPause()
        #expect(player.isPlaying == false)
    }
    
    @Test("Stop functionality")
    func stopFunctionality() async throws {
        let player = AudioPlayer()
        
        // Stopping when not playing should be safe
        player.stop()
        #expect(player.isPlaying == false)
        #expect(player.currentTime == 0)
    }
    
    @Test("Skip operations without file")
    func skipWithoutFile() async throws {
        let player = AudioPlayer()
        
        // Should be safe to call skip functions without a file
        player.skipForward()
        player.skipBackward()
        
        #expect(player.currentTime == 0)
        #expect(player.isPlaying == false)
    }
    
    @Test("Seek bounds checking")
    func seekBounds() async throws {
        let player = AudioPlayer()
        
        // Should handle seeking without a file gracefully
        player.seek(to: 10.0)
        #expect(player.currentTime == 0)
        
        player.seek(to: -5.0)
        #expect(player.currentTime == 0)
    }
    
    @Test("Error state management")
    func errorStates() async throws {
        let player = AudioPlayer()

        // Initially no error
        #expect(player.hasError == false)

        // Test loading a non-existent file
        let invalidURL = URL(fileURLWithPath: "/nonexistent/file.mp3")
        player.loadFile(url: invalidURL)
        await player.waitForCurrentLoad()

        // Should have error state
        #expect(player.hasError == true)
        #expect(!player.statusMessage.isEmpty)
        #expect(!player.sampleRateStatusDetail.isEmpty)
    }

}

@Suite("AudioPlayer Folder Loading Tests", .serialized)
@MainActor
struct AudioPlayerFolderLoadingTests {

    @Test("Loading a folder builds a playable playlist from discovered files")
    func loadFolderBuildsPlaylist() async throws {
        let rootFolder = try TemporaryFolder.make()
        defer { try? TemporaryFolder.remove(rootFolder) }

        let fileURL = rootFolder.appending(path: "album/track.wav")
        try TemporaryFolder.writeWaveFile(at: fileURL)

        let player = AudioPlayer(
            engine: AudioPlaybackEngine(sampleRateManager: StubSampleRateManager()),
            hardwareObserver: StubAudioHardwareObserver()
        )

        player.loadFolder(url: rootFolder)
        await player.waitForCurrentLoad()

        #expect(player.currentFileName == "track.wav")
        #expect(player.playlistTrackPosition == "1 of 1")
        #expect(player.hasError == false)
    }

    @Test("Moving to the next playlist track starts playback automatically")
    func nextTrackAutoplays() async throws {
        let rootFolder = try TemporaryFolder.make()
        defer { try? TemporaryFolder.remove(rootFolder) }

        try TemporaryFolder.writeWaveFile(at: rootFolder.appending(path: "album/01-first.wav"))
        try TemporaryFolder.writeWaveFile(at: rootFolder.appending(path: "album/02-second.wav"))

        let player = AudioPlayer(
            engine: AudioPlaybackEngine(sampleRateManager: StubSampleRateManager()),
            hardwareObserver: StubAudioHardwareObserver()
        )

        player.loadFolder(url: rootFolder)
        await player.waitForCurrentLoad()

        player.playNextTrack()
        await player.waitForCurrentLoad()

        #expect(player.currentFileName == "02-second.wav")
        #expect(player.playlistTrackPosition == "2 of 2")
        #expect(player.isPlaying == true)
        #expect(player.hasError == false)
    }
}

@Suite("TimeFormatter Tests")
struct TimeFormatterTests {

    @Test("Time string formatting edge cases")
    func timeStringEdgeCases() async throws {
        // Test edge cases using TimeFormatter directly
        #expect(TimeFormatter.format(0.5) == "0:00")
        #expect(TimeFormatter.format(59.9) == "0:59")
        #expect(TimeFormatter.format(3600) == "60:00")
        #expect(TimeFormatter.format(Double.infinity) == "0:00") // Invalid input returns 0:00
        #expect(TimeFormatter.format(-10) == "0:00") // Negative should be handled gracefully
    }
}

@Suite("SecurityScopedFileLoader Tests")
struct SecurityScopedFileLoaderTests {

    @Test("Loads regular file URLs even when no direct scoped access is granted")
    func loadsUnscopedReadableFile() async throws {
        let rootFolder = try TemporaryFolder.make()
        defer { try? TemporaryFolder.remove(rootFolder) }

        let fileURL = rootFolder.appending(path: "track.wav")
        let contents = Data("audio".utf8)
        try TemporaryFolder.writeFile(at: fileURL, contents: contents)

        let loader = SecurityScopedFileLoader()
        let loadedFile = try await loader.load(url: fileURL)

        #expect(loadedFile.data == contents)
        #expect(loadedFile.fileName == "track.wav")
        #expect(loadedFile.fileExtension == "wav")
    }
}

@Suite("PlaybackControlUseCase Tests")
@MainActor
struct PlaybackControlUseCaseTests {

    @Test("Playing a finished track rewinds before restarting")
    func playFinishedTrackRewindsToStart() throws {
        let useCase = PlaybackControlUseCase()
        let player = try StubAudioPlayer()
        let audioInfo = AudioInfo(fileName: "test.wav", duration: 1, sampleRate: 44_100)

        player.currentTime = 0.75
        let newState = try useCase.play(player: player, state: .finished(audioInfo))

        #expect(newState == .playing(audioInfo))
        #expect(player.playCallCount == 1)
        #expect(player.currentTime == 0)
    }

    @Test("State does not advance when AVAudioPlayer fails to start")
    func playFailureDoesNotAdvanceState() throws {
        let useCase = PlaybackControlUseCase()
        let player = try StubAudioPlayer(playResult: false)
        let audioInfo = AudioInfo(fileName: "test.wav", duration: 1, sampleRate: 44_100)

        #expect(throws: PlaybackError.playbackStartFailed) {
            try useCase.play(player: player, state: .ready(audioInfo))
        }
        #expect(player.playCallCount == 1)
    }
}

@Suite("PlaybackPlaylist Tests")
struct PlaybackPlaylistTests {

    @Test("Playlist tracks move forward and backward safely")
    func playlistNavigation() throws {
        let tracks = [
            URL(fileURLWithPath: "/tmp/a.wav"),
            URL(fileURLWithPath: "/tmp/b.wav"),
            URL(fileURLWithPath: "/tmp/c.wav")
        ]

        let firstPlaylist = try #require(PlaybackPlaylist(tracks: tracks))
        #expect(firstPlaylist.currentTrackURL == tracks[0])
        #expect(firstPlaylist.canMoveToPreviousTrack == false)
        #expect(firstPlaylist.canMoveToNextTrack == true)
        #expect(firstPlaylist.positionDescription == "1 of 3")

        let secondPlaylist = try #require(firstPlaylist.playlistByMovingToNextTrack())
        #expect(secondPlaylist.currentTrackURL == tracks[1])
        #expect(secondPlaylist.canMoveToPreviousTrack == true)
        #expect(secondPlaylist.canMoveToNextTrack == true)

        let thirdPlaylist = try #require(secondPlaylist.playlistByMovingToNextTrack())
        #expect(thirdPlaylist.currentTrackURL == tracks[2])
        #expect(thirdPlaylist.canMoveToNextTrack == false)
        #expect(thirdPlaylist.playlistByMovingToNextTrack() == nil)
        #expect(try #require(thirdPlaylist.playlistByMovingToPreviousTrack()).currentTrackURL == tracks[1])
    }

    @Test("Playlist rejects empty track lists")
    func rejectsEmptyPlaylists() {
        #expect(PlaybackPlaylist(tracks: []) == nil)
    }
}

@Suite("PlaybackState Tests")
struct PlaybackStateTests {

    @Test("Loading state preserves prior audio info during transitions")
    func loadingStatePreservesAudioInfo() {
        let audioInfo = AudioInfo(fileName: "track.wav", duration: 42, sampleRate: 44_100)

        #expect(PlaybackState.loading(audioInfo).isLoading == true)
        #expect(PlaybackState.loading(audioInfo).audioInfo == audioInfo)
        #expect(PlaybackState.loading(nil).audioInfo == nil)
    }
}

@Suite("PlaylistSession Tests")
struct PlaylistSessionTests {

    @Test("Playlist session moves between tracks while preserving playlist metadata")
    func sessionNavigationPreservesPlaylistContext() throws {
        let tracks = [
            URL(fileURLWithPath: "/tmp/a.wav"),
            URL(fileURLWithPath: "/tmp/b.wav")
        ]
        let playlist = try #require(PlaybackPlaylist(tracks: tracks))
        let session = PlaylistSession(playlist: playlist)

        #expect(session.currentTrackURL == tracks[0])
        #expect(session.positionDescription == "1 of 2")
        #expect(session.canMoveToNextTrack)

        let nextSession = try #require(session.movingToNextTrack())
        #expect(nextSession.currentTrackURL == tracks[1])
        #expect(nextSession.positionDescription == "2 of 2")
        #expect(nextSession.canMoveToPreviousTrack)
    }
}

@Suite("SampleRateManager Tests")
struct SampleRateManagerTests {

    @Test("Nominal sample-rate ranges are treated as ranges")
    func rangeSupportCheck() {
        let ranges = [
            AudioValueRange(mMinimum: 44_100, mMaximum: 192_000)
        ]

        #expect(CoreAudioSampleRateManager.sampleRate(96_000, isSupportedBy: ranges))
        #expect(!CoreAudioSampleRateManager.sampleRate(22_050, isSupportedBy: ranges))
    }

    @Test("Range-backed sample rates expand to common nominal rates")
    func rangeExpansionUsesCommonNominalRates() {
        let discrete = AudioValueRange(mMinimum: 44_100, mMaximum: 44_100)
        let ranged = AudioValueRange(mMinimum: 44_100, mMaximum: 192_000)

        #expect(
            CoreAudioSampleRateManager.expandSupportedRates(from: discrete) == [44_100]
        )
        #expect(
            CoreAudioSampleRateManager.expandSupportedRates(from: ranged)
            == [44_100, 48_000, 88_200, 96_000, 176_400, 192_000]
        )
    }
}

@Suite("PlaybackProgressTracker Tests")
@MainActor
struct PlaybackProgressTrackerTests {

    @Test("Ignoring finish callbacks from a previously tracked player")
    func ignoresStaleFinishCallbacks() async throws {
        let tracker = PlaybackProgressTracker()
        let stalePlayer = try StubAudioPlayer()
        let activePlayer = try StubAudioPlayer()
        var finishCount = 0

        tracker.startTracking(
            player: stalePlayer,
            duration: 1,
            updateInterval: 1,
            onProgressUpdate: { _ in },
            onPlaybackFinished: { finishCount += 1 },
            onPeriodicUpdate: {}
        )

        tracker.startTracking(
            player: activePlayer,
            duration: 1,
            updateInterval: 1,
            onProgressUpdate: { _ in },
            onPlaybackFinished: { finishCount += 1 },
            onPeriodicUpdate: {}
        )

        tracker.audioPlayerDidFinishPlaying(stalePlayer, successfully: true)
        try await Task.sleep(for: .milliseconds(10))

        #expect(finishCount == 0)
    }

    @Test("Ignoring unsuccessful finish callbacks")
    func ignoresUnsuccessfulFinishCallbacks() async throws {
        let tracker = PlaybackProgressTracker()
        let player = try StubAudioPlayer()
        var finishCount = 0

        tracker.startTracking(
            player: player,
            duration: 1,
            updateInterval: 1,
            onProgressUpdate: { _ in },
            onPlaybackFinished: { finishCount += 1 },
            onPeriodicUpdate: {}
        )

        tracker.audioPlayerDidFinishPlaying(player, successfully: false)
        try await Task.sleep(for: .milliseconds(10))

        #expect(finishCount == 0)
    }
}

@Suite("AudioPlaylistFolderScanner Tests")
struct AudioPlaylistFolderScannerTests {

    @Test("Recursively scans folders, keeps playable files, and sorts by full path")
    func scansRecursivelyAndSortsByPath() throws {
        let rootFolder = try TemporaryFolder.make()
        defer { try? TemporaryFolder.remove(rootFolder) }

        try TemporaryFolder.createSubfolder(named: "z-last", in: rootFolder)
        try TemporaryFolder.createSubfolder(named: "a-first/deeper", in: rootFolder)

        let topLevelPlayable = rootFolder.appending(path: "middle.wav")
        let nestedPlayable = rootFolder.appending(path: "a-first/song.mp3")
        let deepPlayable = rootFolder.appending(path: "a-first/deeper/intro.aiff")
        let ignoredText = rootFolder.appending(path: "notes.txt")
        let hiddenPlayable = rootFolder.appending(path: ".hidden.mp3")

        try TemporaryFolder.writeFile(at: topLevelPlayable)
        try TemporaryFolder.writeFile(at: nestedPlayable)
        try TemporaryFolder.writeFile(at: deepPlayable)
        try TemporaryFolder.writeFile(at: ignoredText)
        try TemporaryFolder.writeFile(at: hiddenPlayable)

        let scanner = AudioPlaylistFolderScanner()

        let result = try scanner.scan(folderURL: rootFolder)

        #expect(result.files == [deepPlayable, nestedPlayable, topLevelPlayable])
        #expect(result.warnings.isEmpty)
    }

    @Test("Rejects file URLs instead of folders")
    func rejectsNonDirectoryURLs() throws {
        let rootFolder = try TemporaryFolder.make()
        defer { try? TemporaryFolder.remove(rootFolder) }

        let fileURL = rootFolder.appending(path: "track.wav")
        try TemporaryFolder.writeFile(at: fileURL)

        let scanner = AudioPlaylistFolderScanner()

        #expect(throws: AudioPlaylistFolderScannerError.notADirectory(fileURL)) {
            try scanner.scan(folderURL: fileURL)
        }
    }

    @Test("Separates recursion from filtering so selection logic stays unit testable")
    func supportsInjectedEnumerationAndFiltering() throws {
        let rootFolder = try TemporaryFolder.make()
        defer { try? TemporaryFolder.remove(rootFolder) }

        let expectedAudio = rootFolder.appending(path: "disc-1/keep-me.wav")
        let alsoPlayable = rootFolder.appending(path: "disc-2/another-song.mp3")
        let ignoredText = rootFolder.appending(path: "disc-1/readme.txt")
        let enumerator = StubDirectoryTreeEnumerator(urls: [ignoredText, alsoPlayable, expectedAudio])
        let classifier = StubPlayableAudioFileClassifier(playableURLs: [alsoPlayable, expectedAudio])
        let scanner = AudioPlaylistFolderScanner(
            directoryEnumerator: enumerator,
            audioFileClassifier: classifier
        )

        let result = try scanner.scan(folderURL: rootFolder)

        #expect(result.files == [expectedAudio, alsoPlayable])
        #expect(result.warnings.isEmpty)
    }

    @Test("Reports skipped paths when directory enumeration encounters errors")
    func reportsEnumerationWarnings() throws {
        let rootFolder = try TemporaryFolder.make()
        defer { try? TemporaryFolder.remove(rootFolder) }

        let playable = rootFolder.appending(path: "track.wav")
        let warning = AudioPlaylistFolderScanWarning(
            path: rootFolder.appending(path: "restricted").path,
            message: "Permission denied"
        )
        let enumerator = StubDirectoryTreeEnumerator(urls: [playable], warnings: [warning])
        let classifier = StubPlayableAudioFileClassifier(playableURLs: [playable])
        let scanner = AudioPlaylistFolderScanner(
            directoryEnumerator: enumerator,
            audioFileClassifier: classifier
        )

        let result = try scanner.scan(folderURL: rootFolder)

        #expect(result.files == [playable])
        #expect(result.warnings == [warning])
        #expect(result.warningSummary == "Skipped 1 unreadable item while scanning the folder.")
    }
}

private final class StubAudioPlayer: AVAudioPlayer {
    var playResult: Bool
    var playCallCount = 0

    init(playResult: Bool = true) throws {
        self.playResult = playResult
        try super.init(data: Self.makeWaveData(), fileTypeHint: "wav")
    }

    override func play() -> Bool {
        playCallCount += 1
        return playResult
    }

    override func stop() {
        super.stop()
        currentTime = 0
    }

    private static func makeWaveData() -> Data {
        let sampleRate: UInt32 = 44_100
        let bitsPerSample: UInt16 = 16
        let channels: UInt16 = 1
        let frameCount: UInt32 = 44
        let bytesPerSample = UInt32(bitsPerSample / 8)
        let dataSize = frameCount * UInt32(channels) * bytesPerSample
        let byteRate = sampleRate * UInt32(channels) * bytesPerSample
        let blockAlign = channels * bitsPerSample / 8

        var data = Data()
        data.append("RIFF".data(using: .ascii)!)
        data.appendLE(UInt32(36 + dataSize))
        data.append("WAVE".data(using: .ascii)!)
        data.append("fmt ".data(using: .ascii)!)
        data.appendLE(UInt32(16))
        data.appendLE(UInt16(1))
        data.appendLE(channels)
        data.appendLE(sampleRate)
        data.appendLE(byteRate)
        data.appendLE(blockAlign)
        data.appendLE(bitsPerSample)
        data.append("data".data(using: .ascii)!)
        data.appendLE(dataSize)
        data.append(Data(repeating: 0, count: Int(dataSize)))
        return data
    }
}

private extension Data {
    mutating func appendLE<T: FixedWidthInteger>(_ value: T) {
        var littleEndian = value.littleEndian
        Swift.withUnsafeBytes(of: &littleEndian) { bytes in
            append(bytes.bindMemory(to: UInt8.self))
        }
    }
}

private struct StubDirectoryTreeEnumerator: DirectoryTreeEnumerating {
    let urls: [URL]
    var warnings: [AudioPlaylistFolderScanWarning] = []

    func recursivelyEnumerateFiles(in folderURL: URL) throws -> DirectoryTreeEnumerationResult {
        DirectoryTreeEnumerationResult(urls: urls, warnings: warnings)
    }
}

private struct StubPlayableAudioFileClassifier: PlayableAudioFileClassifying {
    let playableURLs: Set<URL>

    func isPlayableFile(at url: URL) -> Bool {
        playableURLs.contains(url)
    }
}


private enum TemporaryFolder {
    static func make() throws -> URL {
        let baseURL = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: baseURL, withIntermediateDirectories: true)
        return baseURL
    }

    static func createSubfolder(named relativePath: String, in rootFolder: URL) throws {
        let folderURL = rootFolder.appending(path: relativePath, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
    }

    static func writeFile(at url: URL, contents: Data = Data("test".utf8)) throws {
        let parentURL = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: parentURL, withIntermediateDirectories: true)
        try contents.write(to: url)
    }

    static func writeWaveFile(at url: URL) throws {
        try writeFile(at: url, contents: WaveData.make())
    }

    static func remove(_ url: URL) throws {
        try FileManager.default.removeItem(at: url)
    }
}

private final class StubAudioHardwareObserver: AudioHardwareObserving {
    nonisolated func startObserving(onChange: @escaping @Sendable () -> Void) {}
    nonisolated func stopObserving() {}
}

private struct StubSampleRateManager: SampleRateManaging {
    nonisolated func getCurrentSampleRate() -> Double? { 44_100 }
    nonisolated func getCurrentOutputDeviceName() -> String? { "Test Device" }
    nonisolated func setSampleRate(_ rate: Double) throws {}
    nonisolated func getSupportedSampleRates() -> [Double] { [44_100] }
    nonisolated func getCurrentDeviceInfo() -> AudioDeviceInfo? {
        AudioDeviceInfo(name: "Test Device", currentSampleRate: 44_100, supportedSampleRates: [44_100])
    }
}

private enum WaveData {
    static func make() -> Data {
        let sampleRate: UInt32 = 44_100
        let bitsPerSample: UInt16 = 16
        let channels: UInt16 = 1
        let frameCount: UInt32 = 44
        let bytesPerSample = UInt32(bitsPerSample / 8)
        let dataSize = frameCount * UInt32(channels) * bytesPerSample
        let byteRate = sampleRate * UInt32(channels) * bytesPerSample
        let blockAlign = channels * bitsPerSample / 8

        var data = Data()
        data.append("RIFF".data(using: .ascii)!)
        data.appendLE(UInt32(36 + dataSize))
        data.append("WAVE".data(using: .ascii)!)
        data.append("fmt ".data(using: .ascii)!)
        data.appendLE(UInt32(16))
        data.appendLE(UInt16(1))
        data.appendLE(channels)
        data.appendLE(sampleRate)
        data.appendLE(byteRate)
        data.appendLE(blockAlign)
        data.appendLE(bitsPerSample)
        data.append("data".data(using: .ascii)!)
        data.appendLE(dataSize)
        data.append(Data(repeating: 0, count: Int(dataSize)))
        return data
    }
}
