import UIKit
import CarPlay

class CarPlaySceneDelegate: UIResponder, CPTemplateApplicationSceneDelegate {
    var interfaceController: CPInterfaceController?

    func templateApplicationScene(
        _ templateApplicationScene: CPTemplateApplicationScene,
        didConnect interfaceController: CPInterfaceController
    ) {
        self.interfaceController = interfaceController

        let rootTemplate = createRootTemplate()
        interfaceController.setRootTemplate(rootTemplate, animated: true, completion: nil)
    }

    func templateApplicationScene(
        _ templateApplicationScene: CPTemplateApplicationScene,
        didDisconnectInterfaceController interfaceController: CPInterfaceController
    ) {
        self.interfaceController = nil
    }

    // MARK: - Template Creation

    private func createRootTemplate() -> CPTabBarTemplate {
        let libraryTemplate = createLibraryTemplate()
        let playlistsTemplate = createPlaylistsTemplate()

        let tabBar = CPTabBarTemplate(templates: [libraryTemplate, playlistsTemplate])
        return tabBar
    }

    private func createLibraryTemplate() -> CPListTemplate {
        let playbackService = PlaybackService.shared

        // Get all songs from queue (or a default list)
        let songs = playbackService.playQueue
        let items: [CPListItem] = songs.prefix(100).map { song in
            let item = CPListItem(text: song.title, detailText: song.artist)
            item.handler = { [weak self] _, completion in
                playbackService.play(song: song)
                completion()
            }
            return item
        }

        let section = CPListSection(items: items)
        let template = CPListTemplate(title: "音乐库", sections: [section])
        template.tabSystemItem = .favorites
        return template
    }

    private func createPlaylistsTemplate() -> CPListTemplate {
        let template = CPListTemplate(title: "播放列表", sections: [])
        template.tabSystemItem = .more
        return template
    }
}
