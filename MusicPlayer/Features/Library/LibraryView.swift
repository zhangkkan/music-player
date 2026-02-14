import SwiftUI
import SwiftData
import PhotosUI
import UniformTypeIdentifiers

struct LibraryView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(PlaybackService.self) private var playbackService
    @State private var viewModel = LibraryViewModel()
    @State private var showImporter = false
    @State private var showDeleteConfirm = false
    @State private var pendingDeleteSong: Song?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Category picker
                Picker("分类", selection: $viewModel.selectedCategory) {
                    ForEach(LibraryCategory.allCases, id: \.self) { category in
                        Text(category.rawValue).tag(category)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.vertical, 8)

                // Content
                switch viewModel.selectedCategory {
                case .songs:
                    songsList
                case .albums:
                    albumsList
                case .artists:
                    artistsList
                case .genres:
                    genresList
                }
            }
            .navigationTitle("音乐库")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showImporter = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showImporter) {
                DocumentPicker(contentTypes: ImportService.supportedTypes) { urls in
                    viewModel.importFiles(urls)
                }
            }
            .alert("删除歌曲", isPresented: $showDeleteConfirm) {
                Button("删除", role: .destructive) {
                    if let song = pendingDeleteSong {
                        playbackService.removeFromQueue(songID: song.id)
                        viewModel.deleteSong(song)
                    }
                    pendingDeleteSong = nil
                }
                Button("取消", role: .cancel) {
                    pendingDeleteSong = nil
                }
            } message: {
                Text("将删除：\(pendingDeleteSong?.title ?? "")")
            }
            .onAppear {
                viewModel.setup(modelContext: modelContext)
            }
            .onReceive(NotificationCenter.default.publisher(for: .backupWillImport)) { _ in
                pendingDeleteSong = nil
                showDeleteConfirm = false
                showImporter = false
                viewModel.resetForImport()
            }
        }
    }

    // MARK: - Songs List

    private var songsList: some View {
        Group {
            if viewModel.songs.isEmpty {
                emptyState
            } else {
                List {
                    // Play all button
                    Button {
                        playbackService.play(songs: viewModel.songs)
                    } label: {
                        Label("播放全部 (\(viewModel.songs.count)首)", systemImage: "play.fill")
                            .foregroundColor(.accentColor)
                    }

                    ForEach(viewModel.songs, id: \.id) { song in
                        SongRow(
                            song: song,
                            onTap: {
                                playbackService.showNowPlaying = true
                                playbackService.enqueueAndPlay(song)
                            },
                            onDoubleTap: {
                                playbackService.showNowPlaying = true
                                playbackService.play(
                                    songs: viewModel.songs,
                                    startIndex: viewModel.songs.firstIndex(where: { $0.id == song.id }) ?? 0
                                )
                            }
                        )
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                pendingDeleteSong = song
                                showDeleteConfirm = true
                            } label: {
                                Label("删除", systemImage: "trash")
                            }
                        }
                        .swipeActions(edge: .leading) {
                            Button {
                                viewModel.toggleFavorite(song)
                            } label: {
                                Label(song.isFavorite ? "取消收藏" : "收藏",
                                      systemImage: song.isFavorite ? "heart.slash" : "heart")
                            }
                            .tint(song.isFavorite ? .gray : .red)
                        }
                    }
                }
                .listStyle(.plain)
            }
        }
    }

    // MARK: - Albums List

    private var albumsList: some View {
        Group {
            if viewModel.albums.isEmpty {
                emptyState
            } else {
                List(viewModel.albums, id: \.album) { albumInfo in
                    NavigationLink {
                        AlbumDetailView(album: albumInfo.album, artist: albumInfo.artist,
                                       songs: viewModel.songsForAlbum(albumInfo.album))
                    } label: {
                        HStack {
                            if let data = viewModel.artworkForAlbum(albumInfo.album),
                               let uiImage = UIImage(data: data) {
                                Image(uiImage: uiImage)
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                                    .frame(width: 44, height: 44)
                                    .clipShape(RoundedRectangle(cornerRadius: 6))
                            } else {
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(Color.gray.opacity(0.2))
                                    .frame(width: 44, height: 44)
                                    .overlay(
                                        Image(systemName: "square.stack")
                                            .foregroundColor(.gray)
                                    )
                            }
                            VStack(alignment: .leading) {
                                Text(albumInfo.album)
                                    .font(.body)
                                Text(albumInfo.artist)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
                .listStyle(.plain)
            }
        }
    }

    // MARK: - Artists List

    private var artistsList: some View {
        Group {
            if viewModel.artists.isEmpty {
                emptyState
            } else {
                List(viewModel.artists, id: \.self) { artist in
                    NavigationLink {
                        ArtistDetailView(
                            artist: artist,
                            songs: viewModel.songsForArtist(artist),
                            viewModel: viewModel
                        )
                    } label: {
                        HStack {
                            if let data = viewModel.artworkForArtist(artist),
                               let uiImage = UIImage(data: data) {
                                Image(uiImage: uiImage)
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                                    .frame(width: 44, height: 44)
                                    .clipShape(Circle())
                            } else {
                                Circle()
                                    .fill(Color.gray.opacity(0.2))
                                    .frame(width: 44, height: 44)
                                    .overlay(
                                        Image(systemName: "person.circle")
                                            .foregroundColor(.gray)
                                    )
                            }
                            Text(artist)
                        }
                    }
                    .onAppear {
                        viewModel.loadArtistArtworkIfNeeded(artist)
                    }
                }
                .listStyle(.plain)
            }
        }
    }

    // MARK: - Genres List

    private var genresList: some View {
        Group {
            if viewModel.genres.isEmpty {
                emptyState
            } else {
                List(viewModel.genres, id: \.self) { genre in
                    NavigationLink {
                        GenreDetailView(genre: genre, songs: viewModel.songsForGenre(genre))
                    } label: {
                        HStack {
                            Image(systemName: "guitars")
                                .font(.title2)
                                .foregroundColor(.secondary)
                                .frame(width: 44, height: 44)
                            Text(genre)
                        }
                    }
                }
                .listStyle(.plain)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "music.note")
                .font(.system(size: 60))
                .foregroundColor(.secondary)
            Text("暂无音乐")
                .font(.title2)
                .foregroundColor(.secondary)
            Text("点击右上角 + 导入音乐文件")
                .font(.subheadline)
                .foregroundColor(.secondary)
            Spacer()
        }
    }
}

// MARK: - Song Row

struct SongRow: View {
    let song: Song
    let onTap: () -> Void
    let onDoubleTap: (() -> Void)?
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Playlist.createdAt) private var playlists: [Playlist]
    @State private var showPlaylistSheet = false
    @State private var singleTapWorkItem: DispatchWorkItem?

    var body: some View {
        HStack(spacing: 12) {
            // Artwork
            if let artworkData = song.artworkData, let uiImage = UIImage(data: artworkData) {
                Image(uiImage: uiImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 48, height: 48)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            } else {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.gray.opacity(0.2))
                    .frame(width: 48, height: 48)
                    .overlay(
                        Image(systemName: "music.note")
                            .foregroundColor(.gray)
                    )
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(song.title)
                    .font(.body)
                    .lineLimit(1)
                HStack(spacing: 4) {
                    if song.isFavorite {
                        Image(systemName: "heart.fill")
                            .font(.caption2)
                            .foregroundColor(.red)
                    }
                    Text(song.artist)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                    Text("·")
                        .foregroundColor(.secondary)
                    Text(song.format.uppercased())
                        .font(.caption2)
                        .foregroundColor(.orange)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Color.orange.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 3))
                }
            }

            Spacer()

            Button {
                let repo = SongRepository(modelContext: modelContext)
                repo.toggleFavorite(song)
            } label: {
                Image(systemName: song.isFavorite ? "heart.fill" : "heart")
                    .foregroundColor(song.isFavorite ? .red : .secondary)
            }
            .buttonStyle(.plain)

            Button {
                showPlaylistSheet = true
            } label: {
                Image(systemName: hasAnyPlaylist(song) ? "text.badge.checkmark" : "text.badge.plus")
                    .foregroundColor(hasAnyPlaylist(song) ? .accentColor : .secondary)
                    .padding(6)
                    .background((hasAnyPlaylist(song) ? Color.accentColor.opacity(0.12) : Color.secondary.opacity(0.08)))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)

            Text(formatDuration(song.duration))
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) {
            singleTapWorkItem?.cancel()
            singleTapWorkItem = nil
            onDoubleTap?()
        }
        .onTapGesture {
            singleTapWorkItem?.cancel()
            let workItem = DispatchWorkItem { onTap() }
            singleTapWorkItem = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: workItem)
        }
        .sheet(isPresented: $showPlaylistSheet) {
            PlaylistPickerSheet(
                song: song,
                playlists: playlists,
                onAdd: add
            )
            .presentationDetents([.medium, .large])
        }
    }

    private func formatDuration(_ seconds: Double) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", mins, secs)
    }

    private func add(song: Song, to playlist: Playlist) {
        if playlist.playlistSongs.contains(where: { $0.song?.id == song.id }) {
            return
        }
        let order = playlist.playlistSongs.count
        let item = PlaylistSong(order: order, song: song, playlist: playlist)
        modelContext.insert(item)
        try? modelContext.save()
    }

    private func hasAnyPlaylist(_ song: Song) -> Bool {
        playlists.contains { playlist in
            playlist.playlistSongs.contains(where: { $0.song?.id == song.id })
        }
    }

    private func inPlaylist(_ song: Song, _ playlist: Playlist) -> Bool {
        playlist.playlistSongs.contains(where: { $0.song?.id == song.id })
    }
}

private struct PlaylistPickerSheet: View {
    let song: Song
    let playlists: [Playlist]
    let onAdd: (Song, Playlist) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var newPlaylistName = ""

    var body: some View {
        NavigationStack {
            List {
                Section("加入播放列表") {
                    if playlists.isEmpty {
                        Text("暂无播放列表")
                            .foregroundColor(.secondary)
                            .font(.footnote)
                    } else {
                        ForEach(playlists, id: \.id) { playlist in
                            Button {
                                toggle(song: song, in: playlist)
                            } label: {
                                HStack {
                                    Text(playlist.name)
                                    Spacer()
                                    if isInPlaylist(song, playlist) {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundColor(.accentColor)
                                    }
                                }
                            }
                        }
                    }
                }

                Section("新建播放列表") {
                    TextField("播放列表名称", text: $newPlaylistName)
                        .textInputAutocapitalization(.never)
                    Button("创建并添加") {
                        let trimmed = newPlaylistName.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !trimmed.isEmpty else { return }
                        createPlaylistAndAddSong(name: trimmed)
                        newPlaylistName = ""
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("快速收藏")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }

    private func createPlaylistAndAddSong(name: String) {
        let playlist = Playlist(name: name)
        modelContext.insert(playlist)
        onAdd(song, playlist)
        try? modelContext.save()
    }

    private func toggle(song: Song, in playlist: Playlist) {
        if let existing = playlist.playlistSongs.first(where: { $0.song?.id == song.id }) {
            modelContext.delete(existing)
        } else {
            onAdd(song, playlist)
        }
        try? modelContext.save()
    }

    private func isInPlaylist(_ song: Song, _ playlist: Playlist) -> Bool {
        playlist.playlistSongs.contains(where: { $0.song?.id == song.id })
    }
}

// MARK: - Detail Views

struct AlbumDetailView: View {
    let album: String
    let artist: String
    let songs: [Song]
    @Environment(PlaybackService.self) private var playbackService
    @Environment(\.modelContext) private var modelContext
    @State private var displayedSongs: [Song]
    private let headerHeight: CGFloat = 280

    init(album: String, artist: String, songs: [Song]) {
        self.album = album
        self.artist = artist
        self.songs = songs
        _displayedSongs = State(initialValue: songs)
    }

    var body: some View {
        List {
            Section {
                ZStack(alignment: .bottomLeading) {
                    albumHeaderImage
                    VStack(alignment: .leading, spacing: 4) {
                        Text(album)
                            .font(.title2)
                            .bold()
                            .foregroundColor(.white)
                            .shadow(radius: 2)
                        Text(artist)
                            .font(.subheadline)
                            .foregroundColor(.white.opacity(0.9))
                            .shadow(radius: 2)
                    }
                    .padding(16)
                }
                .listRowInsets(EdgeInsets())
                .listRowSeparator(.hidden)
            }
            Button {
                playbackService.play(songs: displayedSongs)
            } label: {
                Label("播放全部", systemImage: "play.fill")
                    .foregroundColor(.accentColor)
            }
            ForEach(displayedSongs, id: \.id) { song in
                SongRow(
                            song: song,
                            onTap: {
                                playbackService.showNowPlaying = true
                                playbackService.enqueueAndPlay(song)
                            },
                            onDoubleTap: {
                                playbackService.showNowPlaying = true
                                playbackService.play(
                                    songs: displayedSongs,
                                    startIndex: displayedSongs.firstIndex(where: { $0.id == song.id }) ?? 0
                                )
                            }
                        )
                .swipeActions(edge: .trailing) {
                    Button(role: .destructive) {
                        deleteSong(song)
                    } label: {
                        Label("删除", systemImage: "trash")
                    }
                }
                .swipeActions(edge: .leading) {
                    Button {
                        toggleFavorite(song)
                    } label: {
                        Label(song.isFavorite ? "取消收藏" : "收藏",
                              systemImage: song.isFavorite ? "heart.slash" : "heart")
                    }
                    .tint(song.isFavorite ? .gray : .red)
                }
            }
        }
        .listStyle(.plain)
        .navigationTitle(album)
        .navigationBarTitleDisplayMode(.inline)
        .onReceive(NotificationCenter.default.publisher(for: .backupWillImport)) { _ in
            displayedSongs = []
        }
    }

    private var albumHeaderImage: some View {
        let data = displayedSongs.compactMap(\.artworkData).max { $0.count < $1.count }
        if let data, let uiImage = UIImage(data: data) {
            return AnyView(
                Image(uiImage: uiImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(height: headerHeight)
                    .frame(maxWidth: .infinity)
                    .clipped()
                    .overlay(
                        LinearGradient(
                            gradient: Gradient(colors: [Color.black.opacity(0.6), Color.clear]),
                            startPoint: .bottom,
                            endPoint: .center
                        )
                    )
            )
        }

        return AnyView(
            Rectangle()
                .fill(Color.gray.opacity(0.2))
                .frame(height: headerHeight)
                .overlay(
                    Image(systemName: "square.stack")
                        .font(.largeTitle)
                        .foregroundColor(.gray)
                )
        )
    }

    private func deleteSong(_ song: Song) {
        displayedSongs.removeAll { $0.id == song.id }
        playbackService.removeFromQueue(songID: song.id)
        let repo = SongRepository(modelContext: modelContext)
        repo.deleteSongAndCleanup(song)
    }

    private func toggleFavorite(_ song: Song) {
        let repo = SongRepository(modelContext: modelContext)
        repo.toggleFavorite(song)
    }
}

struct ArtistDetailView: View {
    let artist: String
    let songs: [Song]
    @Bindable var viewModel: LibraryViewModel
    @Environment(PlaybackService.self) private var playbackService
    @Environment(\.modelContext) private var modelContext
    @State private var displayedSongs: [Song]
    private let headerHeight: CGFloat = 280
    @State private var showAvatarActions = false
    @State private var showAvatarDrawer = false
    @State private var showFilePicker = false
    @State private var showPhotoPicker = false
    @State private var pickedPhotoItem: PhotosPickerItem?
    @State private var candidates: [ArtistAvatarCandidate] = []
    @State private var isLoadingCandidates = false
    @State private var selectedCandidate: ArtistAvatarCandidate?
    @State private var showSaveError = false

    init(artist: String, songs: [Song], viewModel: LibraryViewModel) {
        self.artist = artist
        self.songs = songs
        self._viewModel = Bindable(wrappedValue: viewModel)
        _displayedSongs = State(initialValue: songs)
    }

    var body: some View {
        ScrollViewReader { proxy in
            List {
                Section {
                    ZStack(alignment: .bottomLeading) {
                        artistHeaderImage
                        Text(artist)
                            .font(.title2)
                            .bold()
                            .foregroundColor(.white)
                            .shadow(radius: 2)
                            .padding(16)
                    }
                    .listRowInsets(EdgeInsets())
                    .listRowSeparator(.hidden)
                }
                .id("artist-top")
                Button {
                    playbackService.play(songs: displayedSongs)
                } label: {
                    Label("播放全部", systemImage: "play.fill")
                        .foregroundColor(.accentColor)
                }
                if isLoadingCandidates {
                    HStack {
                        Spacer()
                        ProgressView()
                        Spacer()
                    }
                    .listRowSeparator(.hidden)
                }
                if !candidates.isEmpty {
                    Section("候选头像") {
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 2), spacing: 8) {
                            ForEach(candidates) { candidate in
                                AsyncImage(url: candidate.thumbnailURL) { image in
                                    image
                                        .resizable()
                                        .aspectRatio(contentMode: .fill)
                                } placeholder: {
                                    Color.gray.opacity(0.2)
                                }
                                .frame(height: 140)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(
                                            selectedCandidate?.id == candidate.id ? Color.accentColor : Color.clear,
                                            lineWidth: 2
                                        )
                                )
                                .onTapGesture {
                                    selectedCandidate = candidate
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .listRowSeparator(.hidden)
                }
                ForEach(displayedSongs, id: \.id) { song in
                    SongRow(
                                song: song,
                                onTap: {
                                    playbackService.showNowPlaying = true
                                    playbackService.enqueueAndPlay(song)
                                },
                                onDoubleTap: {
                                    playbackService.showNowPlaying = true
                                    playbackService.play(
                                        songs: displayedSongs,
                                        startIndex: displayedSongs.firstIndex(where: { $0.id == song.id }) ?? 0
                                    )
                                }
                            )
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            deleteSong(song)
                        } label: {
                            Label("删除", systemImage: "trash")
                        }
                    }
                    .swipeActions(edge: .leading) {
                        Button {
                            toggleFavorite(song)
                        } label: {
                            Label(song.isFavorite ? "取消收藏" : "收藏",
                                  systemImage: song.isFavorite ? "heart.slash" : "heart")
                        }
                        .tint(song.isFavorite ? .gray : .red)
                    }
                }
            }
            .listStyle(.plain)
            .navigationTitle(artist)
            .navigationBarTitleDisplayMode(.inline)
            .onReceive(NotificationCenter.default.publisher(for: .backupWillImport)) { _ in
                displayedSongs = []
                candidates = []
                selectedCandidate = nil
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("头像") { showAvatarDrawer = true }
                }
                if !candidates.isEmpty {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("取消") {
                            candidates = []
                            selectedCandidate = nil
                        }
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("保存") {
                            guard let candidate = selectedCandidate else { return }
                            Task {
                                let saved = await viewModel.applyCandidateAvatar(artist: artist, candidate: candidate)
                                await MainActor.run {
                                    if saved {
                                        print("[ArtistAvatar] UI saved candidate=\(candidate.id) for artist=\(artist)")
                                        candidates = []
                                        selectedCandidate = nil
                                        proxy.scrollTo("artist-top", anchor: .top)
                                    } else {
                                        print("[ArtistAvatar] UI save failed for artist=\(artist)")
                                        showSaveError = true
                                    }
                                }
                            }
                        }
                        .disabled(selectedCandidate == nil)
                    }
                }
            }
            .sheet(isPresented: $showAvatarDrawer) {
                AvatarActionSheet(
                    artist: artist,
                    isLocked: viewModel.isLockedAvatar(artist) || viewModel.isManualAvatar(artist),
                    onFetchMore: {
                        isLoadingCandidates = true
                        Task {
                            let result = await viewModel.fetchAvatarCandidates(artist: artist, limit: 100)
                            await MainActor.run {
                                print("[ArtistAvatar] UI got candidates=\(result.count) for artist=\(artist)")
                                candidates = result
                                selectedCandidate = nil
                                isLoadingCandidates = false
                                showAvatarDrawer = false
                            }
                        }
                    },
                    onPickPhoto: {
                        showAvatarDrawer = false
                        showPhotoPicker = true
                    },
                    onPickFile: {
                        showAvatarDrawer = false
                        showFilePicker = true
                    },
                    onRestoreAuto: {
                        Task { await viewModel.restoreAutoAvatar(artist: artist) }
                        showAvatarDrawer = false
                    }
                )
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
            }
            .photosPicker(isPresented: $showPhotoPicker, selection: $pickedPhotoItem, matching: .images)
            .alert("保存失败", isPresented: $showSaveError) {
                Button("知道了", role: .cancel) {}
            } message: {
                Text("头像下载或保存失败，请稍后重试。")
            }
            .onChange(of: pickedPhotoItem) { _, newItem in
                guard let newItem else { return }
                Task {
                    if let data = try? await newItem.loadTransferable(type: Data.self) {
                        await MainActor.run {
                            viewModel.setManualAvatar(artist: artist, data: data)
                            candidates = []
                            selectedCandidate = nil
                            proxy.scrollTo("artist-top", anchor: .top)
                        }
                    }
                }
            }
            .sheet(isPresented: $showFilePicker) {
                ImageDocumentPicker { urls in
                    guard let url = urls.first else { return }
                    let hasAccess = url.startAccessingSecurityScopedResource()
                    defer {
                        if hasAccess { url.stopAccessingSecurityScopedResource() }
                    }
                    if let data = try? Data(contentsOf: url) {
                        viewModel.setManualAvatar(artist: artist, data: data)
                        candidates = []
                        selectedCandidate = nil
                        proxy.scrollTo("artist-top", anchor: .top)
                    }
                }
            }
        }
    }

    private var artistHeaderImage: some View {
        let data = viewModel.artworkForArtist(artist)
        if let data, let uiImage = UIImage(data: data) {
            return AnyView(
                Image(uiImage: uiImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: .infinity, maxHeight: headerHeight)
                    .background(Color.black.opacity(0.05))
                    .overlay(
                        LinearGradient(
                            gradient: Gradient(colors: [Color.black.opacity(0.6), Color.clear]),
                            startPoint: .bottom,
                            endPoint: .center
                        )
                    )
            )
        }

        return AnyView(
            Rectangle()
                .fill(Color.gray.opacity(0.2))
                .frame(height: headerHeight)
                .overlay(
                    Image(systemName: "person.circle")
                        .font(.largeTitle)
                        .foregroundColor(.gray)
                )
        )
    }

    private func deleteSong(_ song: Song) {
        displayedSongs.removeAll { $0.id == song.id }
        playbackService.removeFromQueue(songID: song.id)
        let repo = SongRepository(modelContext: modelContext)
        repo.deleteSongAndCleanup(song)
    }

    private func toggleFavorite(_ song: Song) {
        let repo = SongRepository(modelContext: modelContext)
        repo.toggleFavorite(song)
    }
}

private struct ImageDocumentPicker: UIViewControllerRepresentable {
    let onPick: ([URL]) -> Void

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.image], asCopy: true)
        picker.allowsMultipleSelection = false
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onPick: onPick)
    }

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onPick: ([URL]) -> Void

        init(onPick: @escaping ([URL]) -> Void) {
            self.onPick = onPick
        }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            onPick(urls)
        }
    }
}

private struct AvatarActionSheet: View {
    let artist: String
    let isLocked: Bool
    let onFetchMore: () -> Void
    let onPickPhoto: () -> Void
    let onPickFile: () -> Void
    let onRestoreAuto: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Capsule()
                .fill(Color.secondary.opacity(0.3))
                .frame(width: 36, height: 5)
                .padding(.top, 8)

            VStack(spacing: 4) {
                Text("头像设置")
                    .font(.headline)
                Text(artist)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            VStack(spacing: 12) {
                Button(action: onFetchMore) {
                    Label("获取更多头像", systemImage: "sparkles")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)

                Button(action: onPickPhoto) {
                    Label("从相册选择", systemImage: "photo")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)

                Button(action: onPickFile) {
                    Label("从文件选择", systemImage: "doc")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)

                if isLocked {
                    Button(role: .destructive, action: onRestoreAuto) {
                        Label("恢复自动", systemImage: "arrow.counterclockwise")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }
            }
            .padding(.horizontal)

            Spacer(minLength: 0)
        }
        .padding(.bottom, 16)
    }
}

struct GenreDetailView: View {
    let genre: String
    let songs: [Song]
    @Environment(PlaybackService.self) private var playbackService
    @Environment(\.modelContext) private var modelContext
    @State private var displayedSongs: [Song]

    init(genre: String, songs: [Song]) {
        self.genre = genre
        self.songs = songs
        _displayedSongs = State(initialValue: songs)
    }

    var body: some View {
        List {
            Button {
                playbackService.play(songs: displayedSongs)
            } label: {
                Label("播放全部", systemImage: "play.fill")
                    .foregroundColor(.accentColor)
            }
            ForEach(displayedSongs, id: \.id) { song in
                SongRow(
                            song: song,
                            onTap: {
                                playbackService.showNowPlaying = true
                                playbackService.enqueueAndPlay(song)
                            },
                            onDoubleTap: {
                                playbackService.showNowPlaying = true
                                playbackService.play(
                                    songs: displayedSongs,
                                    startIndex: displayedSongs.firstIndex(where: { $0.id == song.id }) ?? 0
                                )
                            }
                        )
                .swipeActions(edge: .trailing) {
                    Button(role: .destructive) {
                        deleteSong(song)
                    } label: {
                        Label("删除", systemImage: "trash")
                    }
                }
                .swipeActions(edge: .leading) {
                    Button {
                        toggleFavorite(song)
                    } label: {
                        Label(song.isFavorite ? "取消收藏" : "收藏",
                              systemImage: song.isFavorite ? "heart.slash" : "heart")
                    }
                    .tint(song.isFavorite ? .gray : .red)
                }
            }
        }
        .listStyle(.plain)
        .navigationTitle(genre)
        .onReceive(NotificationCenter.default.publisher(for: .backupWillImport)) { _ in
            displayedSongs = []
        }
    }

    private func deleteSong(_ song: Song) {
        displayedSongs.removeAll { $0.id == song.id }
        playbackService.removeFromQueue(songID: song.id)
        let repo = SongRepository(modelContext: modelContext)
        repo.deleteSongAndCleanup(song)
    }

    private func toggleFavorite(_ song: Song) {
        let repo = SongRepository(modelContext: modelContext)
        repo.toggleFavorite(song)
    }
}
