import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    private enum LayoutMetrics {
        static let width: CGFloat = 520
        static let verticalPadding: CGFloat = 24
        static let playlistCardPadding: CGFloat = 20
        static let playlistTrackSpacing: CGFloat = 8
        static let playlistRowMinHeight: CGFloat = 56
        static let playlistMaxVisibleRowCount: Int = 5
    }

    private enum ImportTarget {
        case file
        case folder
    }

    @Environment(\.colorScheme) private var colorScheme
    @State private var player = AudioPlayer()
    @State private var activeImportTarget: ImportTarget?
    @State private var showingImporter = false
    @State private var sliderPosition: Double = 0
    @State private var isEditingSlider = false

    private var viewState: ContentViewState {
        player.contentViewState
    }

    var body: some View {
        ZStack {
            backgroundView
            contentStack
        }
        .frame(width: LayoutMetrics.width)
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
                player.send(.reportFileSelectionError(error.localizedDescription))
            }
        }
    }

    private var contentStack: some View {
        VStack(spacing: 18) {
            headerCard
            transportSection
            playlistBrowserCard
        }
        .padding(LayoutMetrics.verticalPadding)
    }

    private var backgroundView: some View {
        ZStack {
            LinearGradient(
                colors: backgroundGradientColors,
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Circle()
                .fill(Color.cyan.opacity(colorScheme == .dark ? 0.16 : 0.22))
                .blur(radius: colorScheme == .dark ? 70 : 90)
                .frame(width: 220, height: 220)
                .offset(x: -150, y: -170)

            Circle()
                .fill(Color.orange.opacity(colorScheme == .dark ? 0.14 : 0.18))
                .blur(radius: colorScheme == .dark ? 90 : 110)
                .frame(width: 260, height: 260)
                .offset(x: 180, y: 210)

            Rectangle()
                .fill(backgroundVeilColor)
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

                    VStack(alignment: .leading, spacing: 12) {
                        Group {
                            if let currentTrackTitle = viewState.currentTrackTitle {
                                Text(currentTrackTitle)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            } else {
                                Text("Choose an audio file or folder to begin")
                                    .foregroundStyle(secondaryTextColor)
                                    .lineLimit(2)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .font(.system(size: 24, weight: .semibold, design: .rounded))
                        .frame(maxWidth: .infinity, alignment: .leading)

                        sampleRateBanner

                        GlassEffectContainer {
                            HStack(spacing: 8) {
                                libraryButton(
                                    systemImage: "waveform.badge.plus",
                                    action: { presentImporter(for: .file) },
                                    help: !viewState.hasLoadedFile
                                        ? "Open Audio File (⌘O)"
                                        : "Choose Another Audio File (⌘O)"
                                )

                                libraryButton(
                                    systemImage: "folder.badge.plus",
                                    action: { presentImporter(for: .folder) },
                                    help: "Open Folder (⇧⌘O)"
                                )
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        if let playlistTrackPosition = viewState.playlistTrackPosition {
                            Label("Track \(playlistTrackPosition)", systemImage: "music.note.list")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(secondaryTextColor)
                        }
                    }
                }

                Spacer()
            }

            VStack(spacing: 10) {
                Slider(value: $sliderPosition, in: 0...max(viewState.duration, 1)) { isEditing in
                    isEditingSlider = isEditing
                    if !isEditing {
                        player.send(.seek(to: sliderPosition))
                    }
                }
                .tint(.white.opacity(0.95))
                .onChange(of: viewState.currentTime) { oldValue, newValue in
                    if !isEditingSlider {
                        sliderPosition = newValue
                    }
                }

                HStack {
                    Label(timeString(displayedPlaybackTime), systemImage: "clock")
                        .contentTransition(.numericText())
                    Spacer()
                    HStack(spacing: 10) {
                        Text(remainingTimeString(currentTime: displayedPlaybackTime, duration: viewState.duration))
                            .foregroundStyle(secondaryTextColor)
                            .contentTransition(.numericText())
                        Text(timeString(viewState.duration))
                            .contentTransition(.numericText())
                    }
                }
                .font(.caption.weight(.medium))
                .foregroundStyle(tertiaryTextColor)
                .monospacedDigit()
            }
            .disabled(!viewState.sliderIsEnabled)
            .opacity(viewState.sliderOpacity)
        }
        .padding(22)
        .background(cardBackground)
    }

    private var sampleRateBanner: some View {
        HStack(spacing: 12) {
            Image(systemName: sampleRateBannerIconName)
                .font(.system(size: 16, weight: .semibold))
                .frame(width: 18, height: 18)

            VStack(alignment: .leading, spacing: 2) {
                Text(sampleRateBannerTitle)
                    .font(.caption.weight(.bold))
                    .textCase(.uppercase)
                    .tracking(0.8)

                if let detail = sampleRateBannerDetail {
                    Text(detail)
                        .font(.callout.weight(.semibold))
                        .monospacedDigit()
                }
            }

            Spacer()

            if viewState.isLoading {
                ProgressView()
                    .controlSize(.small)
                    .tint(sampleRateBannerForegroundColor)
            }
        }
        .foregroundStyle(sampleRateBannerForegroundColor)
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(sampleRateBannerBackground)
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(sampleRateBannerBorderColor, lineWidth: 1.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .help(sampleRateBannerHelpText)
    }

    private var transportSection: some View {
        HStack(spacing: 16) {
            GlassEffectContainer {
                HStack(spacing: 12) {
                    Button(action: { player.send(.navigatePlaylist(next: false, autoplay: true)) }) {
                        Image(systemName: "backward.end.fill")
                            .frame(width: 20, height: 20)
                    }
                    .buttonStyle(.glass)
                    .help("Previous Track (⌘←)")
                    .disabled(!viewState.transport.canPlayPreviousTrack)

                    Button(action: { player.send(.skipBackward) }) {
                        Image(systemName: "gobackward.10")
                            .frame(width: 20, height: 20)
                    }
                    .buttonStyle(.glass)
                    .help("Skip Backward 10s")
                    .disabled(!viewState.transport.canSkip)

                    Button(action: { player.send(.togglePlayPause) }) {
                        Image(systemName: viewState.transport.playPauseSymbolName)
                            .frame(width: 20, height: 20)
                    }
                    .buttonStyle(.glassProminent)
                    .help(viewState.transport.playPauseHelp)
                    .disabled(!viewState.transport.canPlayPause)

                    Button(action: { player.send(.skipForward) }) {
                        Image(systemName: "goforward.10")
                            .frame(width: 20, height: 20)
                    }
                    .buttonStyle(.glass)
                    .help("Skip Forward 10s")
                    .disabled(!viewState.transport.canSkip)

                    Button(action: { player.send(.navigatePlaylist(next: true, autoplay: true)) }) {
                        Image(systemName: "forward.end.fill")
                            .frame(width: 20, height: 20)
                    }
                    .buttonStyle(.glass)
                    .help("Next Track (⌘→)")
                    .disabled(!viewState.transport.canPlayNextTrack)

                    Button(action: { player.send(.stop) }) {
                        Image(systemName: "stop.fill")
                            .frame(width: 20, height: 20)
                    }
                    .buttonStyle(.glass)
                    .help("Stop")
                    .disabled(!viewState.transport.canStop)
                }
            }

            HStack(spacing: 6) {
                Image(systemName: "speaker.fill")
                    .foregroundStyle(secondaryTextColor)
                    .frame(width: 16)
                Slider(value: $player.volume, in: 0...1)
                    .tint(sliderTintColor)
                    .disabled(!viewState.transport.canAdjustVolume)
                Image(systemName: "speaker.wave.3.fill")
                    .foregroundStyle(secondaryTextColor)
                    .frame(width: 16)
            }
            .font(.caption)
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity, minHeight: 60)
            .background(auxiliaryControlBackground)
        }
    }

    private var playlistBrowserCard: some View {
        Group {
            if viewState.playlist.isVisible {
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        Label("Playlist", systemImage: "music.note.list")
                            .font(.system(size: 18, weight: .semibold, design: .rounded))

                        Spacer()

                        if let playlistTrackPosition = viewState.playlist.positionDescription {
                            Text(playlistTrackPosition)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                    }

                    ScrollView {
                        VStack(spacing: LayoutMetrics.playlistTrackSpacing) {
                            ForEach(viewState.playlist.tracks) { track in
                                playlistTrackRow(track)
                            }
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .frame(minHeight: playlistMinimumHeight)
                    .scrollBounceBehavior(.basedOnSize)
                    .scrollIndicators(.automatic)
                }
                .padding(LayoutMetrics.playlistCardPadding)
                .background(cardBackground)
            }
        }
    }

    private var playlistMinimumHeight: CGFloat {
        let visibleTrackCount = min(
            max(viewState.playlist.tracks.count, 1),
            LayoutMetrics.playlistMaxVisibleRowCount
        )
        let spacingCount = max(visibleTrackCount - 1, 0)

        return CGFloat(visibleTrackCount) * LayoutMetrics.playlistRowMinHeight
            + CGFloat(spacingCount) * LayoutMetrics.playlistTrackSpacing
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 26, style: .continuous)
            .fill(cardFillColor)
            .overlay(
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .strokeBorder(cardStrokeColor, lineWidth: 1)
            )
            .shadow(color: cardShadowColor, radius: colorScheme == .dark ? 24 : 18, y: 14)
    }

    private var auxiliaryControlBackground: some View {
        RoundedRectangle(cornerRadius: 24, style: .continuous)
            .fill(auxiliaryFillColor)
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .strokeBorder(auxiliaryStrokeColor, lineWidth: 1)
            )
    }

    // MARK: - Computed Properties

    private var displayedPlaybackTime: Double {
        isEditingSlider ? sliderPosition : viewState.currentTime
    }

    private var playbackCommandActions: PlaybackCommandActions {
        PlaybackCommandActions(
            openFilePicker: { presentImporter(for: .file) },
            openFolderPicker: { presentImporter(for: .folder) },
            togglePlayPause: {
                guard viewState.transport.canPlayPause else { return }
                player.send(.togglePlayPause)
            },
            stopPlayback: {
                guard viewState.transport.canStop else { return }
                player.send(.stop)
            },
            skipForward: {
                guard viewState.transport.canSkip else { return }
                player.send(.skipForward)
            },
            skipBackward: {
                guard viewState.transport.canSkip else { return }
                player.send(.skipBackward)
            },
            playNextTrack: {
                guard viewState.transport.canPlayNextTrack else { return }
                player.send(.navigatePlaylist(next: true, autoplay: true))
            },
            playPreviousTrack: {
                guard viewState.transport.canPlayPreviousTrack else { return }
                player.send(.navigatePlaylist(next: false, autoplay: true))
            },
            canTogglePlayPause: viewState.transport.canPlayPause,
            canStopPlayback: viewState.transport.canStop,
            canSkipForward: viewState.transport.canSkip,
            canSkipBackward: viewState.transport.canSkip,
            canPlayNextTrack: viewState.transport.canPlayNextTrack,
            canPlayPreviousTrack: viewState.transport.canPlayPreviousTrack
        )
    }

    private var backgroundGradientColors: [Color] {
        if colorScheme == .dark {
            return [
                Color(red: 0.08, green: 0.11, blue: 0.16),
                Color(red: 0.11, green: 0.15, blue: 0.22),
                Color(red: 0.17, green: 0.20, blue: 0.27)
            ]
        }

        return [
            Color(red: 0.92, green: 0.95, blue: 0.98),
            Color(red: 0.84, green: 0.90, blue: 0.96),
            Color(red: 0.95, green: 0.91, blue: 0.86)
        ]
    }

    private var backgroundVeilColor: Color {
        colorScheme == .dark ? .black.opacity(0.08) : .white.opacity(0.18)
    }

    private var primaryTextColor: Color {
        colorScheme == .dark ? .white.opacity(0.92) : .black.opacity(0.78)
    }

    private var secondaryTextColor: Color {
        colorScheme == .dark ? .white.opacity(0.78) : .black.opacity(0.60)
    }

    private var tertiaryTextColor: Color {
        colorScheme == .dark ? .white.opacity(0.72) : .black.opacity(0.52)
    }

    private var sliderTintColor: Color {
        colorScheme == .dark ? .white.opacity(0.92) : .black.opacity(0.72)
    }

    private var cardFillColor: AnyShapeStyle {
        if colorScheme == .dark {
            return AnyShapeStyle(.regularMaterial.opacity(0.78))
        }

        return AnyShapeStyle(.white.opacity(0.42))
    }

    private var cardStrokeColor: Color {
        colorScheme == .dark ? .white.opacity(0.09) : .white.opacity(0.45)
    }

    private var cardShadowColor: Color {
        colorScheme == .dark ? .black.opacity(0.18) : .cyan.opacity(0.10)
    }

    private var auxiliaryFillColor: Color {
        colorScheme == .dark ? .white.opacity(0.08) : .white.opacity(0.20)
    }

    private var auxiliaryStrokeColor: Color {
        colorScheme == .dark ? .white.opacity(0.10) : .white.opacity(0.35)
    }

    private var sampleRateBannerForegroundColor: Color {
        switch viewState.sampleRateBanner.style {
        case .matched:
            return colorScheme == .dark ? Color(red: 0.82, green: 1.0, blue: 0.88) : Color(red: 0.07, green: 0.40, blue: 0.18)
        case .switching:
            return colorScheme == .dark ? Color(red: 1.0, green: 0.93, blue: 0.70) : Color(red: 0.56, green: 0.34, blue: 0.00)
        case .unsupported, .error:
            return colorScheme == .dark ? Color(red: 1.0, green: 0.86, blue: 0.86) : Color(red: 0.62, green: 0.07, blue: 0.10)
        case .idle:
            return primaryTextColor
        }
    }

    private var sampleRateBannerBorderColor: Color {
        switch viewState.sampleRateBanner.style {
        case .matched:
            return colorScheme == .dark ? .green.opacity(0.55) : .green.opacity(0.35)
        case .switching:
            return colorScheme == .dark ? .orange.opacity(0.60) : .orange.opacity(0.42)
        case .unsupported, .error:
            return colorScheme == .dark ? .red.opacity(0.70) : .red.opacity(0.42)
        case .idle:
            return colorScheme == .dark ? .white.opacity(0.12) : .black.opacity(0.10)
        }
    }

    private var sampleRateBannerBackground: some View {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .fill(sampleRateBannerFillColor)
    }

    private var sampleRateBannerFillColor: Color {
        switch viewState.sampleRateBanner.style {
        case .matched:
            return colorScheme == .dark ? .green.opacity(0.18) : .green.opacity(0.12)
        case .switching:
            return colorScheme == .dark ? .orange.opacity(0.20) : .orange.opacity(0.13)
        case .unsupported, .error:
            return colorScheme == .dark ? .red.opacity(0.24) : .red.opacity(0.14)
        case .idle:
            return colorScheme == .dark ? .white.opacity(0.07) : .white.opacity(0.24)
        }
    }

    private var sampleRateBannerIconName: String {
        viewState.sampleRateBanner.iconName
    }

    private var sampleRateBannerTitle: String {
        viewState.sampleRateBanner.title
    }

    private var sampleRateBannerDetail: String? {
        viewState.sampleRateBanner.detail
    }

    private var sampleRateBannerHelpText: String {
        viewState.sampleRateBanner.helpText
    }

    // MARK: - Private Methods

    private func timeString(_ time: Double) -> String {
        TimeFormatter.format(time)
    }

    private func remainingTimeString(currentTime: Double, duration: Double) -> String {
        TimeFormatter.formatRemaining(currentTime: currentTime, duration: duration)
    }

    private func libraryButton(systemImage: String, action: @escaping () -> Void, help: String) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 17, weight: .semibold))
                .frame(width: 20, height: 20)
        }
        .buttonStyle(.glass)
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
            player.send(.loadFolder(url: url, importerDismissalDelay: .milliseconds(50)))
        case .file, .none:
            player.send(.loadFile(url: url, importerDismissalDelay: .milliseconds(50)))
        }
    }

    private func playlistTrackRow(_ track: PlaylistTrackRow) -> some View {
        Button(action: { player.send(.selectPlaylistTrack(index: track.index)) }) {
            HStack(spacing: 12) {
                Text("\(track.index + 1)")
                    .font(.caption.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(track.isCurrent ? primaryTextColor : secondaryTextColor)
                    .frame(width: 24, alignment: .trailing)

                VStack(alignment: .leading, spacing: 2) {
                    Text(track.title)
                        .font(.callout.weight(track.isCurrent ? .semibold : .medium))
                        .lineLimit(1)

                    Text(track.subtitle)
                        .font(.caption)
                        .foregroundStyle(secondaryTextColor)
                        .lineLimit(1)
                }

                Spacer()

                if track.isCurrent {
                    Image(systemName: viewState.isPlaying ? "speaker.wave.2.fill" : "music.note")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.cyan)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, minHeight: LayoutMetrics.playlistRowMinHeight)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(track.isCurrent ? currentTrackFillColor : trackFillColor)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(track.isCurrent ? .cyan.opacity(colorScheme == .dark ? 0.25 : 0.35) : trackStrokeColor, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .contextMenu {
            if track.isCurrent {
                Button("Show in Finder") {
                    player.send(.revealCurrentTrackInFinder)
                }
            }
        }
    }

    private var currentTrackFillColor: Color {
        colorScheme == .dark ? .white.opacity(0.12) : .white.opacity(0.30)
    }

    private var trackFillColor: Color {
        colorScheme == .dark ? .white.opacity(0.05) : .white.opacity(0.18)
    }

    private var trackStrokeColor: Color {
        colorScheme == .dark ? .white.opacity(0.06) : .white.opacity(0.26)
    }
}

#Preview {
    ContentView()
}
