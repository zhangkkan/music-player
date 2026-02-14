# Library Detail Headers

## 目标
- 在专辑/艺术家详情页顶部展示大图头图。

## 范围
- 影响专辑/艺术家详情页 UI。
- 涉及文件：`MusicPlayer/Features/Library/LibraryView.swift`

## 关键改动点
- 专辑详情页顶部增加大图头图与标题信息。
- 艺术家详情页顶部增加大图头图与标题信息。
- 头图默认使用该列表中最大 artwork 作为封面，缺省时显示占位。

## 影响入口
- 音乐库：`MusicPlayer/Features/Library/LibraryView.swift`

## 验收清单
- 专辑/艺术家详情页顶部显示头图。
- 有封面时显示实际图，无封面时显示占位图。

## 风险/回滚点
- 若头图布局与列表样式冲突，可改为 `ScrollView` 结构或降低头图高度。
- 回滚方式：移除头图 Section 与相关 UI 逻辑。
