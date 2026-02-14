import Foundation
import CoreFoundation
import SwiftData

enum EnrichReason {
    case importFile
    case playback
    case manual
    case force
}

actor MetadataEnrichmentService {
    static let shared = MetadataEnrichmentService()

    private var inFlight: [UUID: Task<Void, Never>] = [:]
    private var lastMBRequestAt: Date?

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
        if !shouldEnrich(song, reason: reason) {
            print("[Enrich] Skip for \(songID) (cache or not needed)")
            return
        }

        await MainActor.run {
            repository.update(songID: songID) { song in
                song.lastMetadataAttemptAt = Date()
            }
        }

        let query = Self.buildQuery(title: song.title, artist: song.artist, fileURL: song.fileURL)

        print("[Enrich] Start for \(songID) - \(query.artist ?? "Unknown") / \(query.title)")
        if let itunes = await fetchFromiTunes(query: query) {
            print("[Enrich] iTunes hit for \(songID)")
            await applyEnrichedData(
                songID: songID,
                repository: repository,
                source: "itunes",
                title: itunes.title,
                artist: itunes.artist,
                album: itunes.album,
                artworkURL: itunes.artworkURL,
                reason: reason
            )
            return
        }

        if let mb = await fetchFromMusicBrainz(title: query.title, artist: query.artist) {
            print("[Enrich] MusicBrainz hit for \(songID)")
            await applyEnrichedData(
                songID: songID,
                repository: repository,
                source: "musicbrainz",
                title: mb.title,
                artist: mb.artist,
                album: mb.album,
                artworkURL: nil,
                reason: reason
            )
        } else {
            print("[Enrich] No results for \(songID)")
        }
    }

    private func shouldEnrich(_ song: Song, reason: EnrichReason) -> Bool {
        if reason == .manual || reason == .force { return true }

        let needsInfo = Self.isMissing(song.title, fileURL: song.fileURL) ||
            Self.isUnknown(song.artist) ||
            Self.isUnknown(song.album) ||
            song.artworkData == nil

        if !needsInfo { return false }

        if let last = song.lastEnrichedAt, Date().timeIntervalSince(last) < EnrichmentSettings.cacheInterval {
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

    nonisolated private static func shouldOverwrite(
        current: String,
        candidate: String,
        fileURL: String?,
        reason: EnrichReason
    ) -> Bool {
        if reason == .manual || reason == .force { return true }

        if hasSourceTag(current) {
            return true
        }

        if let fileURL = fileURL, Self.isMissing(current, fileURL: fileURL) {
            return true
        }

        if Self.isUnknown(current) {
            return true
        }

        let score = similarityScore(current, candidate)
        return score >= EnrichmentSettings.correctionThreshold
    }

    nonisolated private static func hasSourceTag(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return false }
        if trimmed.range(of: #"^\s*[\[\(\{].+[\]\)\}]\s*"#, options: .regularExpression) != nil {
            return true
        }
        if trimmed.range(of: #"https?://|www\\."#, options: .regularExpression) != nil {
            return true
        }
        if trimmed.range(of: #"\\.(com|net|org|cn|jp|kr|io|me|tv)\\b"#, options: .regularExpression) != nil {
            return true
        }
        return false
    }

    nonisolated private static func similarityScore(_ a: String, _ b: String) -> Double {
        let left = normalize(a)
        let right = normalize(b)
        if left.isEmpty || right.isEmpty { return 0 }
        if left == right { return 1 }
        let distance = levenshtein(left, right)
        let maxLen = max(left.count, right.count)
        if maxLen == 0 { return 1 }
        return 1.0 - (Double(distance) / Double(maxLen))
    }

    nonisolated private static func normalize(_ value: String) -> String {
        let lowered = value.lowercased()
        let removedBrackets = lowered.replacingOccurrences(of: #"\(.*?\)|\[.*?\]|\{.*?\}"#, with: "", options: .regularExpression)
        let removedFeat = removedBrackets.replacingOccurrences(of: "feat.", with: "", options: .caseInsensitive)
        let removedSymbols = removedFeat.replacingOccurrences(of: #"[^a-z0-9\u4e00-\u9fa5]+"#, with: " ", options: .regularExpression)
        return removedSymbols.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "  ", with: " ")
    }

    nonisolated private static func levenshtein(_ a: String, _ b: String) -> Int {
        let aChars = Array(a)
        let bChars = Array(b)
        var costs = Array(0...bChars.count)

        for i in 1...aChars.count {
            costs[0] = i
            var prev = i - 1
            for j in 1...bChars.count {
                let temp = costs[j]
                if aChars[i - 1] == bChars[j - 1] {
                    costs[j] = prev
                } else {
                    costs[j] = min(prev, costs[j - 1], costs[j]) + 1
                }
                prev = temp
            }
        }
        return costs[bChars.count]
    }

    nonisolated private static func normalizeChineseIfNeeded(_ value: String) -> (value: String, wasConverted: Bool) {
        let simplified = convertToSimplified(value)
        let ratio = detectTraditionalRatio(original: value, simplified: simplified)
        if ratio >= 0.1 {
            return (simplified, true)
        }
        return (value, false)
    }

    nonisolated private static func detectTraditionalRatio(original: String, simplified: String) -> Double {
        let originalScalars = Array(original.unicodeScalars)
        let simplifiedScalars = Array(simplified.unicodeScalars)
        guard originalScalars.count == simplifiedScalars.count else { return 0 }

        var cjkCount = 0
        var diffCount = 0
        for (o, s) in zip(originalScalars, simplifiedScalars) {
            if isCJK(o) {
                cjkCount += 1
                if o != s {
                    diffCount += 1
                }
            }
        }
        guard cjkCount > 0 else { return 0 }
        return Double(diffCount) / Double(cjkCount)
    }

    nonisolated private static func convertToSimplified(_ text: String) -> String {
        let mutable = NSMutableString(string: text) as CFMutableString
        CFStringTransform(mutable, nil, "Traditional-Simplified" as CFString, false)
        return mutable as String
    }

    nonisolated private static func isCJK(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x4E00...0x9FFF,
             0x3400...0x4DBF,
             0xF900...0xFAFF:
            return true
        default:
            return false
        }
    }

    private func applyEnrichedData(
        songID: UUID,
        repository: SongRepository,
        source: String,
        title: String?,
        artist: String?,
        album: String?,
        artworkURL: String?,
        reason: EnrichReason
    ) async {
        let downloadedArtwork = await fetchArtworkData(from: artworkURL)
        await MainActor.run {
            repository.update(songID: songID) { song in
                let base = Self.fileBaseName(song.fileURL)
                var updatedFields: [String] = []
                if let title = title {
                    let normalizedTitle = Self.normalizeChineseIfNeeded(title)
                    if normalizedTitle.wasConverted {
                        print("[Enrich] Simplified title for \(songID)")
                    }
                    if Self.shouldOverwrite(current: song.title, candidate: normalizedTitle.value, fileURL: song.fileURL, reason: reason) {
                        song.title = normalizedTitle.value
                        updatedFields.append("title")
                    }
                } else if Self.isMissing(song.title, fileURL: song.fileURL) && !base.isEmpty {
                    let normalizedBase = Self.normalizeChineseIfNeeded(base)
                    if normalizedBase.wasConverted {
                        print("[Enrich] Simplified title from filename for \(songID)")
                    }
                    song.title = normalizedBase.value
                    updatedFields.append("title")
                }

                if let artist = artist {
                    let normalizedArtist = Self.normalizeChineseIfNeeded(artist)
                    if normalizedArtist.wasConverted {
                        print("[Enrich] Simplified artist for \(songID)")
                    }
                    if Self.shouldOverwrite(current: song.artist, candidate: normalizedArtist.value, fileURL: nil, reason: reason) {
                        song.artist = normalizedArtist.value
                        updatedFields.append("artist")
                    }
                }

                if let album = album, Self.shouldOverwrite(current: song.album, candidate: album, fileURL: nil, reason: reason) {
                    song.album = album
                    updatedFields.append("album")
                }

                if song.artworkData == nil, let data = downloadedArtwork {
                    song.artworkData = data
                    updatedFields.append("artwork")
                }

                if let artworkURL = artworkURL, song.artworkURL == nil {
                    song.artworkURL = artworkURL
                }

                if updatedFields.isEmpty {
                    print("[Enrich] No field updated for \(songID) from \(source)")
                } else {
                    song.lastEnrichedAt = Date()
                    song.metadataSource = source
                    print("[Enrich] Updated \(updatedFields.joined(separator: ", ")) for \(songID) from \(source)")
                }
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
            await throttleMusicBrainz()
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

    private func throttleMusicBrainz() async {
        if let last = lastMBRequestAt {
            let elapsed = Date().timeIntervalSince(last)
            if elapsed < 1.0 {
                let delay = UInt64((1.0 - elapsed) * 1_000_000_000)
                try? await Task.sleep(nanoseconds: delay)
            }
        }
        lastMBRequestAt = Date()
    }
}
