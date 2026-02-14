import SwiftUI

struct NowPlayingView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(PlaybackService.self) private var playbackService
    @State private var viewModel = NowPlayingViewModel()
    @State private var isDragging = false
    @State private var dragTime: TimeInterval = 0
    @State private var enrichInfoMessage = ""
    @State private var showEnrichResult = false
    @State private var enrichResults: [EnrichResultRow] = []
    @State private var showForceAction = false
    @State private var isEnriching = false
    @State private var enrichSheetHeight: CGFloat = 420
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
        .sheet(isPresented: $showEnrichResult, onDismiss: {
            showForceAction = false
            enrichInfoMessage = ""
            isEnriching = false
        }) {
            EnrichResultSheet(
                results: enrichResults,
                lastSyncText: enrichInfoMessage,
                showForceAction: showForceAction,
                isEnriching: isEnriching,
                onForce: {
                    if let song = playbackService.currentSong {
                        Task { await refreshEnrichment(for: song, force: true) }
                    }
                },
                onHeightChange: { height in
                    enrichSheetHeight = max(260, min(height, 600))
                }
            )
                .presentationDetents([.height(enrichSheetHeight)])
        }
        .onChange(of: playbackService.currentSong?.id) { oldValue, newValue in
            print("[NowPlaying] onChange(currentSong.id) - old: \(oldValue?.uuidString ?? "nil"), new: \(newValue?.uuidString ?? "nil")")
            if let song = playbackService.currentSong {
                print("[NowPlaying] onChange(currentSong.id) - loading lyrics for: \(song.title)")
                viewModel.loadLyrics(for: song)
                triggerAutoLyricsFetchIfNeeded(song: song)
            }
        }
        .onChange(of: playbackService.currentSong?.lyricsPath) { oldValue, newValue in
            print("[NowPlaying] onChange(lyricsPath) - old: \(oldValue ?? "nil"), new: \(newValue ?? "nil")")
            if let song = playbackService.currentSong {
                print("[NowPlaying] onChange(lyricsPath) - reloading lyrics for: \(song.title)")
                viewModel.loadLyrics(for: song)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .lyricsDidUpdate)) { notification in
            guard let songID = notification.userInfo?["songID"] as? UUID else { return }
            print("[NowPlaying] lyricsDidUpdate notification received for songID: \(songID)")
            // 检查当前是否正在播放这首歌
            guard playbackService.currentSong?.id == songID else {
                print("[NowPlaying] lyricsDidUpdate - ignored, not current song")
                return
            }
            print("[NowPlaying] lyricsDidUpdate - fetching updated song from DB")
            // 重新从数据库获取最新的歌曲对象，确保歌词路径已更新
            let repo = SongRepository(modelContext: modelContext)
            if let updatedSong = repo.fetchById(songID) {
                print("[NowPlaying] lyricsDidUpdate - updating playbackService.currentSong, lyricsPath: \(updatedSong.lyricsPath ?? "nil")")
                // 更新 playbackService 的引用（这会触发 .onChange 监听器，自动加载歌词）
                playbackService.currentSong = updatedSong
            } else {
                print("[NowPlaying] lyricsDidUpdate - ERROR: song not found in DB!")
            }
        }
            .onChange(of: playbackService.currentTime) { _, newTime in
                if !isDragging {
                    viewModel.updateLyricIndex(at: newTime)
                }
            }
            .onAppear {
                print("[NowPlaying] onAppear - entering detail page")
                if !viewModel.didSetInitialLyrics {
                    viewModel.showLyrics = true
                    viewModel.showVisualizer = false
                    viewModel.didSetInitialLyrics = true
                }
                if let currentSong = playbackService.currentSong {
                    // 重新从数据库获取最新的歌曲对象，避免使用过时的内存对象
                    let repo = SongRepository(modelContext: modelContext)
                    if let song = repo.fetchById(currentSong.id) {
                        print("[NowPlaying] onAppear - fetched latest song from DB: \(song.title) by \(song.artist)")
                        print("[NowPlaying] onAppear - lyricsPath: \(song.lyricsPath ?? "nil")")
                        print("[NowPlaying] onAppear - lastLyricsFetchedAt: \(song.lastLyricsFetchedAt?.description ?? "nil")")
                        print("[NowPlaying] onAppear - lastLyricsAttemptAt: \(song.lastLyricsAttemptAt?.description ?? "nil")")
                        // 更新 playbackService 的引用为最新对象
                        playbackService.currentSong = song
                        viewModel.loadLyrics(for: song)
                        triggerAutoLyricsFetchIfNeeded(song: song)
                    } else {
                        print("[NowPlaying] onAppear - ERROR: song not found in DB!")
                    }
                } else {
                    print("[NowPlaying] onAppear - no current song")
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
                enrichInfoMessage = buildLastSyncText(for: song)
                showForceAction = true
                enrichResults = buildResultResults(before: snapshot(song: song), after: song)
                showEnrichResult = true
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

    private func buildLastSyncText(for song: Song) -> String {
        if let last = latestSyncTime(for: song) {
            return "上次同步：\(formatDate(last))"
        }
        return "上次同步：暂无成功同步"
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
        print("[NowPlaying] refreshEnrichment - MANUAL REFRESH triggered (force: \(force)) for: \(song.title)")
        let before = snapshot(song: song)
        let repo = SongRepository(modelContext: modelContext)
        let reason: EnrichReason = force ? .force : .manual
        await MainActor.run {
            isEnriching = true
            enrichResults = buildLoadingResults()
            showEnrichResult = true
            enrichInfoMessage = buildLastSyncText(for: song)
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
            showEnrichResult = true
            showForceAction = true
            isEnriching = false
            if let updated = updated {
                enrichInfoMessage = buildLastSyncText(for: updated)
            }
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
            return [EnrichResultRow(title: "同步", status: "同步失败", source: nil)]
        }

        let titleStatus = fieldStatus(before: before.title, after: after.title, isUnknown: isUnknownText(after.title))
        let artistStatus = fieldStatus(before: before.artist, after: after.artist, isUnknown: isUnknownText(after.artist))
        let albumStatus = fieldStatus(before: before.album, after: after.album, isUnknown: isUnknownText(after.album))
        let artworkStatus = artworkResult(before: before.hasArtwork, after: after.artworkData != nil)
        let lyricsStatus = lyricsResult(before: before.lyricsPath, after: after.lyricsPath)

        let metaSource = after.metadataSource
        let lyricsSource = after.lyricsSource

        return [
            EnrichResultRow(title: "歌名", status: titleStatus, source: metaSource),
            EnrichResultRow(title: "歌手", status: artistStatus, source: metaSource),
            EnrichResultRow(title: "专辑", status: albumStatus, source: metaSource),
            EnrichResultRow(title: "封面", status: artworkStatus, source: metaSource),
            EnrichResultRow(title: "歌词", status: lyricsStatus, source: lyricsSource)
        ]
    }

    private func buildLoadingResults() -> [EnrichResultRow] {
        [
            EnrichResultRow(title: "歌名", status: "同步中", source: nil),
            EnrichResultRow(title: "歌手", status: "同步中", source: nil),
            EnrichResultRow(title: "专辑", status: "同步中", source: nil),
            EnrichResultRow(title: "封面", status: "同步中", source: nil),
            EnrichResultRow(title: "歌词", status: "同步中", source: nil)
        ]
    }

    private func fieldStatus(before: String, after: String, isUnknown: Bool) -> String {
        let beforeMissing = isUnknownText(before)
        let afterMissing = isUnknown
        if afterMissing {
            return beforeMissing ? "同步失败" : "已同步"
        }
        if before == after {
            return beforeMissing ? "同步失败" : "已同步"
        }
        return "同步成功"
    }

    private func artworkResult(before: Bool, after: Bool) -> String {
        if after {
            return before ? "已同步" : "同步成功"
        }
        return before ? "已同步" : "同步失败"
    }

    private func lyricsResult(before: String?, after: String?) -> String {
        let hadBefore = before != nil
        let hasAfter = after != nil
        if hasAfter {
            return hadBefore ? "已同步" : "同步成功"
        }
        return hadBefore ? "已同步" : "同步失败"
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

    private func triggerAutoLyricsFetchIfNeeded(song: Song) {
        if song.lyricsPath == nil {
            print("[NowPlaying] triggerAutoLyricsFetchIfNeeded - no lyrics path, will fetch for: \(song.title)")
            let repo = SongRepository(modelContext: modelContext)
            Task {
                await LyricsEnrichmentService.shared.enrich(
                    songID: song.id,
                    repository: repo,
                    reason: .playback
                )
            }
        } else {
            print("[NowPlaying] triggerAutoLyricsFetchIfNeeded - already has lyrics path: \(song.lyricsPath ?? "")")
        }
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
    let source: String?
}

private struct EnrichResultSheet: View {
    let results: [EnrichResultRow]
    let lastSyncText: String
    let showForceAction: Bool
    let isEnriching: Bool
    let onForce: () -> Void
    let onHeightChange: (CGFloat) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List {
            if !lastSyncText.isEmpty {
                Section {
                    HStack(spacing: 10) {
                        Image(systemName: "checkmark.seal.fill")
                            .foregroundColor(.accentColor)
                            .font(.body)
                        Text(lastSyncText)
                            .font(.body)
                            .fontWeight(.semibold)
                        Spacer()
                        if showForceAction {
                            Button {
                                onForce()
                            } label: {
                                Image(systemName: "arrow.clockwise")
                                    .font(.body)
                                    .rotationEffect(.degrees(isEnriching ? 360 : 0))
                                    .animation(
                                        .linear(duration: 1).repeatForever(autoreverses: false),
                                        value: isEnriching
                                    )
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .buttonBorderShape(.capsule)
                            .disabled(isEnriching)
                        }
                    }
                    .padding(.vertical, 4)
                }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 4, trailing: 16))
            }

            Section {
                ForEach(results) { row in
                    HStack {
                        Text(row.title)
                        Spacer()
                        HStack(spacing: 6) {
                            statusPill(text: row.status, status: row.status)
                            if let source = row.source, row.status != "同步中" {
                                sourcePill(text: source)
                            }
                        }
                    }
                }
            }
        }
        .listStyle(.plain)
        .listSectionSpacing(0)
        .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
        .background(
            GeometryReader { proxy in
                Color.clear
                    .preference(key: EnrichSheetHeightKey.self, value: proxy.size.height)
            }
        )
        .onPreferenceChange(EnrichSheetHeightKey.self) { height in
            onHeightChange(height)
        }
    }

    private func color(for status: String) -> Color {
        switch status {
        case "同步成功":
            return .green
        case "已同步":
            return .blue
        case "同步中":
            return .accentColor
        default:
            return .orange
        }
    }

    private func statusPill(text: String, status: String) -> some View {
        Text(text)
            .font(.subheadline)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .foregroundColor(color(for: status))
            .background(
                Capsule()
                    .fill(color(for: status).opacity(0.15))
            )
    }

    private func sourcePill(text: String) -> some View {
        Text(text)
            .font(.subheadline)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .foregroundColor(.secondary)
            .background(
                Capsule()
                    .fill(Color.secondary.opacity(0.12))
            )
    }
}

private struct EnrichSheetHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        let next = nextValue()
        if next > 0 {
            value = next
        }
    }
}
