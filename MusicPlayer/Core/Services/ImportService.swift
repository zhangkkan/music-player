import SwiftUI
import UniformTypeIdentifiers

struct DocumentPicker: UIViewControllerRepresentable {
    let contentTypes: [UTType]
    let onPick: ([URL]) -> Void

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: contentTypes, asCopy: false)
        picker.allowsMultipleSelection = true
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onPick: onPick)
    }

    class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onPick: ([URL]) -> Void

        init(onPick: @escaping ([URL]) -> Void) {
            self.onPick = onPick
        }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            onPick(urls)
        }
    }
}

@Observable
final class ImportService {
    static let shared = ImportService()

    var isImporting = false
    var importProgress: Double = 0
    var importedCount = 0

    private let metadataService = MetadataService.shared

    static let supportedTypes: [UTType] = [
        .mp3, .wav, .aiff, .audio,
        UTType(filenameExtension: "flac") ?? .audio,
        UTType(filenameExtension: "m4a") ?? .audio,
        UTType(filenameExtension: "aac") ?? .audio,
        UTType(filenameExtension: "alac") ?? .audio,
    ]

    private init() {}

    /// Import audio files: copy to app sandbox and create Song entries
    func importFiles(_ urls: [URL], songRepository: SongRepository) async -> [Song] {
        isImporting = true
        importedCount = 0
        importProgress = 0

        var songs: [Song] = []

        for (index, url) in urls.enumerated() {
            let hasAccess = url.startAccessingSecurityScopedResource()
            defer {
                if hasAccess {
                    url.stopAccessingSecurityScopedResource()
                }
            }

            if !hasAccess {
                print("No permission to access \(url.lastPathComponent)")
            }

            if songRepository.fetchByFileURL(url.path) != nil {
                print("Skip import (already exists): \(url.lastPathComponent)")
                continue
            }

            // Extract metadata
            let metadata = await metadataService.extractMetadata(from: url)
            let format = metadataService.audioFormat(for: url)

            // Check for LRC lyrics file
            let lrcURL = url.deletingPathExtension().appendingPathExtension("lrc")
            var lyricsPath: String?
            if FileManager.default.fileExists(atPath: lrcURL.path) {
                lyricsPath = lrcURL.path
            }

            let bookmark = try? url.bookmarkData(
                options: .minimalBookmark,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )

            let song = Song(
                title: metadata.title,
                artist: metadata.artist,
                album: metadata.album,
                genre: metadata.genre,
                duration: metadata.duration,
                fileURL: url.path,
                isRemote: false,
                format: format,
                sampleRate: metadata.sampleRate,
                bitDepth: metadata.bitDepth,
                artworkData: metadata.artwork,
                fileBookmark: bookmark,
                lyricsPath: lyricsPath
            )

            songRepository.add(song)
            songs.append(song)

            Task {
                // 先执行元数据增强，等待完成
                await MetadataEnrichmentService.shared.enrich(
                    songID: song.id,
                    repository: songRepository,
                    reason: .importFile
                )

                // 等待一小段时间，确保数据库持久化完成
                try? await Task.sleep(nanoseconds: 500_000_000) // 0.5秒延迟

                // 重新获取歌曲对象，确保使用最新的元数据（简体歌名）
                if let updatedSong = songRepository.fetchById(song.id),
                   let lastEnrichedAt = updatedSong.lastEnrichedAt {
                    // 确认元数据增强已完成
                    print("[Import] Metadata enrichment confirmed for \(song.id) at \(lastEnrichedAt)")

                    // 现在开始查询歌词，使用最新的简体歌名
                    await LyricsEnrichmentService.shared.enrich(
                        songID: song.id,
                        repository: songRepository,
                        reason: .importFile
                    )
                } else {
                    print("[Import] WARNING: Metadata enrichment may not have completed for \(song.id)")
                    // 即使元数据增强可能未完成，也尝试查询歌词（作为降级方案）
                    await LyricsEnrichmentService.shared.enrich(
                        songID: song.id,
                        repository: songRepository,
                        reason: .importFile
                    )
                }
            }

            importedCount = index + 1
            importProgress = Double(index + 1) / Double(urls.count)
        }

        isImporting = false
        return songs
    }

    static func musicDirectory() -> URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let musicDir = docs.appendingPathComponent("Music")
        if !FileManager.default.fileExists(atPath: musicDir.path) {
            try? FileManager.default.createDirectory(at: musicDir, withIntermediateDirectories: true)
        }
        return musicDir
    }
}
