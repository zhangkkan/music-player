# Artist Avatar via iTunes

## 目标
- 为艺术家列表提供独立头像来源，不再复用歌曲封面。
- 使用 iTunes Search 获取艺术家相关专辑封面作为头像。

## 范围
- 影响艺术家头像获取与缓存。
- 涉及文件：
  - `MusicPlayer/Core/Services/ArtistImageService.swift`
  - `MusicPlayer/Features/Library/LibraryViewModel.swift`
  - `MusicPlayer/Features/Library/LibraryView.swift`

## 关键改动点
- 新增 `ArtistImageService`，通过 iTunes Search 拉取 artist 相关专辑封面并缓存到本地。
- 艺术家列表按需触发头像拉取与更新（onAppear）。

## 影响入口
- 音乐库：`MusicPlayer/Features/Library/LibraryView.swift`

## 验收清单
- 艺术家列表首次进入时可逐步出现头像。
- 头像缓存命中后不重复请求。

## 风险/回滚点
- iTunes Search 返回结果可能与艺术家不完全匹配；如误匹配可调整查询或回滚。
- 回滚方式：移除 `ArtistImageService` 与列表加载逻辑。
