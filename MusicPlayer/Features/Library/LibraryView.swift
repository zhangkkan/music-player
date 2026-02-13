import SwiftUI
import SwiftData

struct LibraryView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(PlaybackService.self) private var playbackService
    @State private var viewModel = LibraryViewModel()
    @State private var showImporter = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Category picker
                Picker("分类", selection: $viewModel.selectedCategory) {
                    ForEach(LibraryCategory.allCases, id: \.self) { category in
                        Text(category.rawValue).tag(category)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.vertical, 8)

                // Content
                switch viewModel.selectedCategory {
                case .songs:
                    songsList
                case .albums:
                    albumsList
                case .artists:
                    artistsList
                case .genres:
                    genresList
                }
            }
            .navigationTitle("音乐库")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showImporter = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showImporter) {
                DocumentPicker(contentTypes: ImportService.supportedTypes) { urls in
                    viewModel.importFiles(urls)
                }
            }
            .onAppear {
                viewModel.setup(modelContext: modelContext)
            }
        }
    }

    // MARK: - Songs List

    private var songsList: some View {
        Group {
            if viewModel.songs.isEmpty {
                emptyState
            } else {
                List {
                    // Play all button
                    Button {
                        playbackService.play(songs: viewModel.songs)
                    } label: {
                        Label("播放全部 (\(viewModel.songs.count)首)", systemImage: "play.fill")
                            .foregroundColor(.accentColor)
                    }

                    ForEach(viewModel.songs, id: \.id) { song in
                        SongRow(song: song) {
                            playbackService.play(songs: viewModel.songs,
                                                startIndex: viewModel.songs.firstIndex(where: { $0.id == song.id }) ?? 0)
                        }
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                viewModel.deleteSong(song)
                            } label: {
                                Label("删除", systemImage: "trash")
                            }
                        }
                        .swipeActions(edge: .leading) {
                            Button {
                                viewModel.toggleFavorite(song)
                            } label: {
                                Label(song.isFavorite ? "取消收藏" : "收藏",
                                      systemImage: song.isFavorite ? "heart.slash" : "heart")
                            }
                            .tint(song.isFavorite ? .gray : .red)
                        }
                    }
                }
                .listStyle(.plain)
            }
        }
    }

    // MARK: - Albums List

    private var albumsList: some View {
        Group {
            if viewModel.albums.isEmpty {
                emptyState
            } else {
                List(viewModel.albums, id: \.album) { albumInfo in
                    NavigationLink {
                        AlbumDetailView(album: albumInfo.album, artist: albumInfo.artist,
                                       songs: viewModel.songsForAlbum(albumInfo.album))
                    } label: {
                        HStack {
                            Image(systemName: "square.stack")
                                .font(.title2)
                                .foregroundColor(.secondary)
                                .frame(width: 44, height: 44)
                            VStack(alignment: .leading) {
                                Text(albumInfo.album)
                                    .font(.body)
                                Text(albumInfo.artist)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
                .listStyle(.plain)
            }
        }
    }

    // MARK: - Artists List

    private var artistsList: some View {
        Group {
            if viewModel.artists.isEmpty {
                emptyState
            } else {
                List(viewModel.artists, id: \.self) { artist in
                    NavigationLink {
                        ArtistDetailView(artist: artist, songs: viewModel.songsForArtist(artist))
                    } label: {
                        HStack {
                            Image(systemName: "person.circle")
                                .font(.title2)
                                .foregroundColor(.secondary)
                                .frame(width: 44, height: 44)
                            Text(artist)
                        }
                    }
                }
                .listStyle(.plain)
            }
        }
    }

    // MARK: - Genres List

    private var genresList: some View {
        Group {
            if viewModel.genres.isEmpty {
                emptyState
            } else {
                List(viewModel.genres, id: \.self) { genre in
                    NavigationLink {
                        GenreDetailView(genre: genre, songs: viewModel.songsForGenre(genre))
                    } label: {
                        HStack {
                            Image(systemName: "guitars")
                                .font(.title2)
                                .foregroundColor(.secondary)
                                .frame(width: 44, height: 44)
                            Text(genre)
                        }
                    }
                }
                .listStyle(.plain)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "music.note")
                .font(.system(size: 60))
                .foregroundColor(.secondary)
            Text("暂无音乐")
                .font(.title2)
                .foregroundColor(.secondary)
            Text("点击右上角 + 导入音乐文件")
                .font(.subheadline)
                .foregroundColor(.secondary)
            Spacer()
        }
    }
}

// MARK: - Song Row

struct SongRow: View {
    let song: Song
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                // Artwork
                if let artworkData = song.artworkData, let uiImage = UIImage(data: artworkData) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 48, height: 48)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                } else {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.gray.opacity(0.2))
                        .frame(width: 48, height: 48)
                        .overlay(
                            Image(systemName: "music.note")
                                .foregroundColor(.gray)
                        )
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(song.title)
                        .font(.body)
                        .lineLimit(1)
                    HStack(spacing: 4) {
                        if song.isFavorite {
                            Image(systemName: "heart.fill")
                                .font(.caption2)
                                .foregroundColor(.red)
                        }
                        Text(song.artist)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                        Text("·")
                            .foregroundColor(.secondary)
                        Text(song.format.uppercased())
                            .font(.caption2)
                            .foregroundColor(.orange)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Color.orange.opacity(0.1))
                            .clipShape(RoundedRectangle(cornerRadius: 3))
                    }
                }

                Spacer()

                Text(formatDuration(song.duration))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .buttonStyle(.plain)
    }

    private func formatDuration(_ seconds: Double) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", mins, secs)
    }
}

// MARK: - Detail Views

struct AlbumDetailView: View {
    let album: String
    let artist: String
    let songs: [Song]
    @Environment(PlaybackService.self) private var playbackService

    var body: some View {
        List {
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
        .listStyle(.plain)
        .navigationTitle(album)
    }
}

struct ArtistDetailView: View {
    let artist: String
    let songs: [Song]
    @Environment(PlaybackService.self) private var playbackService

    var body: some View {
        List {
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
        .listStyle(.plain)
        .navigationTitle(artist)
    }
}

struct GenreDetailView: View {
    let genre: String
    let songs: [Song]
    @Environment(PlaybackService.self) private var playbackService

    var body: some View {
        List {
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
        .listStyle(.plain)
        .navigationTitle(genre)
    }
}
