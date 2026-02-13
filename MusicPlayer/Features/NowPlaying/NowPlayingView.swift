import SwiftUI

struct NowPlayingView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(PlaybackService.self) private var playbackService
    @State private var viewModel = NowPlayingViewModel()
    @State private var isDragging = false
    @State private var dragTime: TimeInterval = 0

    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                let isCompact = geometry.size.height < 700

                VStack(spacing: isCompact ? 12 : 20) {
                    // Drag indicator
                    Capsule()
                        .fill(Color.secondary.opacity(0.3))
                        .frame(width: 40, height: 5)
                        .padding(.top, 8)

                    if let song = playbackService.currentSong {
                        // Artwork
                        artworkView(song: song, size: isCompact ? 200 : 300)

                        // Song info
                        VStack(spacing: 4) {
                            Text(song.title)
                                .font(.title2)
                                .fontWeight(.bold)
                                .lineLimit(1)
                            Text(song.artist)
                                .font(.body)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                            Text(song.album)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }
                        .padding(.horizontal)

                        // Lyrics / Visualizer toggle area
                        if viewModel.showLyrics {
                            LyricsView(lyrics: viewModel.lyrics,
                                      currentIndex: viewModel.currentLyricIndex)
                                .frame(height: isCompact ? 80 : 120)
                        } else if viewModel.showVisualizer {
                            VisualizerView(spectrumData: playbackService.visualizer.spectrumData)
                                .frame(height: isCompact ? 80 : 120)
                        }

                        Spacer()

                        // Progress bar
                        progressSection

                        // Playback controls
                        controlsSection

                        // Bottom toolbar
                        bottomToolbar(song: song)
                    }
                }
                .padding(.horizontal)
            }
            .background(Color(.systemBackground))
            .onChange(of: playbackService.currentSong?.id) { _, _ in
                if let song = playbackService.currentSong {
                    viewModel.loadLyrics(for: song)
                }
            }
            .onChange(of: playbackService.currentTime) { _, newTime in
                if !isDragging {
                    viewModel.updateLyricIndex(at: newTime)
                }
            }
            .onAppear {
                if let song = playbackService.currentSong {
                    viewModel.loadLyrics(for: song)
                }
                playbackService.visualizer.isActive = viewModel.showVisualizer
            }
            .onDisappear {
                playbackService.visualizer.isActive = false
            }
            .sheet(isPresented: $viewModel.showEqualizer) {
                EqualizerView()
            }
        }
    }

    // MARK: - Artwork

    @ViewBuilder
    private func artworkView(song: Song, size: CGFloat) -> some View {
        if let artworkData = song.artworkData, let uiImage = UIImage(data: artworkData) {
            Image(uiImage: uiImage)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: size, height: size)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .shadow(color: .black.opacity(0.3), radius: 20, y: 10)
        } else {
            RoundedRectangle(cornerRadius: 16)
                .fill(
                    LinearGradient(
                        colors: [.purple.opacity(0.6), .blue.opacity(0.4)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: size, height: size)
                .overlay(
                    Image(systemName: "music.note")
                        .font(.system(size: size * 0.3))
                        .foregroundColor(.white.opacity(0.7))
                )
                .shadow(color: .black.opacity(0.3), radius: 20, y: 10)
        }
    }

    // MARK: - Progress

    private var progressSection: some View {
        VStack(spacing: 4) {
            Slider(
                value: Binding(
                    get: { isDragging ? dragTime : playbackService.currentTime },
                    set: { newValue in
                        isDragging = true
                        dragTime = newValue
                    }
                ),
                in: 0...max(playbackService.duration, 1),
                onEditingChanged: { editing in
                    if !editing {
                        playbackService.seek(to: dragTime)
                        isDragging = false
                    }
                }
            )
            .tint(.accentColor)

            HStack {
                Text(formatTime(isDragging ? dragTime : playbackService.currentTime))
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .monospacedDigit()
                Spacer()
                Text(formatTime(playbackService.duration))
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .monospacedDigit()
            }
        }
        .padding(.horizontal)
    }

    // MARK: - Controls

    private var controlsSection: some View {
        HStack(spacing: 40) {
            // Playback mode
            Button {
                playbackService.cyclePlaybackMode()
            } label: {
                Image(systemName: playbackService.playbackMode.icon)
                    .font(.body)
                    .foregroundColor(playbackService.playbackMode == .sequential ? .secondary : .accentColor)
            }

            // Previous
            Button {
                playbackService.playPrevious()
            } label: {
                Image(systemName: "backward.fill")
                    .font(.title2)
                    .foregroundColor(.primary)
            }

            // Play/Pause
            Button {
                playbackService.togglePlayPause()
            } label: {
                Image(systemName: playbackService.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.system(size: 60))
                    .foregroundColor(.accentColor)
            }

            // Next
            Button {
                playbackService.playNext()
            } label: {
                Image(systemName: "forward.fill")
                    .font(.title2)
                    .foregroundColor(.primary)
            }

            // Volume / Airplay placeholder
            Button {
                // TODO: AirPlay picker
            } label: {
                Image(systemName: "airplayaudio")
                    .font(.body)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 8)
    }

    // MARK: - Bottom Toolbar

    private func bottomToolbar(song: Song) -> some View {
        HStack(spacing: 32) {
            // Favorite
            Button {
                song.isFavorite.toggle()
            } label: {
                Image(systemName: song.isFavorite ? "heart.fill" : "heart")
                    .foregroundColor(song.isFavorite ? .red : .secondary)
            }

            // Lyrics toggle
            Button {
                viewModel.showLyrics.toggle()
                if viewModel.showLyrics { viewModel.showVisualizer = false }
            } label: {
                Image(systemName: "text.quote")
                    .foregroundColor(viewModel.showLyrics ? .accentColor : .secondary)
            }

            // Visualizer toggle
            Button {
                viewModel.showVisualizer.toggle()
                playbackService.visualizer.isActive = viewModel.showVisualizer
                if viewModel.showVisualizer { viewModel.showLyrics = false }
            } label: {
                Image(systemName: "waveform")
                    .foregroundColor(viewModel.showVisualizer ? .accentColor : .secondary)
            }

            // EQ
            Button {
                viewModel.showEqualizer = true
            } label: {
                Image(systemName: "slider.vertical.3")
                    .foregroundColor(.secondary)
            }

            // Metadata Enrich
            Button {
                guard let song = playbackService.currentSong else { return }
                let repo = SongRepository(modelContext: modelContext)
                Task {
                    await MetadataEnrichmentService.shared.enrich(
                        songID: song.id,
                        repository: repo,
                        reason: .manual
                    )
                }
            } label: {
                Image(systemName: "wand.and.stars")
                    .foregroundColor(.secondary)
            }

            // Close
            Button {
                dismiss()
            } label: {
                Image(systemName: "chevron.down")
                    .foregroundColor(.secondary)
            }
        }
        .font(.title3)
        .padding(.bottom, 16)
    }

    private func formatTime(_ seconds: TimeInterval) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", mins, secs)
    }
}
