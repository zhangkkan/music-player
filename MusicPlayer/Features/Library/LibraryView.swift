import SwiftUI
import SwiftData

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
                            Image(systemName: "square.stack")
                                .font(.title2)
                                .foregroundColor(.secondary)
                                .frame(width: 44, height: 44)
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
                        ArtistDetailView(artist: artist, songs: viewModel.songsForArtist(artist))
                    } label: {
                        HStack {
                            Image(systemName: "person.circle")
                                .font(.title2)
                                .foregroundColor(.secondary)
                                .frame(width: 44, height: 44)
                            Text(artist)
                        }
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

    init(album: String, artist: String, songs: [Song]) {
        self.album = album
        self.artist = artist
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
        .navigationTitle(album)
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
    @Environment(PlaybackService.self) private var playbackService
    @Environment(\.modelContext) private var modelContext
    @State private var displayedSongs: [Song]

    init(artist: String, songs: [Song]) {
        self.artist = artist
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
        .navigationTitle(artist)
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
