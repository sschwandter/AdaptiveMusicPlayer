# TODO: Sync Sample Rate Follow-Ups

## Review findings

- [ ] Cancel any pending playback-start task when beginning a new file or playlist-track load. Right now `beginLoading()` does not invalidate `playbackStartupTask`, so a stale startup can finish against a replaced player/state and surface the wrong error or start the wrong player after the user has already moved on.
- [ ] Decide how the main play/pause button should behave while startup is pending, and cover it with a test. `togglePlayPause()` only checks `isPlaying`, so a second tap during sample-rate switching is treated as another Play request and becomes a no-op instead of canceling startup.

## Fix playback-start races

- [x] Serialize playback startup so repeated taps on Play cannot spawn overlapping startup tasks.
- [x] Introduce an explicit "starting playback" state, or track a cancellable startup task in `AudioPlayer`.
- [x] Make `Play`, `Pause`, and `Stop` coordinate through the same startup flow so a stop or pause request can cancel a pending playback start before audio begins.

## Simplify sample-rate switching responsibility

- [x] Decide whether sample-rate switching should happen on file load or only when playback starts.
- [x] If the product rule is "set the sample rate when playback starts", remove the load-time switch from `AdaptiveMusicPlayer/Playback/Services/AudioSessionManager.swift` to avoid duplicate switching attempts and duplicate delays.
- [x] Keep one authoritative code path for "switch hardware to file sample rate" so behavior is easier to reason about and test.

## Clean up presentation logic

- [x] Consider replacing the separate badge title/color/icon branches in `AdaptiveMusicPlayer/Playback/UI/ContentView.swift` with a small presentation model from `AudioPlayer`.
- [x] Keep the view focused on rendering and move status derivation into one UI-facing type or enum.

## Tests to add

- [x] Add a test covering rapid repeated Play taps while startup is still pending.
- [x] Add a test covering `Stop` during a delayed sample-rate switch, proving playback does not start afterward.
- [x] Add a test covering the already-matched case, proving playback skips the hardware switch.
- [ ] Add a test covering `Pause` during startup if pause is expected to cancel or block startup.
