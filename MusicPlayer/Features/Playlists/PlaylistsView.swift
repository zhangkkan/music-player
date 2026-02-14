import SwiftUI
import SwiftData

struct PlaylistsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(PlaybackService.self) private var playbackService
    @State private var viewModel = PlaylistViewModel()
    @State private var showCreate = false
    @State private var newPlaylistName = ""

    var body: some View {
        NavigationStack {
            List {
                // Favorites section
                Section {
                    NavigationLink {
                        FavoritesDetailView(songs: viewModel.favoriteSongs)
                    } label: {
                        HStack {
                            Image(systemName: "heart.fill")
                                .foregroundColor(.red)
                                .frame(width: 32)
                            Text("我的收藏")
                            Spacer()
                            Text("\(viewModel.favoriteSongs.count)")
                                .foregroundColor(.secondary)
                        }
                    }
                }

                // Custom playlists
                Section("播放列表") {
                    if viewModel.playlists.isEmpty {
                        Text("暂无播放列表")
                            .foregroundColor(.secondary)
                    } else {
                        ForEach(viewModel.playlists, id: \.id) { playlist in
                            NavigationLink {
                                PlaylistDetailView(playlist: playlist, viewModel: viewModel)
                            } label: {
                                HStack {
                                    Image(systemName: "music.note.list")
                                        .foregroundColor(.accentColor)
                                        .frame(width: 32)
                                    VStack(alignment: .leading) {
                                        Text(playlist.name)
                                        Text("\(playlist.playlistSongs.count) 首歌曲")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                }
                            }
                        }
                        .onDelete { indexSet in
                            for index in indexSet {
                                viewModel.deletePlaylist(viewModel.playlists[index])
                            }
                        }
                    }
                }
            }
            .navigationTitle("播放列表")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showCreate = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .alert("新建播放列表", isPresented: $showCreate) {
                TextField("播放列表名称", text: $newPlaylistName)
                Button("取消", role: .cancel) {
                    newPlaylistName = ""
                }
                Button("创建") {
                    if !newPlaylistName.isEmpty {
                        viewModel.createPlaylist(name: newPlaylistName)
                        newPlaylistName = ""
                    }
                }
            }
            .onAppear {
                viewModel.setup(modelContext: modelContext)
            }
        }
    }
}

// MARK: - Favorites Detail

struct FavoritesDetailView: View {
    let songs: [Song]
    @Environment(PlaybackService.self) private var playbackService
    @Environment(\.modelContext) private var modelContext
    @State private var displayedSongs: [Song]

    init(songs: [Song]) {
        self.songs = songs
        _displayedSongs = State(initialValue: songs)
    }

    var body: some View {
        List {
            if displayedSongs.isEmpty {
                Text("暂无收藏的歌曲")
                    .foregroundColor(.secondary)
            } else {
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
                            removeFromFavorites(song)
                        } label: {
                            Label("移出收藏", systemImage: "heart.slash")
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
        }
        .listStyle(.plain)
        .navigationTitle("我的收藏")
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
        if !song.isFavorite {
            displayedSongs.removeAll { $0.id == song.id }
        }
    }

    private func removeFromFavorites(_ song: Song) {
        if song.isFavorite {
            toggleFavorite(song)
        } else {
            displayedSongs.removeAll { $0.id == song.id }
        }
    }
}
