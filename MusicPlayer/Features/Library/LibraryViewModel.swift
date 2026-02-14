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
    var albumArtwork: [String: Data] = [:]
    var artistArtwork: [String: Data] = [:]
    var artistArtworkSource: [String: String] = [:]
    var artistLocked: [String: Bool] = [:]
    private var knownArtistKeys: Set<String> = []

    private var songRepository: SongRepository?
    private var modelContext: ModelContext?
    private let artistImageService = ArtistImageService.shared
    private var artistAvatarRepository: ArtistAvatarRepository?
    private let avatarFetchLimiter = AvatarFetchLimiter(limit: 3)

    func setup(modelContext: ModelContext) {
        self.modelContext = modelContext
        songRepository = SongRepository(modelContext: modelContext)
        artistAvatarRepository = ArtistAvatarRepository(modelContext: modelContext)
        refresh()
    }

    func refresh() {
        guard let repo = songRepository else { return }
        songs = repo.fetchAll()
        artists = repo.allArtists()
        albums = repo.allAlbums()
        genres = repo.allGenres()
        rebuildArtworkCache()
        refreshArtistAvatars()
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
        songRepository?.deleteSongAndCleanup(song)
        refresh()
    }

    func importFiles(_ urls: [URL]) {
        guard let repo = songRepository else { return }
        Task {
            _ = await ImportService.shared.importFiles(urls, songRepository: repo)
            await MainActor.run { refresh() }
        }
    }

    func artworkForAlbum(_ album: String) -> Data? {
        let key = album.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return nil }
        return albumArtwork[key]
    }

    func artworkForArtist(_ artist: String) -> Data? {
        let key = ArtistImageService.normalizedKey(for: artist)
        guard !key.isEmpty else { return nil }
        let data = artistArtwork[key]
        print("[ArtistAvatar] artworkForArtist - artist=\(artist), key=\(key), hasData=\(data != nil)")
        return data
    }

    func isManualAvatar(_ artist: String) -> Bool {
        let key = ArtistImageService.normalizedKey(for: artist)
        return artistArtworkSource[key] == "manual"
    }

    func isLockedAvatar(_ artist: String) -> Bool {
        let key = ArtistImageService.normalizedKey(for: artist)
        return artistLocked[key] == true
    }

    func loadArtistArtworkIfNeeded(_ artist: String) {
        let key = ArtistImageService.normalizedKey(for: artist)
        guard !key.isEmpty else { return }
        if artistArtwork[key] != nil { return }

        Task {
            await fetchAutoAvatarIfNeeded(artistName: artist)
        }
    }

    func setManualAvatar(artist: String, data: Data) {
        let key = ArtistImageService.normalizedKey(for: artist)
        guard !key.isEmpty else { return }
        print("[ArtistAvatar] setManualAvatar - artist=\(artist), key=\(key), size=\(data.count)")
        Task { @MainActor in
            artistAvatarRepository?.upsert(
                artistKey: key,
                artistName: artist,
                data: data,
                source: "manual",
                isLocked: true
            )
            artistArtwork[key] = data
            artistArtworkSource[key] = "manual"
            artistLocked[key] = true
        }
    }

    func restoreAutoAvatar(artist: String) async {
        let key = ArtistImageService.normalizedKey(for: artist)
        guard !key.isEmpty else { return }
        print("[ArtistAvatar] restoreAutoAvatar - artist=\(artist), key=\(key)")
        await MainActor.run {
            artistAvatarRepository?.clearImage(
                artistKey: key,
                artistName: artist,
                source: "locked",
                isLocked: true
            )
            artistArtwork[key] = nil
            artistArtworkSource[key] = nil
            artistLocked[key] = true
        }
    }

    private func refreshArtistAvatars() {
        guard let avatarRepo = artistAvatarRepository else { return }

        let artistMap = artists.reduce(into: [String: String]()) { result, name in
            let key = ArtistImageService.normalizedKey(for: name)
            if !key.isEmpty {
                result[key] = name
            }
        }

        let newKeys = Set(artistMap.keys)
        let removedKeys = knownArtistKeys.subtracting(newKeys)
        print("[ArtistAvatar] refreshArtistAvatars - artists=\(artists.count), newKeys=\(newKeys.count), removed=\(removedKeys.count)")
        Task { @MainActor in
            if !removedKeys.isEmpty {
                avatarRepo.deleteByKeys(Array(removedKeys))
            }

            let avatars = avatarRepo.fetchByKeys(Array(newKeys))
            var dataMap: [String: Data] = [:]
            var sourceMap: [String: String] = [:]
            var lockMap: [String: Bool] = [:]
            for avatar in avatars {
                if let data = avatar.imageData {
                    dataMap[avatar.artistKey] = data
                    sourceMap[avatar.artistKey] = avatar.source
                }
                lockMap[avatar.artistKey] = avatar.isLocked
                print("[ArtistAvatar] refreshArtistAvatars - fetched key=\(avatar.artistKey), size=\(avatar.imageData?.count ?? 0), source=\(avatar.source), locked=\(avatar.isLocked)")
            }
            print("[ArtistAvatar] refreshArtistAvatars - loaded avatars=\(dataMap.count), locked=\(lockMap.filter { $0.value }.count)")

            artistArtwork = dataMap
            artistArtworkSource = sourceMap
            artistLocked = lockMap
            let addedKeys = newKeys.subtracting(knownArtistKeys)
            knownArtistKeys = newKeys

            for (key, name) in artistMap where addedKeys.contains(key) {
                Task {
                    await fetchAutoAvatarIfNeeded(artistName: name)
                }
            }
        }
    }

    private func fetchAutoAvatarIfNeeded(artistName: String) async {
        if isManualAvatar(artistName) { return }
        let key = ArtistImageService.normalizedKey(for: artistName)
        if artistArtwork[key] != nil { return }
        if artistLocked[key] == true { return }
        print("[ArtistAvatar] fetchAutoAvatarIfNeeded - artist=\(artistName), key=\(key)")
        await fetchAutoAvatar(artistName: artistName, force: false)
    }

    private func fetchAutoAvatar(artistName: String, force: Bool) async {
        let key = ArtistImageService.normalizedKey(for: artistName)
        guard !key.isEmpty else { return }
        if !force, artistArtwork[key] != nil { return }
        if isManualAvatar(artistName) { return }
        if artistLocked[key] == true { return }

        await avatarFetchLimiter.withPermit {
            if let data = await artistImageService.imageData(for: artistName) {
                await MainActor.run {
                    print("[ArtistAvatar] fetchAutoAvatar - artist=\(artistName), key=\(key), size=\(data.count)")
                    self.artistAvatarRepository?.upsert(
                        artistKey: key,
                        artistName: artistName,
                        data: data,
                        source: "itunes",
                        isLocked: false
                    )
                    self.artistArtwork[key] = data
                    self.artistArtworkSource[key] = "itunes"
                    self.artistLocked[key] = false
                }
            }
        }
    }

    func fetchAvatarCandidates(artist: String, limit: Int = 100) async -> [ArtistAvatarCandidate] {
        let key = ArtistImageService.normalizedKey(for: artist)
        guard !key.isEmpty else { return [] }
        artistLocked[key] = true
        await MainActor.run {
            artistAvatarRepository?.updateLock(artistKey: key, artistName: artist, isLocked: true)
            print("[ArtistAvatar] updateLock - key=\(key), artist=\(artist)")
        }
        print("[ArtistAvatar] fetchAvatarCandidates - artist=\(artist), key=\(key), limit=\(limit)")
        return await artistImageService.fetchCandidates(artist: artist, limit: limit)
    }

    func applyCandidateAvatar(artist: String, candidate: ArtistAvatarCandidate) async -> Bool {
        let key = ArtistImageService.normalizedKey(for: artist)
        guard !key.isEmpty else { return false }
        print("[ArtistAvatar] applyCandidateAvatar - artist=\(artist), key=\(key), candidate=\(candidate.id)")
        if let data = await artistImageService.fetchImageData(url: candidate.fullsizeURL) {
            await MainActor.run {
                print("[ArtistAvatar] applyCandidateAvatar - save data size=\(data.count)")
                self.artistAvatarRepository?.updateImage(
                    artistKey: key,
                    artistName: artist,
                    data: data,
                    source: "manual",
                    isLocked: true,
                    sourceId: candidate.id
                )
                self.artistArtwork[key] = data
                self.artistArtworkSource[key] = "manual"
                self.artistLocked[key] = true
            }
            return true
        }
        print("[ArtistAvatar] applyCandidateAvatar - failed to download")
        return false
    }

    private func rebuildArtworkCache() {
        var albumMap: [String: Data] = [:]

        for song in songs {
            guard let data = song.artworkData, !data.isEmpty else { continue }

            let albumKey = song.album.trimmingCharacters(in: .whitespacesAndNewlines)
            if !albumKey.isEmpty {
                if let existing = albumMap[albumKey] {
                    if data.count > existing.count {
                        albumMap[albumKey] = data
                    }
                } else {
                    albumMap[albumKey] = data
                }
            }
        }

        albumArtwork = albumMap
    }
}

private actor AvatarFetchLimiter {
    private var permits: Int
    private var waiters: [CheckedContinuation<Void, Never>] = []

    init(limit: Int) {
        self.permits = max(1, limit)
    }

    func withPermit<T>(_ operation: () async -> T) async -> T {
        await acquire()
        defer { release() }
        return await operation()
    }

    private func acquire() async {
        if permits > 0 {
            permits -= 1
            return
        }
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    private func release() {
        if !waiters.isEmpty {
            let continuation = waiters.removeFirst()
            continuation.resume()
        } else {
            permits += 1
        }
    }
}
