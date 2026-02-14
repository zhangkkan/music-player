import SwiftUI

@Observable
final class NowPlayingViewModel {
    var showLyrics = false
    var showVisualizer = false
    var showEqualizer = false
    var lyrics: [LyricLine] = []
    var currentLyricIndex: Int?
    var didSetInitialLyrics = false

    private let lyricsService = LyricsService.shared

    func loadLyrics(for song: Song) {
        print("[ViewModel] loadLyrics called for: \(song.title)")
        print("[ViewModel] - lyricsPath from DB: \(song.lyricsPath ?? "nil")")
        print("[ViewModel] - lastLyricsFetchedAt: \(song.lastLyricsFetchedAt?.description ?? "nil")")

        if let lyricsPath = song.lyricsPath {
            print("[ViewModel] - loading from lyricsPath: \(lyricsPath)")
            let url = URL(fileURLWithPath: lyricsPath)
            let parsed = lyricsService.parseLRC(from: url)
            lyrics = parsed ?? []
            print("[ViewModel] - loaded \(lyrics.count) lines from lyricsPath")
        } else {
            print("[ViewModel] - no lyricsPath, trying to find local LRC file")
            let songURL = URL(fileURLWithPath: song.fileURL)
            if let lrcURL = lyricsService.findLyricsFile(for: songURL) {
                print("[ViewModel] - found local LRC file: \(lrcURL.path)")
                let parsed = lyricsService.parseLRC(from: lrcURL)
                lyrics = parsed ?? []
                print("[ViewModel] - loaded \(lyrics.count) lines from local file")
            } else {
                print("[ViewModel] - no local LRC file found, lyrics will be empty")
                lyrics = []
            }
        }
    }

    func updateLyricIndex(at time: TimeInterval) {
        currentLyricIndex = lyricsService.currentLineIndex(at: time, in: lyrics)
    }
}
