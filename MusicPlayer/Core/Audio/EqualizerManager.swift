import AVFoundation
import Foundation

@Observable
final class EqualizerManager {
    static let shared = EqualizerManager()

    let frequencies: [Float] = [32, 64, 125, 250, 500, 1000, 2000, 4000, 8000, 16000]
    let frequencyLabels = ["32", "64", "125", "250", "500", "1K", "2K", "4K", "8K", "16K"]

    var gains: [Float] = Array(repeating: 0, count: 10) {
        didSet { applyGains() }
    }
    var currentPreset: EQPreset = .flat
    var isEnabled: Bool = true {
        didSet { updateBypass() }
    }

    private weak var eqNode: AVAudioUnitEQ?

    enum EQPreset: String, CaseIterable, Identifiable {
        case flat = "平直"
        case pop = "流行"
        case rock = "摇滚"
        case classical = "古典"
        case jazz = "爵士"
        case vocal = "人声"
        case custom = "自定义"

        var id: String { rawValue }

        var gains: [Float] {
            switch self {
            case .flat:      return [0, 0, 0, 0, 0, 0, 0, 0, 0, 0]
            case .pop:       return [2, 3, 1, 0, -1, -1, 0, 1, 2, 3]
            case .rock:      return [4, 3, 1, 0, -1, -2, 0, 2, 3, 4]
            case .classical: return [0, 0, 0, 0, 0, 0, -1, -2, -2, -4]
            case .jazz:      return [3, 2, 1, 2, -1, -1, 0, 1, 2, 3]
            case .vocal:     return [-2, -1, 0, 1, 3, 4, 3, 1, 0, -1]
            case .custom:    return UserDefaults.standard.array(forKey: "customEQ") as? [Float] ?? Array(repeating: 0, count: 10)
            }
        }
    }

    func bind(to eqNode: AVAudioUnitEQ) {
        self.eqNode = eqNode
        applyGains()
    }

    func applyPreset(_ preset: EQPreset) {
        currentPreset = preset
        gains = preset.gains
    }

    func adjustBand(_ index: Int, gain: Float) {
        guard index >= 0, index < 10 else { return }
        gains[index] = max(-12, min(12, gain))
        currentPreset = .custom
    }

    func saveCustomPreset() {
        UserDefaults.standard.set(gains, forKey: "customEQ")
    }

    func reset() {
        applyPreset(.flat)
    }

    private func applyGains() {
        guard let eqNode = eqNode else { return }
        for (index, gain) in gains.enumerated() where index < eqNode.bands.count {
            eqNode.bands[index].gain = gain
        }
    }

    private func updateBypass() {
        guard let eqNode = eqNode else { return }
        eqNode.bypass = !isEnabled
    }
}
