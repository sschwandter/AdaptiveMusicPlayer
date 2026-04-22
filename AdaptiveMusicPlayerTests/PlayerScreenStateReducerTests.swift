import Testing
@testable import AdaptiveMusicPlayer

@Suite("PlayerScreenStateReducer Tests")
@MainActor
struct PlayerScreenStateReducerTests {
    private let reducer = PlayerScreenStateReducer()

    @Test("beginLoading preserves provided audio info as ready playback")
    func beginLoadingWithPreservedAudio() {
        let audioInfo = AudioInfo(
            fileName: "track.wav",
            displayTitle: "Track",
            duration: 1,
            sampleRate: 44_100
        )
        let initialState = PlayerScreenState(
            playback: .idle,
            loading: .idle,
            status: .init(),
            playlist: .init(),
            hardware: .init()
        )

        let nextState = reducer.reduce(
            state: initialState,
            action: .beginLoading(preservedAudioInfo: audioInfo)
        )

        guard case .ready(let reducedAudioInfo) = nextState.playback else {
            Issue.record("Expected ready playback after beginLoading with preserved audio.")
            return
        }

        #expect(reducedAudioInfo.fileName == "track.wav")
    }

    @Test("beginLoading keeps current audio info when no preserved audio is supplied")
    func beginLoadingUsesCurrentAudio() {
        let audioInfo = AudioInfo(
            fileName: "current.wav",
            displayTitle: "Current",
            duration: 1,
            sampleRate: 48_000
        )
        let initialState = PlayerScreenState(
            playback: .playing(audioInfo),
            loading: .idle,
            status: .init(),
            playlist: .init(),
            hardware: .init()
        )

        let nextState = reducer.reduce(
            state: initialState,
            action: .beginLoading(preservedAudioInfo: nil)
        )

        guard case .ready(let reducedAudioInfo) = nextState.playback else {
            Issue.record("Expected ready playback after beginLoading with current audio.")
            return
        }

        #expect(reducedAudioInfo.fileName == "current.wav")
    }

    @Test("ready, playing, and paused transitions set the matching playback state")
    func directPlaybackTransitions() {
        let audioInfo = AudioInfo(
            fileName: "track.wav",
            displayTitle: "Track",
            duration: 1,
            sampleRate: 44_100
        )
        let initialState = PlayerScreenState()

        let readyState = reducer.reduce(
            state: initialState,
            action: .ready(audioInfo)
        )
        let playingState = reducer.reduce(
            state: readyState,
            action: .playing(audioInfo)
        )
        let pausedState = reducer.reduce(
            state: playingState,
            action: .paused(audioInfo)
        )

        if case .ready(let reducedAudioInfo) = readyState.playback {
            #expect(reducedAudioInfo.fileName == "track.wav")
        } else {
            Issue.record("Expected ready playback state.")
        }

        if case .playing(let reducedAudioInfo) = playingState.playback {
            #expect(reducedAudioInfo.fileName == "track.wav")
        } else {
            Issue.record("Expected playing playback state.")
        }

        if case .paused(let reducedAudioInfo) = pausedState.playback {
            #expect(reducedAudioInfo.fileName == "track.wav")
        } else {
            Issue.record("Expected paused playback state.")
        }
    }

    @Test("stopped falls back to idle when no audio remains")
    func stoppedWithoutAudio() {
        let initialState = PlayerScreenState(
            playback: .idle,
            loading: .idle,
            status: .init(),
            playlist: .init(),
            hardware: .init()
        )

        let nextState = reducer.reduce(
            state: initialState,
            action: .stopped(preservedAudioInfo: nil)
        )

        if case .idle = nextState.playback {
            #expect(Bool(true))
        } else {
            Issue.record("Expected idle playback state after stop without audio.")
        }
    }

    @Test("finished transition only applies when audio info exists")
    func finishedTransition() {
        let audioInfo = AudioInfo(
            fileName: "track.wav",
            displayTitle: "Track",
            duration: 1,
            sampleRate: 44_100
        )
        let initialState = PlayerScreenState(
            playback: .playing(audioInfo),
            loading: .idle,
            status: .init(),
            playlist: .init(),
            hardware: .init()
        )

        let finishedState = reducer.reduce(
            state: initialState,
            action: .finished(audioInfo)
        )
        let unchangedState = reducer.reduce(
            state: initialState,
            action: .finished(nil)
        )

        if case .finished(let reducedAudioInfo) = finishedState.playback {
            #expect(reducedAudioInfo.fileName == "track.wav")
        } else {
            Issue.record("Expected finished playback state.")
        }

        if case .playing = unchangedState.playback {
            #expect(Bool(true))
        } else {
            Issue.record("Expected playback state to remain unchanged when finish audio is nil.")
        }
    }
}
