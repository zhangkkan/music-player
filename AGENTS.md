# 项目指引（AGENTS）

## 项目概览
- iOS SwiftUI 音乐播放器，核心代码在 `MusicPlayer/`。
- 采用 SwiftData 持久化，播放引擎位于 `MusicPlayer/Core/Audio`，业务服务位于 `MusicPlayer/Core/Services`。

## 开发约定
- 语言：Swift 5.9；UI：SwiftUI；数据：SwiftData。
- 结构：保持 `Features` 下的模块化视图 + ViewModel 组织方式。
- 只在必要时调整 `MusicPlayer.xcodeproj`；常规代码修改集中在 `MusicPlayer/`。
- 新功能优先复用 `Core/Services` 与 `Core/Data`，避免在 View 中堆积业务逻辑。

## 常用入口
- 应用入口：`MusicPlayer/App/MusicPlayerApp.swift`
- 根视图：`MusicPlayer/App/ContentView.swift`
- 音频播放：`MusicPlayer/Core/Services/PlaybackService.swift`

## 运行与构建
- 用 Xcode 打开 `MusicPlayer.xcodeproj`，配置签名后运行（iOS 17+）。
- 如需通过 `project.yml` 重新生成工程，请使用 XcodeGen 运行 `xcodegen`。

## 说明
- 本仓库当前未提供自动化测试配置；如添加测试，请在 `MusicPlayer` 下新增对应测试目标并补充文档。
