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

    var body: some View {
        List {
            if songs.isEmpty {
                Text("暂无收藏的歌曲")
                    .foregroundColor(.secondary)
            } else {
                Button {
                    playbackService.play(songs: songs)
                } label: {
                    Label("播放全部", systemImage: "play.fill")
                        .foregroundColor(.accentColor)
                }

                ForEach(songs, id: \.id) { song in
                    SongRow(song: song) {
                        playbackService.play(songs: songs,
                                            startIndex: songs.firstIndex(where: { $0.id == song.id }) ?? 0)
                    }
                }
            }
        }
        .listStyle(.plain)
        .navigationTitle("我的收藏")
    }
}
