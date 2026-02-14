# Lyrics Priority Order

## 目标
- 按用户指定的严格顺序优先尝试查询歌词。

## 范围
- 影响歌词查询请求的前置顺序。
- 涉及文件：`MusicPlayer/Core/Services/LyricsEnrichmentService.swift`

## 关键改动点
- 新增两条严格优先序：
  1) 简体歌手 + 简体歌名（不带专辑/时长）
  2) 繁体歌手 + 繁体歌名（不带专辑/时长）
- 后续查询继续使用既有候选与组合策略，但避免重复请求。

## 影响入口
- 导入流程：`MusicPlayer/Core/Services/ImportService.swift`
- 播放触发：`MusicPlayer/Core/Services/PlaybackService.swift`
- 手动刷新：`MusicPlayer/Features/NowPlaying/NowPlayingView.swift`

## 验收清单
- 日志中前两次请求严格符合指定顺序与参数（album/duration 为空）。
- 后续请求仍能按策略继续尝试，且不重复前两次查询。

## 风险/回滚点
- 前置严格顺序可能增加部分曲目的总尝试时间；如需可回滚。
- 回滚方式：移除 strict 优先序与去重逻辑。
