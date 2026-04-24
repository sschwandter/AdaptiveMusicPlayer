# Review Guidelines

This document describes how changes in Adaptive Music Player should be reviewed.

The goal is not stylistic perfection. The goal is to keep playback behavior correct, async flows predictable, and the codebase easy to evolve.

## Review Priorities

Review changes in this order:

1. Correctness
   Does the code behave correctly for the happy path and realistic edge cases?
2. Behavioral regressions
   Could this break an existing user workflow such as loading, playback start, seeking, stop, autoplay, or playlist navigation?
3. Concurrency and cancellation safety
   Do async tasks cancel cleanly, suppress stale results, and avoid updating state after ownership has changed?
4. State ownership
   Is there one clear owner for each user-visible rule, or is state being mutated from too many places?
5. Testability
   Are important transitions and failure paths covered by focused tests?
6. Maintainability
   Will the next change be easier or harder because of this implementation?
7. Style and consistency
   Follow the existing Swift and SwiftUI conventions, but do not prioritize style over behavior.

## Repo-Specific Heuristics

When reviewing this project, pay extra attention to these areas:

- Playback lifecycle
  Loading, startup, progress tracking, finish handling, pause, stop, and autoplay should stay symmetric and explicit.
- Latest-request-wins behavior
  Folder scans, file loads, and playback starts must not allow stale async results to publish after a newer request takes over.
- Main-actor boundaries
  UI-facing state should stay on the main actor, while blocking work should stay off it.
- Reducer-backed session state
  Prefer keeping user-visible state transitions in the session-state flow instead of scattering mutations across the UI and engine.
- Engine vs. controller ownership
  The engine should stay focused on runtime playback behavior. App-level orchestration belongs in the session controller and coordinators.
- User-visible messaging
  Status text, loading banners, and command availability should match the actual playback context.

## What Counts As A Good Change

A strong change in this repo usually has these properties:

- It preserves or improves existing playback behavior.
- It makes ownership clearer instead of introducing another parallel state path.
- It handles cancellation and stale async work deliberately.
- It adds or updates focused tests when behavior changes.
- It avoids broad refactors unless they clearly simplify the current design.

## Common Red Flags

These are worth calling out during review:

- Async work that can outlive the state it was started for.
- Background polling or refresh loops without a clear teardown path.
- Status or loading state that depends on incidental side effects instead of explicit transitions.
- Duplicate sources of truth between the engine, controller, store, and view layer.
- UI command paths that behave differently from on-screen controls for the same feature.
- Refactors that rename patterns without improving ownership, testability, or correctness.

## Architecture Expectations During Review

This project does not need a framework-heavy rewrite.

Prefer a pragmatic architecture:

- `AudioPlayerSessionController` owns app-level orchestration.
- `AudioPlayerSessionState` is the authoritative UI-facing state.
- Reducer-style transitions remain the default way to update that state.
- Services and engine operations stay narrow and focused.
- Views consume presentation models and send commands instead of owning playback rules.

Review should reinforce those boundaries rather than chase abstract purity.
