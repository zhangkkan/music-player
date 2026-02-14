# Spec: Now Playing 体验、播放队列与补全体系增强

日期：2026-02-14

## 目标
- 完善播放队列（Now Playing Queue）能力，支持查看/排序/删除/保存为歌单。
- 统一歌曲列表交互（单击追加队列并播放，双击替换队列并播放）。
- 引入元数据与歌词补全体系（iTunes/MusicBrainz + LRCLIB），提供自动/手动触发与同步结果提示。
- 强化播放页面交互与 UI 细节（迷你播放器、详情页卡片、提示样式）。
- 明确数据安全策略：删除只移除 App 记录，不删除文件本体。

## 范围
- Now Playing UI 与交互
- 播放队列 UI 与逻辑
- 歌曲列表统一交互与快速收藏
- 元数据/歌词补全服务与设置项
- 歌曲管理与删除策略

## 关键改动点
- 新增播放队列视图：支持拖拽排序、移除单曲、保存为歌单。
- 播放逻辑：单击追加队列并播放；双击替换队列并播放并弹出详情。
- 元数据补全：iTunes Search + MusicBrainz（无需 API Key），支持来源与时间记录。
- 歌词补全：LRCLIB，同步 LRC 保存，导入/播放/手动三种触发。
- 补全结果提示：显示字段更新状态、来源与更新时间，支持强制刷新。
- 列表与歌单统一 `SongRow` 风格，快速收藏到歌单。
- 删除仅移除 App 记录，清理与播放列表、队列关系。

## 影响入口
- `MusicPlayer/App/ContentView.swift`
- `MusicPlayer/Core/Services/PlaybackService.swift`
- `MusicPlayer/Core/Services/MetadataEnrichmentService.swift`
- `MusicPlayer/Core/Services/LyricsEnrichmentService.swift`
- `MusicPlayer/Core/Data/SongRepository.swift`
- `MusicPlayer/Features/NowPlaying/NowPlayingView.swift`
- `MusicPlayer/Features/NowPlaying/NowPlayingQueueView.swift`
- `MusicPlayer/Features/Library/LibraryView.swift`
- `MusicPlayer/Features/Playlists/PlaylistsView.swift`
- `MusicPlayer/Features/Settings/SongManagementView.swift`

## 验收清单
- 播放队列可查看、排序、删除；删除当前曲目会自动播放下一首。
- 单击歌曲可追加队列并播放；双击可替换队列并播放。
- 元数据补全支持自动与手动触发，显示来源与更新时间。
- 歌词补全可生成 LRC 文件，播放页展示歌词。
- 删除歌曲仅移除记录，不删除文件本体；播放列表计数同步更新。
- Now Playing 详情卡片贴合底部安全区，视觉一致。

## 风险与回滚
- 风险：补全服务网络不可达或响应异常；需允许重试并避免覆盖可信本地数据。
- 风险：队列/列表关系清理不完整导致计数不一致；需确保删除路径统一走仓库清理。
- 回滚：可通过还原补全服务与队列相关提交恢复基础播放能力。
