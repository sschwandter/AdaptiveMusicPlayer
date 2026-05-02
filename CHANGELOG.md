# Changelog

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
