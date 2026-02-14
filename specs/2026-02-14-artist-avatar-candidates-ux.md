# Artist Avatar Candidates UX

## 目标
- 候选头像去重并优先高清。
- 选择头像后自动滚动到顶部展示新头像。
- 选择完成后可一键退出候选模式。

## 范围
- 影响艺术家详情页候选头像展示与交互。
- 涉及文件：
  - `MusicPlayer/Core/Services/ArtistImageService.swift`
  - `MusicPlayer/Features/Library/LibraryView.swift`

## 关键改动点
- iTunes 候选按 fullsize URL 去重，优先保留高清来源。
- 选择/上传后清空候选并滚动回顶部。
- 候选展示时增加“完成”按钮退出选择模式。

## 影响入口
- 艺术家详情页：`MusicPlayer/Features/Library/LibraryView.swift`

## 验收清单
- 候选不重复，优先显示高清。
- 选中后头图即时更新并滚动到顶部。
- 可通过“完成”退出候选模式。

## 风险/回滚点
- 若滚动影响体验，可移除自动滚动。
- 回滚方式：恢复候选展示逻辑。
