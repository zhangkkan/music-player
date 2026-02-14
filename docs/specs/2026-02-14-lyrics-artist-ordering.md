# Lyrics Artist Candidate Ordering

## 目标
- 提升歌词命中率，歌手名候选顺序与标题一致：简体优先、繁体其次。

## 范围
- 影响歌词查询参数的候选顺序。
- 涉及文件：`MusicPlayer/Core/Services/LyricsEnrichmentService.swift`

## 关键改动点
- 歌手名候选顺序改为：简体 -> 繁体 -> 原文（去重）。

## 影响入口
- 导入流程：`MusicPlayer/Core/Services/ImportService.swift`
- 播放触发：`MusicPlayer/Core/Services/PlaybackService.swift`
- 手动刷新：`MusicPlayer/Features/NowPlaying/NowPlayingView.swift`

## 验收清单
- 日志中 artist 候选顺序符合“简体优先、繁体其次”。
- 404 次数减少，命中率提升。

## 风险/回滚点
- 宽松候选顺序可能匹配到不同版本歌手名；如误匹配可回滚。
- 回滚方式：恢复 `buildArtistCandidates` 的改动。
