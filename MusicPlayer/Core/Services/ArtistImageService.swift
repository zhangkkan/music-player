import Foundation

actor ArtistImageService {
    static let shared = ArtistImageService()

    private var inFlight: [String: Task<Data?, Never>] = [:]

    private init() {}

    func imageData(for artist: String) async -> Data? {
        let key = Self.normalizedKey(for: artist)
        guard !key.isEmpty else { return nil }

        if let existing = inFlight[key] {
            return await existing.value
        }

        let task = Task<Data?, Never> { [weak self] in
            guard let self else { return nil }
            return await self.fetchFromITunes(artist: artist)
        }

        inFlight[key] = task
        let result = await task.value
        inFlight[key] = nil
        return result
    }

    func fetchCandidates(artist: String, limit: Int) async -> [ArtistAvatarCandidate] {
        let trimmed = artist.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        let capped = min(max(limit, 1), 100)

        var components = URLComponents(string: "https://itunes.apple.com/search")
        components?.queryItems = [
            URLQueryItem(name: "term", value: trimmed),
            URLQueryItem(name: "media", value: "music"),
            URLQueryItem(name: "entity", value: "album"),
            URLQueryItem(name: "attribute", value: "artistTerm"),
            URLQueryItem(name: "limit", value: String(capped))
        ]
        guard let url = components?.url else { return [] }

        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            if let http = response as? HTTPURLResponse, http.statusCode != 200 {
                return []
            }
            let decoded = try JSONDecoder().decode(ITunesResponse.self, from: data)
            var bestByURL: [String: (candidate: ArtistAvatarCandidate, quality: Int)] = [:]
            for item in decoded.results {
                guard let artwork = item.artworkUrl100 ?? item.artworkUrl60 else { continue }
                guard let fullsize = upgradedArtworkURL(artwork),
                      let thumbURL = URL(string: artwork),
                      let fullURL = URL(string: fullsize) else {
                    continue
                }
                let id = item.collectionId.map(String.init) ?? fullURL.absoluteString
                let quality = max(parseResolution(fullsize), parseResolution(artwork))
                let candidate = ArtistAvatarCandidate(
                    id: id,
                    thumbnailURL: thumbURL,
                    fullsizeURL: fullURL
                )
                let key = fullURL.absoluteString
                if let existing = bestByURL[key] {
                    if quality > existing.quality {
                        bestByURL[key] = (candidate, quality)
                    }
                } else {
                    bestByURL[key] = (candidate, quality)
                }
            }
            return bestByURL.values
                .sorted { (lhs, rhs) in
                    lhs.quality > rhs.quality
                }
                .map { $0.candidate }
        } catch {
            return []
        }
    }

    func fetchImageData(url: URL) async -> Data? {
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

    private func fetchFromITunes(artist: String) async -> Data? {
        let trimmed = artist.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        var components = URLComponents(string: "https://itunes.apple.com/search")
        components?.queryItems = [
            URLQueryItem(name: "term", value: trimmed),
            URLQueryItem(name: "media", value: "music"),
            URLQueryItem(name: "entity", value: "album"),
            URLQueryItem(name: "attribute", value: "artistTerm"),
            URLQueryItem(name: "limit", value: "1")
        ]
        guard let url = components?.url else { return nil }

        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            if let http = response as? HTTPURLResponse, http.statusCode != 200 {
                return nil
            }
            let decoded = try JSONDecoder().decode(ITunesResponse.self, from: data)
            guard let item = decoded.results.first,
                  let artwork = upgradedArtworkURL(item.artworkUrl100 ?? item.artworkUrl60),
                  let artworkURL = URL(string: artwork) else {
                return nil
            }
            let (artData, artResponse) = try await URLSession.shared.data(from: artworkURL)
            if let http = artResponse as? HTTPURLResponse, http.statusCode != 200 {
                return nil
            }
            if artData.count > 2 * 1024 * 1024 {
                return nil
            }
            return artData
        } catch {
            return nil
        }
    }

    private struct ITunesResponse: Decodable {
        let resultCount: Int
        let results: [ITunesItem]
    }

    private struct ITunesItem: Decodable {
        let collectionId: Int?
        let artworkUrl100: String?
        let artworkUrl60: String?
    }

    private func upgradedArtworkURL(_ url: String?) -> String? {
        guard let url else { return nil }
        return url.replacingOccurrences(of: "100x100", with: "600x600")
    }

    private func parseResolution(_ urlString: String) -> Int {
        guard let url = URL(string: urlString) else { return 0 }
        let last = url.deletingPathExtension().lastPathComponent
        if let match = last.range(of: #"\d+x\d+"#, options: .regularExpression) {
            let size = String(last[match]).split(separator: "x")
            if size.count == 2, let w = Int(size[0]), let h = Int(size[1]) {
                return w * h
            }
        }
        return 0
    }

    static func normalizedKey(for artist: String) -> String {
        let trimmed = artist.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if trimmed.isEmpty { return "" }
        let collapsed = trimmed.replacingOccurrences(of: #"\\s+"#, with: " ", options: .regularExpression)
        let cleaned = collapsed.trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned
    }
}

struct ArtistAvatarCandidate: Identifiable {
    let id: String
    let thumbnailURL: URL
    let fullsizeURL: URL
}
