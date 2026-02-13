import SwiftUI

@Observable
final class NowPlayingViewModel {
    var showLyrics = false
    var showVisualizer = false
    var showEqualizer = false
    var lyrics: [LyricLine] = []
    var currentLyricIndex: Int?

    private let lyricsService = LyricsService.shared

    func loadLyrics(for song: Song) {
        if let lyricsPath = song.lyricsPath {
            let url = URL(fileURLWithPath: lyricsPath)
            lyrics = lyricsService.parseLRC(from: url) ?? []
        } else {
            let songURL = URL(fileURLWithPath: song.fileURL)
            if let lrcURL = lyricsService.findLyricsFile(for: songURL) {
                lyrics = lyricsService.parseLRC(from: lrcURL) ?? []
            } else {
                lyrics = []
            }
        }
    }

    func updateLyricIndex(at time: TimeInterval) {
        currentLyricIndex = lyricsService.currentLineIndex(at: time, in: lyrics)
    }
}
