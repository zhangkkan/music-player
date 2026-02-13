import SwiftUI
import UniformTypeIdentifiers

struct DocumentPicker: UIViewControllerRepresentable {
    let contentTypes: [UTType]
    let onPick: ([URL]) -> Void

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: contentTypes, asCopy: true)
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

        let musicDir = Self.musicDirectory()
        var songs: [Song] = []

        for (index, url) in urls.enumerated() {
            let destURL = musicDir.appendingPathComponent(url.lastPathComponent)

            // Copy file to sandbox if not already there
            if !FileManager.default.fileExists(atPath: destURL.path) {
                do {
                    try FileManager.default.copyItem(at: url, to: destURL)
                } catch {
                    print("Failed to copy \(url.lastPathComponent): \(error)")
                    continue
                }
            }

            // Extract metadata
            let metadata = await metadataService.extractMetadata(from: destURL)
            let format = metadataService.audioFormat(for: destURL)

            // Check for LRC lyrics file
            let lrcURL = url.deletingPathExtension().appendingPathExtension("lrc")
            var lyricsPath: String?
            if FileManager.default.fileExists(atPath: lrcURL.path) {
                let lrcDest = musicDir.appendingPathComponent(lrcURL.lastPathComponent)
                try? FileManager.default.copyItem(at: lrcURL, to: lrcDest)
                lyricsPath = lrcDest.path
            }

            let song = Song(
                title: metadata.title,
                artist: metadata.artist,
                album: metadata.album,
                genre: metadata.genre,
                duration: metadata.duration,
                fileURL: destURL.path,
                isRemote: false,
                format: format,
                sampleRate: metadata.sampleRate,
                bitDepth: metadata.bitDepth,
                artworkData: metadata.artwork,
                lyricsPath: lyricsPath
            )

            songRepository.add(song)
            songs.append(song)

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
