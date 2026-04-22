# AudioPlayer Extraction Plan

This file tracks the refactor work for `AdaptiveMusicPlayer/Playback/UI/AudioPlayer.swift`.

Working rules:

- Move exactly one task into `In Progress` before starting implementation.
- Move a task to `Done` only after code changes and relevant verification are complete.
- Do not commit immediately after verification. Stop and let the user review the changes before creating the commit.
- Add newly discovered follow-up work to `Backlog` instead of keeping it in chat context.
- Keep tasks PR-sized. Split any task that grows beyond one focused change.

## Backlog

- [ ] Extract `PlayerStatusPresenter`
  Exit criteria:
  - Status and error message policy no longer lives in `AudioPlayer`.
  - String literals do not control loading-state transitions.
  - Dedicated unit tests cover ready, playing, cancelled, and error states.

- [ ] Extract `AudioPlayerLoadCoordinator`
  Exit criteria:
  - File and folder loading workflow no longer lives in `AudioPlayer`.
  - Load generation and cancellation bookkeeping live outside `AudioPlayer`.
  - The coordinator reports typed events back to `AudioPlayer`.
  - Existing load-related unit tests still pass, and new tests cover stale-load cancellation.

- [ ] Extract `PlaybackStartupCoordinator`
  Exit criteria:
  - Playback-start task and startup-generation bookkeeping no longer live in `AudioPlayer`.
  - Start, pause, and stop startup flow is coordinated outside `AudioPlayer`.
  - The coordinator reports typed events back to `AudioPlayer`.
  - Tests cover startup success, cancellation, and stale-result handling.

- [ ] Extract `PlayerScreenStateReducer`
  Exit criteria:
  - Screen-state transitions are centralized outside `AudioPlayer`.
  - Load and playback coordinators use the same transition boundary.
  - Tests cover loading, ready, playing, paused, stopped, and finished transitions.

- [ ] Revisit progress-tracking boundary
  Exit criteria:
  - Decide whether `AudioPlaybackEngine` should continue exposing `AVAudioPlayer`.
  - Either keep the current boundary with explicit rationale, or replace it with a higher-level observation API.

## In Progress

- [ ] No task currently in progress

## Done

- [x] Analyze `AudioPlayer.swift` and identify extraction seams
  Notes:
  - The cleanest early seams are sample-rate presentation and content-view state mapping.
  - The highest-value structural seams are load workflow and playback-startup workflow.

- [x] Extract `SampleRatePresenter`
  Notes:
  - Sample-rate banner/status decision logic moved to `Playback/UI/Presentation/SampleRatePresenter.swift`.
  - `AudioPlayer` now delegates sample-rate presentation queries to the presenter.
  - Added isolated presenter tests in `AdaptiveMusicPlayerTests/SampleRatePresenterTests.swift`.
  - Verified with native `xcodebuild test -scheme AdaptiveMusicPlayer -only-testing:AdaptiveMusicPlayerTests/AudioPlayerTests -only-testing:AdaptiveMusicPlayerTests/SampleRatePresenterTests`.

- [x] Extract `ContentViewStatePresenter`
  Notes:
  - `ContentViewState` assembly, playlist row mapping, and transport enablement rules moved to `Playback/UI/Presentation/ContentViewStatePresenter.swift`.
  - `AudioPlayer` now delegates playlist-derived view state and `contentViewState` construction to the presenter.
  - Added isolated presenter tests in `AdaptiveMusicPlayerTests/ContentViewStatePresenterTests.swift`.
  - Verified with native `xcodebuild test -scheme AdaptiveMusicPlayer -only-testing:AdaptiveMusicPlayerTests/AudioPlayerTests -only-testing:AdaptiveMusicPlayerTests/AudioPlayerFolderLoadingTests -only-testing:AdaptiveMusicPlayerTests/ContentViewStatePresenterTests`.

## Risks / Decisions

- Keep early PRs behavior-preserving. Prefer extracting pure logic before moving async workflow code.
- Do not extract coordinators that mutate `AudioPlayer` internals directly. Prefer typed callback or event boundaries.
- Treat extension-only splits as a navigation aid, not the final architecture.
- Local verification currently depends on a full Xcode developer directory. `xcodebuild` is blocked while the active developer directory points at Command Line Tools.

## Follow-Up Notes

- Add new items here when refactor work uncovers fresh debt, test gaps, or design decisions that should not be lost.
