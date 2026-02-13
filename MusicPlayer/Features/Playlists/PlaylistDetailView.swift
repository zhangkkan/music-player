import SwiftUI
import SwiftData

struct PlaylistDetailView: View {
    let playlist: Playlist
    @Bindable var viewModel: PlaylistViewModel
    @Environment(PlaybackService.self) private var playbackService
    @Environment(\.modelContext) private var modelContext
    @State private var showRename = false
    @State private var newName = ""
    @State private var showAddSongs = false

    private var sortedSongs: [PlaylistSong] {
        playlist.sortedSongs
    }

    var body: some View {
        List {
            if sortedSongs.isEmpty {
                Text("播放列表为空")
                    .foregroundColor(.secondary)
            } else {
                Button {
                    let songs = sortedSongs.compactMap(\.song)
                    playbackService.play(songs: songs)
                } label: {
                    Label("播放全部 (\(sortedSongs.count)首)", systemImage: "play.fill")
                        .foregroundColor(.accentColor)
                }

                ForEach(sortedSongs, id: \.id) { ps in
                    if let song = ps.song {
                        SongRow(song: song) {
                            let songs = sortedSongs.compactMap(\.song)
                            let index = songs.firstIndex(where: { $0.id == song.id }) ?? 0
                            playbackService.play(songs: songs, startIndex: index)
                        }
                    }
                }
                .onDelete { indexSet in
                    for index in indexSet {
                        viewModel.removeSong(sortedSongs[index], from: playlist)
                    }
                }
                .onMove { source, destination in
                    viewModel.reorderSongs(in: playlist, from: source, to: destination)
                }
            }
        }
        .listStyle(.plain)
        .navigationTitle(playlist.name)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        newName = playlist.name
                        showRename = true
                    } label: {
                        Label("重命名", systemImage: "pencil")
                    }
                    Button {
                        showAddSongs = true
                    } label: {
                        Label("添加歌曲", systemImage: "plus")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                EditButton()
            }
        }
        .alert("重命名播放列表", isPresented: $showRename) {
            TextField("新名称", text: $newName)
            Button("取消", role: .cancel) {}
            Button("确定") {
                if !newName.isEmpty {
                    viewModel.renamePlaylist(playlist, to: newName)
                }
            }
        }
        .sheet(isPresented: $showAddSongs) {
            AddSongsSheet(playlist: playlist, viewModel: viewModel)
        }
    }
}

// MARK: - Add Songs Sheet

struct AddSongsSheet: View {
    let playlist: Playlist
    @Bindable var viewModel: PlaylistViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var allSongs: [Song] = []

    var body: some View {
        NavigationStack {
            List {
                if allSongs.isEmpty {
                    Text("音乐库中暂无歌曲")
                        .foregroundColor(.secondary)
                } else {
                    ForEach(allSongs, id: \.id) { song in
                        let isInPlaylist = playlist.playlistSongs.contains { $0.song?.id == song.id }
                        Button {
                            if !isInPlaylist {
                                viewModel.addSong(song, to: playlist)
                            }
                        } label: {
                            HStack {
                                SongRow(song: song) {}
                                Spacer()
                                if isInPlaylist {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(.green)
                                } else {
                                    Image(systemName: "plus.circle")
                                        .foregroundColor(.accentColor)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                        .disabled(isInPlaylist)
                    }
                }
            }
            .listStyle(.plain)
            .navigationTitle("添加歌曲")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") { dismiss() }
                }
            }
            .onAppear {
                let repo = SongRepository(modelContext: modelContext)
                allSongs = repo.fetchAll()
            }
        }
    }
}
