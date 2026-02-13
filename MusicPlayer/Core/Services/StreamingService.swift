import Foundation

@Observable
final class StreamingService {
    static let shared = StreamingService()

    var isDownloading = false
    var downloadProgress: Double = 0

    private var currentTask: URLSessionDownloadTask?
    private let cacheDir: URL
    private let maxCacheSize: Int64 = 500 * 1024 * 1024 // 500MB

    private init() {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        cacheDir = caches.appendingPathComponent("StreamingCache")
        if !FileManager.default.fileExists(atPath: cacheDir.path) {
            try? FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
        }
    }

    /// Download audio from URL to local cache, returns local file URL
    func download(from remoteURL: URL) async throws -> URL {
        // Check cache first
        let cachedURL = cacheURL(for: remoteURL)
        if FileManager.default.fileExists(atPath: cachedURL.path) {
            return cachedURL
        }

        isDownloading = true
        downloadProgress = 0

        defer { isDownloading = false }

        let (tempURL, response) = try await URLSession.shared.download(from: remoteURL) { [weak self] progress in
            Task { @MainActor in
                self?.downloadProgress = progress
            }
        }

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw StreamingError.downloadFailed("Server returned error")
        }

        // Move to cache
        try? FileManager.default.removeItem(at: cachedURL)
        try FileManager.default.moveItem(at: tempURL, to: cachedURL)

        // Enforce cache size limit
        enforceCacheLimit()

        return cachedURL
    }

    func cancelDownload() {
        currentTask?.cancel()
        currentTask = nil
        isDownloading = false
    }

    func clearCache() {
        try? FileManager.default.removeItem(at: cacheDir)
        try? FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
    }

    func cacheSize() -> Int64 {
        guard let files = FileManager.default.enumerator(at: cacheDir, includingPropertiesForKeys: [.fileSizeKey]) else { return 0 }
        var size: Int64 = 0
        for case let file as URL in files {
            if let attrs = try? file.resourceValues(forKeys: [.fileSizeKey]) {
                size += Int64(attrs.fileSize ?? 0)
            }
        }
        return size
    }

    private func cacheURL(for remoteURL: URL) -> URL {
        let filename = remoteURL.lastPathComponent
        let hash = String(remoteURL.absoluteString.hashValue)
        return cacheDir.appendingPathComponent("\(hash)_\(filename)")
    }

    private func enforceCacheLimit() {
        var currentSize = cacheSize()
        guard currentSize > maxCacheSize else { return }

        guard let files = FileManager.default.enumerator(at: cacheDir, includingPropertiesForKeys: [.contentAccessDateKey, .fileSizeKey]) else { return }

        var fileInfos: [(url: URL, date: Date, size: Int64)] = []
        for case let file as URL in files {
            if let attrs = try? file.resourceValues(forKeys: [.contentAccessDateKey, .fileSizeKey]) {
                fileInfos.append((url: file, date: attrs.contentAccessDate ?? Date.distantPast, size: Int64(attrs.fileSize ?? 0)))
            }
        }

        // Sort by access date (oldest first) for LRU
        fileInfos.sort { $0.date < $1.date }

        for info in fileInfos {
            guard currentSize > maxCacheSize else { break }
            try? FileManager.default.removeItem(at: info.url)
            currentSize -= info.size
        }
    }

    enum StreamingError: Error, LocalizedError {
        case downloadFailed(String)
        case invalidURL

        var errorDescription: String? {
            switch self {
            case .downloadFailed(let msg): return "下载失败: \(msg)"
            case .invalidURL: return "无效的URL"
            }
        }
    }
}

// MARK: - URLSession download with progress

extension URLSession {
    func download(from url: URL, progressHandler: @escaping (Double) -> Void) async throws -> (URL, URLResponse) {
        try await withCheckedThrowingContinuation { continuation in
            let delegate = ProgressDelegate(progressHandler: progressHandler, continuation: continuation)
            let task = self.downloadTask(with: url)
            // Store delegate reference to prevent deallocation
            objc_setAssociatedObject(task, "delegate", delegate, .OBJC_ASSOCIATION_RETAIN)
            task.delegate = delegate
            task.resume()
        }
    }
}

private class ProgressDelegate: NSObject, URLSessionDownloadDelegate {
    let progressHandler: (Double) -> Void
    let continuation: CheckedContinuation<(URL, URLResponse), Error>
    var resumed = false

    init(progressHandler: @escaping (Double) -> Void, continuation: CheckedContinuation<(URL, URLResponse), Error>) {
        self.progressHandler = progressHandler
        self.continuation = continuation
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        guard !resumed else { return }
        resumed = true
        // Copy to temp location since the file at 'location' will be deleted after this method returns
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        do {
            try FileManager.default.copyItem(at: location, to: tempURL)
            continuation.resume(returning: (tempURL, downloadTask.response!))
        } catch {
            continuation.resume(throwing: error)
        }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        if totalBytesExpectedToWrite > 0 {
            let progress = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
            progressHandler(progress)
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error = error, !resumed {
            resumed = true
            continuation.resume(throwing: error)
        }
    }
}
