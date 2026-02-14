# Lyrics Fetch After Metadata Enrichment

## 目标
- 在歌词查询前等待元数据增强完成，确保使用已矫正的歌手/歌名。

## 范围
- 影响歌词获取流程，涉及 `LyricsEnrichmentService`。

## 关键改动点
- `LyricsEnrichmentService` 在开始歌词查询前调用 `MetadataEnrichmentService.enrich` 并等待完成。
- 重新从数据库获取最新歌曲数据，用于构建 LRCLIB 查询。

## 影响入口
- 导入流程：`MusicPlayer/Core/Services/ImportService.swift`
- 播放触发：`MusicPlayer/Core/Services/PlaybackService.swift`
- 手动刷新：`MusicPlayer/Features/NowPlaying/NowPlayingView.swift`

## 验收清单
- 导入或播放时，歌词查询日志使用已矫正的 artist/title。
- 若元数据增强已完成，歌词查询不会退回旧的带标签/错误值。

## 风险/回滚点
- 增加一次等待可能延迟歌词请求；如有性能问题，可仅对 import/playback 开启。
- 回滚方式：移除 `LyricsEnrichmentService` 中对 `MetadataEnrichmentService` 的调用。
