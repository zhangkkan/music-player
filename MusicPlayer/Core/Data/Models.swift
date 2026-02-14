import Foundation
import SwiftData

@Model
final class Song {
    @Attribute(.unique) var id: UUID
    var title: String
    var artist: String
    var album: String
    var genre: String
    var duration: Double
    var fileURL: String
    var isRemote: Bool
    var format: String
    var sampleRate: Int
    var bitDepth: Int
    var isFavorite: Bool
    var playCount: Int
    var lastPlayedAt: Date?
    @Attribute(.externalStorage) var artworkData: Data?
    @Attribute(.externalStorage) var fileBookmark: Data?
    var lastEnrichedAt: Date?
    var lastMetadataAttemptAt: Date?
    var metadataSource: String?
    var artworkURL: String?
    var lastLyricsFetchedAt: Date?
    var lastLyricsAttemptAt: Date?
    var lyricsSource: String?
    var lyricsPath: String?
    var addedAt: Date

    @Relationship(inverse: \PlaylistSong.song)
    var playlistSongs: [PlaylistSong] = []

    init(
        id: UUID = UUID(),
        title: String,
        artist: String = "未知艺术家",
        album: String = "未知专辑",
        genre: String = "未知",
        duration: Double = 0,
        fileURL: String,
        isRemote: Bool = false,
        format: String = "mp3",
        sampleRate: Int = 44100,
        bitDepth: Int = 16,
        isFavorite: Bool = false,
        playCount: Int = 0,
        lastPlayedAt: Date? = nil,
        artworkData: Data? = nil,
        fileBookmark: Data? = nil,
        lastEnrichedAt: Date? = nil,
        lastMetadataAttemptAt: Date? = nil,
        metadataSource: String? = nil,
        artworkURL: String? = nil,
        lastLyricsFetchedAt: Date? = nil,
        lastLyricsAttemptAt: Date? = nil,
        lyricsSource: String? = nil,
        lyricsPath: String? = nil,
        addedAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.artist = artist
        self.album = album
        self.genre = genre
        self.duration = duration
        self.fileURL = fileURL
        self.isRemote = isRemote
        self.format = format
        self.sampleRate = sampleRate
        self.bitDepth = bitDepth
        self.isFavorite = isFavorite
        self.playCount = playCount
        self.lastPlayedAt = lastPlayedAt
        self.artworkData = artworkData
        self.fileBookmark = fileBookmark
        self.lastEnrichedAt = lastEnrichedAt
        self.lastMetadataAttemptAt = lastMetadataAttemptAt
        self.metadataSource = metadataSource
        self.artworkURL = artworkURL
        self.lastLyricsFetchedAt = lastLyricsFetchedAt
        self.lastLyricsAttemptAt = lastLyricsAttemptAt
        self.lyricsSource = lyricsSource
        self.lyricsPath = lyricsPath
        self.addedAt = addedAt
    }
}

@Model
final class Playlist {
    @Attribute(.unique) var id: UUID
    var name: String
    var createdAt: Date
    var updatedAt: Date

    @Relationship(deleteRule: .cascade, inverse: \PlaylistSong.playlist)
    var playlistSongs: [PlaylistSong] = []

    var sortedSongs: [PlaylistSong] {
        playlistSongs.sorted { $0.order < $1.order }
    }

    init(
        id: UUID = UUID(),
        name: String,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

@Model
final class PlaylistSong {
    var id: UUID
    var order: Int
    var song: Song?
    var playlist: Playlist?

    init(
        id: UUID = UUID(),
        order: Int,
        song: Song? = nil,
        playlist: Playlist? = nil
    ) {
        self.id = id
        self.order = order
        self.song = song
        self.playlist = playlist
    }
}

@Model
final class ArtistAvatar {
    @Attribute(.unique) var artistKey: String
    var artistName: String
    @Attribute(.externalStorage) var imageData: Data?
    var source: String
    var isLocked: Bool
    var sourceId: String?
    var updatedAt: Date

    init(
        artistKey: String,
        artistName: String,
        imageData: Data?,
        source: String,
        isLocked: Bool = false,
        sourceId: String? = nil,
        updatedAt: Date = Date()
    ) {
        self.artistKey = artistKey
        self.artistName = artistName
        self.imageData = imageData
        self.source = source
        self.isLocked = isLocked
        self.sourceId = sourceId
        self.updatedAt = updatedAt
    }
}
