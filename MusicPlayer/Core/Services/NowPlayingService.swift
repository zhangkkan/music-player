import MediaPlayer
import UIKit

final class NowPlayingService {
    private weak var playbackService: PlaybackService?
    private var updateTimer: Timer?

    init(playbackService: PlaybackService) {
        self.playbackService = playbackService
    }

    func update() {
        guard let service = playbackService, let song = service.currentSong else {
            clear()
            return
        }

        var info = [String: Any]()
        info[MPMediaItemPropertyTitle] = song.title
        info[MPMediaItemPropertyArtist] = song.artist
        info[MPMediaItemPropertyAlbumTitle] = song.album
        info[MPMediaItemPropertyPlaybackDuration] = service.duration
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = service.currentTime
        info[MPNowPlayingInfoPropertyPlaybackRate] = service.isPlaying ? 1.0 : 0.0

        if let artworkData = song.artworkData, let image = UIImage(data: artworkData) {
            let artwork = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
            info[MPMediaItemPropertyArtwork] = artwork
        }

        MPNowPlayingInfoCenter.default().nowPlayingInfo = info

        // Start periodic updates for elapsed time
        startPeriodicUpdates()
    }

    func clear() {
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        stopPeriodicUpdates()
    }

    private func startPeriodicUpdates() {
        stopPeriodicUpdates()
        updateTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self = self, let service = self.playbackService, service.isPlaying else { return }
            var info = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
            info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = service.currentTime
            info[MPNowPlayingInfoPropertyPlaybackRate] = 1.0
            MPNowPlayingInfoCenter.default().nowPlayingInfo = info
        }
    }

    private func stopPeriodicUpdates() {
        updateTimer?.invalidate()
        updateTimer = nil
    }

    deinit {
        stopPeriodicUpdates()
    }
}
