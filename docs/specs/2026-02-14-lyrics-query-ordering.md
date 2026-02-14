# Lyrics Query Ordering Tuning

## 目标
- 提升歌词命中率，优先使用更宽松的查询组合。
- 将标题候选顺序调整为：简体优先，其次繁体。

## 范围
- 影响歌词查询参数的候选顺序与组合策略。
- 涉及文件：`MusicPlayer/Core/Services/LyricsEnrichmentService.swift`

## 关键改动点
- 标题候选顺序改为：简体 -> 繁体 -> 原文（去重）。
- 查询组合优先不带专辑/时长的更宽松组合，再尝试带专辑的严格组合。

## 影响入口
- 导入流程：`MusicPlayer/Core/Services/ImportService.swift`
- 播放触发：`MusicPlayer/Core/Services/PlaybackService.swift`
- 手动刷新：`MusicPlayer/Features/NowPlaying/NowPlayingView.swift`

## 验收清单
- 日志中标题候选顺序符合“简体优先、繁体其次”。
- 多次 404 的场景减少，命中率提升。

## 风险/回滚点
- 宽松查询可能导致歌词匹配到错误版本；如出现误匹配，可恢复原先的严格顺序。
- 回滚方式：恢复 `buildTitleCandidates` 和 `buildQueryVariants` 的改动。
