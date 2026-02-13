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
                await MetadataEnrichmentService.shared.enrich(
                    songID: song.id,
                    repository: songRepository,
                    reason: .importFile
                )
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
