# Changelog

## [0.8.1](https://github.com/sschwandter/AdaptiveMusicPlayer/compare/AdaptiveMusicPlayer-v0.8.0...AdaptiveMusicPlayer-v0.8.1) (2026-07-12)


### Bug Fixes

* Fixes and cleanups ([d6f88b9](https://github.com/sschwandter/AdaptiveMusicPlayer/commit/d6f88b9d49917a26bc384f2a5683067840e4673a))

## [0.8.0](https://github.com/sschwandter/AdaptiveMusicPlayer/compare/AdaptiveMusicPlayer-v0.7.4...AdaptiveMusicPlayer-v0.8.0) (2026-07-10)


### Features

* continue playback when the window closes, restore state on reopen ([dabe2ee](https://github.com/sschwandter/AdaptiveMusicPlayer/commit/dabe2eee0b81c0f2fc07f8c450d725972b228a05))
* drag & drop files and folders onto the player window ([6eab040](https://github.com/sschwandter/AdaptiveMusicPlayer/commit/6eab040eb79ca77ebcda2a10b50eede2de5e9c21))
* drag & drop files and folders onto the player window ([08737b4](https://github.com/sschwandter/AdaptiveMusicPlayer/commit/08737b4e38adad60b9bcd8e06f14a8fa7d02e82b))
* make the player a single-window app ([8978715](https://github.com/sschwandter/AdaptiveMusicPlayer/commit/897871510a33c58ce4de967b7648a8e4db05d04b))
* single-window app with playback that survives window close, plus task-lifetime, menu, and seek fixes ([bd2f560](https://github.com/sschwandter/AdaptiveMusicPlayer/commit/bd2f56034b93bd9bf16c42e281412742b7e7acc4))


### Bug Fixes

* hold the security scope across the metadata title read ([533957b](https://github.com/sschwandter/AdaptiveMusicPlayer/commit/533957b4333bbf15f93a7f0cd2aeaf55ca317233))
* hold the security scope across the metadata title read ([222792e](https://github.com/sschwandter/AdaptiveMusicPlayer/commit/222792e2e8c39ef964e9fd5de2acafa32b1195e9)), closes [#19](https://github.com/sschwandter/AdaptiveMusicPlayer/issues/19)
* identity-check the stale-startup stop so it cannot stop a newer player ([5825712](https://github.com/sschwandter/AdaptiveMusicPlayer/commit/5825712f7b1087280782d2072b9acbe60209c2cf))
* identity-check the stale-startup stop so it cannot stop a newer player ([a655e4c](https://github.com/sschwandter/AdaptiveMusicPlayer/commit/a655e4c35fe535d9896b6bb4cb7a793f72c5267c)), closes [#21](https://github.com/sschwandter/AdaptiveMusicPlayer/issues/21)
* keep the app running when the player window closes ([b4429f9](https://github.com/sschwandter/AdaptiveMusicPlayer/commit/b4429f9d5010101abe291be97d83de336ac13a5e))
* prevent stale progress-tracking cleanup from clobbering a newer session ([fac194a](https://github.com/sschwandter/AdaptiveMusicPlayer/commit/fac194a27ba4f8669471b3ae8f0b796baf638248))
* prevent stale progress-tracking cleanup from clobbering a newer session ([5f2aa22](https://github.com/sschwandter/AdaptiveMusicPlayer/commit/5f2aa224970cf1c4f5c71c8813b60d3d6997231a))
* reset playback position to start on stop ([da2239d](https://github.com/sschwandter/AdaptiveMusicPlayer/commit/da2239d6e5471bf4791910c9863aa916bcdbacda))
* reset playback position to start on stop ([0ec3beb](https://github.com/sschwandter/AdaptiveMusicPlayer/commit/0ec3bebf7dd829e5b0d91f7f52f8e68de2b8652d))
* stop menu flicker and crash from focused-value churn ([32925a2](https://github.com/sschwandter/AdaptiveMusicPlayer/commit/32925a2e4e49be32df7d2a7b69c9a3165b5b154d))
* stop playback outliving its window and unstick seek latch ([af6d703](https://github.com/sschwandter/AdaptiveMusicPlayer/commit/af6d7038e9f1f6ddebac91a8acd427fed66c28e7))
* suppress stale load completions after a replacing load takes over ([d5417bc](https://github.com/sschwandter/AdaptiveMusicPlayer/commit/d5417bc840770a57ea4789a7141c89e166e693bb))
* suppress stale load completions after a replacing load takes over ([eca14ff](https://github.com/sschwandter/AdaptiveMusicPlayer/commit/eca14ffa7ea6d71ffafa81fe9461c6f96954d07a))
* tighten playback cancellation, error mapping, and task lifetimes ([2130bf0](https://github.com/sschwandter/AdaptiveMusicPlayer/commit/2130bf07edee05b377e0b6fb5d0b785d66702f11))

## [0.7.4](https://github.com/sschwandter/AdaptiveMusicPlayer/compare/AdaptiveMusicPlayer-v0.7.3...AdaptiveMusicPlayer-v0.7.4) (2026-05-02)


### Bug Fixes

* trigger release pipeline ([c150492](https://github.com/sschwandter/AdaptiveMusicPlayer/commit/c150492b77f9e9e5a4a3742105d32b18ad3d60e4))

## [0.7.3](https://github.com/sschwandter/AdaptiveMusicPlayer/compare/AdaptiveMusicPlayer-v0.7.2...AdaptiveMusicPlayer-v0.7.3) (2026-05-02)


### Bug Fixes

* test release pipeline ([e924697](https://github.com/sschwandter/AdaptiveMusicPlayer/commit/e9246971bf1baace748c10458944d72f8f00d927))

## [0.7.2](https://github.com/sschwandter/AdaptiveMusicPlayer/compare/AdaptiveMusicPlayer-v0.7.1...AdaptiveMusicPlayer-v0.7.2) (2026-05-02)


### Bug Fixes

* tolerate prepare failure in playback tests ([6c0309c](https://github.com/sschwandter/AdaptiveMusicPlayer/commit/6c0309c789d8ba78d134e83e46d1b468b03ba3e5))

## [0.7.1](https://github.com/sschwandter/AdaptiveMusicPlayer/compare/AdaptiveMusicPlayer-v0.7.0...AdaptiveMusicPlayer-v0.7.1) (2026-05-02)


### Bug Fixes

* stabilize playback after sample rate switch ([7b78732](https://github.com/sschwandter/AdaptiveMusicPlayer/commit/7b787327021b95d7a1bf51625788e4500de75fb7))

## [0.7.0](https://github.com/sschwandter/AdaptiveMusicPlayer/compare/AdaptiveMusicPlayer-v0.6.1...AdaptiveMusicPlayer-v0.7.0) (2026-05-02)


### Features

* Phase 2 - AsyncStream modernization with debounce ([47c3670](https://github.com/sschwandter/AdaptiveMusicPlayer/commit/47c36709cc246231fb397b4aa0d132915e8b0014))


### Bug Fixes

* clean up playback finish lifecycle and add review guide ([2ff3172](https://github.com/sschwandter/AdaptiveMusicPlayer/commit/2ff3172294ed0287a25a20f2e7f825f3ddba9c37))
* load audio sessions off main actor ([bf8df2a](https://github.com/sschwandter/AdaptiveMusicPlayer/commit/bf8df2a99acbd03c58d75332eb56908799f488aa))
* remove unsafe observer isolation and harden folder/workflow handling ([0edc485](https://github.com/sschwandter/AdaptiveMusicPlayer/commit/0edc485c2630344d082b7b3e35e58ca46cb8a52b))
* replace invalid playhead symbol ([1e3077f](https://github.com/sschwandter/AdaptiveMusicPlayer/commit/1e3077fe14f12645cae007eafc29ca5ef8637cda))
* restore folder load observation updates ([3cc290f](https://github.com/sschwandter/AdaptiveMusicPlayer/commit/3cc290f0c47352b4fc38b097d9ec76e84051ab85))
* restore live progress updates and offload folder scanning ([92c0010](https://github.com/sschwandter/AdaptiveMusicPlayer/commit/92c001068c3bad4262f1a957c8cbf6237650c528))

## [0.6.1](https://github.com/sschwandter/AdaptiveMusicPlayer/compare/AdaptiveMusicPlayer-v0.6.0...AdaptiveMusicPlayer-v0.6.1) (2026-04-21)


### Bug Fixes

* isolate hardware observation and sample rate access ([2be2422](https://github.com/sschwandter/AdaptiveMusicPlayer/commit/2be24227aa1ae72d29d732a4054c576cf2297ed5))

## [0.6.0](https://github.com/sschwandter/AdaptiveMusicPlayer/compare/AdaptiveMusicPlayer-v0.5.2...AdaptiveMusicPlayer-v0.6.0) (2026-04-17)


### Features

* trigger a fresh release after notarization retry ([6f991a9](https://github.com/sschwandter/AdaptiveMusicPlayer/commit/6f991a9bda6513035ac69314bda476746faa8681))


### Bug Fixes

* **ci:** force node24 for release-please ([b0e3c88](https://github.com/sschwandter/AdaptiveMusicPlayer/commit/b0e3c88389284aa81375b0d97c7793a4be82c71b))

## [0.5.2](https://github.com/sschwandter/AdaptiveMusicPlayer/compare/AdaptiveMusicPlayer-v0.5.1...AdaptiveMusicPlayer-v0.5.2) (2026-04-17)


### Bug Fixes

* build signed app in release-please workflow ([bd57b08](https://github.com/sschwandter/AdaptiveMusicPlayer/commit/bd57b08edd0d2822711b52d1f5b38166f4fc0147))

## [0.5.1](https://github.com/sschwandter/AdaptiveMusicPlayer/compare/AdaptiveMusicPlayer-v0.5.0...AdaptiveMusicPlayer-v0.5.1) (2026-04-17)


### Bug Fixes

* canonicalize finder test URLs in CI ([e6da255](https://github.com/sschwandter/AdaptiveMusicPlayer/commit/e6da255aa0bd47429f6c48831f28c36b0fb6abc8))
* gate release-please on successful CI ([8ca111b](https://github.com/sschwandter/AdaptiveMusicPlayer/commit/8ca111b33fda5c89bab666223de3edd727133741))

## [0.5.0](https://github.com/sschwandter/AdaptiveMusicPlayer/compare/AdaptiveMusicPlayer-v0.4.0...AdaptiveMusicPlayer-v0.5.0) (2026-04-17)


### Features

* redesign sample rate status feedback in the player UI ([c03aef7](https://github.com/sschwandter/AdaptiveMusicPlayer/commit/c03aef7c4b436877c6eeb0d86092a27ec236312f))

## [0.4.0](https://github.com/sschwandter/AdaptiveMusicPlayer/compare/AdaptiveMusicPlayer-v0.3.0...AdaptiveMusicPlayer-v0.4.0) (2026-04-04)


### Features

* context menu for current track: show in finder ([a717e46](https://github.com/sschwandter/AdaptiveMusicPlayer/commit/a717e463029cf8d3903b14d8de847caab5583b6f))


### Bug Fixes

* remaing changes for show in finder feature ([95c7b86](https://github.com/sschwandter/AdaptiveMusicPlayer/commit/95c7b864b8880e8f9a5cfca0bc1ee0e1b907b93d))

## [0.3.0](https://github.com/sschwandter/AdaptiveMusicPlayer/compare/AdaptiveMusicPlayer-v0.2.0...AdaptiveMusicPlayer-v0.3.0) (2026-04-01)


### Features

* show remaining playback time ([3153de7](https://github.com/sschwandter/AdaptiveMusicPlayer/commit/3153de71b9b7c057c67852e320c6d91030af3599))


### Bug Fixes

* clarify release testing workflow ([afa78ef](https://github.com/sschwandter/AdaptiveMusicPlayer/commit/afa78efc52a90f9450fa00932c27458a0655245b))
* note release-please permissions requirement ([43c29ef](https://github.com/sschwandter/AdaptiveMusicPlayer/commit/43c29ef48c67e2fb87a805fea332fb9061d56502))
* sync remaining time with playback progress ([7e35a11](https://github.com/sschwandter/AdaptiveMusicPlayer/commit/7e35a1178effa8da0bb9c6770b2adb5c7ad6a1cc))
* use supported release-please action ([cabf9be](https://github.com/sschwandter/AdaptiveMusicPlayer/commit/cabf9be225752d6dddbfb81568922c64f16ad595))
