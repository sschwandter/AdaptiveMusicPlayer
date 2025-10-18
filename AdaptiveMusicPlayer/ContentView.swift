import SwiftUI
import AVFoundation
import Combine

struct ContentView: View {
    @StateObject private var player = AudioPlayer()
    @State private var showingFilePicker = false
    @State private var isDraggingSlider = false
    @State private var sliderValue: Double = 0
    
    var body: some View {
        VStack(spacing: 20) {
            // Header
            Text("Adaptive Music Player")
                .font(.largeTitle)
                .fontWeight(.bold)
                .padding(.top)
            
            // Current file info
            VStack(spacing: 10) {
                HStack {
                    if let fileName = player.currentFileName {
                        Text(fileName)
                            .font(.headline)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    } else {
                        Text("No file loaded")
                            .font(.headline)
                            .foregroundColor(.secondary)
                    }
                    
                    if player.isLoading {
                        ProgressView()
                            .scaleEffect(0.8)
                            .padding(.leading, 8)
                    }
                }
                
                HStack(spacing: 20) {
                    VStack(alignment: .leading) {
                        Text("File Sample Rate:")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(player.fileSampleRate > 0 ? "\(Int(player.fileSampleRate)) Hz" : "—")
                            .font(.system(.body, design: .monospaced))
                            .fontWeight(.semibold)
                    }
                    
                    VStack(alignment: .leading) {
                        Text("Hardware Sample Rate:")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(player.hardwareSampleRate > 0 ? "\(Int(player.hardwareSampleRate)) Hz" : "—")
                            .font(.system(.body, design: .monospaced))
                            .fontWeight(.semibold)
                            .foregroundColor(sampleRateColor)
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(Color.gray.opacity(0.1))
            .cornerRadius(10)
            
            // Progress bar
            if player.currentFileName != nil {
                VStack(spacing: 5) {
                    Slider(
                        value: Binding(
                            get: { isDraggingSlider ? sliderValue : player.currentTime },
                            set: { newValue in
                                sliderValue = newValue
                                if !isDraggingSlider {
                                    player.seek(to: newValue)
                                }
                            }
                        ),
                        in: 0...max(player.duration, 1)
                    )
                    .onDrag {
                        isDraggingSlider = true
                    }
                    .onRelease {
                        player.seek(to: sliderValue)
                        isDraggingSlider = false
                    }
                    
                    HStack {
                        Text(timeString(isDraggingSlider ? sliderValue : player.currentTime))
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .monospacedDigit()
                        Spacer()
                        Text(timeString(player.duration))
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .monospacedDigit()
                    }
                }
                .disabled(player.isLoading)
                .opacity(player.isLoading ? 0.6 : 1.0)
            }
            
            // Playback controls
            HStack(spacing: 30) {
                Button(action: { showingFilePicker = true }) {
                    Image(systemName: "folder")
                        .font(.system(size: 30))
                        .foregroundColor(.accentColor)
                }
                .buttonStyle(.plain)
                .help("Open Audio File (⌘O)")
                .disabled(player.isLoading)
                
                Button(action: { player.skipBackward() }) {
                    Image(systemName: "backward.fill")
                        .font(.system(size: 30))
                }
                .buttonStyle(.plain)
                .help("Skip Backward 10s (←)")
                .disabled(player.currentFileName == nil || player.isLoading)
                
                Button(action: { player.togglePlayPause() }) {
                    Image(systemName: player.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 50))
                        .foregroundColor(.accentColor)
                }
                .buttonStyle(.plain)
                .help(player.isPlaying ? "Pause (Space)" : "Play (Space)")
                .disabled(player.currentFileName == nil || player.isLoading)
                
                Button(action: { player.skipForward() }) {
                    Image(systemName: "forward.fill")
                        .font(.system(size: 30))
                }
                .buttonStyle(.plain)
                .help("Skip Forward 10s (→)")
                .disabled(player.currentFileName == nil || player.isLoading)
                
                Button(action: { player.stop() }) {
                    Image(systemName: "stop.fill")
                        .font(.system(size: 30))
                }
                .buttonStyle(.plain)
                .help("Stop (⌘.)")
                .disabled(!player.isPlaying)
            }
            .padding()
            .opacity(player.isLoading ? 0.6 : 1.0)
            
            // Volume control
            HStack {
                Image(systemName: "speaker.fill")
                    .foregroundColor(.secondary)
                Slider(value: $player.volume, in: 0...1)
                    .disabled(player.isLoading)
                Image(systemName: "speaker.wave.3.fill")
                    .foregroundColor(.secondary)
                
                Text("\(Int(player.volume * 100))%")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(width: 35, alignment: .trailing)
                    .monospacedDigit()
            }
            .padding(.horizontal)
            .opacity(player.isLoading ? 0.6 : 1.0)
            
            // Status messages
            if !player.statusMessage.isEmpty {
                Text(player.statusMessage)
                    .font(.caption)
                    .foregroundColor(player.hasError ? .red : .blue)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
            
            Spacer()
        }
        .padding()
        .frame(minWidth: 500, minHeight: 400)
        .onKeyDown(key: .space) {
            if player.currentFileName != nil && !player.isLoading {
                player.togglePlayPause()
            }
        }
        .onKeyDown(key: .leftArrow) {
            if player.currentFileName != nil && !player.isLoading {
                player.skipBackward()
            }
        }
        .onKeyDown(key: .rightArrow) {
            if player.currentFileName != nil && !player.isLoading {
                player.skipForward()
            }
        }
        .onKeyDown(key: KeyEquivalent("."), modifiers: .command) {
            if player.isPlaying {
                player.stop()
            }
        }
        .onKeyDown(key: KeyEquivalent("o"), modifiers: .command) {
            showingFilePicker = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .togglePlayPause)) { _ in
            if player.currentFileName != nil && !player.isLoading {
                player.togglePlayPause()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .stopPlayback)) { _ in
            if player.isPlaying {
                player.stop()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .skipForward)) { _ in
            if player.currentFileName != nil && !player.isLoading {
                player.skipForward()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .skipBackward)) { _ in
            if player.currentFileName != nil && !player.isLoading {
                player.skipBackward()
            }
        }
        .fileImporter(
            isPresented: $showingFilePicker,
            allowedContentTypes: [
                .audio,
                .mp3,
                .wav,
                .aiff
            ],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first {
                    player.loadFile(url: url)
                }
            case .failure(let error):
                player.statusMessage = "Error selecting file: \(error.localizedDescription)"
                player.hasError = true
            }
        }
    }
    
    // MARK: - Computed Properties
    private var sampleRateColor: Color {
        guard player.fileSampleRate > 0 && player.hardwareSampleRate > 0 else {
            return .secondary
        }
        return player.fileSampleRate == player.hardwareSampleRate ? .green : .orange
    }
    
    // MARK: - Private Methods
    private func timeString(_ time: Double) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

// MARK: - View Extensions
extension View {
    func onKeyDown(key: KeyEquivalent, modifiers: EventModifiers = [], action: @escaping () -> Void) -> some View {
        background(
            Button("", action: action)
                .keyboardShortcut(key, modifiers: modifiers)
                .hidden()
        )
    }
    
    func onDrag(action: @escaping () -> Void) -> some View {
        simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in action() }
        )
    }
    
    func onRelease(action: @escaping () -> Void) -> some View {
        simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onEnded { _ in action() }
        )
    }
}

#Preview {
    ContentView()
}
