import AVFoundation
import Accelerate

@Observable
final class AudioVisualizer {
    var spectrumData: [Float] = Array(repeating: 0, count: 32)
    var waveformData: [Float] = []
    var isActive = false

    private let fftSize = 1024
    private var fftSetup: vDSP_DFT_Setup?

    init() {
        fftSetup = vDSP_DFT_zop_CreateSetup(nil, vDSP_Length(fftSize), .FORWARD)
    }

    func processAudioData(_ samples: [Float]) {
        guard isActive else { return }

        // Waveform: downsample to 64 points
        let step = max(1, samples.count / 64)
        waveformData = stride(from: 0, to: samples.count, by: step).map { samples[$0] }

        // Spectrum: FFT analysis
        guard samples.count >= fftSize, let setup = fftSetup else { return }

        var realInput = Array(samples.prefix(fftSize))
        var imagInput = [Float](repeating: 0, count: fftSize)
        var realOutput = [Float](repeating: 0, count: fftSize)
        var imagOutput = [Float](repeating: 0, count: fftSize)

        // Apply Hanning window
        var window = [Float](repeating: 0, count: fftSize)
        vDSP_hann_window(&window, vDSP_Length(fftSize), Int32(vDSP_HANN_NORM))
        vDSP_vmul(realInput, 1, window, 1, &realInput, 1, vDSP_Length(fftSize))

        // Perform FFT
        vDSP_DFT_Execute(setup, realInput, imagInput, &realOutput, &imagOutput)

        // Calculate magnitudes (only first half is useful)
        let halfSize = fftSize / 2
        var magnitudes = [Float](repeating: 0, count: halfSize)
        for i in 0..<halfSize {
            magnitudes[i] = sqrt(realOutput[i] * realOutput[i] + imagOutput[i] * imagOutput[i])
        }

        // Convert to dB and normalize
        var dbValues = [Float](repeating: 0, count: halfSize)
        var one: Float = 1.0
        vDSP_vdbcon(magnitudes, 1, &one, &dbValues, 1, vDSP_Length(halfSize), 0)

        // Map to 32 frequency bands (logarithmic spacing)
        let bandCount = 32
        var bands = [Float](repeating: 0, count: bandCount)
        for i in 0..<bandCount {
            let startBin = Int(pow(Float(halfSize), Float(i) / Float(bandCount)))
            let endBin = Int(pow(Float(halfSize), Float(i + 1) / Float(bandCount)))
            let clampedStart = max(0, min(startBin, halfSize - 1))
            let clampedEnd = max(clampedStart + 1, min(endBin, halfSize))
            let slice = dbValues[clampedStart..<clampedEnd]
            bands[i] = slice.isEmpty ? -160 : slice.reduce(0, +) / Float(slice.count)
        }

        // Normalize to 0...1 range
        let minDB: Float = -60
        let maxDB: Float = 0
        spectrumData = bands.map { max(0, min(1, ($0 - minDB) / (maxDB - minDB))) }
    }

    deinit {
        if let setup = fftSetup {
            vDSP_DFT_DestroySetup(setup)
        }
    }
}
