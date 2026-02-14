# Library Album & Artist Images

## 目标
- 在音乐库列表中自动展示专辑封面与艺术家头像。
- 优先复用已有歌曲封面数据，无需新增外部依赖。

## 范围
- 影响音乐库「专辑」「艺术家」列表 UI 展示。
- 涉及文件：
  - `MusicPlayer/Features/Library/LibraryViewModel.swift`
  - `MusicPlayer/Features/Library/LibraryView.swift`

## 关键改动点
- 在 `LibraryViewModel` 中构建专辑/艺术家封面缓存（优先使用更大图）。
- 专辑列表展示封面缩略图；艺术家列表展示圆形头像。

## 影响入口
- 音乐库：`MusicPlayer/Features/Library/LibraryView.swift`

## 验收清单
- 专辑列表能显示对应封面（若歌曲有 artwork）。
- 艺术家列表能显示头像（若歌曲有 artwork）。
- 无封面时保持原占位样式。

## 风险/回滚点
- 若封面选择不符合预期，可调整选取策略或回滚缓存逻辑。
- 回滚方式：移除 `albumArtwork/artistArtwork` 缓存与相关 UI 替换。
