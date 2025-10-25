import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @State private var player = AudioPlayer()
    @State private var showingFilePicker = false
    @State private var sliderPosition: Double = 0
    @State private var isEditingSlider = false
    
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

                    HStack(spacing: 4) {
                        VStack(alignment: .leading) {
                            Text("Hardware Sample Rate:")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text(player.hardwareSampleRate > 0 ? "\(Int(player.hardwareSampleRate)) Hz" : "—")
                                .font(.system(.body, design: .monospaced))
                                .fontWeight(.semibold)
                                .foregroundColor(sampleRateColor)
                        }

                        // Sync button when mismatched
                        if player.hasSampleRateMismatch {
                            Button(action: {
                                Task {
                                    await player.synchronizeSampleRates()
                                }
                            }) {
                                Image(systemName: "arrow.triangle.2.circlepath")
                                    .font(.system(size: 16))
                                    .foregroundColor(.orange)
                            }
                            .buttonStyle(.plain)
                            .help("Set hardware to \(Int(player.fileSampleRate)) Hz for bit-perfect playback")
                            .disabled(player.isLoading)
                        }
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
                    Slider(value: $sliderPosition, in: 0...max(player.duration, 1)) { isEditing in
                        isEditingSlider = isEditing
                        if !isEditing {
                            player.seek(to: sliderPosition)
                        }
                    }
                    .onChange(of: player.currentTime) { oldValue, newValue in
                        if !isEditingSlider {
                            sliderPosition = newValue
                        }
                    }

                    HStack {
                        Text(timeString(sliderPosition))
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
        .onReceive(NotificationCenter.default.publisher(for: .openFilePicker)) { _ in
            showingFilePicker = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .togglePlayPause)) { _ in
            if canPerformPlaybackAction {
                player.togglePlayPause()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .stopPlayback)) { _ in
            if player.isPlaying {
                player.stop()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .skipForward)) { _ in
            if canPerformPlaybackAction {
                player.skipForward()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .skipBackward)) { _ in
            if canPerformPlaybackAction {
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
                    // Set loading state IMMEDIATELY (synchronous, no Task overhead)
                    player.setLoadingState()

                    // Then start async loading
                    Task {
                        await player.loadFile(url: url)
                    }
                }
            case .failure(let error):
                player.statusMessage = "Error selecting file: \(error.localizedDescription)"
                player.hasError = true
            }
        }
    }
    
    // MARK: - Computed Properties

    private var canPerformPlaybackAction: Bool {
        player.currentFileName != nil && !player.isLoading
    }

    private var sampleRateColor: Color {
        guard player.fileSampleRate > 0 && player.hardwareSampleRate > 0 else {
            return .secondary
        }
        return player.fileSampleRate == player.hardwareSampleRate ? .green : .orange
    }
    
    // MARK: - Private Methods
    private func timeString(_ time: Double) -> String {
        TimeFormatter.format(time)
    }
}

#Preview {
    ContentView()
}
