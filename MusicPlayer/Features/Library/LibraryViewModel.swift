import SwiftUI
import SwiftData

enum LibraryCategory: String, CaseIterable {
    case songs = "全部歌曲"
    case albums = "专辑"
    case artists = "艺术家"
    case genres = "流派"
}

@Observable
final class LibraryViewModel {
    var selectedCategory: LibraryCategory = .songs
    var songs: [Song] = []
    var artists: [String] = []
    var albums: [(album: String, artist: String)] = []
    var genres: [String] = []
    var showImporter = false

    private var songRepository: SongRepository?

    func setup(modelContext: ModelContext) {
        songRepository = SongRepository(modelContext: modelContext)
        refresh()
    }

    func refresh() {
        guard let repo = songRepository else { return }
        songs = repo.fetchAll()
        artists = repo.allArtists()
        albums = repo.allAlbums()
        genres = repo.allGenres()
    }

    func songsForArtist(_ artist: String) -> [Song] {
        songRepository?.fetchByArtist(artist) ?? []
    }

    func songsForAlbum(_ album: String) -> [Song] {
        songRepository?.fetchByAlbum(album) ?? []
    }

    func songsForGenre(_ genre: String) -> [Song] {
        songRepository?.fetchByGenre(genre) ?? []
    }

    func toggleFavorite(_ song: Song) {
        songRepository?.toggleFavorite(song)
    }

    func deleteSong(_ song: Song) {
        // Remove file from disk
        let url = URL(fileURLWithPath: song.fileURL)
        try? FileManager.default.removeItem(at: url)
        songRepository?.delete(song)
        refresh()
    }

    func importFiles(_ urls: [URL]) {
        guard let repo = songRepository else { return }
        Task {
            _ = await ImportService.shared.importFiles(urls, songRepository: repo)
            await MainActor.run { refresh() }
        }
    }
}
