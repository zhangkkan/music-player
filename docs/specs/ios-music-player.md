# iOS 无损音乐播放器 - 实施计划

## 概述
从零构建一个 SwiftUI iOS 17+ 音乐播放器，使用 FFmpeg-Kit 解码无损音频（FLAC/WAV/ALAC），支持本地导入与 URL 流媒体播放、EQ 均衡器、歌词显示、音频可视化、CarPlay 等全功能。

## 技术决策
- **架构**: MVVM + @Observable (iOS 17)
- **UI框架**: SwiftUI, 最低 iOS 17+
- **音频引擎**: AVAudioEngine + AVAudioPlayerNode（支持EQ节点链和可视化采样）
- **多格式解码**: FFmpeg-Kit（SPM 集成，支持 FLAC/APE/DSD 等几乎所有格式）
- **原生格式**: AVAudioFile 直接播放 MP3/AAC/ALAC/WAV
- **数据持久化**: SwiftData（iOS 17 原生，替代 Core Data）
- **项目生成**: XcodeGen（从 project.yml 生成 .xcodeproj）
- **包管理**: Swift Package Manager

## 音频播放策略
```
原生格式 (MP3/AAC/ALAC/WAV):
  AVAudioFile → AVAudioPlayerNode → AVAudioUnitEQ → MixerNode(tap) → Output

非原生格式 (FLAC/APE/DSD等):
  FFmpeg-Kit 解码 → PCM AVAudioPCMBuffer → AVAudioPlayerNode → EQ → Mixer → Output
```

## 项目结构
```
music-player/
├── project.yml                            # XcodeGen 项目配置
├── Package.swift                          # SPM 依赖（ffmpeg-kit）
├── MusicPlayer/
│   ├── App/
│   │   ├── MusicPlayerApp.swift           # @main App 入口 + 环境注入
│   │   └── ContentView.swift              # 主容器（TabView + ZStack MiniPlayer）
│   ├── Core/
│   │   ├── Audio/
│   │   │   ├── AudioEngine.swift          # AVAudioEngine 管理：节点链、播放、seek
│   │   │   ├── FFmpegDecoder.swift        # FFmpeg-Kit 解码器（FLAC→PCM Buffer）
│   │   │   ├── EqualizerManager.swift     # 10频段 AVAudioUnitEQ + 预设
│   │   │   └── AudioVisualizer.swift      # installTap 采样 + vDSP FFT
│   │   ├── Data/
│   │   │   ├── Models.swift               # SwiftData @Model: Song, Playlist, PlaylistSong
│   │   │   ├── SongRepository.swift       # 歌曲 CRUD + 查询（按分类/收藏）
│   │   │   └── PlaylistRepository.swift   # 播放列表 CRUD + 歌曲排序
│   │   └── Services/
│   │       ├── PlaybackService.swift      # 播放控制核心：队列、状态、模式
│   │       ├── MetadataService.swift      # 元数据读取（AVAsset + FFmpeg probe）
│   │       ├── ImportService.swift        # UIDocumentPicker 文件导入到沙盒
│   │       ├── StreamingService.swift     # URL 输入 → 下载/缓存 → 播放
│   │       ├── LyricsService.swift        # LRC 歌词解析与时间同步
│   │       ├── SleepTimerService.swift    # 倒计时暂停
│   │       ├── NowPlayingService.swift    # MPNowPlayingInfoCenter 锁屏信息
│   │       └── RemoteCommandService.swift # MPRemoteCommandCenter 远程控制
│   ├── Features/
│   │   ├── Library/
│   │   │   ├── LibraryView.swift          # 音乐库主视图（Segmented: 全部/专辑/艺术家/流派）
│   │   │   └── LibraryViewModel.swift     # @Observable，查询 + 过滤
│   │   ├── NowPlaying/
│   │   │   ├── NowPlayingView.swift       # 全屏播放（封面、进度、控制、歌词/可视化切换）
│   │   │   ├── MiniPlayerView.swift       # 底部悬浮播放条
│   │   │   ├── LyricsView.swift           # 滚动歌词 + 当前行高亮
│   │   │   ├── VisualizerView.swift       # Canvas 频谱/波形绘制
│   │   │   ├── EqualizerView.swift        # 10频段滑块 + 预设选择
│   │   │   └── NowPlayingViewModel.swift  # @Observable，绑定 PlaybackService
│   │   ├── Playlists/
│   │   │   ├── PlaylistsView.swift        # 播放列表 + "我的收藏"
│   │   │   ├── PlaylistDetailView.swift   # 列表内歌曲 + 拖拽排序
│   │   │   └── PlaylistViewModel.swift
│   │   ├── Search/
│   │   │   └── SearchView.swift           # 本地搜索歌曲/专辑/艺术家
│   │   └── Settings/
│   │       ├── SettingsView.swift         # 音质、定时器、URL流媒体入口、缓存管理
│   │       └── SettingsViewModel.swift
│   ├── CarPlay/
│   │   └── CarPlaySceneDelegate.swift     # CPTemplateApplicationSceneDelegate
│   └── Resources/
│       └── Assets.xcassets/
├── MusicPlayer.entitlements               # CarPlay + Background Modes
└── Info.plist                             # 文件类型、场景配置、权限说明
```

## SwiftData 数据模型

```swift
@Model class Song {
    @Attribute(.unique) var id: UUID
    var title: String
    var artist: String
    var album: String
    var genre: String
    var duration: Double           // 秒
    var fileURL: String            // 本地路径或远程URL
    var isRemote: Bool
    var format: String             // "flac", "mp3", "wav", "alac", "aac"
    var sampleRate: Int            // 44100, 96000 等
    var bitDepth: Int              // 16, 24, 32
    var isFavorite: Bool
    var playCount: Int
    var lastPlayedAt: Date?
    @Attribute(.externalStorage) var artworkData: Data?  // 封面图
    var lyricsPath: String?        // LRC文件路径
    var addedAt: Date
    var playlists: [PlaylistSong]  // 反向关系
}

@Model class Playlist {
    @Attribute(.unique) var id: UUID
    var name: String
    var createdAt: Date
    var updatedAt: Date
    @Relationship(deleteRule: .cascade) var songs: [PlaylistSong]
}

@Model class PlaylistSong {
    var id: UUID
    var order: Int                 // 排序序号
    var song: Song
    var playlist: Playlist
}
```

## 实施阶段（26步）

### Phase 1: 项目骨架与数据层
1. 创建 project.yml（XcodeGen），配置 Background Modes、entitlements、Info.plist
2. 集成 FFmpeg-Kit SPM 依赖（ffmpeg-kit-ios-full 或 audio 变体）
3. 实现 SwiftData 模型（Song, Playlist, PlaylistSong）
4. 实现 SongRepository + PlaylistRepository
5. 搭建 ContentView（TabView 4个Tab + ZStack MiniPlayer 占位）

### Phase 2: 音频引擎与基础播放
6. 实现 AudioEngine：初始化 AVAudioEngine、创建节点链、配置 AVAudioSession
7. 实现 AudioEngine 播放接口：play(AVAudioFile) + play(PCMBuffer) + pause/resume/seek
8. 实现 FFmpegDecoder：使用 FFmpeg-Kit 解码 FLAC 等非原生格式为 PCM Buffer
9. 实现 PlaybackService：@Observable 单例，管理播放队列、当前歌曲、播放状态、模式切换
10. 实现 MetadataService：AVAsset 读取原生格式元数据 + FFmpeg probe 读取 FLAC/APE 元数据

### Phase 3: 文件导入与核心UI
11. 实现 ImportService：UIDocumentPickerViewController 包装，支持多选导入，复制到沙盒，自动读取元数据入库
12. 实现 LibraryView + LibraryViewModel：歌曲列表（LazyVStack）、Segmented 切换（全部/专辑/艺术家/流派）
13. 实现 MiniPlayerView：底部悬浮条（封面缩略图 + 标题 + 播放/暂停按钮），点击展开全屏
14. 实现 NowPlayingView + NowPlayingViewModel：全屏播放界面（大封面、进度 Slider、上下曲、播放模式、收藏按钮）
15. 实现收藏功能：歌曲行/播放页点击收藏按钮 → 更新 SwiftData isFavorite 字段

### Phase 4: 播放列表
16. 实现 PlaylistsView：显示所有自定义播放列表 + "我的收藏"系统列表
17. 实现 PlaylistDetailView + PlaylistViewModel：列表内歌曲展示、拖拽排序、删除、添加歌曲
18. 实现 CreatePlaylistSheet：创建/编辑播放列表弹窗

### Phase 5: 高级音频功能
19. 实现 EqualizerManager：10频段 AVAudioUnitEQ 配置 + 6种预设 + 自定义保存
20. 实现 EqualizerView：Sheet 弹窗，10个垂直 Slider + 预设 Picker
21. 实现 AudioVisualizer：installTap 采样 + Accelerate vDSP FFT 转频域
22. 实现 VisualizerView：Canvas 绘制频谱条形图，订阅采样数据实时刷新

### Phase 6: 歌词、流媒体与系统集成
23. 实现 LyricsService + LyricsView：LRC 解析、时间同步、滚动高亮
24. 实现 StreamingService：用户输入 URL → URLSession 下载到缓存 → 送入播放引擎；支持缓存管理
25. 实现 NowPlayingService + RemoteCommandService：锁屏封面/进度/控制 + 耳机/控制中心响应
26. 实现 SleepTimerService + SettingsView + CarPlaySceneDelegate

## 关键技术要点

### FFmpeg-Kit 解码流程
1. 使用 `FFmpegKit.execute()` 将 FLAC 解码为 PCM raw 文件（或直接解码到内存）
2. 读取 PCM 数据创建 `AVAudioPCMBuffer`（Float32, non-interleaved）
3. 通过 `AVAudioPlayerNode.scheduleBuffer()` 分块送入播放
4. 后台线程解码，预缓冲 3-5 秒，buffer 队列循环送入
5. FFmpeg-Kit 同时用于 probe 元数据（封面、采样率、时长等）

### EQ 均衡器
- 频段: 32Hz, 64Hz, 125Hz, 250Hz, 500Hz, 1kHz, 2kHz, 4kHz, 8kHz, 16kHz
- 增益范围: -12dB ~ +12dB
- 预设: 平直、流行、摇滚、古典、爵士、人声
- 自定义预设保存到 UserDefaults

### URL 流媒体播放
- SettingsView 或 LibraryView 提供"添加 URL"入口
- 用户输入音频文件的 HTTP/HTTPS URL
- URLSession.downloadTask 下载到缓存目录
- 下载完成后同本地文件一样处理（读取元数据、入库、播放）
- 缓存目录大小限制 500MB，LRU 清理

### 后台播放配置
- AVAudioSession category: `.playback`, mode: `.default`
- Xcode capability: Background Modes → Audio, AirPlay, and Picture in Picture
- 监听 AVAudioSession.interruptionNotification 处理来电等中断

### CarPlay 集成
- Info.plist 配置 CPTemplateApplicationSceneSessionRoleApplication
- CarPlaySceneDelegate 实现 CPTemplateApplicationSceneDelegate
- 根模板: CPTabBarTemplate（音乐库 + 播放列表）
- 列表模板: CPListTemplate（艺术家/专辑/歌曲）
- 播放界面: CPNowPlayingTemplate（系统自动提供，绑定 MPNowPlayingInfoCenter）

## 第三方依赖 (SPM)
| 依赖 | 用途 | 备注 |
|------|------|------|
| ffmpeg-kit-ios-audio | FLAC/APE等格式解码 + 元数据probe | ~30-50MB，audio变体体积较小 |

> 其余功能全部使用 Apple 原生框架：AVFoundation、MediaPlayer、CarPlay、SwiftData、Accelerate

## 验证方案
1. `xcodegen generate` 生成 .xcodeproj，Xcode 打开并 build 成功
2. 导入 MP3/FLAC/WAV/ALAC 文件 → 验证元数据正确读取 + 播放音质无损
3. 创建播放列表、添加歌曲、收藏歌曲 → 关闭重启后数据保持
4. 调节 EQ 各频段滑块 → 实时听到音效变化
5. 导入同名 .lrc 文件 → 播放时歌词随时间滚动高亮
6. 输入远程音频 URL → 下载并播放成功
7. 锁屏/控制中心 → 显示封面和歌曲信息，按钮可控制播放
8. 后台播放 → 切换到其他 App 后音乐持续播放
9. CarPlay 模拟器 → Tab 导航正常，点击歌曲可播放
