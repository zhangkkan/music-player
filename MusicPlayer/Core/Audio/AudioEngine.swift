import AVFoundation
import Combine

enum AudioEngineError: Error {
    case fileNotFound
    case unsupportedFormat
    case engineSetupFailed
    case decodingFailed(String)
}

@Observable
final class AudioEngine {
    static let shared = AudioEngine()

    private let engine = AVAudioEngine()
    private let playerNode = AVAudioPlayerNode()
    private(set) var eqNode: AVAudioUnitEQ
    private let mixerNode = AVAudioMixerNode()

    private(set) var isPlaying = false
    private(set) var currentTime: TimeInterval = 0
    private(set) var duration: TimeInterval = 0

    private var audioFile: AVAudioFile?
    private var displayLink: CADisplayLink?
    private var seekFrame: AVAudioFramePosition = 0
    private var audioSampleRate: Double = 44100
    private var audioLengthFrames: AVAudioFramePosition = 0

    private var visualizationHandler: (([Float]) -> Void)?
    private var completionHandler: (() -> Void)?

    // Buffer scheduling for decoded audio (FLAC etc.)
    private var pcmBuffers: [AVAudioPCMBuffer] = []
    private var isBufferMode = false
    private var currentBufferIndex = 0

    init() {
        eqNode = AVAudioUnitEQ(numberOfBands: 10)
        setupEQBands()
        setupEngine()
        setupAudioSession()
    }

    private func setupAudioSession() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playback, mode: .default, options: [.allowBluetooth, .allowAirPlay])
            try session.setActive(true)
        } catch {
            print("Audio session setup failed: \(error)")
        }

        NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            self?.handleInterruption(notification)
        }
    }

    private func setupEngine() {
        engine.attach(playerNode)
        engine.attach(eqNode)
        engine.attach(mixerNode)

        // Node chain: playerNode → eqNode → mixerNode → output
        let format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 2)!
        engine.connect(playerNode, to: eqNode, format: format)
        engine.connect(eqNode, to: mixerNode, format: format)
        engine.connect(mixerNode, to: engine.outputNode, format: format)

        engine.prepare()
    }

    private func setupEQBands() {
        let frequencies: [Float] = [32, 64, 125, 250, 500, 1000, 2000, 4000, 8000, 16000]
        for (index, freq) in frequencies.enumerated() {
            let band = eqNode.bands[index]
            band.filterType = .parametric
            band.frequency = freq
            band.bandwidth = 1.0
            band.gain = 0.0
            band.bypass = false
        }
    }

    // MARK: - Play AVAudioFile (native formats: MP3, AAC, ALAC, WAV)

    func play(url: URL) throws {
        stop()
        isBufferMode = false

        let file = try AVAudioFile(forReading: url)
        audioFile = file

        audioSampleRate = file.processingFormat.sampleRate
        audioLengthFrames = file.length
        duration = Double(audioLengthFrames) / audioSampleRate

        // Reconnect with correct format
        engine.disconnectNodeOutput(playerNode)
        engine.disconnectNodeOutput(eqNode)
        engine.disconnectNodeOutput(mixerNode)
        engine.connect(playerNode, to: eqNode, format: file.processingFormat)
        engine.connect(eqNode, to: mixerNode, format: file.processingFormat)
        engine.connect(mixerNode, to: engine.outputNode, format: file.processingFormat)

        if !engine.isRunning {
            try engine.start()
        }

        playerNode.scheduleFile(file, at: nil) { [weak self] in
            DispatchQueue.main.async {
                self?.handlePlaybackCompletion()
            }
        }
        playerNode.play()
        isPlaying = true
        startTimeTracking()
    }

    // MARK: - Play PCM Buffers (decoded formats: FLAC via FFmpeg)

    func play(buffers: [AVAudioPCMBuffer], format: AVAudioFormat) throws {
        stop()
        isBufferMode = true
        pcmBuffers = buffers
        currentBufferIndex = 0

        // Calculate total duration
        let totalFrames = buffers.reduce(AVAudioFramePosition(0)) { $0 + AVAudioFramePosition($1.frameLength) }
        audioSampleRate = format.sampleRate
        audioLengthFrames = totalFrames
        duration = Double(totalFrames) / format.sampleRate

        // Reconnect with correct format
        engine.disconnectNodeOutput(playerNode)
        engine.disconnectNodeOutput(eqNode)
        engine.disconnectNodeOutput(mixerNode)
        engine.connect(playerNode, to: eqNode, format: format)
        engine.connect(eqNode, to: mixerNode, format: format)
        engine.connect(mixerNode, to: engine.outputNode, format: format)

        if !engine.isRunning {
            try engine.start()
        }

        scheduleNextBuffers()
        playerNode.play()
        isPlaying = true
        startTimeTracking()
    }

    private func scheduleNextBuffers() {
        let buffersToSchedule = min(3, pcmBuffers.count - currentBufferIndex)
        guard buffersToSchedule > 0 else { return }

        for i in 0..<buffersToSchedule {
            let index = currentBufferIndex + i
            guard index < pcmBuffers.count else { break }
            let isLast = index == pcmBuffers.count - 1

            playerNode.scheduleBuffer(pcmBuffers[index]) { [weak self] in
                guard let self = self else { return }
                if isLast {
                    DispatchQueue.main.async {
                        self.handlePlaybackCompletion()
                    }
                }
            }
        }
        currentBufferIndex += buffersToSchedule
    }

    // MARK: - Transport Controls

    func pause() {
        playerNode.pause()
        isPlaying = false
        stopTimeTracking()
    }

    func resume() {
        playerNode.play()
        isPlaying = true
        startTimeTracking()
    }

    func stop() {
        playerNode.stop()
        playerNode.reset()
        isPlaying = false
        currentTime = 0
        seekFrame = 0
        audioFile = nil
        pcmBuffers = []
        stopTimeTracking()
    }

    func seek(to time: TimeInterval) {
        guard !isBufferMode else { return } // Seek only supported for file mode
        guard let file = audioFile else { return }

        let targetFrame = AVAudioFramePosition(time * audioSampleRate)
        let clampedFrame = max(0, min(targetFrame, audioLengthFrames))

        playerNode.stop()
        playerNode.reset()

        file.framePosition = clampedFrame
        seekFrame = clampedFrame
        currentTime = time

        let remainingFrames = AVAudioFrameCount(audioLengthFrames - clampedFrame)
        guard remainingFrames > 0 else {
            handlePlaybackCompletion()
            return
        }

        playerNode.scheduleSegment(
            file,
            startingFrame: clampedFrame,
            frameCount: remainingFrames,
            at: nil
        ) { [weak self] in
            DispatchQueue.main.async {
                self?.handlePlaybackCompletion()
            }
        }

        if isPlaying {
            playerNode.play()
        }
    }

    // MARK: - Visualization

    func installVisualizationTap(handler: @escaping ([Float]) -> Void) {
        visualizationHandler = handler
        let bufferSize: AVAudioFrameCount = 1024
        mixerNode.installTap(onBus: 0, bufferSize: bufferSize, format: nil) { [weak self] buffer, _ in
            guard let self = self, let channelData = buffer.floatChannelData else { return }
            let frames = Int(buffer.frameLength)
            var samples = [Float](repeating: 0, count: frames)
            for i in 0..<frames {
                samples[i] = channelData[0][i]
            }
            DispatchQueue.main.async {
                self.visualizationHandler?(samples)
            }
        }
    }

    func removeVisualizationTap() {
        mixerNode.removeTap(onBus: 0)
        visualizationHandler = nil
    }

    // MARK: - Completion

    func onCompletion(_ handler: @escaping () -> Void) {
        completionHandler = handler
    }

    private func handlePlaybackCompletion() {
        guard isPlaying else { return }
        isPlaying = false
        stopTimeTracking()
        completionHandler?()
    }

    // MARK: - Time Tracking

    private func startTimeTracking() {
        stopTimeTracking()
        displayLink = CADisplayLink(target: self, selector: #selector(updateTime))
        displayLink?.preferredFrameRateRange = CAFrameRateRange(minimum: 10, maximum: 30)
        displayLink?.add(to: .main, forMode: .common)
    }

    private func stopTimeTracking() {
        displayLink?.invalidate()
        displayLink = nil
    }

    @objc private func updateTime() {
        guard isPlaying, let nodeTime = playerNode.lastRenderTime,
              let playerTime = playerNode.playerTime(forNodeTime: nodeTime) else { return }
        currentTime = Double(seekFrame + playerTime.sampleTime) / audioSampleRate
    }

    // MARK: - Interruption Handling

    private func handleInterruption(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue) else { return }

        switch type {
        case .began:
            pause()
        case .ended:
            guard let optionsValue = userInfo[AVAudioSessionInterruptionOptionKey] as? UInt else { return }
            let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue)
            if options.contains(.shouldResume) {
                resume()
            }
        @unknown default:
            break
        }
    }

    deinit {
        stopTimeTracking()
        engine.stop()
        NotificationCenter.default.removeObserver(self)
    }
}
