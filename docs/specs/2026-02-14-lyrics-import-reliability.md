# Lyrics Import Reliability

## 目标
- 提升导入阶段歌词获取成功率，减少需要多次手动刷新的情况。
- 对异常元数据（如带来源标签/域名的歌手名）做清洗，确保 LRCLIB 查询参数可用。

## 范围
- 影响歌词获取参数构建与元数据覆盖策略。
- 涉及文件：
  - `MusicPlayer/Core/Services/LyricsEnrichmentService.swift`
  - `MusicPlayer/Core/Services/MetadataEnrichmentService.swift`

## 关键改动点
- 歌词查询参数增加清洗：去除来源标签（如 "[51ape.com]"）、URL/域名与多余分隔符，统一空白。
- 元数据覆盖策略补充：当歌手/标题带来源标签或域名时，允许被增强数据覆盖。

## 影响入口
- 导入流程：`MusicPlayer/Core/Services/ImportService.swift`
- 播放触发：`MusicPlayer/Core/Services/PlaybackService.swift`
- 手动刷新：`MusicPlayer/Features/NowPlaying/NowPlayingView.swift`

## 验收清单
- 导入带来源标签的歌曲时，歌词查询不再携带标签/域名。
- LRCLIB 查询日志中的 artist/title 更干净，404 次数减少。
- 既有正常曲目不受影响，歌词仍可正常获取并保存。

## 风险/回滚点
- 过度清洗可能移除真实歌手名中的特殊字符；如出现误删，可回滚清洗正则或只在检测到标签时清洗。
- 回滚方式：恢复 `sanitizeQueryText` 与 `hasSourceTag` 相关改动。
