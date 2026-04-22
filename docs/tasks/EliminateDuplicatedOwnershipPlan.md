# Eliminate Duplicated Ownership Plan

## Goal

Reduce architectural duplication by ensuring that each rule and each state transition has one clear owner.

This plan does **not** aim for hexagonal architecture. It aims for:

- one authoritative playback/session state model
- one owner for playback lifecycle rules
- one reusable mechanism for cancellable "latest request wins" async work
- pure presentation projection from state, without hidden business rules

## Current Problems

The codebase is cleaner than before, but it still has duplicated ownership in four places:

1. Playback lifecycle state exists in both `PlaybackState` and `PlaybackPresentationState` / `LoadingPresentationState`.
2. Playback and loading rules are split across `AudioPlaybackEngine`, `AudioPlayerLoadWorkflow`, and `AudioPlayerPlaybackWorkflow`.
3. Async generation and stale-result handling are implemented twice in the load and playback-start coordinators.
4. UI-facing status and screen facts are exposed through overlapping layers:
   `AudioPlayer`, `AudioPlayerStateStore`, presenters, and `ContentViewState`.

The result is not just extra code. It makes it unclear which layer is allowed to decide:

- whether a track is ready vs unavailable
- when loading starts and ends
- what happens when one async action interrupts another
- what the current playback lifecycle actually is

## Target Design

### 1. One Authoritative Session State

Create a single application-level state model owned by the UI-facing orchestration layer.

This state should contain:

- current playback lifecycle
- loaded audio info
- playlist session
- current playback time
- hardware snapshot
- transient async activity flags
- current status/error message

The important point is that this becomes the **only** place where the app-level truth lives.

The engine should still own `AVAudioPlayer`, but it should no longer be treated as a second public state machine.

### 2. One Owner for Playback Rules

Introduce one orchestration boundary for app behavior around playback.

Working name:

- `AudioPlayerSessionController`

Responsibilities:

- load file / folder / playlist track
- start, pause, stop, seek, skip
- handle autoplay and end-of-track progression
- coordinate progress tracking
- resolve interruptions between loading and playback start
- update authoritative session state

Non-responsibilities:

- direct SwiftUI projection
- low-level `AVAudioPlayer` operations
- file scanning and security-scoped access details

### 3. Engine Becomes a Narrow Runtime Adapter

Keep `AudioPlaybackEngine`, but narrow its role.

It should own:

- the active `AVAudioPlayer`
- file loading into a player session
- play / pause / stop / seek primitives
- sample-rate synchronization
- progress tracking bridge

It should not own the user-visible lifecycle as an independently meaningful state machine.

Concretely:

- either remove `PlaybackState` entirely from the engine
- or reduce it to internal runtime guards that are not mirrored as app state

Preferred direction:

- move toward a stateless or minimally stateful engine API that returns results, while the session controller owns the app state transitions

### 4. Presentation Becomes Pure Projection

Presentation code should derive UI models from the authoritative session state only.

That means:

- `ContentViewStatePresenter` projects screen state
- `SampleRatePresenter` projects sample-rate UI
- `PlayerStatusPresenter` projects status UI

None of these presenters should own fallback business rules that disagree with the controller.

`AudioPlayer` should expose:

- one or a few read models for the view
- command methods that delegate to the session controller

It should stop re-exposing overlapping fragments that compete with `ContentViewState`.

## Proposed Refactor Phases

### Phase 1: Define the New Authoritative State

Add a new application state type, likely under `Playback/UI/State/`, for example:

- `AudioPlayerSessionState`

It should unify the concepts currently split across:

- `PlaybackState`
- `PlaybackPresentationState`
- `LoadingPresentationState`
- parts of `PlayerScreenState`

Suggested structure:

- `playback`: idle / loading / ready / playing / paused / finished / failed
- `playbackContext`: optional `AudioInfo`
- `activity`: scanning folder / loading track / starting playback / idle
- `playlistSession`
- `currentTime`
- `hardware`
- `status`

Deliverables:

- new state type
- projection helpers for common derived facts
- tests covering lifecycle transitions and derived queries

Exit criteria:

- a reviewer can point at one type and say "this is the app's playback truth"

### Phase 2: Move Lifecycle Rules into One Controller

Create `AudioPlayerSessionController`.

Move into it the rule ownership currently split between:

- `AudioPlayerLoadWorkflow`
- `AudioPlayerPlaybackWorkflow`
- parts of `AudioPlayer`

This controller should receive collaborators such as:

- engine
- folder scanner or load coordinator
- progress tracker
- hardware monitor or hardware info provider
- presenters if needed, though pure projection is preferred

Deliverables:

- controller with command methods for load/play/pause/stop/seek/skip/select-next/select-previous
- central lifecycle transition methods
- central interruption policy

Exit criteria:

- there is one place to inspect when asking "what happens if loading interrupts playback startup?"

### Phase 3: Replace Two Async Coordinators with One Reusable Primitive

Extract the shared generation/cancellation pattern from:

- `AudioPlayerLoadCoordinator`
- `PlaybackStartupCoordinator`

Working names:

- `LatestTaskRunner`
- `GenerationBoundTask`
- `InterruptibleAsyncAction`

It should support:

- replacing an in-flight task
- ignoring stale completion
- explicit cancellation
- waiting for current completion

Use this primitive inside the session controller instead of preserving two separate coordinator types unless one still has unique behavior worth keeping.

Deliverables:

- reusable async latest-wins helper
- updated load/start orchestration built on that helper
- focused tests for stale result suppression and cancellation behavior

Exit criteria:

- there is exactly one concurrency pattern for "start async work, but only latest result counts"

### Phase 4: Reduce the Engine to Runtime Concerns

Refactor `AudioPlaybackEngine` so it no longer acts like a second app-state owner.

Likely changes:

- stop exposing app-level `PlaybackState` as the main contract
- make load/play/pause/stop/seek return concrete results or throw errors
- keep only the minimal internal runtime state necessary to safely manage `AVAudioPlayer`

This phase should be conservative. The goal is not a philosophical rewrite. The goal is to stop duplicating lifecycle meaning above and below the UI layer.

Deliverables:

- simplified engine API
- fewer duplicated transitions between engine and UI
- updated tests around engine-only responsibilities

Exit criteria:

- app lifecycle meaning is owned above the engine
- engine is a runtime dependency, not a peer state machine

### Phase 5: Collapse Overlapping Read Models

Trim the public surface of `AudioPlayer` and `AudioPlayerStateStore`.

Current overlap:

- `AudioPlayer` exposes many individual facts
- `AudioPlayerStateStore` exposes additional derived facts
- `ContentViewStatePresenter` constructs a full screen model

Refactor so the view consumes a smaller number of projections, ideally:

- `contentViewState`
- maybe one diagnostics/read model if the view truly needs it separately

Remove pass-through properties that duplicate information already present in the projected state unless there is a strong reason to keep them.

Deliverables:

- smaller `AudioPlayer` API
- reduced surface area in `AudioPlayerStateStore`
- presenters operating from the new unified state

Exit criteria:

- there is one obvious way for SwiftUI to read current playback UI state

### Phase 6: Deduplicate Status Presentation

Unify `PlayerStatusReadyInput` and `PlayerStatusPlayingInput` into one model, for example:

- `PlayerStatusContext`

Then make the presenter decide based on a single phase enum:

- ready
- playing
- loading
- error
- informational

This is a smaller cleanup, but it matters because status text is currently assembled in multiple places from almost identical inputs.

Deliverables:

- single status input type
- simplified `PlayerStatusPresenter`
- reduced repeated message-building in workflows/controller

Exit criteria:

- status text rules live in one presentation path

## Recommended Order

Implement in this order:

1. Phase 1
2. Phase 3
3. Phase 2
4. Phase 4
5. Phase 5
6. Phase 6

Reasoning:

- Phase 1 establishes a target state model.
- Phase 3 gives a reusable async control primitive before more orchestration moves around.
- Phase 2 centralizes behavior using the new state and async primitive.
- Phase 4 simplifies the engine only after the controller exists.
- Phases 5 and 6 are cleanup passes once ownership is already correct.

## Concrete File Impact

Expected files to change heavily:

- `AdaptiveMusicPlayer/Playback/UI/AudioPlayer.swift`
- `AdaptiveMusicPlayer/Playback/UI/State/AudioPlayerStateStore.swift`
- `AdaptiveMusicPlayer/Playback/UI/Workflow/AudioPlayerLoadWorkflow.swift`
- `AdaptiveMusicPlayer/Playback/UI/Workflow/AudioPlayerPlaybackWorkflow.swift`
- `AdaptiveMusicPlayer/Playback/UI/Coordination/AudioPlayerLoadCoordinator.swift`
- `AdaptiveMusicPlayer/Playback/UI/Coordination/PlaybackStartupCoordinator.swift`
- `AdaptiveMusicPlayer/Playback/Engine/AudioPlaybackEngine.swift`
- `AdaptiveMusicPlayer/Playback/UI/Presentation/PlayerStatusPresenter.swift`
- `AdaptiveMusicPlayer/Playback/UI/Presentation/ContentViewStatePresenter.swift`
- `AdaptiveMusicPlayer/Playback/UI/Presentation/PlayerScreenStateReducer.swift`

Expected new files:

- session state type
- session controller
- shared async latest-task helper

Expected files likely to shrink substantially or disappear:

- `AudioPlayerLoadWorkflow.swift`
- `AudioPlayerPlaybackWorkflow.swift`
- one or both coordinator types
- `PlayerScreenStateReducer.swift` if transitions move fully into the controller

## Testing Strategy

Add or update tests in this order:

1. State transition tests for the new authoritative session state.
2. Latest-task helper tests for cancellation and stale completion.
3. Session controller tests for:
   - load file
   - load folder
   - autoplay next track
   - cancelling load with pending playback start
   - selecting playlist track during startup
   - playback finish behavior
4. Presenter tests to verify pure projection from state.
5. Engine tests narrowed to runtime behavior only.

Keep existing behavior tests where possible, but rewrite them to target the new owner of the rule.

## Guardrails

During implementation:

- do not move UI formatting rules into the engine
- do not let presenters mutate state
- do not keep mirrored lifecycle enums unless one is strictly UI-only and derived
- do not add another orchestration layer on top of the current two workflows
- prefer deleting old abstractions after migration instead of keeping compatibility wrappers long-term

## Definition of Done

This refactor is complete when:

- app lifecycle truth is represented once
- interruption and cancellation policy is represented once
- playback/load orchestration is represented once
- presentation is a projection of state rather than a second source of policy
- the public `AudioPlayer` surface is smaller and clearer than today

## Open Decisions

These should be resolved during Phase 1 before larger moves:

1. Should `AudioPlayerStateStore` survive as a mutable container around the new authoritative state, or should `AudioPlayer` own the state directly?
2. Should `AudioPlaybackEngine` retain any public state enum at all, or should it expose only commands and query methods?
3. Should folder scanning stay in a dedicated load coordinator, or move directly into the new session controller once the shared async helper exists?

## Recommendation on Open Decisions

Current recommendation:

1. Keep `AudioPlayerStateStore`, but reduce it to a thin observable container around one authoritative session state object.
2. Remove public app-level state ownership from `AudioPlaybackEngine`; keep only runtime state needed for safe media control.
3. Move folder scanning orchestration into the session controller after extracting the shared async helper. Keep dedicated services, but reduce dedicated coordinators.
