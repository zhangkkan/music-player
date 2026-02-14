import SwiftUI
import SwiftData

struct SongManagementView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var searchText = ""
    @Environment(PlaybackService.self) private var playbackService
    @State private var songs: [Song] = []

    var body: some View {
        List {
            if songs.isEmpty {
                Text("暂无歌曲")
                    .foregroundColor(.secondary)
            } else {
                ForEach(songs, id: \.id) { song in
                    HStack(spacing: 12) {
                        if let artworkData = song.artworkData, let uiImage = UIImage(data: artworkData) {
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
                                    Image(systemName: "music.note")
                                        .foregroundColor(.gray)
                                )
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
                    }
                }
                .onDelete(perform: deleteSongs)
            }
        }
        .listStyle(.plain)
        .navigationTitle("歌曲管理")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $searchText, prompt: "搜索歌曲")
        .onAppear(perform: reload)
        .onChange(of: searchText) { _, _ in
            reload()
        }
    }

    private func reload() {
        let repo = SongRepository(modelContext: modelContext)
        if searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            songs = repo.fetchAll()
        } else {
            songs = repo.search(query: searchText)
        }
    }

    private func deleteSongs(at offsets: IndexSet) {
        let repo = SongRepository(modelContext: modelContext)
        for index in offsets {
            let song = songs[index]
            playbackService.removeFromQueue(songID: song.id)
            songs.removeAll { $0.id == song.id }
            repo.deleteSongAndCleanup(song)
        }
        reload()
    }
}
