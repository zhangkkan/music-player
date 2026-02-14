# Lyrics Candidate Dedup

## 目标
- 移除重复的候选构建逻辑，保持一致的候选顺序策略。

## 范围
- 影响歌词查询候选生成。
- 涉及文件：`MusicPlayer/Core/Services/LyricsEnrichmentService.swift`

## 关键改动点
- 合并候选生成逻辑为统一 `buildCandidates`，按策略参数控制顺序。
- 删除旧的重复方法，降低维护成本。

## 影响入口
- 导入流程：`MusicPlayer/Core/Services/ImportService.swift`
- 播放触发：`MusicPlayer/Core/Services/PlaybackService.swift`
- 手动刷新：`MusicPlayer/Features/NowPlaying/NowPlayingView.swift`

## 验收清单
- 歌词查询候选顺序保持与既定策略一致。
- 无编译错误，查询日志正常。

## 风险/回滚点
- 合并逻辑后若顺序异常，可恢复原方法。
- 回滚方式：还原 `buildCandidates` 合并改动。
