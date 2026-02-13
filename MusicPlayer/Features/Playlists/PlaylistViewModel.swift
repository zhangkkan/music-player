import SwiftUI
import SwiftData

@Observable
final class PlaylistViewModel {
    var playlists: [Playlist] = []
    var favoriteSongs: [Song] = []
    var showCreateSheet = false
    var editingPlaylist: Playlist?

    private var playlistRepository: PlaylistRepository?
    private var songRepository: SongRepository?

    func setup(modelContext: ModelContext) {
        playlistRepository = PlaylistRepository(modelContext: modelContext)
        songRepository = SongRepository(modelContext: modelContext)
        refresh()
    }

    func refresh() {
        playlists = playlistRepository?.fetchAll() ?? []
        favoriteSongs = songRepository?.fetchFavorites() ?? []
    }

    func createPlaylist(name: String) {
        _ = playlistRepository?.create(name: name)
        refresh()
    }

    func deletePlaylist(_ playlist: Playlist) {
        playlistRepository?.delete(playlist)
        refresh()
    }

    func renamePlaylist(_ playlist: Playlist, to name: String) {
        playlistRepository?.rename(playlist, to: name)
        refresh()
    }

    func addSong(_ song: Song, to playlist: Playlist) {
        playlistRepository?.addSong(song, to: playlist)
        refresh()
    }

    func removeSong(_ playlistSong: PlaylistSong, from playlist: Playlist) {
        playlistRepository?.removeSong(playlistSong, from: playlist)
        refresh()
    }

    func reorderSongs(in playlist: Playlist, from source: IndexSet, to destination: Int) {
        playlistRepository?.reorderSongs(in: playlist, from: source, to: destination)
    }
}
