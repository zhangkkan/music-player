# MusicPlayer

一个基于 SwiftUI 的本地音乐播放器项目，支持音乐库管理、播放列表、搜索以及播放控制等核心能力，面向 iOS 17+。

## 主要功能
- 音乐库：按歌曲/专辑/艺术家/流派浏览，支持导入本地音频文件与收藏
- 播放控制：顺序/列表循环/单曲循环/随机播放、播放队列管理
- 迷你播放器与正在播放界面
- 均衡器与可视化
- 歌词展示
- 睡眠定时与锁屏/系统控制集成（Now Playing/Remote Command）

## 技术栈
- Swift 5.9 / SwiftUI
- SwiftData（持久化）
- AVFoundation / MediaPlayer
- Xcode 15 / iOS 17

## 目录结构
- `MusicPlayer/App`：App 入口与根视图
- `MusicPlayer/Features`：功能模块（Library/Playlists/NowPlaying/Search/Settings）
- `MusicPlayer/Core`：核心服务、数据模型与音频引擎
- `MusicPlayer/Resources`：资源与资产
- `MusicPlayer/CarPlay`：CarPlay 相关

## 运行项目
1. 使用 Xcode 打开 `MusicPlayer.xcodeproj`
2. 在 Signing & Capabilities 中配置开发者签名
3. 选择 iOS 模拟器或真机运行（iOS 17+）

可选：如需通过 `project.yml` 重新生成工程，请安装 XcodeGen 后运行 `xcodegen`。

## 备注
- 本项目主要围绕本地音频文件播放，导入入口在音乐库页面右上角“+”。
