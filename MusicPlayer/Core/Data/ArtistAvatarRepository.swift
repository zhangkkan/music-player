import Foundation
import SwiftData

final class ArtistAvatarRepository {
    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func fetchByKeys(_ keys: [String]) -> [ArtistAvatar] {
        guard !keys.isEmpty else { return [] }
        let keySet = Set(keys)
        let descriptor = FetchDescriptor<ArtistAvatar>(
            predicate: #Predicate<ArtistAvatar> { keySet.contains($0.artistKey) }
        )
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    func fetchByKey(_ key: String) -> ArtistAvatar? {
        let descriptor = FetchDescriptor<ArtistAvatar>(
            predicate: #Predicate<ArtistAvatar> { $0.artistKey == key }
        )
        return (try? modelContext.fetch(descriptor))?.first
    }

    func upsert(
        artistKey: String,
        artistName: String,
        data: Data,
        source: String,
        isLocked: Bool,
        sourceId: String? = nil
    ) {
        if let existing = fetchByKey(artistKey) {
            existing.artistName = artistName
            existing.imageData = data
            existing.source = source
            existing.isLocked = isLocked
            existing.sourceId = sourceId
            existing.updatedAt = Date()
        } else {
            let avatar = ArtistAvatar(
                artistKey: artistKey,
                artistName: artistName,
                imageData: data,
                source: source,
                isLocked: isLocked,
                sourceId: sourceId,
                updatedAt: Date()
            )
            modelContext.insert(avatar)
        }
        save()
    }

    func updateLock(artistKey: String, artistName: String, isLocked: Bool) {
        if let existing = fetchByKey(artistKey) {
            existing.isLocked = isLocked
            existing.updatedAt = Date()
        } else {
            let avatar = ArtistAvatar(
                artistKey: artistKey,
                artistName: artistName,
                imageData: nil,
                source: "locked",
                isLocked: isLocked,
                sourceId: nil,
                updatedAt: Date()
            )
            modelContext.insert(avatar)
        }
        save()
    }

    func updateImage(
        artistKey: String,
        artistName: String,
        data: Data,
        source: String,
        isLocked: Bool,
        sourceId: String? = nil
    ) {
        upsert(
            artistKey: artistKey,
            artistName: artistName,
            data: data,
            source: source,
            isLocked: isLocked,
            sourceId: sourceId
        )
        if let item = fetchByKey(artistKey) {
            let size = item.imageData?.count ?? 0
            print("[ArtistAvatar] repo updateImage - key=\(artistKey), size=\(size), source=\(item.source), locked=\(item.isLocked)")
        } else {
            print("[ArtistAvatar] repo updateImage - key=\(artistKey) not found after upsert")
        }
    }

    func clearImage(artistKey: String, artistName: String, source: String, isLocked: Bool) {
        if let existing = fetchByKey(artistKey) {
            existing.artistName = artistName
            existing.imageData = nil
            existing.source = source
            existing.isLocked = isLocked
            existing.updatedAt = Date()
        } else {
            let avatar = ArtistAvatar(
                artistKey: artistKey,
                artistName: artistName,
                imageData: nil,
                source: source,
                isLocked: isLocked,
                sourceId: nil,
                updatedAt: Date()
            )
            modelContext.insert(avatar)
        }
        save()
    }

    func deleteByKeys(_ keys: [String]) {
        guard !keys.isEmpty else { return }
        let keySet = Set(keys)
        let descriptor = FetchDescriptor<ArtistAvatar>(
            predicate: #Predicate<ArtistAvatar> { keySet.contains($0.artistKey) }
        )
        if let items = try? modelContext.fetch(descriptor) {
            for item in items {
                modelContext.delete(item)
            }
            save()
        }
    }

    func deleteByKey(_ key: String) {
        if let item = fetchByKey(key) {
            modelContext.delete(item)
            save()
        }
    }

    private func save() {
        do {
            try modelContext.save()
        } catch {
            print("[ArtistAvatar] repo save error: \(error)")
        }
    }
}
