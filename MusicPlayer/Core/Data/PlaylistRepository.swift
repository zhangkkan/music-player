import Foundation
import SwiftData

@Observable
final class PlaylistRepository {
    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func fetchAll() -> [Playlist] {
        let descriptor = FetchDescriptor<Playlist>(
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    func create(name: String) -> Playlist {
        let playlist = Playlist(name: name)
        modelContext.insert(playlist)
        save()
        return playlist
    }

    func rename(_ playlist: Playlist, to name: String) {
        playlist.name = name
        playlist.updatedAt = Date()
        save()
    }

    func delete(_ playlist: Playlist) {
        modelContext.delete(playlist)
        save()
    }

    func addSong(_ song: Song, to playlist: Playlist) {
        let exists = playlist.playlistSongs.contains { $0.song?.id == song.id }
        guard !exists else { return }
        let maxOrder = playlist.playlistSongs.map(\.order).max() ?? -1
        let playlistSong = PlaylistSong(order: maxOrder + 1, song: song, playlist: playlist)
        modelContext.insert(playlistSong)
        playlist.updatedAt = Date()
        save()
    }

    func removeSong(_ playlistSong: PlaylistSong, from playlist: Playlist) {
        modelContext.delete(playlistSong)
        playlist.updatedAt = Date()
        save()
    }

    func reorderSongs(in playlist: Playlist, from source: IndexSet, to destination: Int) {
        var songs = playlist.sortedSongs
        songs.move(fromOffsets: source, toOffset: destination)
        for (index, ps) in songs.enumerated() {
            ps.order = index
        }
        playlist.updatedAt = Date()
        save()
    }

    func save() {
        try? modelContext.save()
    }
}
