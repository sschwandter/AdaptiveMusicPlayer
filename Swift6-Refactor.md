# Swift 6 Refactoring Plan - AdaptiveMusicPlayer

This document outlines the comprehensive refactoring plan to modernize the AdaptiveMusicPlayer codebase for Swift 6 strict concurrency, following best practices and modern Swift patterns.

## Executive Summary

The codebase requires refactoring in three priority levels:
1. **CRITICAL** - Must fix for Swift 6 compatibility and data race safety
2. **IMPORTANT** - Should fix for modern Swift patterns and better architecture
3. **NICE-TO-HAVE** - Optional improvements for code quality

## Phase 1: Critical Fixes (Must Complete)

### 1.1 Remove `nonisolated(unsafe)` from Timer ⚠️ CRITICAL

**File**: `AudioPlayer.swift:26`

**Problem**:
- Defeats Swift 6 data race protection
- Timer is already MainActor-isolated, no need to escape isolation

**Current Code**:
```swift
private nonisolated(unsafe) var timer: Timer?
```

**Fix**:
```swift
// Simply remove nonisolated(unsafe)
private var timer: Timer?
```

**Rationale**: The entire `AudioPlayer` class is `@MainActor`, so all properties are automatically MainActor-isolated. The timer is created and accessed on the main actor, making `nonisolated(unsafe)` unnecessary and dangerous.

---

### 1.2 Add Sendable Conformance ⚠️ CRITICAL

**File**: `AudioPlayer.swift:7`

**Problem**:
- Class is passed across concurrency boundaries without Sendable
- Swift 6 strict mode will reject this

**Current Code**:
```swift
@MainActor
class AudioPlayer: ObservableObject {
```

**Fix**:
```swift
@MainActor
final class AudioPlayer: ObservableObject, @unchecked Sendable {
```

**Rationale**:
- `@MainActor` ensures all access is serialized, making manual Sendable safe
- `final` prevents subclassing issues with actor isolation
- `@unchecked Sendable` acknowledges we're manually ensuring thread safety

---

### 1.3 Fix AVFoundation Callback Isolation ⚠️ CRITICAL

**Files**: `AudioPlayer.swift:161-165, 203-207, 229-233, 252-256`

**Problem**:
- Unstructured Task creation in completion handlers
- Unclear actor isolation
- No error handling or cancellation support

**Current Code**:
```swift
playerNode.scheduleFile(file, at: nil) { [weak self] in
    Task { @MainActor in
        self?.handlePlaybackFinished()
    }
}
```

**Fix**:
```swift
playerNode.scheduleFile(file, at: nil) { [weak self] in
    guard let self else { return }
    Task { @MainActor [weak self] in
        guard let self else { return }
        await self.handlePlaybackFinished()
    }
}
```

**Better Alternative** (extract to method):
```swift
@MainActor
private func schedulePlaybackWithCompletion(_ file: AVAudioFile) {
    playerNode.scheduleFile(file, at: nil) { [weak self] in
        Task { @MainActor [weak self] in
            await self?.handlePlaybackFinished()
        }
    }
}
```

**Rationale**: Makes actor isolation explicit and checked by compiler, prevents race conditions.

---

### 1.4 Fix Test Code Duplication ⚠️ CRITICAL

**File**: `AdaptiveMusicPlayerTests.swift:147-152`

**Problem**:
- Test duplicates production code in extension
- If production changes, tests don't catch regressions

**Current Code**:
```swift
extension ContentView {
    func timeString(_ time: Double) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}
```

**Fix Option 1** (Make method internal):
```swift
// In ContentView.swift - change from private to internal
func timeString(_ time: Double) -> String {
    let minutes = Int(time) / 60
    let seconds = Int(time) % 60
    return String(format: "%d:%02d", minutes, seconds)
}

// In tests - just use it directly, remove extension
```

**Fix Option 2** (Extract to utility - RECOMMENDED):
```swift
// New file: TimeFormatter.swift
struct TimeFormatter {
    static func format(_ time: Double) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

// In ContentView
private func timeString(_ time: Double) -> String {
    TimeFormatter.format(time)
}

// In tests
@Test("Time formatting works correctly")
func timeFormatting() async throws {
    #expect(TimeFormatter.format(0) == "0:00")
    #expect(TimeFormatter.format(30) == "0:30")
    // ...
}
```

**Rationale**: Tests should test actual production code, not duplicates. Extracting to utility makes it reusable and properly testable.

---

## Phase 2: Important Improvements (Should Complete)

### 2.1 Migrate to @Observable Framework 🔄 IMPORTANT

**File**: `AudioPlayer.swift:6-21`

**Problem**:
- Using legacy `ObservableObject` + `@Published`
- Less efficient than modern `@Observable` macro
- Requires Combine dependency

**Current Code**:
```swift
@MainActor
class AudioPlayer: ObservableObject {
    @Published var isPlaying = false
    @Published var currentTime: Double = 0
    @Published var duration: Double = 0
    // ... etc
}
```

**Fix**:
```swift
import Observation

@MainActor
@Observable
final class AudioPlayer {
    var isPlaying = false
    var currentTime: Double = 0
    var duration: Double = 0
    var volume: Double = 0.5 {
        didSet {
            audioEngine.mainMixerNode.outputVolume = Float(volume)
        }
    }
    var currentFileName: String?
    var fileSampleRate: Double = 0
    var hardwareSampleRate: Double = 0
    var statusMessage: String = ""
    var hasError: Bool = false
    var isLoading: Bool = false

    // Remove Combine import
    // Rest of implementation stays the same
}
```

**ContentView Update**:
```swift
struct ContentView: View {
    @State private var player = AudioPlayer()  // Change from @StateObject
    // ... rest remains the same
}
```

**Rationale**:
- Granular observation (only re-renders views using changed properties)
- No Combine dependency
- Better performance
- More idiomatic Swift 5.9+

---

### 2.2 Remove Unnecessary MainActor.run Calls 🔄 IMPORTANT

**File**: `AudioPlayer.swift` (multiple locations)

**Problem**:
- `MainActor.run` is redundant when already on MainActor
- Adds unnecessary overhead

**Current Code**:
```swift
private func loadFileAsync(url: URL) async {
    await MainActor.run {
        stop()
        audioFile = nil
        isLoading = true
        statusMessage = "Loading file..."
        hasError = false
    }
    // ...
}
```

**Fix**:
```swift
private func loadFileAsync(url: URL) async {
    // Already on MainActor, no need for MainActor.run
    stop()
    audioFile = nil
    isLoading = true
    statusMessage = "Loading file..."
    hasError = false

    // ... rest of method
}
```

**Locations to Fix**:
- Line 64-70: Initial state update
- Line 73-78: Error state update
- Line 96-101: File loaded state update
- Line 109-113: Ready state update
- Line 115-119: Warning state update
- Line 125-132: Error state update

**Rationale**: Cleaner code, less overhead, compiler already enforces MainActor isolation.

---

### 2.3 Add Task Cancellation Support 🔄 IMPORTANT

**File**: `AudioPlayer.swift:56-134`

**Problem**:
- Unstructured Task creation
- No cancellation when loading new file
- Can cause race conditions

**Current Code**:
```swift
func loadFile(url: URL) {
    Task {
        await loadFileAsync(url: url)
    }
}
```

**Fix**:
```swift
@MainActor
final class AudioPlayer {
    private var loadingTask: Task<Void, Never>?

    func loadFile(url: URL) async {
        // Cancel any existing load operation
        loadingTask?.cancel()

        loadingTask = Task {
            await loadFileAsync(url: url)
        }

        await loadingTask?.value
    }

    private func loadFileAsync(url: URL) async {
        // Check for cancellation early
        guard !Task.isCancelled else { return }

        stop()
        audioFile = nil
        isLoading = true
        statusMessage = "Loading file..."
        hasError = false

        guard url.startAccessingSecurityScopedResource() else {
            statusMessage = "Error: Cannot access file"
            hasError = true
            isLoading = false
            return
        }

        defer {
            url.stopAccessingSecurityScopedResource()
        }

        // Check cancellation before expensive operations
        guard !Task.isCancelled else {
            isLoading = false
            return
        }

        do {
            let file = try AVAudioFile(forReading: url)

            guard !Task.isCancelled else {
                isLoading = false
                return
            }

            audioFile = file
            let format = file.processingFormat
            sampleRate = format.sampleRate
            audioLengthSamples = file.length

            fileSampleRate = sampleRate
            currentFileName = url.lastPathComponent
            duration = Double(audioLengthSamples) / sampleRate
            currentTime = 0

            // Set hardware sample rate
            do {
                try setSystemSampleRate(sampleRate)
                try await Task.sleep(nanoseconds: 500_000_000)

                guard !Task.isCancelled else {
                    isLoading = false
                    return
                }

                updateHardwareSampleRate()
                statusMessage = "Ready to play at \(Int(sampleRate)) Hz"
                hasError = false
                isLoading = false
            } catch {
                statusMessage = "Warning: Could not set sample rate - \(error.localizedDescription)"
                hasError = false
                isLoading = false
                updateHardwareSampleRate()
            }

        } catch is CancellationError {
            statusMessage = "Loading cancelled"
            isLoading = false
        } catch {
            statusMessage = "Error loading file: \(error.localizedDescription)"
            hasError = true
            isLoading = false
            currentFileName = nil
            fileSampleRate = 0
            audioFile = nil
        }
    }
}
```

**ContentView Update**:
```swift
.fileImporter(...) { result in
    switch result {
    case .success(let urls):
        if let url = urls.first {
            Task {
                await player.loadFile(url: url)
            }
        }
    case .failure(let error):
        player.statusMessage = "Error selecting file: \(error.localizedDescription)"
        player.hasError = true
    }
}
```

**Rationale**: Prevents race conditions, better resource management, cleaner cancellation flow.

---

### 2.4 Improve Timer Lifecycle Management 🔄 IMPORTANT

**File**: `AudioPlayer.swift:275-303`

**Problem**:
- Timer logic mixed with playback time calculation
- Deinit comments are misleading
- Could be more robust

**Current Code**:
```swift
private var timerTickCount = 0

private func startTimer() {
    stopTimer()
    timerTickCount = 0
    timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
        guard let self = self else { return }
        Task { @MainActor in
            if let nodeTime = self.playerNode.lastRenderTime,
               let playerTime = self.playerNode.playerTime(forNodeTime: nodeTime) {
                let currentFrame = Double(playerTime.sampleTime)
                let newTime = currentFrame / self.sampleRate
                if abs(newTime - self.currentTime) > 0.05 {
                    self.currentTime = min(newTime, self.duration)
                }
            }

            self.timerTickCount += 1
            if self.timerTickCount >= 20 {
                self.updateHardwareSampleRate()
                self.timerTickCount = 0
            }
        }
    }
}

deinit {
    timer?.invalidate()
}
```

**Fix**:
```swift
private var timerTickCount = 0

private func startTimer() {
    stopTimer() // Ensure no timer leaks
    timerTickCount = 0

    timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
        Task { @MainActor [weak self] in
            await self?.updatePlaybackState()
        }
    }
}

private func stopTimer() {
    timer?.invalidate()
    timer = nil
    timerTickCount = 0
}

@MainActor
private func updatePlaybackState() {
    // Update playback time
    guard let nodeTime = playerNode.lastRenderTime,
          let playerTime = playerNode.playerTime(forNodeTime: nodeTime) else {
        return
    }

    let currentFrame = Double(playerTime.sampleTime)
    let newTime = currentFrame / sampleRate

    if abs(newTime - currentTime) > 0.05 {
        currentTime = min(newTime, duration)
    }

    // Update hardware sample rate every 2 seconds
    timerTickCount += 1
    if timerTickCount >= 20 {
        updateHardwareSampleRate()
        timerTickCount = 0
    }
}

deinit {
    // Clean up resources
    timer?.invalidate()
    timer = nil
    audioEngine.stop()
    audioEngine.detach(playerNode)
}
```

**Rationale**: Extracted logic is easier to test, clearer responsibilities, better cleanup.

---

### 2.5 Add Structured Error Types 🔄 IMPORTANT

**File**: `AudioPlayer.swift` (new section)

**Problem**:
- Errors only shown as UI strings
- No type safety
- Can't differentiate error types
- No logging/debugging support

**Fix** (add new error type):
```swift
// Add near top of file after imports
enum AudioPlayerError: LocalizedError {
    case engineStartFailed(underlying: Error)
    case fileLoadFailed(underlying: Error)
    case sampleRateNotSupported(requested: Double, supported: [Double])
    case invalidFileFormat
    case fileAccessDenied

    var errorDescription: String? {
        switch self {
        case .engineStartFailed(let error):
            return "Failed to start audio engine: \(error.localizedDescription)"
        case .fileLoadFailed(let error):
            return "Failed to load audio file: \(error.localizedDescription)"
        case .sampleRateNotSupported(let requested, let supported):
            return "Sample rate \(Int(requested)) Hz not supported. Available rates: \(supported.map(Int.init))"
        case .invalidFileFormat:
            return "Invalid or unsupported audio file format"
        case .fileAccessDenied:
            return "Cannot access file. Please check permissions."
        }
    }
}

// Add error handling helper
@MainActor
private func handleError(_ error: AudioPlayerError) {
    #if DEBUG
    print("AudioPlayer Error: \(error)")
    #endif

    statusMessage = error.localizedDescription
    hasError = true
}
```

**Update error handling throughout**:
```swift
// Example in setupAudioEngine
private func setupAudioEngine() {
    audioEngine.attach(playerNode)
    audioEngine.connect(playerNode, to: audioEngine.mainMixerNode, format: nil)
    audioEngine.mainMixerNode.outputVolume = Float(volume)

    do {
        try audioEngine.start()
    } catch {
        handleError(.engineStartFailed(underlying: error))
    }
}

// Example in loadFileAsync
guard url.startAccessingSecurityScopedResource() else {
    handleError(.fileAccessDenied)
    isLoading = false
    return
}

do {
    let file = try AVAudioFile(forReading: url)
    // ...
} catch {
    handleError(.fileLoadFailed(underlying: error))
    isLoading = false
    audioFile = nil
}
```

**Rationale**: Type-safe errors, better debugging, easier to add logging/telemetry later.

---

## Phase 3: Architecture Refactoring (Nice-to-Have)

### 3.1 Separate Concerns into Focused Components

**Problem**: `AudioPlayer` has too many responsibilities:
- Audio playback (AVAudioEngine/AVAudioPlayerNode)
- System configuration (Core Audio APIs)
- UI state management
- Timer management

**Proposed Architecture**:

```
AudioPlayer (State Management)
    ├── AudioEngineManager (Low-level playback)
    ├── AudioSystemConfiguration (Core Audio APIs)
    └── PlaybackTimer (Timer management)
```

**Implementation**:

```swift
// 1. Audio Engine Manager
@MainActor
final class AudioEngineManager {
    private let engine = AVAudioEngine()
    private let playerNode = AVAudioPlayerNode()

    var volume: Float {
        get { engine.mainMixerNode.outputVolume }
        set { engine.mainMixerNode.outputVolume = newValue }
    }

    var isRunning: Bool {
        engine.isRunning
    }

    func setup() throws {
        engine.attach(playerNode)
        engine.connect(playerNode, to: engine.mainMixerNode, format: nil)
        try engine.start()
    }

    func play(file: AVAudioFile, completion: @escaping @MainActor () -> Void) {
        playerNode.scheduleFile(file, at: nil) {
            Task { @MainActor in
                completion()
            }
        }
        playerNode.play()
    }

    func playSegment(
        file: AVAudioFile,
        startFrame: AVAudioFramePosition,
        frameCount: AVAudioFrameCount,
        completion: @escaping @MainActor () -> Void
    ) {
        playerNode.scheduleSegment(
            file,
            startingFrame: startFrame,
            frameCount: frameCount,
            at: nil
        ) {
            Task { @MainActor in
                completion()
            }
        }
        playerNode.play()
    }

    func pause() {
        playerNode.pause()
    }

    func stop() {
        playerNode.stop()
    }

    func getCurrentTime(sampleRate: Double) -> Double? {
        guard let nodeTime = playerNode.lastRenderTime,
              let playerTime = playerNode.playerTime(forNodeTime: nodeTime) else {
            return nil
        }
        return Double(playerTime.sampleTime) / sampleRate
    }

    deinit {
        engine.stop()
        engine.detach(playerNode)
    }
}

// 2. Audio System Configuration
struct AudioSystemConfiguration {
    static func setSystemSampleRate(_ sampleRate: Double) throws {
        let deviceID = try getDefaultOutputDevice()
        let supportedRates = try getSupportedSampleRates(for: deviceID)

        guard supportedRates.contains(sampleRate) else {
            throw AudioPlayerError.sampleRateNotSupported(
                requested: sampleRate,
                supported: supportedRates
            )
        }

        try setSampleRate(sampleRate, on: deviceID)
    }

    static func getCurrentSampleRate() -> Double {
        guard let deviceID = try? getDefaultOutputDevice(),
              let rate = try? getSampleRate(from: deviceID) else {
            return 0
        }
        return rate
    }

    // Private helpers
    private static func getDefaultOutputDevice() throws -> AudioDeviceID {
        var deviceID = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &size,
            &deviceID
        )

        guard status == noErr else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status))
        }

        return deviceID
    }

    private static func getSampleRate(from deviceID: AudioDeviceID) throws -> Double {
        var sampleRate: Double = 0
        var size = UInt32(MemoryLayout<Double>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyNominalSampleRate,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        let status = AudioObjectGetPropertyData(
            deviceID,
            &address,
            0,
            nil,
            &size,
            &sampleRate
        )

        guard status == noErr else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status))
        }

        return sampleRate
    }

    private static func setSampleRate(_ rate: Double, on deviceID: AudioDeviceID) throws {
        var sampleRate = rate
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyNominalSampleRate,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        let status = AudioObjectSetPropertyData(
            deviceID,
            &address,
            0,
            nil,
            UInt32(MemoryLayout<Double>.size),
            &sampleRate
        )

        guard status == noErr else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status))
        }
    }

    private static func getSupportedSampleRates(for deviceID: AudioDeviceID) throws -> [Double] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyAvailableNominalSampleRates,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(deviceID, &address, 0, nil, &size) == noErr else {
            return []
        }

        let count = Int(size) / MemoryLayout<AudioValueRange>.size
        var ranges = [AudioValueRange](repeating: AudioValueRange(), count: count)

        guard AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &ranges) == noErr else {
            return []
        }

        return ranges.map { $0.mMinimum }
    }
}

// 3. Playback Timer
@MainActor
final class PlaybackTimer {
    private var timer: Timer?
    private var tickCount = 0
    var onTick: (() -> Void)?
    var onSlowTick: (() -> Void)? // Called every 2 seconds

    func start(interval: TimeInterval = 0.1) {
        stop()
        tickCount = 0

        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            guard let self else { return }

            self.onTick?()

            self.tickCount += 1
            if self.tickCount >= 20 {
                self.onSlowTick?()
                self.tickCount = 0
            }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        tickCount = 0
    }

    deinit {
        stop()
    }
}

// 4. Simplified AudioPlayer (orchestration only)
@MainActor
@Observable
final class AudioPlayer {
    // Dependencies
    private let engineManager = AudioEngineManager()
    private let playbackTimer = PlaybackTimer()

    // State
    var isPlaying = false
    var currentTime: Double = 0
    var duration: Double = 0
    var volume: Double = 0.5 {
        didSet {
            engineManager.volume = Float(volume)
        }
    }
    var currentFileName: String?
    var fileSampleRate: Double = 0
    var hardwareSampleRate: Double = 0
    var statusMessage: String = ""
    var hasError: Bool = false
    var isLoading: Bool = false

    // File management
    private var audioFile: AVAudioFile?
    private var currentFileURL: URL?
    private var audioLengthSamples: AVAudioFramePosition = 0
    private var sampleRate: Double = 0
    private var loadingTask: Task<Void, Never>?

    init() {
        do {
            try engineManager.setup()
        } catch {
            handleError(.engineStartFailed(underlying: error))
        }

        updateHardwareSampleRate()
        setupTimer()
    }

    private func setupTimer() {
        playbackTimer.onTick = { [weak self] in
            self?.updatePlaybackTime()
        }

        playbackTimer.onSlowTick = { [weak self] in
            self?.updateHardwareSampleRate()
        }
    }

    // Rest of methods remain similar but delegate to components
}
```

**Rationale**:
- Each component has a single, clear responsibility
- Easier to test in isolation
- Better code organization
- Reusable components

---

### 3.2 Extract Time Formatting Utility

**Create new file**: `TimeFormatter.swift`

```swift
import Foundation

struct TimeFormatter {
    static func format(_ time: Double) -> String {
        guard time.isFinite && time >= 0 else {
            return "0:00"
        }

        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}
```

**Update ContentView**:
```swift
private func timeString(_ time: Double) -> String {
    TimeFormatter.format(time)
}
```

---

## Implementation Order

### Step 1: Critical Fixes (Required)
1. Remove `nonisolated(unsafe)` from timer
2. Add `@unchecked Sendable` conformance
3. Fix AVFoundation callback isolation
4. Extract TimeFormatter utility and fix test duplication

**Estimated Time**: 30 minutes
**Test After**: Build and run, verify no concurrency warnings

---

### Step 2: Observable Migration (High Priority)
1. Remove `import Combine`
2. Add `import Observation`
3. Change `ObservableObject` to `@Observable`
4. Remove all `@Published` annotations
5. Update `ContentView` to use `@State` instead of `@StateObject`

**Estimated Time**: 15 minutes
**Test After**: Build and run, verify UI updates work correctly

---

### Step 3: Clean Up Async Code (High Priority)
1. Remove unnecessary `MainActor.run` calls throughout `loadFileAsync`
2. Add task cancellation support with `loadingTask` property
3. Add cancellation checks at key points
4. Update `ContentView` to use async `loadFile`

**Estimated Time**: 45 minutes
**Test After**: Load multiple files quickly, verify cancellation works

---

### Step 4: Improve Error Handling (Medium Priority)
1. Add `AudioPlayerError` enum
2. Add `handleError` method
3. Update all error handling to use typed errors
4. Add debug logging

**Estimated Time**: 30 minutes
**Test After**: Trigger various errors, verify messaging

---

### Step 5: Refine Timer Management (Medium Priority)
1. Extract timer logic to `updatePlaybackState` method
2. Improve `stopTimer` to reset tick count
3. Enhance `deinit` cleanup

**Estimated Time**: 20 minutes
**Test After**: Play/pause/stop repeatedly, verify no leaks

---

### Step 6: Architecture Refactoring (Optional)
1. Create `AudioEngineManager` class
2. Create `AudioSystemConfiguration` struct
3. Create `PlaybackTimer` class
4. Create `TimeFormatter` struct
5. Refactor `AudioPlayer` to use these components

**Estimated Time**: 2-3 hours
**Test After**: Full regression testing of all features

---

## Testing Strategy

After each phase:

1. **Build Verification**
   ```bash
   xcodebuild -project AdaptiveMusicPlayer.xcodeproj -scheme AdaptiveMusicPlayer clean build
   ```

2. **Manual Testing**
   - Load audio file
   - Play/pause/stop
   - Seek using slider
   - Skip forward/backward
   - Adjust volume
   - Load different sample rate files
   - Verify hardware sample rate updates
   - Load multiple files rapidly (test cancellation)

3. **Unit Tests**
   ```bash
   xcodebuild test -project AdaptiveMusicPlayer.xcodeproj -scheme AdaptiveMusicPlayer
   ```

---

## Success Criteria

### Critical Phase
- ✅ Build succeeds with zero concurrency warnings
- ✅ No `nonisolated(unsafe)` in code
- ✅ Proper Sendable conformance
- ✅ Tests use production code (no duplication)

### Important Phase
- ✅ Using `@Observable` instead of `ObservableObject`
- ✅ No unnecessary `MainActor.run` calls
- ✅ Task cancellation works when loading multiple files
- ✅ Typed error handling throughout
- ✅ Clean timer lifecycle management

### Architecture Phase
- ✅ Clear separation of concerns
- ✅ Each component has single responsibility
- ✅ Code is more testable
- ✅ Better maintainability

---

## Rollback Plan

If issues arise during refactoring:

1. **Git commits** after each phase
2. **Tag working states**: `git tag phase-1-complete`
3. **Quick rollback**: `git reset --hard phase-1-complete`

---

## Documentation Updates

After completion, update:

1. **CLAUDE.md**
   - New architecture overview
   - Observable pattern usage
   - Task cancellation patterns
   - Error handling approach
   - Component responsibilities

2. **README.md** (if exists)
   - Swift 6 compatibility noted
   - Updated architecture diagram
   - New dependencies (Observation framework)

---

## Post-Refactor Review

After all changes:

1. Run full test suite
2. Performance profiling (no regressions)
3. Memory leak check with Instruments
4. Code review checklist:
   - [ ] No force unwraps
   - [ ] All Tasks are structured or cancellable
   - [ ] No data race warnings
   - [ ] Proper actor isolation
   - [ ] Clean resource management
   - [ ] Comprehensive error handling

---

## Estimated Total Time

- **Critical Fixes**: 30 minutes
- **Observable Migration**: 15 minutes
- **Async Cleanup**: 45 minutes
- **Error Handling**: 30 minutes
- **Timer Management**: 20 minutes
- **Architecture Refactor**: 2-3 hours (optional)
- **Testing & Documentation**: 1 hour

**Total (without architecture refactor)**: ~2.5 hours
**Total (with architecture refactor)**: ~5 hours

---

## Notes

- Refactoring should be done incrementally
- Test after each phase
- Commit frequently
- Don't skip critical fixes
- Architecture refactor is optional but recommended for long-term maintainability
- All changes maintain backward compatibility with existing functionality
