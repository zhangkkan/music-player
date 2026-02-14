import AVFoundation
import SwiftData
import MediaPlayer

enum PlaybackMode: String, CaseIterable {
    case sequential = "顺序播放"
    case repeatAll = "列表循环"
    case repeatOne = "单曲循环"
    case shuffle = "随机播放"

    var icon: String {
        switch self {
        case .sequential: return "arrow.right"
        case .repeatAll: return "repeat"
        case .repeatOne: return "repeat.1"
        case .shuffle: return "shuffle"
        }
    }
}

@Observable
final class PlaybackService {
    static let shared = PlaybackService()

    var modelContainer: ModelContainer?

    private let audioEngine = AudioEngine.shared
    private let decoder = FFmpegDecoder()
    let equalizer = EqualizerManager.shared
    let visualizer = AudioVisualizer()

    // Playback state
    var currentSong: Song?
    var playQueue: [Song] = []
    var currentIndex: Int = 0
    var playbackMode: PlaybackMode = .sequential
    var missingFileMessage: String?
    var showNowPlaying: Bool = false

    var isPlaying: Bool { audioEngine.isPlaying }
    var currentTime: TimeInterval { audioEngine.currentTime }
    var duration: TimeInterval { audioEngine.duration }

    private var nowPlayingService: NowPlayingService?
    private var remoteCommandService: RemoteCommandService?
    private var securityScopedURL: URL?

    private init() {
        equalizer.bind(to: audioEngine.eqNode)

        audioEngine.onCompletion { [weak self] in
            self?.handleSongCompletion()
        }

        audioEngine.installVisualizationTap { [weak self] samples in
            self?.visualizer.processAudioData(samples)
        }
    }

    func setupSystemIntegration() {
        nowPlayingService = NowPlayingService(playbackService: self)
        remoteCommandService = RemoteCommandService(playbackService: self)
        remoteCommandService?.setup()
    }

    // MARK: - Play Controls

    func play(song: Song) {
        guard let index = playQueue.firstIndex(where: { $0.id == song.id }) else {
            playQueue = [song]
            currentIndex = 0
            startPlayback(song)
            return
        }
        currentIndex = index
        startPlayback(song)
    }

    func play(songs: [Song], startIndex: Int = 0) {
        guard !songs.isEmpty else { return }
        playQueue = songs
        currentIndex = min(startIndex, songs.count - 1)
        startPlayback(songs[currentIndex])
    }

    func togglePlayPause() {
        if isPlaying {
            audioEngine.pause()
        } else {
            audioEngine.resume()
        }
        nowPlayingService?.update()
    }

    func playNext() {
        guard !playQueue.isEmpty else { return }

        switch playbackMode {
        case .shuffle:
            var nextIndex = Int.random(in: 0..<playQueue.count)
            if playQueue.count > 1 { while nextIndex == currentIndex { nextIndex = Int.random(in: 0..<playQueue.count) } }
            currentIndex = nextIndex
        case .repeatOne:
            break // same index
        default:
            currentIndex = (currentIndex + 1) % playQueue.count
        }

        startPlayback(playQueue[currentIndex])
    }

    func playPrevious() {
        guard !playQueue.isEmpty else { return }

        // If more than 3 seconds into the song, restart it
        if currentTime > 3 {
            seek(to: 0)
            return
        }

        switch playbackMode {
        case .shuffle:
            var prevIndex = Int.random(in: 0..<playQueue.count)
            if playQueue.count > 1 { while prevIndex == currentIndex { prevIndex = Int.random(in: 0..<playQueue.count) } }
            currentIndex = prevIndex
        default:
            currentIndex = (currentIndex - 1 + playQueue.count) % playQueue.count
        }

        startPlayback(playQueue[currentIndex])
    }

    func seek(to time: TimeInterval) {
        audioEngine.seek(to: time)
        nowPlayingService?.update()
    }

    func addToQueue(_ song: Song) {
        playQueue.append(song)
    }

    func enqueueAndPlay(_ song: Song) {
        if let index = playQueue.firstIndex(where: { $0.id == song.id }) {
            currentIndex = index
            startPlayback(playQueue[currentIndex])
            return
        }
        // Append but play the queued instance to avoid detached context issues
        playQueue.append(song)
        currentIndex = playQueue.count - 1
        startPlayback(playQueue[currentIndex])
    }

    func moveQueue(from source: IndexSet, to destination: Int) {
        let currentID = currentSong?.id
        playQueue.move(fromOffsets: source, toOffset: destination)
        if let currentID = currentID, let newIndex = playQueue.firstIndex(where: { $0.id == currentID }) {
            currentIndex = newIndex
        }
    }

    func removeFromQueue(at index: Int) {
        guard index >= 0, index < playQueue.count else { return }
        playQueue.remove(at: index)
        if index < currentIndex {
            currentIndex -= 1
        } else if index == currentIndex {
            if playQueue.isEmpty {
                stop()
            } else {
                currentIndex = min(currentIndex, playQueue.count - 1)
                startPlayback(playQueue[currentIndex])
            }
        }
    }

    func removeFromQueue(songID: UUID) {
        if let index = playQueue.firstIndex(where: { $0.id == songID }) {
            removeFromQueue(at: index)
        }
    }

    func cyclePlaybackMode() {
        let modes = PlaybackMode.allCases
        guard let currentModeIndex = modes.firstIndex(of: playbackMode) else { return }
        playbackMode = modes[(currentModeIndex + 1) % modes.count]
    }

    func stop() {
        audioEngine.stop()
        currentSong = nil
        stopSecurityScopedAccess()
        nowPlayingService?.clear()
    }

    // MARK: - Private

    private func startPlayback(_ song: Song) {
        currentSong = song
        stopSecurityScopedAccess()

        // Increment play count
        song.playCount += 1
        song.lastPlayedAt = Date()

        let url = resolvedURL(for: song)

        Task {
            do {
                if FFmpegDecoder.requiresDecoding(url) {
                    let (buffers, format) = try await decoder.decodeToPCMBuffers(input: url)
                    try audioEngine.play(buffers: buffers, format: format)
                } else {
                    try audioEngine.play(url: url)
                }
                await MainActor.run {
                    self.nowPlayingService?.update()
                }
                if let container = self.modelContainer {
                    let repo = SongRepository(modelContext: ModelContext(container))
                    Task {
                        await MetadataEnrichmentService.shared.enrich(
                            songID: song.id,
                            repository: repo,
                            reason: .playback
                        )
                        await LyricsEnrichmentService.shared.enrich(
                            songID: song.id,
                            repository: repo,
                            reason: .playback
                        )
                    }
                }
            } catch {
                print("Playback error: \(error)")
                if isFileMissing(error) {
                    await MainActor.run {
                        self.handleMissingFile(song)
                    }
                } else {
                    // Try next song on failure
                    handleSongCompletion()
                }
            }
        }
    }

    private func handleSongCompletion() {
        switch playbackMode {
        case .repeatOne:
            if let song = currentSong {
                startPlayback(song)
            }
        case .sequential:
            if currentIndex < playQueue.count - 1 {
                currentIndex += 1
                startPlayback(playQueue[currentIndex])
            } else {
                stop()
            }
        case .repeatAll:
            currentIndex = (currentIndex + 1) % playQueue.count
            startPlayback(playQueue[currentIndex])
        case .shuffle:
            playNext()
        }
    }

    private func resolvedURL(for song: Song) -> URL {
        let url = URL(fileURLWithPath: song.fileURL)
        if let bookmark = song.fileBookmark {
            var isStale = false
            if let scopedURL = try? URL(resolvingBookmarkData: bookmark,
                                        options: [.withoutUI],
                                        relativeTo: nil,
                                        bookmarkDataIsStale: &isStale) {
                securityScopedURL = scopedURL
                _ = scopedURL.startAccessingSecurityScopedResource()
                return scopedURL
            }
        }
        return url
    }

    private func stopSecurityScopedAccess() {
        if let scopedURL = securityScopedURL {
            scopedURL.stopAccessingSecurityScopedResource()
            securityScopedURL = nil
        }
    }

    private func isFileMissing(_ error: Error) -> Bool {
        if let audioError = error as? AudioEngineError, audioError == .fileNotFound {
            return true
        }
        if let decoderError = error as? FFmpegDecoder.DecoderError, decoderError == .fileNotFound {
            return true
        }
        let nsError = error as NSError
        return nsError.domain == NSCocoaErrorDomain && nsError.code == NSFileNoSuchFileError
    }

    private func handleMissingFile(_ song: Song) {
        missingFileMessage = "文件已失效或无法访问，请重新导入。"
        if let index = playQueue.firstIndex(where: { $0.id == song.id }) {
            playQueue.remove(at: index)
            if currentIndex >= playQueue.count {
                currentIndex = max(0, playQueue.count - 1)
            }
        }
        if currentSong?.id == song.id {
            stop()
        }
        deleteSongRecord(song)
    }

    private func deleteSongRecord(_ song: Song) {
        guard let container = modelContainer else { return }
        let context = ModelContext(container)
        let songID = song.id
        let descriptor = FetchDescriptor<Song>(predicate: #Predicate { $0.id == songID })
        if let existing = try? context.fetch(descriptor).first {
            context.delete(existing)
        } else {
            context.delete(song)
        }
        try? context.save()
    }
}
