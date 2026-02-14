import SwiftUI

struct MiniPlayerView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(PlaybackService.self) private var playbackService
    @State private var showPlaylists = false
    @State private var showQueue = false

    var body: some View {
        if let song = playbackService.currentSong {
            VStack(spacing: 0) {
                // Progress bar
                GeometryReader { geometry in
                    Rectangle()
                        .fill(Color.accentColor)
                        .frame(width: geometry.size.width * progress, height: 2)
                }
                .frame(height: 2)

                HStack(spacing: 12) {
                    // Artwork
                    artworkView(song: song)

                    // Song info
                    VStack(alignment: .leading, spacing: 2) {
                        Text(song.title)
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .lineLimit(1)
                        Text(song.artist)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }

                    Spacer()

                    // Favorite
                    Button {
                        let repo = SongRepository(modelContext: modelContext)
                        repo.toggleFavorite(song)
                    } label: {
                        Image(systemName: song.isFavorite ? "heart.fill" : "heart")
                            .font(.title3)
                            .foregroundColor(song.isFavorite ? .red : .secondary)
                    }
                    .buttonStyle(.plain)

                    // Previous button
                    Button {
                        playbackService.playPrevious()
                    } label: {
                        Image(systemName: "backward.fill")
                            .font(.title3)
                            .foregroundColor(.primary)
                    }
                    .buttonStyle(.plain)

                    // Play/Pause button
                    Button {
                        playbackService.togglePlayPause()
                    } label: {
                        Image(systemName: playbackService.isPlaying ? "pause.fill" : "play.fill")
                            .font(.title2)
                            .foregroundColor(.primary)
                    }
                    .buttonStyle(.plain)

                    // Next button
                    Button {
                        playbackService.playNext()
                    } label: {
                        Image(systemName: "forward.fill")
                            .font(.title3)
                            .foregroundColor(.primary)
                    }
                    .buttonStyle(.plain)

                    Button {
                        showQueue = true
                    } label: {
                        Image(systemName: "list.bullet")
                            .font(.title3)
                            .foregroundColor(.primary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
            }
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .shadow(color: .black.opacity(0.1), radius: 8, y: -2)
            .padding(.horizontal, 8)
            .padding(.bottom, 50) // Above tab bar
            .onTapGesture {
                playbackService.showNowPlaying = true
            }
            .sheet(isPresented: $showQueue) {
                NowPlayingQueueView()
            }
        }
    }

    private var progress: Double {
        guard playbackService.duration > 0 else { return 0 }
        return playbackService.currentTime / playbackService.duration
    }

    @ViewBuilder
    private func artworkView(song: Song) -> some View {
        if let artworkData = song.artworkData, let uiImage = UIImage(data: artworkData) {
            Image(uiImage: uiImage)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 48, height: 48)
                .clipShape(RoundedRectangle(cornerRadius: 8))
        } else {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.gray.opacity(0.2))
                .frame(width: 48, height: 48)
                .overlay(
                    Image(systemName: "music.note")
                        .foregroundColor(.gray)
                )
        }
    }
}
