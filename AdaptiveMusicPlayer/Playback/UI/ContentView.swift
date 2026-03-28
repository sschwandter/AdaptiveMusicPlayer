import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @State private var player = AudioPlayer()
    @State private var showingFilePicker = false
    @State private var sliderPosition: Double = 0
    @State private var isEditingSlider = false
    
    var body: some View {
        VStack(spacing: 16) {
            // File name and loading indicator
            HStack {
                if let fileName = player.currentFileName {
                    Text(fileName)
                        .font(.headline)
                        .lineLimit(1)
                        .truncationMode(.middle)
                } else {
                    Text("No file loaded")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                if player.isLoading {
                    ProgressView()
                        .scaleEffect(0.8)
                }
            }
            
            // Progress slider — always visible
            VStack(spacing: 4) {
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
                        .contentTransition(.numericText())
                    Spacer()
                    Text(timeString(player.duration))
                        .contentTransition(.numericText())
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
            }
            .disabled(player.currentFileName == nil || player.isLoading)
            .opacity(player.currentFileName == nil ? 0.4 : (player.isLoading ? 0.6 : 1.0))
            
            // Transport controls with Liquid Glass
            GlassEffectContainer {
                HStack(spacing: 12) {
                    Button(action: { player.skipBackward() }) {
                        Image(systemName: "backward.fill")
                            .frame(width: 20, height: 20)
                    }
                    .buttonStyle(.glass)
                    .help("Skip Backward 10s")
                    .disabled(player.currentFileName == nil || player.isLoading)
                    
                    Button(action: { player.togglePlayPause() }) {
                        Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                            .frame(width: 20, height: 20)
                    }
                    .buttonStyle(.glassProminent)
                    .help(player.isPlaying ? "Pause (Space)" : "Play (Space)")
                    .disabled(player.currentFileName == nil || player.isLoading)
                    
                    Button(action: { player.skipForward() }) {
                        Image(systemName: "forward.fill")
                            .frame(width: 20, height: 20)
                    }
                    .buttonStyle(.glass)
                    .help("Skip Forward 10s")
                    .disabled(player.currentFileName == nil || player.isLoading)
                    
                    Button(action: { player.stop() }) {
                        Image(systemName: "stop.fill")
                            .frame(width: 20, height: 20)
                    }
                    .buttonStyle(.glass)
                    .help("Stop")
                    .disabled(player.currentFileName == nil || player.isLoading)
                }
            }
            
            // Volume
            HStack(spacing: 6) {
                Image(systemName: "speaker.fill")
                    .foregroundStyle(.secondary)
                    .frame(width: 16)
                Slider(value: $player.volume, in: 0...1)
                    .disabled(player.isLoading)
                Image(systemName: "speaker.wave.3.fill")
                    .foregroundStyle(.secondary)
                    .frame(width: 16)
            }
            .font(.caption)
            
            // Sample rate display
            HStack(spacing: 16) {
                LabeledContent("File") {
                    Text(player.fileSampleRate > 0 ? "\(Int(player.fileSampleRate)) Hz" : "—")
                        .monospacedDigit()
                }
                
                Spacer()
                
                LabeledContent("Hardware") {
                    HStack(spacing: 4) {
                        Image(systemName: "circle.fill")
                            .font(.system(size: 8))
                            .foregroundStyle(sampleRateColor)
                        
                        Text(player.hardwareSampleRate > 0 ? "\(Int(player.hardwareSampleRate)) Hz" : "—")
                            .monospacedDigit()
                        
                        if player.hasSampleRateMismatch {
                            Button(action: {
                                Task {
                                    await player.synchronizeSampleRates()
                                }
                            }) {
                                Image(systemName: "arrow.triangle.2.circlepath")
                                    .font(.caption)
                            }
                            .buttonStyle(.borderless)
                            .help("Set hardware to \(Int(player.fileSampleRate)) Hz for bit-perfect playback")
                            .disabled(player.isLoading)
                        }
                    }
                }
            }
            .font(.callout)
            
            // Status message
            if !player.statusMessage.isEmpty {
                Text(player.statusMessage)
                    .font(.footnote)
                    .foregroundStyle(player.hasError ? .red : .secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding()
        .frame(width: 480)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(action: { showingFilePicker = true }) {
                    Label("Open File", systemImage: "folder")
                }
                .help("Open Audio File (⌘O)")
                .disabled(player.isLoading)
            }
            

        }
        .focusedSceneValue(\.playbackCommandActions, playbackCommandActions)
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

                    // Defer the actual load until after the importer has dismissed.
                    // On some network-backed files this avoids the picker appearing frozen
                    // while security-scoped access and file reads begin.
                    DispatchQueue.main.async {
                        Task {
                            do {
                                try await Task.sleep(for: .milliseconds(50))
                            } catch is CancellationError {
                                return
                            } catch {
                                return
                            }
                            await player.loadFile(url: url)
                        }
                    }
                }
            case .failure(let error):
                player.reportFileSelectionError(error.localizedDescription)
            }
        }
    }
    
    // MARK: - Computed Properties

    private var canPerformPlaybackAction: Bool {
        player.currentFileName != nil && !player.isLoading
    }

    private var playbackCommandActions: PlaybackCommandActions {
        PlaybackCommandActions(
            openFilePicker: { showingFilePicker = true },
            togglePlayPause: {
                guard canPerformPlaybackAction else { return }
                player.togglePlayPause()
            },
            stopPlayback: {
                guard canPerformPlaybackAction else { return }
                player.stop()
            },
            skipForward: {
                guard canPerformPlaybackAction else { return }
                player.skipForward()
            },
            skipBackward: {
                guard canPerformPlaybackAction else { return }
                player.skipBackward()
            },
            canControlPlayback: canPerformPlaybackAction
        )
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
