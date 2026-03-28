import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @State private var player = AudioPlayer()
    @State private var showingFilePicker = false
    @State private var sliderPosition: Double = 0
    @State private var isEditingSlider = false

    var body: some View {
        ZStack {
            backgroundView

            VStack(spacing: 18) {
                headerCard
                transportSection
                diagnosticsCard

                if !player.statusMessage.isEmpty {
                    statusBanner
                }
            }
            .padding(24)
        }
        .frame(width: 520)
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
                    // Let the picker dismiss before file access begins.
                    player.loadFile(url: url, importerDismissalDelay: .milliseconds(50))
                }
            case .failure(let error):
                player.reportFileSelectionError(error.localizedDescription)
            }
        }
    }

    private var backgroundView: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.08, green: 0.11, blue: 0.16),
                    Color(red: 0.11, green: 0.15, blue: 0.22),
                    Color(red: 0.17, green: 0.20, blue: 0.27)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Circle()
                .fill(Color.cyan.opacity(0.16))
                .blur(radius: 70)
                .frame(width: 220, height: 220)
                .offset(x: -150, y: -170)

            Circle()
                .fill(Color.orange.opacity(0.14))
                .blur(radius: 90)
                .frame(width: 260, height: 260)
                .offset(x: 180, y: 210)

            Rectangle()
                .fill(.ultraThinMaterial.opacity(0.25))
        }
        .ignoresSafeArea()
    }

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Adaptive Music Player")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                        .tracking(1.2)

                    HStack(alignment: .center, spacing: 12) {
                        Group {
                            if let fileName = player.currentFileName {
                                Text(fileName)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            } else {
                                Text("Choose an audio file to begin")
                                    .foregroundStyle(.white.opacity(0.9))
                            }
                        }
                        .font(.system(size: 24, weight: .semibold, design: .rounded))

                        Button(action: { showingFilePicker = true }) {
                            Image(systemName: "waveform.badge.plus")
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.96))
                                .frame(width: 36, height: 36)
                                .background(.white.opacity(0.08))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .strokeBorder(.white.opacity(0.14), lineWidth: 1)
                                )
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .help(player.currentFileName == nil ? "Open Audio File (⌘O)" : "Choose Another Audio File (⌘O)")

                        Spacer(minLength: 0)
                    }

                    Text(player.currentFileName == nil ? "" : player.sampleRateStatusDetail)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Spacer()

                HStack(spacing: 8) {
                    if player.isLoading {
                        ProgressView()
                            .controlSize(.small)
                    }

                    Label(player.isPlaying ? "Live" : "Idle", systemImage: player.isPlaying ? "waveform.circle.fill" : "pause.circle")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(.white.opacity(player.isPlaying ? 0.16 : 0.10))
                        .clipShape(Capsule())
                }
                .foregroundStyle(.white.opacity(0.92))
            }

            VStack(spacing: 10) {
                Slider(value: $sliderPosition, in: 0...max(player.duration, 1)) { isEditing in
                    isEditingSlider = isEditing
                    if !isEditing {
                        player.seek(to: sliderPosition)
                    }
                }
                .tint(.white.opacity(0.95))
                .onChange(of: player.currentTime) { oldValue, newValue in
                    if !isEditingSlider {
                        sliderPosition = newValue
                    }
                }

                HStack {
                    Label(timeString(sliderPosition), systemImage: "playhead")
                        .contentTransition(.numericText())
                    Spacer()
                    Text(timeString(player.duration))
                        .contentTransition(.numericText())
                }
                .font(.caption.weight(.medium))
                .foregroundStyle(.white.opacity(0.72))
                .monospacedDigit()
            }
            .disabled(player.currentFileName == nil || player.isLoading)
            .opacity(player.currentFileName == nil ? 0.45 : (player.isLoading ? 0.7 : 1.0))
        }
        .padding(22)
        .background(cardBackground)
    }

    private var transportSection: some View {
        HStack(spacing: 16) {
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

            HStack(spacing: 6) {
                Image(systemName: "speaker.fill")
                    .foregroundStyle(.white.opacity(0.75))
                    .frame(width: 16)
                Slider(value: $player.volume, in: 0...1)
                    .tint(.white.opacity(0.92))
                    .disabled(player.isLoading)
                Image(systemName: "speaker.wave.3.fill")
                    .foregroundStyle(.white.opacity(0.75))
                    .frame(width: 16)
            }
            .font(.caption)
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity, minHeight: 60)
            .background(cardBackground)
        }
    }

    private var diagnosticsCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Playback Path")
                        .font(.system(size: 18, weight: .semibold, design: .rounded))

                
                }

                Spacer()

                Text(player.sampleRateBadgeTitle)
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(badgeBackgroundColor)
                    .foregroundStyle(badgeForegroundColor)
                    .clipShape(Capsule())

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
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(.white.opacity(0.08))
                    .clipShape(Capsule())
                    .help("Set hardware to \(Int(player.fileSampleRate)) Hz for bit-perfect playback")
                    .disabled(player.isLoading)
                }
            }

            HStack(spacing: 12) {
                InfoTile(
                    title: "Rate",
                    value: player.sampleRateRouteDescription,
                    systemImage: "waveform.path.ecg",
                    emphasized: true
                )

                InfoTile(
                    title: "Output",
                    value: player.hardwareDeviceDisplayName,
                    systemImage: "airplayaudio"
                )
            }

            if player.showsSupportedRatesHint {
                InfoTile(
                    title: "Supported",
                    value: player.supportedHardwareSampleRatesDescription,
                    systemImage: "slider.horizontal.3"
                )
            }

            if let explanation = player.compactSampleRateExplanation {
                Label(explanation, systemImage: "info.circle.fill")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.top, 2)
            }
        }
        .font(.callout)
        .padding(20)
        .background(cardBackground)
    }

    private var statusBanner: some View {
        HStack(spacing: 12) {
            Image(systemName: statusIconName)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(statusForegroundColor)
                .frame(width: 28, height: 28)
                .background(statusForegroundColor.opacity(0.14))
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(player.hasError ? "Attention" : "Status")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                Text(player.statusMessage)
                    .font(.footnote)
                    .foregroundStyle(player.hasError ? Color.primary : Color.primary.opacity(0.92))
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(statusBackgroundColor)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(statusForegroundColor.opacity(0.2), lineWidth: 1)
        )
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 26, style: .continuous)
            .fill(.regularMaterial.opacity(0.78))
            .overlay(
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .strokeBorder(.white.opacity(0.09), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.18), radius: 24, y: 14)
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
            return .green.opacity(0.18)
        case "Resampling":
            return .orange.opacity(0.22)
        case "Unsupported":
            return .red.opacity(0.18)
        default:
            return .white.opacity(0.10)
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
            return .white.opacity(0.72)
        }
    }

    private var statusForegroundColor: Color {
        if player.hasError {
            return .red
        }

        switch player.statusMessage {
        case let message where message.contains("Playing"):
            return .green
        case let message where message.contains("Loading"):
            return .orange
        default:
            return .cyan
        }
    }

    private var statusBackgroundColor: Color {
        player.hasError ? .red.opacity(0.12) : .white.opacity(0.08)
    }

    private var statusIconName: String {
        if player.hasError {
            return "exclamationmark.triangle.fill"
        }

        switch player.statusMessage {
        case let message where message.contains("Playing"):
            return "waveform.circle.fill"
        case let message where message.contains("Loading"):
            return "arrow.clockwise.circle.fill"
        case let message where message.contains("Stopped"):
            return "stop.circle.fill"
        default:
            return "info.circle.fill"
        }
    }

    // MARK: - Private Methods

    private func timeString(_ time: Double) -> String {
        TimeFormatter.format(time)
    }
}

private struct InfoTile: View {
    let title: String
    let value: String
    let systemImage: String
    var emphasized: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: systemImage)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            Text(value)
                .font(emphasized ? .system(.body, design: .monospaced, weight: .semibold) : .body)
                .lineLimit(title == "Output" ? 1 : nil)
                .truncationMode(.tail)
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.white.opacity(0.05))
        )
    }
}

#Preview {
    ContentView()
}
