# Contributing

Thanks for your interest in contributing to Adaptive Music Player.

## Before You Start

- Please open an issue first for significant changes.
- Keep pull requests focused and small when possible.
- Make sure the app builds and tests pass before submitting.

## Development Setup

1. Open `AdaptiveMusicPlayer.xcodeproj` in Xcode.
2. Use the `AdaptiveMusicPlayer` scheme.
3. Run unit tests with:

```sh
xcodebuild test -scheme AdaptiveMusicPlayer -destination 'platform=macOS' -only-testing:AdaptiveMusicPlayerTests
```

## Pull Requests

- Describe the user-facing change clearly.
- Mention testing performed.
- Include screenshots for UI changes when helpful.
- Avoid unrelated refactors in the same PR.

## Style

- Follow the existing Swift and SwiftUI patterns in the project.
- Prefer small, readable helpers over large rewrites.
- Add or update tests when behavior changes.
