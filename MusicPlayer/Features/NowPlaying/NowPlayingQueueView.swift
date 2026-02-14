import SwiftUI
import SwiftData

struct NowPlayingQueueView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(PlaybackService.self) private var playbackService
    @State private var showSaveAlert = false
    @State private var newPlaylistName = ""

    var body: some View {
        NavigationStack {
            List {
                if playbackService.playQueue.isEmpty {
                    Text("正在播放列表为空")
                        .foregroundColor(.secondary)
                } else {
                    ForEach(Array(playbackService.playQueue.enumerated()), id: \.element.id) { index, song in
                        HStack(spacing: 12) {
                            if song.id == playbackService.currentSong?.id {
                                Image(systemName: "play.fill")
                                    .foregroundColor(.accentColor)
                                    .frame(width: 16)
                            } else {
                                Color.clear.frame(width: 16)
                            }

                            VStack(alignment: .leading, spacing: 2) {
                                Text(song.title)
                                    .font(.body)
                                    .lineLimit(1)
                                Text(song.artist)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
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
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            playbackService.play(songs: playbackService.playQueue, startIndex: index)
                        }
                    }
                    .onDelete { indexSet in
                        for index in indexSet {
                            playbackService.removeFromQueue(at: index)
                        }
                    }
                    .onMove { source, destination in
                        playbackService.moveQueue(from: source, to: destination)
                    }
                }
            }
            .listStyle(.plain)
            .navigationTitle("正在播放列表")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("关闭") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if !playbackService.playQueue.isEmpty {
                        Button("保存为歌单") {
                            newPlaylistName = ""
                            showSaveAlert = true
                        }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    EditButton()
                }
            }
            .alert("保存为歌单", isPresented: $showSaveAlert) {
                TextField("播放列表名称", text: $newPlaylistName)
                Button("取消", role: .cancel) {}
                Button("保存") {
                    saveQueueToPlaylist()
                }
            }
        }
    }

    private func saveQueueToPlaylist() {
        let name = newPlaylistName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        let repo = PlaylistRepository(modelContext: modelContext)
        let playlist = repo.create(name: name)
        playbackService.playQueue.forEach { song in
            repo.addSong(song, to: playlist)
        }
    }
}
