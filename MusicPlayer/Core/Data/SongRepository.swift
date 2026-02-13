import Foundation
import SwiftData

@Observable
final class SongRepository {
    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func fetchAll(sortBy: SortOrder = .forward) -> [Song] {
        let descriptor = FetchDescriptor<Song>(
            sortBy: [SortDescriptor(\.addedAt, order: sortBy)]
        )
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    func fetchFavorites() -> [Song] {
        let descriptor = FetchDescriptor<Song>(
            predicate: #Predicate<Song> { $0.isFavorite },
            sortBy: [SortDescriptor(\.title)]
        )
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    func fetchByArtist(_ artist: String) -> [Song] {
        let descriptor = FetchDescriptor<Song>(
            predicate: #Predicate<Song> { $0.artist == artist },
            sortBy: [SortDescriptor(\.title)]
        )
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    func fetchByAlbum(_ album: String) -> [Song] {
        let descriptor = FetchDescriptor<Song>(
            predicate: #Predicate<Song> { $0.album == album },
            sortBy: [SortDescriptor(\.title)]
        )
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    func fetchByGenre(_ genre: String) -> [Song] {
        let descriptor = FetchDescriptor<Song>(
            predicate: #Predicate<Song> { $0.genre == genre },
            sortBy: [SortDescriptor(\.title)]
        )
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    func allArtists() -> [String] {
        let songs = fetchAll()
        return Array(Set(songs.map(\.artist))).sorted()
    }

    func allAlbums() -> [(album: String, artist: String)] {
        let songs = fetchAll()
        let albums = Set(songs.map { "\($0.album)|\($0.artist)" })
        return albums.map { combo in
            let parts = combo.split(separator: "|", maxSplits: 1)
            return (album: String(parts[0]), artist: parts.count > 1 ? String(parts[1]) : "未知艺术家")
        }.sorted { $0.album < $1.album }
    }

    func allGenres() -> [String] {
        let songs = fetchAll()
        return Array(Set(songs.map(\.genre))).sorted()
    }

    func search(query: String) -> [Song] {
        let lowercased = query.lowercased()
        let descriptor = FetchDescriptor<Song>(
            sortBy: [SortDescriptor(\.title)]
        )
        let allSongs = (try? modelContext.fetch(descriptor)) ?? []
        return allSongs.filter {
            $0.title.localizedCaseInsensitiveContains(lowercased) ||
            $0.artist.localizedCaseInsensitiveContains(lowercased) ||
            $0.album.localizedCaseInsensitiveContains(lowercased)
        }
    }

    func add(_ song: Song) {
        modelContext.insert(song)
        save()
    }

    func delete(_ song: Song) {
        modelContext.delete(song)
        save()
    }

    func toggleFavorite(_ song: Song) {
        song.isFavorite.toggle()
        save()
    }

    func incrementPlayCount(_ song: Song) {
        song.playCount += 1
        song.lastPlayedAt = Date()
        save()
    }

    func save() {
        try? modelContext.save()
    }
}
