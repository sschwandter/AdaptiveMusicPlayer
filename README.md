# Adaptive Music Player

Adaptive Music Player is a macOS audio player focused on sample-rate-aware playback. It plays local audio files, shows both file and hardware sample rates, and attempts to switch the output device to the file's rate when playback starts and the hardware does not already match.

## Features

- Local file playback using `AVAudioPlayer`
- File and hardware sample-rate display
- Automatic sample-rate switching on playback start when needed
- Transport controls, progress display, and volume control
- Playlist/folder loading with next/previous track support
- Keyboard shortcuts for common playback actions

## Requirements

- macOS
- Xcode with current macOS SDK support

## Build And Run

1. Open `AdaptiveMusicPlayer.xcodeproj` in Xcode.
2. Select the `AdaptiveMusicPlayer` scheme.
3. Build and run the app on macOS.

## Run Tests

```sh
xcodebuild test -scheme AdaptiveMusicPlayer -destination 'platform=macOS' -only-testing:AdaptiveMusicPlayerTests
```

## Sample Rate Behavior

When playback starts, the app compares the file sample rate with the current hardware sample rate.

- If they already match, playback starts without a hardware change.
- If they differ, the app tries to switch the output device to the file sample rate before playback continues.
- If the switch fails, playback still starts and the UI shows that hardware and file rates differ.

## Project Structure

- `AdaptiveMusicPlayer/`
  App source, playback domain logic, services, use cases, and SwiftUI UI.
- `AdaptiveMusicPlayerTests/`
  Unit tests and shared test support.
- `AdaptiveMusicPlayerUITests/`
  UI tests.

## Contributing

Please read [CONTRIBUTING.md](CONTRIBUTING.md) before opening a pull request.

## Security

Please read [SECURITY.md](SECURITY.md) for how to report security issues.

## License

This project is licensed under the MIT License. See [LICENSE](LICENSE).
