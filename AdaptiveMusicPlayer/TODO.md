# TODO

## Issues

### High Priority

- [x] **Core Audio blocks main thread** — Fixed. `getCurrentHardwareSampleRate()` now uses `Task.detached` to run Core Audio reads off the main thread. `setSampleRate()` calls were already safe in Swift 6 (nonisolated async hop); fixed misleading comments.

- [ ] **File loading race condition** — `AudioPlayer.loadFile()` cancels the previous `loadingTask` then creates a new one, but cancellation is cooperative. The old task's error handler could run after the new task succeeds, overwriting good state with an error. Add a generation counter or task identity check so stale completions are discarded. (`AudioPlayer.swift:78-106`)

### Medium Priority

- [ ] **`AudioSession` marked `Sendable` but contains `AVAudioPlayer`** — `AVAudioPlayer` is not `Sendable`. This compiles today but is semantically unsafe and may break in future Swift versions. Consider removing the `Sendable` conformance or wrapping the player access. (`AudioSessionManager.swift:5`)

- [ ] **Protocol `Sendable` vs `@MainActor` mismatch** — `PlaybackControlUseCaseProtocol` and `SeekingUseCaseProtocol` require `Sendable`, but their concrete implementations are `@MainActor`. A caller off the main actor could theoretically invoke these and violate isolation. Make the protocols `@MainActor` or remove `Sendable`. (`PlaybackControlUseCase.swift:5,32`, `SeekingUseCase.swift:5,36`)

- [ ] **Combine usage despite project convention** — `PlaybackProgressTracker` imports Combine and uses `Timer.publish().autoconnect().values`. The CLAUDE.md states to avoid Combine and prefer async/await. Replace with a `while !Task.isCancelled` loop using `Task.sleep`. (`PlaybackProgressTracker.swift:3,65`)

- [ ] **Duplicate `SampleRateManager` instances** — `AudioPlaybackEngine` and `AudioSessionManager` each create their own `CoreAudioSampleRateManager`. Not a bug today since neither caches state, but a maintenance risk. Consider sharing a single instance via dependency injection. (`AudioPlaybackEngine.swift:29`, `AudioSessionManager.swift:39`)

### Low Priority

- [ ] **Stop button disabled when paused** — `disabled(!player.isPlaying)` prevents stopping from a paused state, which is a common user expectation. Consider `disabled(player.currentFileName == nil)`. (`ContentView.swift:156`)

- [ ] **File picker error bypasses `updateStatus()`** — The `.failure` case in the `fileImporter` result sets `statusMessage` and `hasError` directly, breaking the single-source-of-truth pattern. Route through `AudioPlayer`'s error handling instead. (`ContentView.swift:241-242`)

- [ ] **`getSupportedSampleRates` ignores range maximums** — `AudioValueRange` has `mMinimum` and `mMaximum`. For discrete rates they're equal, but range-reporting devices could be handled incorrectly. Consider handling the range case. (`SampleRateManager.swift:141`)

- [ ] **Fragile file picker dismissal workaround** — `DispatchQueue.main.async` wrapping a `Task` with a 50ms sleep is a workaround for file picker dismissal on network shares. The `try?` silently swallows cancellation errors. Document why this exists and revisit on future macOS versions. (`ContentView.swift:233-238`)
