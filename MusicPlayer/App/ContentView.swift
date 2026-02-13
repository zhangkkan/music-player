import SwiftUI

struct ContentView: View {
    @Environment(PlaybackService.self) private var playbackService

    var body: some View {
        ZStack(alignment: .bottom) {
            TabView {
                LibraryView()
                    .tabItem {
                        Label("音乐库", systemImage: "music.note.house")
                    }

                PlaylistsView()
                    .tabItem {
                        Label("播放列表", systemImage: "music.note.list")
                    }

                SearchView()
                    .tabItem {
                        Label("搜索", systemImage: "magnifyingglass")
                    }

                SettingsView()
                    .tabItem {
                        Label("设置", systemImage: "gearshape")
                    }
            }

            if playbackService.currentSong != nil {
                MiniPlayerView()
                    .transition(.move(edge: .bottom))
            }
        }
        .alert("文件已失效", isPresented: Binding(
            get: { playbackService.missingFileMessage != nil },
            set: { if !$0 { playbackService.missingFileMessage = nil } }
        )) {
            Button("知道了", role: .cancel) {}
        } message: {
            Text(playbackService.missingFileMessage ?? "文件已失效，请重新导入。")
        }
    }
}
