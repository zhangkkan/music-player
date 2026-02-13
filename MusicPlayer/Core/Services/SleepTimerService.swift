import Foundation

@Observable
final class SleepTimerService {
    static let shared = SleepTimerService()

    var isActive = false
    var remainingTime: TimeInterval = 0
    var selectedDuration: TimeInterval = 0

    private var timer: Timer?
    private weak var playbackService: PlaybackService?

    static let presets: [(label: String, duration: TimeInterval)] = [
        ("15 分钟", 15 * 60),
        ("30 分钟", 30 * 60),
        ("45 分钟", 45 * 60),
        ("1 小时", 60 * 60),
        ("1.5 小时", 90 * 60),
        ("2 小时", 120 * 60),
    ]

    private init() {}

    func bind(to playbackService: PlaybackService) {
        self.playbackService = playbackService
    }

    func start(duration: TimeInterval) {
        stop()
        selectedDuration = duration
        remainingTime = duration
        isActive = true

        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            self.remainingTime -= 1
            if self.remainingTime <= 0 {
                self.playbackService?.togglePlayPause()
                self.stop()
            }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        isActive = false
        remainingTime = 0
    }

    var formattedRemaining: String {
        let minutes = Int(remainingTime) / 60
        let seconds = Int(remainingTime) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}
