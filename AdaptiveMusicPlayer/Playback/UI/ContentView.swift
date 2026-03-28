import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    private enum LayoutMetrics {
        static let width: CGFloat = 520
        static let minimumHeight: CGFloat = 700
    }

    private enum ImportTarget {
        case file
        case folder
    }

    @State private var player = AudioPlayer()
    @State private var activeImportTarget: ImportTarget?
    @State private var showingImporter = false
    @State private var sliderPosition: Double = 0
    @State private var isEditingSlider = false

    var body: some View {
        ZStack {
            backgroundView

            VStack(spacing: 18) {
                headerCard
                transportSection
                playlistBrowserCard
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .padding(24)
        }
        .frame(width: LayoutMetrics.width)
        .frame(minHeight: LayoutMetrics.minimumHeight, alignment: .top)
        .focusedSceneValue(\.playbackCommandActions, playbackCommandActions)
        .fileImporter(
            isPresented: $showingImporter,
            allowedContentTypes: allowedImportContentTypes,
            allowsMultipleSelection: false
        ) { result in
            let importTarget = activeImportTarget
            showingImporter = false
            activeImportTarget = nil

            switch result {
            case .success(let urls):
                if let url = urls.first {
                    handleImportedURL(url, target: importTarget)
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
                                Text("Choose an audio file or folder to begin")
                                    .foregroundStyle(.white.opacity(0.9))
                            }
                        }
                        .font(.system(size: 24, weight: .semibold, design: .rounded))

                        HStack(spacing: 8) {
                            libraryButton(
                                systemImage: "waveform.badge.plus",
                                action: { presentImporter(for: .file) },
                                help: player.currentFileName == nil
                                    ? "Open Audio File (⌘O)"
                                    : "Choose Another Audio File (⌘O)"
                            )

                            libraryButton(
                                systemImage: "folder.badge.plus",
                                action: { presentImporter(for: .folder) },
                                help: "Open Folder (⇧⌘O)"
                            )
                        }

                        Spacer(minLength: 0)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        if let playlistTrackPosition = player.playlistTrackPosition {
                            Label("Track \(playlistTrackPosition)", systemImage: "music.note.list")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.white.opacity(0.78))
                        }
                    }
                }

                Spacer()

                HStack(spacing: 8) {
                    if player.isLoading {
                        ProgressView()
                            .controlSize(.small)
                    }

                    Label(activityIndicatorTitle, systemImage: activityIndicatorIconName)
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(activityIndicatorBackgroundColor)
                        .clipShape(Capsule())
                        .help(activityIndicatorHelpText)
                }
                .foregroundStyle(activityIndicatorForegroundColor)
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
                    Button(action: { player.playPreviousTrack() }) {
                        Image(systemName: "backward.end.fill")
                            .frame(width: 20, height: 20)
                    }
                    .buttonStyle(.glass)
                    .help("Previous Track (⌘←)")
                    .disabled(!player.canPlayPreviousTrack || player.isLoading)

                    Button(action: { player.skipBackward() }) {
                        Image(systemName: "gobackward.10")
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
                        Image(systemName: "goforward.10")
                            .frame(width: 20, height: 20)
                    }
                    .buttonStyle(.glass)
                    .help("Skip Forward 10s")
                    .disabled(player.currentFileName == nil || player.isLoading)

                    Button(action: { player.playNextTrack() }) {
                        Image(systemName: "forward.end.fill")
                            .frame(width: 20, height: 20)
                    }
                    .buttonStyle(.glass)
                    .help("Next Track (⌘→)")
                    .disabled(!player.canPlayNextTrack || player.isLoading)

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

    private var playlistBrowserCard: some View {
        Group {
            if player.hasPlaylist && player.currentFileName != nil {
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        Label("Playlist", systemImage: "music.note.list")
                            .font(.system(size: 18, weight: .semibold, design: .rounded))

                        Spacer()

                        if let playlistTrackPosition = player.playlistTrackPosition {
                            Text(playlistTrackPosition)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                    }

                    ScrollView {
                        LazyVStack(spacing: 8) {
                            ForEach(player.playlistTracks) { track in
                                playlistTrackRow(track)
                            }
                        }
                    }
                    .frame(maxHeight: 180)
                }
                .padding(20)
                .background(cardBackground)
            }
        }
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
            openFilePicker: { presentImporter(for: .file) },
            openFolderPicker: { presentImporter(for: .folder) },
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
            playNextTrack: {
                guard player.canPlayNextTrack && !player.isLoading else { return }
                player.playNextTrack()
            },
            playPreviousTrack: {
                guard player.canPlayPreviousTrack && !player.isLoading else { return }
                player.playPreviousTrack()
            },
            canControlPlayback: canPerformPlaybackAction,
            canNavigatePlaylist: !player.isLoading && (player.canPlayNextTrack || player.canPlayPreviousTrack)
        )
    }

    private var activityIndicatorForegroundColor: Color {
        if player.hasError {
            return .red
        }

        if player.isPlaying {
            return .green
        }

        return .white.opacity(0.92)
    }

    private var activityIndicatorBackgroundColor: Color {
        if player.hasError {
            return .red.opacity(0.16)
        }

        return .white.opacity(player.isPlaying ? 0.16 : 0.10)
    }

    private var activityIndicatorIconName: String {
        if player.hasError {
            return "exclamationmark.triangle.fill"
        }

        if player.isPlaying {
            return "waveform.circle.fill"
        }

        return "pause.circle"
    }

    private var activityIndicatorTitle: String {
        if player.hasError {
            return "Error"
        }

        return player.isPlaying ? "Live" : "Idle"
    }

    private var activityIndicatorHelpText: String {
        if player.hasError, !player.statusMessage.isEmpty {
            return player.statusMessage
        }

        return player.isPlaying ? "Playback in progress" : "Playback is idle"
    }

    // MARK: - Private Methods

    private func timeString(_ time: Double) -> String {
        TimeFormatter.format(time)
    }

    private func libraryButton(systemImage: String, action: @escaping () -> Void, help: String) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
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
        .help(help)
    }

    private var allowedImportContentTypes: [UTType] {
        switch activeImportTarget {
        case .folder:
            return [.folder]
        case .file, .none:
            return [
                .audio,
                .mp3,
                .wav,
                .aiff
            ]
        }
    }

    private func presentImporter(for target: ImportTarget) {
        activeImportTarget = target
        showingImporter = true
    }

    private func handleImportedURL(_ url: URL, target: ImportTarget?) {
        // Let the picker dismiss before file access begins.
        switch target {
        case .folder:
            player.loadFolder(url: url, importerDismissalDelay: .milliseconds(50))
        case .file, .none:
            player.loadFile(url: url, importerDismissalDelay: .milliseconds(50))
        }
    }

    private func playlistTrackRow(_ track: AudioPlayer.PlaylistTrackRow) -> some View {
        Button(action: { player.selectPlaylistTrack(at: track.index) }) {
            HStack(spacing: 12) {
                Text("\(track.index + 1)")
                    .font(.caption.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(track.isCurrent ? .white : .secondary)
                    .frame(width: 24, alignment: .trailing)

                VStack(alignment: .leading, spacing: 2) {
                    Text(track.title)
                        .font(.callout.weight(track.isCurrent ? .semibold : .medium))
                        .lineLimit(1)

                    Text(track.subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                if track.isCurrent {
                    Image(systemName: player.isPlaying ? "speaker.wave.2.fill" : "music.note")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.cyan)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(track.isCurrent ? .white.opacity(0.12) : .white.opacity(0.05))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(track.isCurrent ? .cyan.opacity(0.25) : .white.opacity(0.06), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    ContentView()
}
