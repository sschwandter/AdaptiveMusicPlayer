# AudioPlayer Extraction Plan

This file tracks the refactor work for `AdaptiveMusicPlayer/Playback/UI/AudioPlayer.swift`.

Working rules:

- Move exactly one task into `In Progress` before starting implementation.
- Move a task to `Done` only after code changes and relevant verification are complete.
- Do not commit immediately after verification. Stop and let the user review the changes before creating the commit.
- Add newly discovered follow-up work to `Backlog` instead of keeping it in chat context.
- Keep tasks PR-sized. Split any task that grows beyond one focused change.

## Backlog

No backlog items currently tracked.

## In Progress

No task currently in progress.

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

- [x] Extract `PlayerStatusPresenter`
  Notes:
  - Status message policy and error presentation moved to `Playback/UI/Presentation/PlayerStatusPresenter.swift`.
  - `AudioPlayer` now applies presenter outputs instead of mutating status/loading state through string-driven helper logic.
  - Removed string literal checks that previously decided loading-state transitions for scanning and cancellation.
  - Added isolated presenter tests in `AdaptiveMusicPlayerTests/PlayerStatusPresenterTests.swift`.
  - Verified with native `xcodebuild test -scheme AdaptiveMusicPlayer -only-testing:AdaptiveMusicPlayerTests/AudioPlayerTests -only-testing:AdaptiveMusicPlayerTests/AudioPlayerFolderLoadingTests -only-testing:AdaptiveMusicPlayerTests/PlayerStatusPresenterTests`.

- [x] Extract `AudioPlayerLoadCoordinator`
  Notes:
  - File and folder loading orchestration moved to `Playback/UI/Coordination/AudioPlayerLoadCoordinator.swift`.
  - Load task lifecycle, generation tracking, importer-dismissal waiting, and stale-load suppression now live in the coordinator.
  - `AudioPlayer` now handles typed load events instead of running the async load workflow directly.
  - Added focused coordinator tests in `AdaptiveMusicPlayerTests/AudioPlayerLoadCoordinatorTests.swift`, including stale folder-load suppression.
  - Verified with native `xcodebuild test -scheme AdaptiveMusicPlayer -only-testing:AdaptiveMusicPlayerTests/AudioPlayerTests -only-testing:AdaptiveMusicPlayerTests/AudioPlayerFolderLoadingTests -only-testing:AdaptiveMusicPlayerTests/AudioPlayerLoadCoordinatorTests`.

- [x] Extract `PlaybackStartupCoordinator`
  Notes:
  - Playback-start orchestration moved to `Playback/UI/Coordination/PlaybackStartupCoordinator.swift`.
  - Startup task lifecycle, generation invalidation, cancellation, and stale-start suppression now live in the coordinator.
  - `AudioPlayer` now handles typed startup events instead of managing startup tasks directly.
  - Added focused coordinator tests in `AdaptiveMusicPlayerTests/PlaybackStartupCoordinatorTests.swift` for success, cancellation, and stale-result handling.
  - Verified with native `xcodebuild test -scheme AdaptiveMusicPlayer -only-testing:AdaptiveMusicPlayerTests/AudioPlayerTests -only-testing:AdaptiveMusicPlayerTests/PlaybackStartupCoordinatorTests`.

- [x] Extract `PlayerScreenStateReducer`
  Notes:
  - Playback screen-state transitions moved to `Playback/UI/Presentation/PlayerScreenStateReducer.swift`.
  - `AudioPlayer` now applies typed reducer actions instead of mutating playback state through transition helpers.
  - Added focused reducer tests in `AdaptiveMusicPlayerTests/PlayerScreenStateReducerTests.swift` for loading, ready, playing, paused, stopped, and finished transitions.
  - Verified with native `xcodebuild test -scheme AdaptiveMusicPlayer -only-testing:AdaptiveMusicPlayerTests/AudioPlayerTests -only-testing:AdaptiveMusicPlayerTests/PlayerScreenStateReducerTests`.

- [x] Revisit progress-tracking boundary
  Notes:
  - Removed the `AudioPlaybackEngine.getPlayer()` escape hatch so `AudioPlayer` no longer depends on the engine's internal `AVAudioPlayer`.
  - Added engine-level `startProgressTracking` and `stopProgressTracking` entry points to keep progress observation behind the playback-engine boundary.
  - Simplified `PlaybackProgressTracking` by removing the unused `duration` parameter and added focused engine tests for the new boundary.
  - Verified with native `xcodebuild test -scheme AdaptiveMusicPlayer -only-testing:AdaptiveMusicPlayerTests/AudioPlayerTests -only-testing:AdaptiveMusicPlayerTests/AudioPlaybackEngineTests -only-testing:AdaptiveMusicPlayerTests/PlaybackProgressTrackerTests`.

## Risks / Decisions

- Keep early PRs behavior-preserving. Prefer extracting pure logic before moving async workflow code.
- Do not extract coordinators that mutate `AudioPlayer` internals directly. Prefer typed callback or event boundaries.
- Treat extension-only splits as a navigation aid, not the final architecture.
- Local verification currently depends on a full Xcode developer directory. `xcodebuild` is blocked while the active developer directory points at Command Line Tools.

## Follow-Up Notes

- Add new items here when refactor work uncovers fresh debt, test gaps, or design decisions that should not be lost.
