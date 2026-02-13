import Foundation

enum LyricsSourceOption: String, CaseIterable, Identifiable {
    case lrclib
    case localOnly

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .lrclib:
            return "LRCLIB"
        case .localOnly:
            return "仅本地 LRC"
        }
    }
}

enum EnrichmentSettings {
    private static let lyricsSourceKey = "enrichment.lyrics.source"
    private static let thresholdKey = "enrichment.correction.threshold"
    private static let cacheHoursKey = "enrichment.cache.hours"

    static var lyricsSource: LyricsSourceOption {
        get {
            let raw = UserDefaults.standard.string(forKey: lyricsSourceKey) ?? LyricsSourceOption.lrclib.rawValue
            return LyricsSourceOption(rawValue: raw) ?? .lrclib
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: lyricsSourceKey)
        }
    }

    static var correctionThreshold: Double {
        get {
            let value = UserDefaults.standard.double(forKey: thresholdKey)
            return value == 0 ? 0.8 : value
        }
        set {
            UserDefaults.standard.set(min(max(newValue, 0.5), 1.0), forKey: thresholdKey)
        }
    }

    static var cacheHours: Double {
        get {
            let value = UserDefaults.standard.double(forKey: cacheHoursKey)
            return value == 0 ? 24 : value
        }
        set {
            UserDefaults.standard.set(min(max(newValue, 1), 168), forKey: cacheHoursKey)
        }
    }

    static var cacheInterval: TimeInterval {
        cacheHours * 60 * 60
    }
}
