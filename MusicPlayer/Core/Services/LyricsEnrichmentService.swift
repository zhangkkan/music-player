import Foundation
import SwiftData

actor LyricsEnrichmentService {
    static let shared = LyricsEnrichmentService()

    private var inFlight: [UUID: Task<Void, Never>] = [:]

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

        if reason != .manual && reason != .force {
            let needsLyrics = song.lyricsPath == nil
            if !needsLyrics { return }
            if let last = song.lastLyricsFetchedAt, Date().timeIntervalSince(last) < EnrichmentSettings.cacheInterval {
                return
            }
        }

        if EnrichmentSettings.lyricsSource == .localOnly {
            print("[Lyrics] Skip fetch (local only) for \(songID)")
            return
        }

        print("[Lyrics] Fetch start for \(songID) - \(song.artist) / \(song.title)")
        guard let lrc = await fetchLRC(artist: song.artist, title: song.title, album: song.album, duration: song.duration) else {
            print("[Lyrics] Fetch empty for \(songID)")
            await MainActor.run {
                repository.update(songID: songID) { song in
                    song.lastLyricsFetchedAt = Date()
                }
            }
            return
        }

        let url = lyricsFileURL(for: song.id)
        do {
            try ensureLyricsDirectory()
            try lrc.write(to: url, atomically: true, encoding: .utf8)
            print("[Lyrics] Saved LRC for \(songID) at \(url.lastPathComponent)")
            await MainActor.run {
                repository.update(songID: songID) { song in
                    song.lyricsPath = url.path
                    song.lyricsSource = "lrclib"
                    song.lastLyricsFetchedAt = Date()
                }
                NotificationCenter.default.post(
                    name: .lyricsDidUpdate,
                    object: nil,
                    userInfo: ["songID": songID]
                )
            }
        } catch {
            await MainActor.run {
                repository.update(songID: songID) { song in
                    song.lastLyricsFetchedAt = Date()
                }
            }
        }
    }

    private func lyricsFileURL(for id: UUID) -> URL {
        let dir = lyricsDirectory()
        return dir.appendingPathComponent("\(id.uuidString).lrc")
    }

    private func lyricsDirectory() -> URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent("Lyrics")
    }

    private func ensureLyricsDirectory() throws {
        let dir = lyricsDirectory()
        if !FileManager.default.fileExists(atPath: dir.path) {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
    }

    // MARK: - LRCLIB

    private struct LrcResponse: Decodable {
        let syncedLyrics: String?
        let plainLyrics: String?
    }

    private func fetchLRC(artist: String, title: String, album: String, duration: TimeInterval) async -> String? {
        let trimmedArtist = artist.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedArtist.isEmpty, !trimmedTitle.isEmpty else { return nil }

        var components = URLComponents(string: "https://lrclib.net/api/get")
        components?.queryItems = [
            URLQueryItem(name: "artist_name", value: trimmedArtist),
            URLQueryItem(name: "track_name", value: trimmedTitle),
            URLQueryItem(name: "album_name", value: album.trimmingCharacters(in: .whitespacesAndNewlines))
        ]

        if duration > 0 {
            components?.queryItems?.append(URLQueryItem(name: "duration", value: String(Int(duration))))
        }

        guard let url = components?.url else { return nil }

        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            if let http = response as? HTTPURLResponse, http.statusCode != 200 {
                return nil
            }
            let decoded = try JSONDecoder().decode(LrcResponse.self, from: data)
            if let lrc = decoded.syncedLyrics, !lrc.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return lrc
            }
            return nil
        } catch {
            return nil
        }
    }
}

extension Notification.Name {
    static let lyricsDidUpdate = Notification.Name("lyricsDidUpdate")
}
