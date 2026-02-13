import Foundation
import SwiftData

enum EnrichReason {
    case importFile
    case playback
    case manual
}

actor MetadataEnrichmentService {
    static let shared = MetadataEnrichmentService()

    private var inFlight: [UUID: Task<Void, Never>] = [:]
    private let cacheInterval: TimeInterval = 24 * 60 * 60

    private init() {}

    func enrich(songID: UUID, repository: SongRepository, reason: EnrichReason) async {
        if let existing = inFlight[songID] {
            await existing.value
            return
        }

        let task = Task { [weak self] in
            guard let self = self else { return }
            await self.enrichInternal(songID: songID, repository: repository, reason: reason)
        }
        inFlight[songID] = task
        await task.value
        inFlight[songID] = nil
    }

    private func enrichInternal(songID: UUID, repository: SongRepository, reason: EnrichReason) async {
        let song = await MainActor.run { repository.fetchById(songID) }
        guard let song else { return }
        guard shouldEnrich(song, reason: reason) else { return }

        let query = Self.buildQuery(title: song.title, artist: song.artist, fileURL: song.fileURL)

        if let itunes = await fetchFromiTunes(query: query) {
            await applyEnrichedData(
                songID: songID,
                repository: repository,
                source: "itunes",
                title: itunes.title,
                artist: itunes.artist,
                album: itunes.album,
                artworkURL: itunes.artworkURL
            )
            return
        }

        if let mb = await fetchFromMusicBrainz(title: query.title, artist: query.artist) {
            await applyEnrichedData(
                songID: songID,
                repository: repository,
                source: "musicbrainz",
                title: mb.title,
                artist: mb.artist,
                album: mb.album,
                artworkURL: nil
            )
        }
    }

    private func shouldEnrich(_ song: Song, reason: EnrichReason) -> Bool {
        if reason == .manual { return true }

        let needsInfo = Self.isMissing(song.title, fileURL: song.fileURL) ||
            Self.isUnknown(song.artist) ||
            Self.isUnknown(song.album) ||
            song.artworkData == nil

        if !needsInfo { return false }

        if let last = song.lastEnrichedAt, Date().timeIntervalSince(last) < cacheInterval {
            return false
        }

        return true
    }

    nonisolated private static func isMissing(_ title: String, fileURL: String) -> Bool {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return true }
        let base = fileBaseName(fileURL)
        return trimmed == base || isUnknown(trimmed)
    }

    nonisolated private static func isUnknown(_ value: String) -> Bool {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if normalized.isEmpty { return true }
        return normalized == "unknown" ||
            normalized == "unknown artist" ||
            normalized == "unknown album" ||
            normalized == "未知" ||
            normalized == "未知艺术家" ||
            normalized == "未知专辑"
    }

    nonisolated private static func fileBaseName(_ path: String) -> String {
        URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
    }

    nonisolated private static func buildQuery(title: String, artist: String, fileURL: String) -> (title: String, artist: String?) {
        let baseName = Self.fileBaseName(fileURL)
        let cleanedTitle = Self.isMissing(title, fileURL: fileURL) ? baseName : title
        let cleanedArtist = Self.isUnknown(artist) ? nil : artist
        return (cleanedTitle, cleanedArtist)
    }

    private func applyEnrichedData(
        songID: UUID,
        repository: SongRepository,
        source: String,
        title: String?,
        artist: String?,
        album: String?,
        artworkURL: String?
    ) async {
        let downloadedArtwork = await fetchArtworkData(from: artworkURL)
        await MainActor.run {
            repository.update(songID: songID) { song in
                let base = Self.fileBaseName(song.fileURL)
                if let title = title, Self.isMissing(song.title, fileURL: song.fileURL) {
                    song.title = title
                } else if Self.isMissing(song.title, fileURL: song.fileURL) && !base.isEmpty {
                    song.title = base
                }

                if let artist = artist, Self.isUnknown(song.artist) {
                    song.artist = artist
                }

                if let album = album, Self.isUnknown(song.album) {
                    song.album = album
                }

                if song.artworkData == nil, let data = downloadedArtwork {
                    song.artworkData = data
                }

                if let artworkURL = artworkURL, song.artworkURL == nil {
                    song.artworkURL = artworkURL
                }

                song.lastEnrichedAt = Date()
                song.metadataSource = source
            }
        }
    }

    private func fetchArtworkData(from urlString: String?) async -> Data? {
        guard let urlString = urlString, let url = URL(string: urlString) else { return nil }
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            if let http = response as? HTTPURLResponse, http.statusCode != 200 {
                return nil
            }
            if data.count > 2 * 1024 * 1024 {
                return nil
            }
            return data
        } catch {
            return nil
        }
    }

    // MARK: - iTunes

    private struct ITunesResponse: Decodable {
        let resultCount: Int
        let results: [ITunesItem]
    }

    private struct ITunesItem: Decodable {
        let trackName: String?
        let artistName: String?
        let collectionName: String?
        let artworkUrl100: String?
    }

    private func fetchFromiTunes(query: (title: String, artist: String?)) async -> (title: String?, artist: String?, album: String?, artworkURL: String?)? {
        var term = query.title
        if let artist = query.artist {
            term = "\(artist) \(query.title)"
        }

        var components = URLComponents(string: "https://itunes.apple.com/search")
        components?.queryItems = [
            URLQueryItem(name: "term", value: term),
            URLQueryItem(name: "entity", value: "song"),
            URLQueryItem(name: "limit", value: "1")
        ]
        guard let url = components?.url else { return nil }

        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            if let http = response as? HTTPURLResponse, http.statusCode != 200 {
                return nil
            }
            let decoded = try JSONDecoder().decode(ITunesResponse.self, from: data)
            guard let item = decoded.results.first else { return nil }
            let artwork = upgradedArtworkURL(item.artworkUrl100)
            return (item.trackName, item.artistName, item.collectionName, artwork)
        } catch {
            return nil
        }
    }

    private func upgradedArtworkURL(_ url: String?) -> String? {
        guard let url = url else { return nil }
        return url.replacingOccurrences(of: "100x100", with: "600x600")
    }

    // MARK: - MusicBrainz

    private struct MusicBrainzResponse: Decodable {
        let recordings: [MBRecording]
    }

    private struct MBRecording: Decodable {
        let title: String?
        let releases: [MBRelease]?
        let artistCredit: [MBArtistCredit]?

        enum CodingKeys: String, CodingKey {
            case title
            case releases
            case artistCredit = "artist-credit"
        }
    }

    private struct MBArtistCredit: Decodable {
        let name: String?
    }

    private struct MBRelease: Decodable {
        let title: String?
    }

    private func fetchFromMusicBrainz(title: String, artist: String?) async -> (title: String?, artist: String?, album: String?)? {
        var queryParts: [String] = []
        queryParts.append("recording:\"\(title)\"")
        if let artist = artist {
            queryParts.append("artist:\"\(artist)\"")
        }
        let query = queryParts.joined(separator: " AND ")

        var components = URLComponents(string: "https://musicbrainz.org/ws/2/recording/")
        components?.queryItems = [
            URLQueryItem(name: "query", value: query),
            URLQueryItem(name: "fmt", value: "json"),
            URLQueryItem(name: "limit", value: "1")
        ]
        guard let url = components?.url else { return nil }

        do {
            var request = URLRequest(url: url)
            request.setValue("OneMusic/1.0 (metadata enrichment)", forHTTPHeaderField: "User-Agent")
            let (data, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, http.statusCode != 200 {
                return nil
            }
            let decoded = try JSONDecoder().decode(MusicBrainzResponse.self, from: data)
            guard let recording = decoded.recordings.first else { return nil }
            let artistName = recording.artistCredit?.first?.name
            let albumName = recording.releases?.first?.title
            return (recording.title, artistName, albumName)
        } catch {
            return nil
        }
    }
}
