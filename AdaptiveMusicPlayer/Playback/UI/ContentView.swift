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
            
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .center, spacing: 12) {
                    Text(player.sampleRateBadgeTitle)
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(badgeBackgroundColor)
                        .foregroundStyle(badgeForegroundColor)
                        .clipShape(Capsule())

                    Spacer()

                    if player.hasSampleRateMismatch {
                        Button(action: {
                            Task {
                                await player.synchronizeSampleRates()
                            }
                        }) {
                            Label("Sync", systemImage: "arrow.triangle.2.circlepath")
                                .labelStyle(.titleAndIcon)
                        }
                        .buttonStyle(.borderless)
                        .help("Set hardware to \(Int(player.fileSampleRate)) Hz for bit-perfect playback")
                        .disabled(player.isLoading)
                    }
                }

                LabeledContent("Rate") {
                    Text(player.sampleRateRouteDescription)
                        .monospacedDigit()
                }

                LabeledContent("Output") {
                    Text(player.hardwareDeviceDisplayName)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }

                if player.showsSupportedRatesHint {
                    LabeledContent("Supported") {
                        Text(player.supportedHardwareSampleRatesDescription)
                            .multilineTextAlignment(.trailing)
                    }
                }

                if let explanation = player.compactSampleRateExplanation {
                    Text(explanation)
                        .font(.caption)
                        .foregroundStyle(.secondary)
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
                    // Defer the load slightly so the importer can dismiss before
                    // security-scoped access and file reads start.
                    player.loadFile(url: url, importerDismissalDelay: .milliseconds(50))
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

    private var badgeBackgroundColor: Color {
        switch player.sampleRateBadgeTitle {
        case "Matched":
            return .green.opacity(0.16)
        case "Resampling":
            return .orange.opacity(0.18)
        case "Unsupported":
            return .red.opacity(0.14)
        default:
            return .secondary.opacity(0.14)
        }
    }

    private var badgeForegroundColor: Color {
        switch player.sampleRateBadgeTitle {
        case "Matched":
            return .green
        case "Resampling":
            return .orange
        case "Unsupported":
            return .red
        default:
            return .secondary
        }
    }
    
    // MARK: - Private Methods
    private func timeString(_ time: Double) -> String {
        TimeFormatter.format(time)
    }
}

#Preview {
    ContentView()
}
