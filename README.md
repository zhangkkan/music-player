# MusicPlayer

一个基于 SwiftUI 的本地音乐播放器（iOS 17+），面向离线文件播放与管理，覆盖完整的导入、播放、收藏、播放列表、歌词与元数据补全能力。

## 功能特性
- 音乐库
  - 歌曲/专辑/歌手/流派/收藏多维浏览
  - 文件导入（Document Picker / Files）
  - 单击追加到队列并播放；双击替换队列并播放
- 正在播放与队列
  - 迷你播放器 + 全屏 Now Playing
  - 播放队列管理：查看/排序/删除/保存为歌单
  - 播放模式：顺序/列表循环/单曲循环/随机
- 播放列表
  - 歌单创建、添加/移除歌曲
  - 列表页快捷收藏到歌单
  - 队列一键保存为歌单
- 元数据与封面补全
  - iTunes Search + MusicBrainz（无需 API Key）
  - 缺失/可疑字段自动补全，支持强制刷新
  - 同步结果与来源提示
- 歌词自动获取
  - LRCLIB（无 API Key）
  - 导入/播放/手动触发三种入口
  - 仅保存同步歌词（LRC）
- 均衡器与可视化
- 系统集成
  - Now Playing / Remote Command
  - 睡眠定时
- 数据安全
  - 删除仅移除 App 记录，不删除文件本体
  - 歌曲管理页统一清理/管理记录

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

## 开发指南
- 入口与路由：`MusicPlayer/App/ContentView.swift`
- 播放控制：`MusicPlayer/Core/Services/PlaybackService.swift`
- 数据读写：`MusicPlayer/Core/Data/SongRepository.swift`
- 元数据补全：`MusicPlayer/Core/Services/MetadataEnrichmentService.swift`
- 歌词补全：`MusicPlayer/Core/Services/LyricsEnrichmentService.swift`
- 现在播放：`MusicPlayer/Features/NowPlaying`
- 播放列表：`MusicPlayer/Features/Playlists`
- 音乐库：`MusicPlayer/Features/Library`

## 备注
- 本项目面向本地音频文件播放，导入入口在音乐库页面右上角“+”。
