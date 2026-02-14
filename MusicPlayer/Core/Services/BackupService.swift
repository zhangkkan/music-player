import Foundation
import SwiftData

extension Notification.Name {
    static let backupWillImport = Notification.Name("backupWillImport")
    static let backupDidImport = Notification.Name("backupDidImport")
}

struct BackupPayload: Codable {
    struct Settings: Codable {
        var lyricsSource: String
        var correctionThreshold: Double
        var cacheHours: Double
        var customEQ: [Float]
    }

    struct SongItem: Codable {
        var id: UUID
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
        var artworkURL: String?
        var metadataSource: String?
        var lastEnrichedAt: Date?
        var lastMetadataAttemptAt: Date?
        var lastLyricsFetchedAt: Date?
        var lastLyricsAttemptAt: Date?
        var lyricsSource: String?
        var lyricsPath: String?
        var addedAt: Date
        var fileBookmark: Data?
        var artworkData: Data?
    }

    struct PlaylistItem: Codable {
        var id: UUID
        var name: String
        var createdAt: Date
        var updatedAt: Date
    }

    struct PlaylistSongItem: Codable {
        var id: UUID
        var order: Int
        var songID: UUID?
        var playlistID: UUID?
    }

    struct ArtistAvatarItem: Codable {
        var artistKey: String
        var artistName: String
        var source: String
        var isLocked: Bool
        var sourceId: String?
        var updatedAt: Date
        var imagePath: String?
    }

    var version: Int
    var exportedAt: Date
    var settings: Settings
    var songs: [SongItem]
    var playlists: [PlaylistItem]
    var playlistSongs: [PlaylistSongItem]
    var artistAvatars: [ArtistAvatarItem]
}

final class BackupService {
    static let shared = BackupService()

    private init() {}

    func exportZip(modelContext: ModelContext) -> Data? {
        print("[Backup] exportZip - start")
        let payload = buildPayload(modelContext: modelContext)
        print("[Backup] exportZip - payload songs=\(payload.songs.count) playlists=\(payload.playlists.count) avatars=\(payload.artistAvatars.count)")
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let jsonData: Data
        do {
            jsonData = try encoder.encode(payload)
        } catch {
            print("[Backup] exportZip - failed to encode payload: \(error)")
            return nil
        }

        let writer = SimpleZipWriter()
        writer.addFile(path: "backup.json", data: jsonData)

        let lyricsEntries = collectLyricsFiles(payload: payload)
        for (path, data) in lyricsEntries {
            writer.addFile(path: path, data: data)
        }

        let avatarEntries = collectAvatarFiles(modelContext: modelContext, payload: payload)
        for (path, data) in avatarEntries {
            writer.addFile(path: path, data: data)
        }

        let data = writer.finalize()
        print("[Backup] exportZip - zip size=\(data.count)")
        return data
    }

    func importZip(modelContext: ModelContext, data: Data) -> Bool {
        let reader = SimpleZipReader(data: data)
        let files = reader.extractAll()
        guard let jsonData = files["backup.json"] else { return false }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let payload = try? decoder.decode(BackupPayload.self, from: jsonData) else { return false }

        restoreSettings(payload.settings)
        clearAllData(modelContext: modelContext)
        restoreData(modelContext: modelContext, payload: payload, files: files)
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .backupDidImport, object: nil)
        }
        return true
    }

    private func buildPayload(modelContext: ModelContext) -> BackupPayload {
        let songs = (try? modelContext.fetch(FetchDescriptor<Song>())) ?? []
        let playlists = (try? modelContext.fetch(FetchDescriptor<Playlist>())) ?? []
        let playlistSongs = (try? modelContext.fetch(FetchDescriptor<PlaylistSong>())) ?? []
        let avatars = (try? modelContext.fetch(FetchDescriptor<ArtistAvatar>())) ?? []

        let settings = BackupPayload.Settings(
            lyricsSource: EnrichmentSettings.lyricsSource.rawValue,
            correctionThreshold: sanitizedDouble(EnrichmentSettings.correctionThreshold),
            cacheHours: sanitizedDouble(EnrichmentSettings.cacheHours),
            customEQ: (UserDefaults.standard.array(forKey: "customEQ") as? [Float] ?? Array(repeating: 0, count: 10))
                .map { sanitizedFloat($0) }
        )

        let songItems = songs.map {
            BackupPayload.SongItem(
                id: $0.id,
                title: $0.title,
                artist: $0.artist,
                album: $0.album,
                genre: $0.genre,
                duration: sanitizedDouble($0.duration),
                fileURL: $0.fileURL,
                isRemote: $0.isRemote,
                format: $0.format,
                sampleRate: $0.sampleRate,
                bitDepth: $0.bitDepth,
                isFavorite: $0.isFavorite,
                playCount: $0.playCount,
                lastPlayedAt: $0.lastPlayedAt,
                artworkURL: $0.artworkURL,
                metadataSource: $0.metadataSource,
                lastEnrichedAt: $0.lastEnrichedAt,
                lastMetadataAttemptAt: $0.lastMetadataAttemptAt,
                lastLyricsFetchedAt: $0.lastLyricsFetchedAt,
                lastLyricsAttemptAt: $0.lastLyricsAttemptAt,
                lyricsSource: $0.lyricsSource,
                lyricsPath: $0.lyricsPath,
                addedAt: $0.addedAt,
                fileBookmark: $0.fileBookmark,
                artworkData: $0.artworkData
            )
        }

        let playlistItems = playlists.map {
            BackupPayload.PlaylistItem(
                id: $0.id,
                name: $0.name,
                createdAt: $0.createdAt,
                updatedAt: $0.updatedAt
            )
        }

        let playlistSongItems = playlistSongs.map {
            BackupPayload.PlaylistSongItem(
                id: $0.id,
                order: $0.order,
                songID: $0.song?.id,
                playlistID: $0.playlist?.id
            )
        }

        let avatarItems = avatars.map {
            BackupPayload.ArtistAvatarItem(
                artistKey: $0.artistKey,
                artistName: $0.artistName,
                source: $0.source,
                isLocked: $0.isLocked,
                sourceId: $0.sourceId,
                updatedAt: $0.updatedAt,
                imagePath: $0.imageData == nil ? nil : "Avatars/\($0.artistKey).img"
            )
        }

        return BackupPayload(
            version: 1,
            exportedAt: Date(),
            settings: settings,
            songs: songItems,
            playlists: playlistItems,
            playlistSongs: playlistSongItems,
            artistAvatars: avatarItems
        )
    }

    private func sanitizedDouble(_ value: Double) -> Double {
        value.isFinite ? value : 0
    }

    private func sanitizedFloat(_ value: Float) -> Float {
        value.isFinite ? value : 0
    }

    private func collectLyricsFiles(payload: BackupPayload) -> [(String, Data)] {
        var results: [(String, Data)] = []
        for song in payload.songs {
            guard let lyricsPath = song.lyricsPath else { continue }
            let url = URL(fileURLWithPath: lyricsPath)
            if let data = try? Data(contentsOf: url) {
                results.append(("Lyrics/\(song.id.uuidString).lrc", data))
            }
        }
        return results
    }

    private func collectAvatarFiles(modelContext: ModelContext, payload: BackupPayload) -> [(String, Data)] {
        let avatars = (try? modelContext.fetch(FetchDescriptor<ArtistAvatar>())) ?? []
        var map: [String: Data] = [:]
        for avatar in avatars {
            if let data = avatar.imageData {
                map[avatar.artistKey] = data
            }
        }
        return payload.artistAvatars.compactMap { item in
            guard let path = item.imagePath, let data = map[item.artistKey] else { return nil }
            return (path, data)
        }
    }

    private func restoreSettings(_ settings: BackupPayload.Settings) {
        UserDefaults.standard.set(settings.lyricsSource, forKey: "enrichment.lyrics.source")
        let threshold = settings.correctionThreshold > 0 ? settings.correctionThreshold : 0.8
        let cacheHours = settings.cacheHours > 0 ? settings.cacheHours : 24
        UserDefaults.standard.set(threshold, forKey: "enrichment.correction.threshold")
        UserDefaults.standard.set(cacheHours, forKey: "enrichment.cache.hours")
        UserDefaults.standard.set(settings.customEQ, forKey: "customEQ")
    }

    private func clearAllData(modelContext: ModelContext) {
        deleteAll(modelContext: modelContext, type: PlaylistSong.self)
        deleteAll(modelContext: modelContext, type: Playlist.self)
        deleteAll(modelContext: modelContext, type: Song.self)
        deleteAll(modelContext: modelContext, type: ArtistAvatar.self)
        try? modelContext.save()
    }

    private func deleteAll<T: PersistentModel>(modelContext: ModelContext, type: T.Type) {
        let descriptor = FetchDescriptor<T>()
        if let items = try? modelContext.fetch(descriptor) {
            for item in items {
                modelContext.delete(item)
            }
        }
    }

    private func restoreData(modelContext: ModelContext, payload: BackupPayload, files: [String: Data]) {
        var songMap: [UUID: Song] = [:]
        var playlistMap: [UUID: Playlist] = [:]

        for songItem in payload.songs {
            let song = Song(
                id: songItem.id,
                title: songItem.title,
                artist: songItem.artist,
                album: songItem.album,
                genre: songItem.genre,
                duration: songItem.duration,
                fileURL: songItem.fileURL,
                isRemote: songItem.isRemote,
                format: songItem.format,
                sampleRate: songItem.sampleRate,
                bitDepth: songItem.bitDepth,
                isFavorite: songItem.isFavorite,
                playCount: songItem.playCount,
                lastPlayedAt: songItem.lastPlayedAt,
                artworkData: songItem.artworkData,
                fileBookmark: songItem.fileBookmark,
                lastEnrichedAt: songItem.lastEnrichedAt,
                lastMetadataAttemptAt: songItem.lastMetadataAttemptAt,
                metadataSource: songItem.metadataSource,
                artworkURL: songItem.artworkURL,
                lastLyricsFetchedAt: songItem.lastLyricsFetchedAt,
                lastLyricsAttemptAt: songItem.lastLyricsAttemptAt,
                lyricsSource: songItem.lyricsSource,
                lyricsPath: songItem.lyricsPath,
                addedAt: songItem.addedAt
            )
            if let lyricsData = files["Lyrics/\(songItem.id.uuidString).lrc"] {
                let url = lyricsFileURL(for: songItem.id)
                try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                try? lyricsData.write(to: url, options: .atomic)
                song.lyricsPath = url.path
            }
            modelContext.insert(song)
            songMap[songItem.id] = song
        }

        for playlistItem in payload.playlists {
            let playlist = Playlist(
                id: playlistItem.id,
                name: playlistItem.name,
                createdAt: playlistItem.createdAt,
                updatedAt: playlistItem.updatedAt
            )
            modelContext.insert(playlist)
            playlistMap[playlistItem.id] = playlist
        }

        for item in payload.playlistSongs {
            let ps = PlaylistSong(
                id: item.id,
                order: item.order,
                song: item.songID.flatMap { songMap[$0] },
                playlist: item.playlistID.flatMap { playlistMap[$0] }
            )
            modelContext.insert(ps)
        }

        for avatarItem in payload.artistAvatars {
            let avatar = ArtistAvatar(
                artistKey: avatarItem.artistKey,
                artistName: avatarItem.artistName,
                imageData: nil,
                source: avatarItem.source,
                isLocked: avatarItem.isLocked,
                sourceId: avatarItem.sourceId,
                updatedAt: avatarItem.updatedAt
            )
            if let path = avatarItem.imagePath, let data = files[path] {
                avatar.imageData = data
            }
            modelContext.insert(avatar)
        }

        try? modelContext.save()
    }

    private func lyricsFileURL(for id: UUID) -> URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent("Lyrics").appendingPathComponent("\(id.uuidString).lrc")
    }
}
