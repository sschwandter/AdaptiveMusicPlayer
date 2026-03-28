# TODO

## Issues

### High Priority

- [x] **Core Audio blocks main thread** — Fixed. `getCurrentHardwareSampleRate()` now uses `Task.detached` to run Core Audio reads off the main thread. `setSampleRate()` calls were already safe in Swift 6 (nonisolated async hop); fixed misleading comments.

- [x] **File loading race condition** — Fixed. Added `loadGeneration` counter so stale task completions from cancelled loads are silently discarded.

### Medium Priority

- [x] **`AudioSession` marked `Sendable` but contains `AVAudioPlayer`** — Fixed. Changed to `@unchecked Sendable` with safety comment (created on background, consumed on MainActor).

- [x] **Protocol `Sendable` vs `@MainActor` mismatch** — Fixed. Removed `@MainActor` from `PlaybackControlUseCase` and `SeekingUseCase` (stateless, no isolation needed).

- [x] **Combine usage despite project convention** — Won't fix. The single `Timer.publish(...).values` usage is a lightweight bridge to AsyncSequence, not a heavy Combine dependency. RunLoop-based timing is more consistent for UI progress updates than `Task.sleep`.

- [x] **Duplicate `SampleRateManager` instances** — Fixed. `AudioPlaybackEngine` now shares its `sampleRateManager` with `AudioSessionManager` via constructor injection.

### Low Priority

- [ ] **Stop button disabled when paused** — `disabled(!player.isPlaying)` prevents stopping from a paused state, which is a common user expectation. Consider `disabled(player.currentFileName == nil)`. (`ContentView.swift:156`)

- [x] **File picker error bypasses `updateStatus()`** — Fixed. Added `reportFileSelectionError()` on AudioPlayer so ContentView routes errors through `updateStatus()`.

- [ ] **`getSupportedSampleRates` ignores range maximums** — `AudioValueRange` has `mMinimum` and `mMaximum`. For discrete rates they're equal, but range-reporting devices could be handled incorrectly. Consider handling the range case. (`SampleRateManager.swift:141`)

- [ ] **Fragile file picker dismissal workaround** — `DispatchQueue.main.async` wrapping a `Task` with a 50ms sleep is a workaround for file picker dismissal on network shares. The `try?` silently swallows cancellation errors. Document why this exists and revisit on future macOS versions. (`ContentView.swift:233-238`)
