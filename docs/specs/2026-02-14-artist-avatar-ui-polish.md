# Artist Avatar UI Polish

## 目标
- 头像操作改为下方抽屉，优化文案与交互。
- 候选头像支持无限下滑与更大卡片展示。
- 新头像排序靠前、去重并优先高清。

## 范围
- 影响艺术家详情页头像相关 UI 与候选排序。
- 涉及文件：
  - `MusicPlayer/Features/Library/LibraryView.swift`
  - `MusicPlayer/Core/Services/ArtistImageService.swift`

## 关键改动点
- “头像”按钮改为 sheet 抽屉，提供获取更多/相册/文件/恢复自动。
- 候选头像改为两列更大卡片，便于瀑布流式连续浏览。
- 候选按高清优先并新头像靠前排序，基于解析分辨率去重。

## 影响入口
- 艺术家详情页：`MusicPlayer/Features/Library/LibraryView.swift`

## 验收清单
- 头像操作不再出现带箭头菜单。
- 候选可持续下滑，列表不截断。
- 新头像靠前且去重效果更好。

## 风险/回滚点
- 网格变大可能影响滚动性能，可回退到 3 列小卡片。
- 回滚方式：恢复旧的菜单与候选布局。
