import Foundation
import CoreFoundation
import SwiftData

actor LyricsEnrichmentService {
    static let shared = LyricsEnrichmentService()

    private var inFlight: [UUID: Task<Void, Never>] = [:]

    private init() {}

    func enrich(songID: UUID, repository: SongRepository, reason: EnrichReason) async {
        if let existing = inFlight[songID] {
            print("[Lyrics] Sync already in progress for \(songID) (reason: \(reason))")
            await existing.value
            return
        }

        print("[Lyrics] Sync triggered for \(songID) (reason: \(reason))")
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
        guard let song else {
            print("[Lyrics] Song not found for \(songID) (reason: \(reason))")
            return
        }

        if reason != .manual && reason != .force {
            let needsLyrics = song.lyricsPath == nil
            if !needsLyrics {
                print("[Lyrics] Skip fetch (already has lyrics) for \(songID) (reason: \(reason))")
                return
            }
            let cooldown: TimeInterval = 5 * 60
            if let last = song.lastLyricsAttemptAt, Date().timeIntervalSince(last) < cooldown {
                print("[Lyrics] Skip fetch (cooldown: \(Int(cooldown / 60))min) for \(songID) (reason: \(reason))")
                return
            }
        }

        await MainActor.run {
            repository.update(songID: songID) { song in
                song.lastLyricsAttemptAt = Date()
            }
        }

        // Ensure metadata enrichment completes before lyrics fetch.
        await MetadataEnrichmentService.shared.enrich(
            songID: songID,
            repository: repository,
            reason: reason
        )

        // 重新从数据库获取最新的歌曲信息，确保获取到元数据增强后的简体歌名
        // 也确保元数据增强已经完成（因为元数据增强会修改歌手名、歌名等）
        let latestSong = await MainActor.run { repository.fetchById(songID) }
        guard let latestSong else {
            print("[Lyrics] ERROR: Could not fetch latest song data after metadata update")
            return
        }

        // 添加详细日志，显示使用的元数据
        print("[Lyrics] Fetch start for \(songID) - \(latestSong.artist) / \(latestSong.title) (reason: \(reason))")
        print("[Lyrics] Song metadata - artist: \(latestSong.artist), title: \(latestSong.title), album: \(latestSong.album), duration: \(latestSong.duration)s")
        print("[Lyrics] Metadata source - iTunes: \(latestSong.metadataSource ?? "none")")

        let fetchStartTime = Date()
        guard let rawLrc = await fetchLRC(artist: latestSong.artist, title: latestSong.title, album: latestSong.album, duration: latestSong.duration) else {
            let totalFetchTime = Date().timeIntervalSince(fetchStartTime)
            print("[Lyrics] Fetch FAILED - no lyrics found for \(songID) (reason: \(reason)) (total time: \(String(format: "%.2f", totalFetchTime))s)")
            return
        }

        let totalFetchTime = Date().timeIntervalSince(fetchStartTime)
        print("[Lyrics] Fetch completed for \(songID) in \(String(format: "%.2f", totalFetchTime))s")

        let (lrc, ratio, converted) = normalizeLrc(rawLrc)
        if converted {
            print("[Lyrics] Converted to simplified (ratio=\(String(format: "%.2f", ratio))) for \(songID)")
        }

        let url = lyricsFileURL(for: song.id)
        do {
            try ensureLyricsDirectory()
            try lrc.write(to: url, atomically: true, encoding: .utf8)
            print("[Lyrics] Fetch SUCCESS - saved LRC for \(songID) (reason: \(reason))")
            await MainActor.run {
                repository.update(songID: songID) { song in
                    song.lyricsPath = url.path
                    song.lyricsSource = "lrclib"
                    song.lastLyricsFetchedAt = Date()
                    song.lastLyricsAttemptAt = Date()
                }
                NotificationCenter.default.post(
                    name: .lyricsDidUpdate,
                    object: nil,
                    userInfo: ["songID": songID]
                )
            }
        } catch {
            print("[Lyrics] Fetch FAILED - save error for \(songID) (reason: \(reason)): \(error)")
            await MainActor.run {
                repository.update(songID: songID) { song in
                    song.lastLyricsAttemptAt = Date()
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
        print("🔍 [Lyrics] ===== fetchLRC START ===== artist=\(artist.prefix(20)), title=\(title.prefix(30))")
        let trimmedArtist = sanitizeQueryText(artist)
        let trimmedTitle = sanitizeQueryText(title)
        guard !trimmedArtist.isEmpty, !trimmedTitle.isEmpty else {
            print("🔍 [Lyrics] ===== fetchLRC ABORTED: empty artist or title =====")
            return nil
        }

        let artistCandidates = buildCandidates(
            trimmedArtist,
            order: .simplifiedTraditionalOriginal
        )
        let titleCandidates = buildTitleCandidates(trimmedTitle)
        let trimmedAlbum = album.trimmingCharacters(in: .whitespacesAndNewlines)

        print("[Lyrics] Query candidates - artist: \(artistCandidates.count), title: \(titleCandidates.count)")
        let queryVariants = buildQueryVariants(album: trimmedAlbum, duration: duration)

        var attemptCount = 0
        var lastAttemptTime = Date()
        var triedKeys = Set<String>()

        func makeKey(artist: String, title: String, album: String, duration: TimeInterval) -> String {
            "\(artist)|\(title)|\(album)|\(duration)"
        }

        func attemptFetch(
            artist: String,
            title: String,
            album: String,
            duration: TimeInterval,
            isPrimary: Bool
        ) async -> String? {
            let key = makeKey(artist: artist, title: title, album: album, duration: duration)
            if triedKeys.contains(key) {
                return nil
            }
            triedKeys.insert(key)

            attemptCount += 1
            print("[Lyrics] Query attempt \(attemptCount): artist=\(artist.prefix(20)), title=\(title.prefix(30)), album=\(album.isEmpty ? "(empty)" : album.prefix(20)), duration=\(duration), isPrimary=\(isPrimary)")

            if let lrc = await fetchLRCOnce(
                artist: artist,
                title: title,
                album: album,
                duration: duration
            ) {
                if artist != trimmedArtist || title != trimmedTitle || !isPrimary {
                    print("✅ [Lyrics] ===== SUCCESS: Fallback match with variant =====")
                } else {
                    print("✅ [Lyrics] ===== SUCCESS: Direct match with primary query =====")
                }
                return lrc
            }

            print("[Lyrics] ❌ Query attempt \(attemptCount) failed")
            lastAttemptTime = Date()
            return nil
        }

        // Strict user-specified order:
        // 1) simplified artist + simplified title, no album/duration
        // 2) traditional artist + traditional title, no album/duration
        let simplifiedArtist = sanitizeQueryText(convertToSimplified(trimmedArtist))
        let simplifiedTitle = sanitizeQueryText(convertToSimplified(trimmedTitle))
        if let lrc = await attemptFetch(
            artist: simplifiedArtist,
            title: simplifiedTitle,
            album: "",
            duration: 0,
            isPrimary: true
        ) {
            return lrc
        }

        let traditionalArtist = sanitizeQueryText(convertToTraditional(trimmedArtist))
        let traditionalTitle = sanitizeQueryText(convertToTraditional(trimmedTitle))
        if (traditionalArtist != simplifiedArtist || traditionalTitle != simplifiedTitle),
           let lrc = await attemptFetch(
            artist: traditionalArtist,
            title: traditionalTitle,
            album: "",
            duration: 0,
            isPrimary: true
           ) {
            return lrc
        }

        for candidateArtist in artistCandidates {
            for candidateTitle in titleCandidates {
                for variant in queryVariants {
                    // 检查是否超时（每个查询超过30秒就中止）
                    if attemptCount > 1 && Date().timeIntervalSince(lastAttemptTime) > 30 {
                        print("⏱️ [Lyrics] ===== fetchLRC TIMEOUT after \(attemptCount) attempts and 30s =====")
                        return nil
                    }

                    if let lrc = await attemptFetch(
                        artist: candidateArtist,
                        title: candidateTitle,
                        album: variant.album,
                        duration: variant.duration,
                        isPrimary: variant.isPrimary
                    ) {
                        return lrc
                    }
                }
            }
        }

        print("❌ [Lyrics] ===== fetchLRC FAILED: All \(attemptCount) attempts failed =====")
        return nil
    }

    private func fetchLRCOnce(artist: String, title: String, album: String, duration: TimeInterval) async -> String? {
        var components = URLComponents(string: "https://lrclib.net/api/get")
        var items = [
            URLQueryItem(name: "artist_name", value: artist),
            URLQueryItem(name: "track_name", value: title)
        ]
        if !album.isEmpty {
            items.append(URLQueryItem(name: "album_name", value: album))
        }
        components?.queryItems = items

        if duration > 0 {
            components?.queryItems?.append(URLQueryItem(name: "duration", value: String(Int(duration))))
        }

        guard let url = components?.url else {
            print("[Lyrics] ❌ Failed to build URL from components")
            return nil
        }

        do {
            // 创建自定义 URLSession 配置，添加 10 秒超时
            let config = URLSessionConfiguration.default
            config.timeoutIntervalForRequest = 10.0
            config.timeoutIntervalForResource = 15.0
            let session = URLSession(configuration: config)

            let startDate = Date()
            let (data, response) = try await session.data(from: url)
            let elapsed = Date().timeIntervalSince(startDate)

            if let http = response as? HTTPURLResponse, http.statusCode != 200 {
                print("[Lyrics] ❌ HTTP error: \(http.statusCode) for URL: \(url.absoluteString.prefix(80)) (took \(String(format: "%.2f", elapsed))s)")
                return nil
            }

            print("[Lyrics] 📡 Network request succeeded (took \(String(format: "%.2f", elapsed))s)")

            let decoded = try JSONDecoder().decode(LrcResponse.self, from: data)
            if let lrc = decoded.syncedLyrics, !lrc.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                print("[Lyrics] ✅ Synced lyrics found (\(lrc.count) chars)")
                return lrc
            }

            if let plain = decoded.plainLyrics, !plain.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                print("[Lyrics] ⚠️ Only plain lyrics found (no synced lyrics)")
                return plain  // 返回纯文本歌词作为降级方案
            }

            print("[Lyrics] ❌ No lyrics content in response")
            return nil
        } catch let error {
            print("[Lyrics] ❌ Network/decoding error: \(error.localizedDescription)")
            return nil
        }
    }

    // MARK: - Simplified Chinese normalization

    private func normalizeLrc(_ text: String) -> (String, Double, Bool) {
        let ratio = detectTraditionalRatio(text)
        if ratio >= 0.1 {
            let simplified = convertToSimplified(text)
            return (simplified, ratio, true)
        }
        return (text, ratio, false)
    }

    private func detectTraditionalRatio(_ text: String) -> Double {
        let simplified = convertToSimplified(text)
        let originalScalars = Array(text.unicodeScalars)
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

    private func convertToSimplified(_ text: String) -> String {
        let mutable = NSMutableString(string: text) as CFMutableString
        CFStringTransform(mutable, nil, "Traditional-Simplified" as CFString, false)
        return mutable as String
    }

    private func isCJK(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x4E00...0x9FFF,
             0x3400...0x4DBF,
             0xF900...0xFAFF:
            return true
        default:
            return false
        }
    }

    private func convertToTraditional(_ text: String) -> String {
        let mutable = NSMutableString(string: text) as CFMutableString
        CFStringTransform(mutable, nil, "Simplified-Traditional" as CFString, false)
        return mutable as String
    }

    private func buildTitleCandidates(_ text: String) -> [String] {
        buildCandidates(text, order: .simplifiedTraditionalOriginal)
    }

    private enum CandidateOrder {
        case simplifiedOriginalTraditional
        case simplifiedTraditionalOriginal
    }

    private func buildCandidates(_ text: String, order: CandidateOrder) -> [String] {
        var candidates: [String] = []
        func appendIfNew(_ value: String) {
            let trimmed = sanitizeQueryText(value)
            guard !trimmed.isEmpty, !candidates.contains(trimmed) else { return }
            candidates.append(trimmed)
        }

        let simplified = convertToSimplified(text)
        let traditional = convertToTraditional(text)

        switch order {
        case .simplifiedOriginalTraditional:
            appendIfNew(simplified)
            if simplified != text {
                appendIfNew(text)
            }
            appendIfNew(traditional)
        case .simplifiedTraditionalOriginal:
            appendIfNew(simplified)
            if traditional != simplified {
                appendIfNew(traditional)
            }
            if text != simplified && text != traditional {
                appendIfNew(text)
            }
        }

        return candidates
    }

    private func sanitizeQueryText(_ text: String) -> String {
        var value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.isEmpty { return value }

        // Remove leading source tags like "[51ape.com]" or "(source)".
        value = value.replacingOccurrences(of: #"^\s*[\[\(\{][^\]\)\}]+[\]\)\}]\s*"#, with: "", options: .regularExpression)
        // Remove embedded URLs/domains.
        value = value.replacingOccurrences(of: #"https?://\S+|www\.\S+"#, with: "", options: .regularExpression)
        value = value.replacingOccurrences(of: #"\b[\w\-]+(\.[\w\-]+)+\b"#, with: "", options: .regularExpression)

        // Remove common separators around tags.
        value = value.replacingOccurrences(of: #"[-_/]+"#, with: " ", options: .regularExpression)

        // Collapse whitespace.
        value = value.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        return value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func buildQueryVariants(album: String, duration: TimeInterval) -> [(album: String, duration: TimeInterval, isPrimary: Bool)] {
        // Prefer looser queries earlier to improve hit rate.
        if album.isEmpty {
            return [
                ("", duration, true),
                ("", 0, false)
            ]
        }

        return [
            ("", duration, true),
            ("", 0, false),
            (album, duration, false),
            (album, 0, false)
        ]
    }
}

extension Notification.Name {
    static let lyricsDidUpdate = Notification.Name("lyricsDidUpdate")
}
