import SwiftUI
import SwiftData

@main
struct MusicPlayerApp: App {
    let modelContainer: ModelContainer

    @State private var playbackService = PlaybackService.shared

    init() {
        do {
            let schema = Schema([Song.self, Playlist.self, PlaylistSong.self, ArtistAvatar.self])
            let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
            modelContainer = try ModelContainer(for: schema, configurations: [config])
            PlaybackService.shared.modelContainer = modelContainer
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(playbackService)
        }
        .modelContainer(modelContainer)
    }
}
