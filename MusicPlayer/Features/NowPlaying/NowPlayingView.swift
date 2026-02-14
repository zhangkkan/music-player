import SwiftUI

struct NowPlayingView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(PlaybackService.self) private var playbackService
    @State private var viewModel = NowPlayingViewModel()
    @State private var isDragging = false
    @State private var dragTime: TimeInterval = 0
    @State private var showEnrichInfo = false
    @State private var enrichInfoMessage = ""
    @State private var showEnrichResult = false
    @State private var enrichResults: [EnrichResultRow] = []
    @State private var showForceAction = false
    @State private var showEnrichLoading = false
    @State private var isDismissing = false
    @State private var dragOffset: CGSize = .zero
    @State private var dragAxis: DragAxis = .none
    @State private var showQueue = false

    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                let isCompact = geometry.size.height < 700
                let progress = dragProgress

                ZStack(alignment: .bottom) {
                    Color.black.opacity(0.2 * (1 - progress))
                        .ignoresSafeArea()

                    VStack(spacing: isCompact ? 12 : 20) {
                        // Drag indicator
                        Capsule()
                            .fill(Color.secondary.opacity(0.3))
                            .frame(width: 40, height: 5)
                            .padding(.top, 8)

                    if let song = playbackService.currentSong {
                        // Artwork
                        artworkView(song: song, size: isCompact ? 200 : 300)

                        // Song info
                        VStack(spacing: 4) {
                            Text(song.title)
                                .font(.title2)
                                .fontWeight(.bold)
                                .lineLimit(1)
                            Text(song.artist)
                                .font(.body)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                            Text(song.album)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }
                        .padding(.horizontal)

                        // Lyrics / Visualizer toggle area
                        if viewModel.showLyrics {
                            LyricsView(lyrics: viewModel.lyrics,
                                      currentIndex: viewModel.currentLyricIndex)
                                .frame(height: isCompact ? 80 : 120)
                        } else if viewModel.showVisualizer {
                            VisualizerView(spectrumData: playbackService.visualizer.spectrumData)
                                .frame(height: isCompact ? 80 : 120)
                        }

                        Spacer()

                        // Progress bar
                        progressSection

                        // Playback controls
                        controlsSection

                        // Bottom toolbar
                        bottomToolbar(song: song)
                    }
                    }
                    .padding(.horizontal)
                    .padding(.top, 12)
                    .padding(.bottom, geometry.safeAreaInsets.bottom)
                    .background(
                        UnevenRoundedRectangle(cornerRadii: .init(
                            topLeading: 24,
                            topTrailing: 24
                        ))
                            .fill(Color(.systemBackground))
                    )
                    .shadow(color: .black.opacity(0.15), radius: 20, y: 8)
                    .contentShape(Rectangle())
                    .offset(x: max(0, dragOffset.width), y: max(0, dragOffset.height))
                    .gesture(dismissGesture)
                    .ignoresSafeArea(edges: .bottom)
                }
            }
        .background(Color.clear)
        .presentationBackground(.clear)
        .sheet(isPresented: $showEnrichInfo) {
            if let song = playbackService.currentSong {
                EnrichInfoSheet(
                    lastSyncText: enrichInfoMessage,
                    showForceAction: showForceAction,
                    onForce: {
                        Task { await refreshEnrichment(for: song, force: true) }
                    }
                )
                .presentationDetents([.height(240)])
            }
        }
        .sheet(isPresented: $showEnrichLoading) {
            EnrichLoadingSheet()
                .presentationDetents([.height(220)])
        }
        .sheet(isPresented: $showEnrichResult) {
            EnrichResultSheet(results: enrichResults)
                .presentationDetents([.medium])
        }
        .onChange(of: playbackService.currentSong?.id) { _, _ in
            if let song = playbackService.currentSong {
                viewModel.loadLyrics(for: song)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .lyricsDidUpdate)) { notification in
            guard let song = playbackService.currentSong else { return }
            if let id = notification.userInfo?["songID"] as? UUID, id == song.id {
                viewModel.loadLyrics(for: song)
            }
        }
            .onChange(of: playbackService.currentTime) { _, newTime in
                if !isDragging {
                    viewModel.updateLyricIndex(at: newTime)
                }
            }
            .onAppear {
                if !viewModel.didSetInitialLyrics {
                    viewModel.showLyrics = true
                    viewModel.showVisualizer = false
                    viewModel.didSetInitialLyrics = true
                }
                if let song = playbackService.currentSong {
                    viewModel.loadLyrics(for: song)
                }
                playbackService.visualizer.isActive = viewModel.showVisualizer
            }
            .onDisappear {
                viewModel.didSetInitialLyrics = false
                playbackService.visualizer.isActive = false
            }
            .sheet(isPresented: $viewModel.showEqualizer) {
                EqualizerView()
            }
            .sheet(isPresented: $showQueue) {
                NowPlayingQueueView()
            }
        }
    }

    private var dragProgress: Double {
        let distance = max(dragOffset.width, dragOffset.height)
        if distance <= 0 { return 0 }
        return min(1.0, Double(distance / 200))
    }

    // MARK: - Artwork

    @ViewBuilder
    private func artworkView(song: Song, size: CGFloat) -> some View {
        if let artworkData = song.artworkData, let uiImage = UIImage(data: artworkData) {
            Image(uiImage: uiImage)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: size, height: size)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .shadow(color: .black.opacity(0.3), radius: 20, y: 10)
        } else {
            RoundedRectangle(cornerRadius: 16)
                .fill(
                    LinearGradient(
                        colors: [.purple.opacity(0.6), .blue.opacity(0.4)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: size, height: size)
                .overlay(
                    Image(systemName: "music.note")
                        .font(.system(size: size * 0.3))
                        .foregroundColor(.white.opacity(0.7))
                )
                .shadow(color: .black.opacity(0.3), radius: 20, y: 10)
        }
    }

    // MARK: - Progress

    private var progressSection: some View {
        VStack(spacing: 4) {
            Slider(
                value: Binding(
                    get: { isDragging ? dragTime : playbackService.currentTime },
                    set: { newValue in
                        isDragging = true
                        dragTime = newValue
                    }
                ),
                in: 0...max(playbackService.duration, 1),
                onEditingChanged: { editing in
                    if !editing {
                        playbackService.seek(to: dragTime)
                        isDragging = false
                    }
                }
            )
            .tint(.accentColor)

            HStack {
                Text(formatTime(isDragging ? dragTime : playbackService.currentTime))
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .monospacedDigit()
                Spacer()
                Text(formatTime(playbackService.duration))
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .monospacedDigit()
            }
        }
        .padding(.horizontal)
    }

    // MARK: - Controls

    private var controlsSection: some View {
        HStack(spacing: 40) {
            // Playback mode
            Button {
                playbackService.cyclePlaybackMode()
            } label: {
                Image(systemName: playbackService.playbackMode.icon)
                    .font(.body)
                    .foregroundColor(playbackService.playbackMode == .sequential ? .secondary : .accentColor)
            }

            // Previous
            Button {
                playbackService.playPrevious()
            } label: {
                Image(systemName: "backward.fill")
                    .font(.title2)
                    .foregroundColor(.primary)
            }

            // Play/Pause
            Button {
                playbackService.togglePlayPause()
            } label: {
                Image(systemName: playbackService.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.system(size: 60))
                    .foregroundColor(.accentColor)
            }

            // Next
            Button {
                playbackService.playNext()
            } label: {
                Image(systemName: "forward.fill")
                    .font(.title2)
                    .foregroundColor(.primary)
            }

            // Volume / Airplay placeholder
            Button {
                // TODO: AirPlay picker
            } label: {
                Image(systemName: "airplayaudio")
                    .font(.body)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 8)
    }

    // MARK: - Bottom Toolbar

    private func bottomToolbar(song: Song) -> some View {
        HStack(spacing: 32) {
            // Favorite
            Button {
                song.isFavorite.toggle()
            } label: {
                Image(systemName: song.isFavorite ? "heart.fill" : "heart")
                    .foregroundColor(song.isFavorite ? .red : .secondary)
            }

            // Lyrics toggle
            Button {
                viewModel.showLyrics.toggle()
                if viewModel.showLyrics { viewModel.showVisualizer = false }
            } label: {
                Image(systemName: "text.quote")
                    .foregroundColor(viewModel.showLyrics ? .accentColor : .secondary)
            }

            // Visualizer toggle
            Button {
                viewModel.showVisualizer.toggle()
                playbackService.visualizer.isActive = viewModel.showVisualizer
                if viewModel.showVisualizer { viewModel.showLyrics = false }
            } label: {
                Image(systemName: "waveform")
                    .foregroundColor(viewModel.showVisualizer ? .accentColor : .secondary)
            }

            // EQ
            Button {
                viewModel.showEqualizer = true
            } label: {
                Image(systemName: "slider.vertical.3")
                    .foregroundColor(.secondary)
            }

            Button {
                showQueue = true
            } label: {
                Image(systemName: "list.bullet")
                    .foregroundColor(.secondary)
            }

            // Metadata Enrich
            Button {
                guard let song = playbackService.currentSong else { return }
                if let last = latestSyncTime(for: song) {
                    enrichInfoMessage = "已在 \(formatDate(last)) 同步过信息。"
                    showForceAction = true
                    showEnrichInfo = true
                } else {
                    Task {
                        await refreshEnrichment(for: song, force: false)
                    }
                }
            } label: {
                Image(systemName: "wand.and.stars")
                    .foregroundColor(.secondary)
            }

            // Close
            Button {
                dismiss()
            } label: {
                Image(systemName: "chevron.down")
                    .foregroundColor(.secondary)
            }
        }
        .font(.title2)
        .padding(.bottom, 20)
    }

    private func formatTime(_ seconds: TimeInterval) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", mins, secs)
    }

    private func latestSyncTime(for song: Song) -> Date? {
        let times = [song.lastEnrichedAt, song.lastLyricsFetchedAt].compactMap { $0 }
        return times.max()
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter.string(from: date)
    }

    private var dismissGesture: some Gesture {
        DragGesture(minimumDistance: 12)
            .onChanged { value in
                let horizontal = value.translation.width
                let vertical = value.translation.height
                let startY = value.startLocation.y
                let allowDown = startY < 120 && vertical > 0
                let allowRight = horizontal > 0 && abs(vertical) < 120

                if dragAxis == .none {
                    if abs(vertical) > abs(horizontal), allowDown {
                        dragAxis = .vertical
                    } else if abs(horizontal) > abs(vertical), allowRight {
                        dragAxis = .horizontal
                    }
                }

                var offset = CGSize.zero
                switch dragAxis {
                case .vertical:
                    if allowDown {
                        offset.height = max(0, vertical)
                    }
                case .horizontal:
                    if allowRight {
                        offset.width = max(0, horizontal)
                    }
                case .none:
                    break
                }
                dragOffset = offset
            }
            .onEnded { value in
                guard !isDismissing else { return }
                let horizontal = value.translation.width
                let vertical = value.translation.height
                let startY = value.startLocation.y
                let isTopPull = startY < 120 && vertical > 80
                let isRightSwipe = horizontal > 80 && abs(vertical) < 60
                if isTopPull || isRightSwipe {
                    isDismissing = true
                    dismiss()
                } else {
                    dragOffset = .zero
                }
                dragAxis = .none
            }
    }

    private func refreshEnrichment(for song: Song, force: Bool) async {
        let before = snapshot(song: song)
        let repo = SongRepository(modelContext: modelContext)
        let reason: EnrichReason = force ? .force : .manual
        await MainActor.run {
            showEnrichLoading = true
        }

        await MetadataEnrichmentService.shared.enrich(
            songID: song.id,
            repository: repo,
            reason: reason
        )
        await LyricsEnrichmentService.shared.enrich(
            songID: song.id,
            repository: repo,
            reason: reason
        )

        let updated = repo.fetchById(song.id)
        let results = buildResultResults(before: before, after: updated)
        await MainActor.run {
            enrichResults = results
            showEnrichLoading = false
            showEnrichResult = true
            showForceAction = false
        }
    }

    private func snapshot(song: Song) -> SongSnapshot {
        SongSnapshot(
            title: song.title,
            artist: song.artist,
            album: song.album,
            hasArtwork: song.artworkData != nil,
            lyricsPath: song.lyricsPath
        )
    }

    private func buildResultResults(before: SongSnapshot, after: Song?) -> [EnrichResultRow] {
        guard let after = after else {
            return [EnrichResultRow(title: "同步", status: "未获取")]
        }

        let titleStatus = fieldStatus(before: before.title, after: after.title, isUnknown: isUnknownText(after.title))
        let artistStatus = fieldStatus(before: before.artist, after: after.artist, isUnknown: isUnknownText(after.artist))
        let albumStatus = fieldStatus(before: before.album, after: after.album, isUnknown: isUnknownText(after.album))
        let artworkStatus = artworkResult(before: before.hasArtwork, after: after.artworkData != nil)
        let lyricsStatus = lyricsResult(before: before.lyricsPath, after: after.lyricsPath)

        let metaSource = after.metadataSource ?? "未知"
        let lyricsSource = after.lyricsSource ?? "未知"
        let metaTime = after.lastEnrichedAt.map(formatDate) ?? "未知"
        let lyricsTime = after.lastLyricsFetchedAt.map(formatDate) ?? "未知"

        return [
            EnrichResultRow(title: "标题", status: titleStatus),
            EnrichResultRow(title: "歌手", status: artistStatus),
            EnrichResultRow(title: "专辑", status: albumStatus),
            EnrichResultRow(title: "封面", status: artworkStatus),
            EnrichResultRow(title: "歌词", status: lyricsStatus),
            EnrichResultRow(title: "元数据来源", status: metaSource),
            EnrichResultRow(title: "歌词来源", status: lyricsSource),
            EnrichResultRow(title: "元数据更新时间", status: metaTime),
            EnrichResultRow(title: "歌词更新时间", status: lyricsTime)
        ]
    }

    private func fieldStatus(before: String, after: String, isUnknown: Bool) -> String {
        if before == after {
            return isUnknown ? "未获取" : "已存在"
        }
        return "已更新"
    }

    private func artworkResult(before: Bool, after: Bool) -> String {
        if before && after { return "已存在" }
        if !before && after { return "获取成功" }
        return "未获取"
    }

    private func lyricsResult(before: String?, after: String?) -> String {
        if before != nil && after != nil { return "已存在" }
        if before == nil && after != nil { return "获取成功" }
        return "未获取"
    }

    private func isUnknownText(_ value: String) -> Bool {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return normalized.isEmpty ||
            normalized == "unknown" ||
            normalized == "unknown artist" ||
            normalized == "unknown album" ||
            normalized == "未知" ||
            normalized == "未知艺术家" ||
            normalized == "未知专辑"
    }
}

private struct SongSnapshot {
    let title: String
    let artist: String
    let album: String
    let hasArtwork: Bool
    let lyricsPath: String?
}

private enum DragAxis {
    case none
    case vertical
    case horizontal
}

private struct EnrichResultRow: Identifiable {
    let id = UUID()
    let title: String
    let status: String
}

private struct EnrichResultSheet: View {
    let results: [EnrichResultRow]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                ForEach(results) { row in
                    HStack {
                        Text(row.title)
                        Spacer()
                        Text(row.status)
                            .foregroundColor(color(for: row.status))
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("同步结果")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }

    private func color(for status: String) -> Color {
        switch status {
        case "已更新", "获取成功":
            return .green
        case "已存在":
            return .secondary
        default:
            return .orange
        }
    }
}

private struct EnrichInfoSheet: View {
    let lastSyncText: String
    let showForceAction: Bool
    let onForce: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 40))
                    .foregroundColor(.accentColor)
                Text("已同步")
                    .font(.headline)
                Text(lastSyncText)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)

                HStack(spacing: 12) {
                    if showForceAction {
                        Button("强制刷新") {
                            onForce()
                            dismiss()
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    Button("知道了") { dismiss() }
                        .buttonStyle(.bordered)
                }
            }
            .padding(.vertical, 24)
            .navigationTitle("同步信息")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

private struct EnrichLoadingSheet: View {
    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                ProgressView()
                    .progressViewStyle(.circular)
                Text("正在同步…")
                    .font(.headline)
                Text("请稍候，正在获取封面、信息与歌词")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            .padding(.vertical, 24)
            .navigationTitle("同步中")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
