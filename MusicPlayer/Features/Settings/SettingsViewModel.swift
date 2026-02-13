import SwiftUI

@Observable
final class SettingsViewModel {
    var cacheSize: String = "计算中..."
    var sleepTimer = SleepTimerService.shared
    var showURLInput = false
    var urlText = ""
    var isDownloading = false
    var downloadError: String?

    func calculateCacheSize() {
        let size = StreamingService.shared.cacheSize()
        if size < 1024 * 1024 {
            cacheSize = String(format: "%.1f KB", Double(size) / 1024)
        } else if size < 1024 * 1024 * 1024 {
            cacheSize = String(format: "%.1f MB", Double(size) / (1024 * 1024))
        } else {
            cacheSize = String(format: "%.2f GB", Double(size) / (1024 * 1024 * 1024))
        }
    }

    func clearCache() {
        StreamingService.shared.clearCache()
        calculateCacheSize()
    }

    func downloadFromURL(songRepository: SongRepository) {
        guard let url = URL(string: urlText), url.scheme != nil else {
            downloadError = "请输入有效的URL"
            return
        }

        isDownloading = true
        downloadError = nil

        Task {
            do {
                let localURL = try await StreamingService.shared.download(from: url)
                let metadata = await MetadataService.shared.extractMetadata(from: localURL)
                let format = MetadataService.shared.audioFormat(for: localURL)

                // Copy to music directory
                let musicDir = ImportService.musicDirectory()
                let destURL = musicDir.appendingPathComponent(localURL.lastPathComponent)
                if !FileManager.default.fileExists(atPath: destURL.path) {
                    try FileManager.default.copyItem(at: localURL, to: destURL)
                }

                let song = Song(
                    title: metadata.title,
                    artist: metadata.artist,
                    album: metadata.album,
                    genre: metadata.genre,
                    duration: metadata.duration,
                    fileURL: destURL.path,
                    isRemote: true,
                    format: format,
                    sampleRate: metadata.sampleRate,
                    bitDepth: metadata.bitDepth,
                    artworkData: metadata.artwork
                )

                await MainActor.run {
                    songRepository.add(song)
                    isDownloading = false
                    urlText = ""
                    showURLInput = false
                }
            } catch {
                await MainActor.run {
                    downloadError = error.localizedDescription
                    isDownloading = false
                }
            }
        }
    }
}
