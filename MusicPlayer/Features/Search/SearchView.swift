import SwiftUI
import SwiftData

struct SearchView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(PlaybackService.self) private var playbackService
    @State private var searchText = ""
    @State private var results: [Song] = []

    var body: some View {
        NavigationStack {
            Group {
                if searchText.isEmpty {
                    VStack(spacing: 16) {
                        Spacer()
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 50))
                            .foregroundColor(.secondary)
                        Text("搜索歌曲、艺术家或专辑")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        Spacer()
                    }
                } else if results.isEmpty {
                    VStack(spacing: 16) {
                        Spacer()
                        Image(systemName: "music.note")
                            .font(.system(size: 50))
                            .foregroundColor(.secondary)
                        Text("未找到 \"\(searchText)\"")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        Spacer()
                    }
                } else {
                    List {
                        ForEach(results, id: \.id) { song in
                            SongRow(song: song) {
                                playbackService.play(songs: results,
                                                    startIndex: results.firstIndex(where: { $0.id == song.id }) ?? 0)
                            }
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("搜索")
            .searchable(text: $searchText, prompt: "搜索音乐")
            .onChange(of: searchText) { _, newValue in
                performSearch(query: newValue)
            }
        }
    }

    private func performSearch(query: String) {
        guard !query.isEmpty else {
            results = []
            return
        }
        let repo = SongRepository(modelContext: modelContext)
        results = repo.search(query: query)
    }
}
