# Contributing

Thanks for your interest in contributing to Adaptive Music Player.

## Before You Start

- Please open an issue first for significant changes.
- Keep pull requests focused and small when possible.
- Make sure the app builds and tests pass before submitting.

## Development Setup

1. Open `AdaptiveMusicPlayer.xcodeproj` in Xcode.
2. Use the `AdaptiveMusicPlayer` scheme.
3. Enable the tracked Git hooks with `git config core.hooksPath .githooks`.
4. Run unit tests with:

```sh
xcodebuild test -scheme AdaptiveMusicPlayer -destination 'platform=macOS' -only-testing:AdaptiveMusicPlayerTests
```

## Pull Requests

- Describe the user-facing change clearly.
- Mention testing performed.
- Include screenshots for UI changes when helpful.
- Avoid unrelated refactors in the same PR.
- Releases are created from `main` with `release-please`; do not create release tags manually.

## Style

- Follow the existing Swift and SwiftUI patterns in the project.
- Prefer small, readable helpers over large rewrites.
- Add or update tests when behavior changes.
- Use Conventional Commit messages such as `fix: ...` and `feat: ...`.
