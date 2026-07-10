import Testing
import Foundation
@testable import AdaptiveMusicPlayerCore
@testable import AdaptiveMusicPlayer

@Suite("AudioPlayerSessionReducer Tests")
@MainActor
struct AudioPlayerSessionReducerTests {
    private let reducer = AudioPlayerSessionReducer()

    @Test("load started preserves current audio and sets semantic loading state")
    func loadStartedPreservesAudioAndSetsLoadingState() throws {
        let audioInfo = AudioInfo(
            fileName: "current.wav",
            displayTitle: "Current",
            duration: 1,
            sampleRate: 48_000
        )
        let playlistSession = try #require(
            PlaylistSession.singleTrack(URL(fileURLWithPath: "/tmp/current.wav"))
        )
        let initialState = AudioPlayerSessionState(playback: .playing(audioInfo))

        let nextState = reducer.reduce(
            state: initialState,
            action: .loadStarted(
                preservedAudioInfo: nil,
                phase: .loadingTrack(playlistSession)
            )
        )

        guard case .ready(let reducedAudioInfo) = nextState.playback else {
            Issue.record("Expected ready playback after loading starts.")
            return
        }

        #expect(reducedAudioInfo.fileName == "current.wav")
        #expect(nextState.activity == LoadingPresentationState.loadingTrack)
        #expect(nextState.status.message == "Loading file...")
        #expect(nextState.currentTime == 0)
    }

    @Test("playlist and track-ready actions update playlist, playback, title cache, and time")
    func playlistAndTrackReadyActions() throws {
        let trackURL = URL(fileURLWithPath: "/tmp/track.wav")
        let playlistSession = try #require(PlaylistSession.singleTrack(trackURL))
        let audioInfo = AudioInfo(
            fileName: "track.wav",
            displayTitle: "Track Title",
            duration: 3,
            sampleRate: 44_100
        )

        let playlistState = reducer.reduce(
            state: AudioPlayerSessionState(),
            action: .playlistSessionUpdated(playlistSession)
        )
        let readyState = reducer.reduce(
            state: playlistState,
            action: .trackReady(url: trackURL, audioInfo: audioInfo)
        )

        #expect(readyState.playlistSession?.currentTrackURL == trackURL)
        #expect(readyState.currentTime == 0)
        #expect(readyState.displayTitlesByTrackURL[trackURL] == "Track Title")
        guard case .ready(let reducedAudioInfo) = readyState.playback else {
            Issue.record("Expected ready playback state.")
            return
        }
        #expect(reducedAudioInfo.displayTitle == "Track Title")
    }

    @Test("switching playlists prunes cached titles for tracks no longer present")
    func playlistSwitchPrunesStaleTitleCache() throws {
        let keptURL = URL(fileURLWithPath: "/tmp/kept.wav")
        let staleURL = URL(fileURLWithPath: "/tmp/stale.wav")
        let newSession = try #require(PlaylistSession.singleTrack(keptURL))

        var initialState = AudioPlayerSessionState()
        initialState.displayTitlesByTrackURL = [
            keptURL: "Kept",
            staleURL: "Stale"
        ]

        let nextState = reducer.reduce(
            state: initialState,
            action: .playlistSessionUpdated(newSession)
        )

        #expect(nextState.displayTitlesByTrackURL[keptURL] == "Kept")
        #expect(nextState.displayTitlesByTrackURL[staleURL] == nil)
    }

    @Test("playback lifecycle actions set expected states")
    func playbackLifecycleActions() {
        let audioInfo = AudioInfo(
            fileName: "track.wav",
            displayTitle: "Track",
            duration: 10,
            sampleRate: 44_100
        )

        let startingState = reducer.reduce(
            state: AudioPlayerSessionState(playback: .ready(audioInfo)),
            action: .playbackStarting
        )
        let playingState = reducer.reduce(
            state: startingState,
            action: .engineEventReceived(.stateChanged(.playing(audioInfo)))
        )
        let progressState = reducer.reduce(
            state: playingState,
            action: .progressChanged(4)
        )
        let pausedState = reducer.reduce(
            state: progressState,
            action: .engineEventReceived(.stateChanged(.paused(audioInfo)))
        )
        let stoppedState = reducer.reduce(
            state: pausedState,
            action: .playbackStopped(preservedAudioInfo: audioInfo)
        )
        let finishedState = reducer.reduce(
            state: playingState,
            action: .playbackFinished(audioInfo)
        )

        #expect(startingState.activity == .startingPlayback)
        #expect(playingState.isPlaying)
        #expect(progressState.currentTime == 4)
        #expect(!pausedState.isPlaying)
        #expect(pausedState.currentTime == 4)
        #expect(stoppedState.currentTime == 0)
        #expect(stoppedState.statusMessage == "Stopped")
        #expect(finishedState.currentTime == 10)
        guard case .finished = finishedState.playback else {
            Issue.record("Expected finished playback state.")
            return
        }
    }

    @Test("failure and hardware actions update their own state slices")
    func failureAndHardwareActions() {
        let deviceInfo = AudioDeviceInfo(
            name: "Test Device",
            currentSampleRate: 44_100,
            supportedSampleRates: [44_100, 48_000]
        )

        let hardwareState = reducer.reduce(
            state: AudioPlayerSessionState(currentTime: 8),
            action: .hardwareInfoChanged(deviceInfo)
        )
        let failedState = reducer.reduce(
            state: hardwareState,
            action: .engineEventReceived(.stateChanged(.error(.noFileLoaded)))
        )
        let ignoredState = reducer.reduce(
            state: failedState,
            action: .commandIgnored(.notReady)
        )

        #expect(hardwareState.hardwareDeviceName == "Test Device")
        #expect(failedState.hasError)
        #expect(ignoredState.statusMessage == failedState.statusMessage)
    }

    @Test("ignored command releases the seek latch so progress updates resume")
    func commandIgnoredClearsSeeking() {
        let ignoredState = reducer.reduce(
            state: AudioPlayerSessionState(isSeeking: true),
            action: .commandIgnored(.noFileLoaded)
        )
        let progressState = reducer.reduce(
            state: ignoredState,
            action: .progressChanged(3)
        )

        #expect(!ignoredState.isSeeking)
        #expect(progressState.currentTime == 3)
    }
}
