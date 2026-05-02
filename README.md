# Adaptive Music Player

Adaptive Music Player is a macOS audio player focused on sample-rate-aware playback. It plays local audio files, shows both file and hardware sample rates, and attempts to switch the output device to the file's rate for bit-perfect playback when possible.

Download the current release from [Latest release](https://github.com/sschwandter/AdaptiveMusicPlayer/releases/latest) and choose the packaged app asset from the release page.

![Adaptive Music Player screenshot](docs/screenshots/app-screenshot.png)

Technical details: [Architecture notes](docs/ARCHITECTURE.md)

## Features

- Local audio playback on macOS
- File and hardware sample-rate display
- Automatic hardware sample-rate switching when needed
- Playback progress, transport controls, and volume control
- Playlist and folder playback support
- Keyboard shortcuts for common playback actions

## Requirements

- macOS 26 or later
- Xcode with macOS 26 SDK support

## Build And Run

1. Open `AdaptiveMusicPlayer.xcodeproj` in Xcode.
2. Select the `AdaptiveMusicPlayer` scheme.
3. Build and run the app on macOS.

## Run Tests

```sh
xcodebuild test -project AdaptiveMusicPlayer.xcodeproj -scheme AdaptiveMusicPlayer -destination 'platform=macOS' -only-testing:AdaptiveMusicPlayerTests
```

UI tests exist, but command-line execution may depend on the local environment and permissions available to the test runner.

## Code Structure

The project is split into two primary targets:

### AdaptiveMusicPlayer (App)
The main application target, located under `AdaptiveMusicPlayer/`.
- Contains the SwiftUI app shell, menu commands, and playback UI layer.
- The UI sends commands into an app-level session controller instead of owning playback rules directly.

### AdaptiveMusicPlayerCore (Framework)
The playback framework target, located under `AdaptiveMusicPlayerCore/`.
- Contains playback domain models, the event-driven playback engine, engine operations, system audio services, and shared utilities.
- Does not contain SwiftUI presentation or app command routing.

For the authoritative contributor-focused walkthrough of both targets, see [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md).

## Releases

Releases are managed with `release-please` and GitHub Actions.

- Pushes to `main` update or create a release PR based on Conventional Commits.
- When the release PR lands and CI passes, the release workflow creates the tag, signs and notarizes the app, and uploads the packaged build to the GitHub release.
- There is also a manual release workflow that can rebuild and upload a tagged release on demand.

Examples:

- `fix: handle missing output device` -> patch release
- `feat: add folder playback shortcuts` -> minor release
- `feat!: redesign playback session model` or a commit body containing `BREAKING CHANGE:` -> major release

## Sample Rate Behavior

When playback starts, the app compares the file sample rate with the current hardware sample rate.

- If they already match, playback starts without a hardware change.
- If they differ, the app tries to switch the output device to the file sample rate before playback continues.
- If the switch fails, playback still starts and the UI shows that hardware and file rates differ.

## Supported Formats

The app relies on system audio support through `AVAudioPlayer` and Core Audio. In practice, that includes common formats such as:

- MP3
- WAV
- AIFF
- AAC / M4A
- Other formats supported by the current macOS audio stack

## Contributing

Please read [CONTRIBUTING.md](CONTRIBUTING.md) before opening a pull request.

## Security

Please read [SECURITY.md](SECURITY.md) for how to report security issues.

## License

This project is licensed under the MIT License. See [LICENSE](LICENSE).
