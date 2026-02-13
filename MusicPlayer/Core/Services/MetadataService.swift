import AVFoundation
import UIKit

struct AudioMetadata {
    var title: String
    var artist: String
    var album: String
    var genre: String
    var duration: TimeInterval
    var sampleRate: Int
    var bitDepth: Int
    var artwork: Data?
    var trackNumber: Int?
    var year: Int?
}

final class MetadataService {
    static let shared = MetadataService()

    private init() {}

    /// Extract metadata from an audio file URL
    func extractMetadata(from url: URL) async -> AudioMetadata {
        let asset = AVAsset(url: url)
        var metadata = AudioMetadata(
            title: url.deletingPathExtension().lastPathComponent,
            artist: "未知艺术家",
            album: "未知专辑",
            genre: "未知",
            duration: 0,
            sampleRate: 44100,
            bitDepth: 16,
            artwork: nil
        )

        // Duration
        if let duration = try? await asset.load(.duration) {
            metadata.duration = CMTimeGetSeconds(duration)
        }

        // Common metadata
        if let items = try? await asset.load(.commonMetadata) {
            for item in items {
                guard let key = item.commonKey else { continue }
                switch key {
                case .commonKeyTitle:
                    if let value = try? await item.load(.stringValue) {
                        metadata.title = value
                    }
                case .commonKeyArtist:
                    if let value = try? await item.load(.stringValue) {
                        metadata.artist = value
                    }
                case .commonKeyAlbumName:
                    if let value = try? await item.load(.stringValue) {
                        metadata.album = value
                    }
                case .commonKeyArtwork:
                    if let data = try? await item.load(.dataValue) {
                        metadata.artwork = data
                    }
                case .commonKeyType:
                    if let value = try? await item.load(.stringValue) {
                        metadata.genre = value
                    }
                default:
                    break
                }
            }
        }

        // Try to get audio format details
        if let tracks = try? await asset.load(.tracks) {
            for track in tracks {
                let mediaType = track.mediaType
                if mediaType == .audio {
                    if let descriptions = try? await track.load(.formatDescriptions) {
                        for desc in descriptions {
                            let audioDesc = CMAudioFormatDescriptionGetStreamBasicDescription(desc)
                            if let asbd = audioDesc?.pointee {
                                metadata.sampleRate = Int(asbd.mSampleRate)
                                metadata.bitDepth = Int(asbd.mBitsPerChannel)
                            }
                        }
                    }
                }
            }
        }

        return metadata
    }

    /// Determine audio format from file extension
    func audioFormat(for url: URL) -> String {
        let ext = url.pathExtension.lowercased()
        switch ext {
        case "flac": return "flac"
        case "wav": return "wav"
        case "m4a", "aac": return "aac"
        case "mp3": return "mp3"
        case "aif", "aiff": return "aiff"
        case "alac": return "alac"
        default: return ext
        }
    }
}
