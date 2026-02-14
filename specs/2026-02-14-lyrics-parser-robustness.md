# Lyrics Parser Robustness

## 目标
- 修复歌词文件存在但解析结果为 0 行的问题。
- 兼容更宽松的 LRC 时间戳格式与编码。

## 范围
- 影响歌词解析逻辑。
- 涉及文件：`MusicPlayer/Core/Services/LyricsService.swift`

## 关键改动点
- 时间戳支持 1-2 位分钟/秒，毫秒可选（支持 `.` 或 `:` 分隔）。
- 支持每行多个时间戳，统一取同一行歌词文本。
- 增加编码回退（UTF-8/UTF-16/UTF-32/GB18030）。

## 影响入口
- 播放页加载歌词：`MusicPlayer/Features/NowPlaying/NowPlayingViewModel.swift`
- 歌词服务：`MusicPlayer/Core/Services/LyricsService.swift`

## 验收清单
- 既有 LRC 文件能解析出非 0 行结果。
- 含 1 位分钟/秒或无毫秒的 LRC 能解析。

## 风险/回滚点
- 过宽匹配可能误解析非歌词元数据行；如出现异常可收紧正则。
- 回滚方式：恢复 `parseLRC` 的正则与解析逻辑。
