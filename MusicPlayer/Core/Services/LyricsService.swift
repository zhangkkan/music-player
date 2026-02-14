import Foundation

struct LyricLine: Identifiable {
    let id = UUID()
    let timestamp: TimeInterval
    let text: String
}

final class LyricsService {
    static let shared = LyricsService()

    private init() {}

    /// Parse an LRC file into an array of LyricLines
    func parseLRC(from url: URL) -> [LyricLine]? {
        guard let content = readLRCContent(from: url) else { return nil }
        return parseLRC(content: content)
    }

    func parseLRC(content: String) -> [LyricLine] {
        let pattern = #"\[(\d{1,2}):(\d{1,2})(?:[.:](\d{1,3}))?\]"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }

        var lyrics: [LyricLine] = []
        let lines = content.components(separatedBy: .newlines)

        for line in lines {
            let range = NSRange(line.startIndex..<line.endIndex, in: line)
            let matches = regex.matches(in: line, range: range)

            guard !matches.isEmpty else { continue }

            let textStart = matches.last.map { $0.range.location + $0.range.length } ?? 0
            let textIndex = line.index(line.startIndex, offsetBy: min(textStart, line.count))
            let text = String(line[textIndex...]).trimmingCharacters(in: .whitespaces)

            for match in matches {
                guard match.numberOfRanges >= 3,
                      let minRange = Range(match.range(at: 1), in: line),
                      let secRange = Range(match.range(at: 2), in: line) else { continue }

                let minutes = Double(line[minRange]) ?? 0
                let seconds = Double(line[secRange]) ?? 0

                var ms: Double = 0
                if match.numberOfRanges >= 4, match.range(at: 3).location != NSNotFound,
                   let msRange = Range(match.range(at: 3), in: line) {
                    let msString = String(line[msRange])
                    if msString.count == 1 {
                        ms = (Double(msString) ?? 0) * 100
                    } else if msString.count == 2 {
                        ms = (Double(msString) ?? 0) * 10
                    } else {
                        ms = Double(msString) ?? 0
                    }
                }

                let timestamp = minutes * 60 + seconds + ms / 1000
                if !text.isEmpty {
                    lyrics.append(LyricLine(timestamp: timestamp, text: text))
                }
            }
        }

        return lyrics.sorted { $0.timestamp < $1.timestamp }
    }

    private func readLRCContent(from url: URL) -> String? {
        let encodings: [String.Encoding] = [
            .utf8,
            .utf16,
            .utf16LittleEndian,
            .utf16BigEndian,
            .utf32
        ]

        for encoding in encodings {
            if let content = try? String(contentsOf: url, encoding: encoding) {
                return content.trimmingCharacters(in: .newlines)
            }
        }

        let gb18030 = String.Encoding(
            rawValue: CFStringConvertEncodingToNSStringEncoding(
                CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)
            )
        )
        if let content = try? String(contentsOf: url, encoding: gb18030) {
            return content.trimmingCharacters(in: .newlines)
        }

        return nil
    }

    /// Find the current lyric line for the given playback time
    func currentLineIndex(at time: TimeInterval, in lyrics: [LyricLine]) -> Int? {
        guard !lyrics.isEmpty else { return nil }

        for i in stride(from: lyrics.count - 1, through: 0, by: -1) {
            if time >= lyrics[i].timestamp {
                return i
            }
        }
        return nil
    }

    /// Find lyrics file for a song (same name with .lrc extension)
    func findLyricsFile(for songURL: URL) -> URL? {
        let lrcURL = songURL.deletingPathExtension().appendingPathExtension("lrc")
        if FileManager.default.fileExists(atPath: lrcURL.path) {
            return lrcURL
        }

        // Also check in a Lyrics subdirectory
        let dir = songURL.deletingLastPathComponent()
        let lyricsDir = dir.appendingPathComponent("Lyrics")
        let lrcInSubdir = lyricsDir.appendingPathComponent(songURL.deletingPathExtension().lastPathComponent + ".lrc")
        if FileManager.default.fileExists(atPath: lrcInSubdir.path) {
            return lrcInSubdir
        }

        return nil
    }
}
