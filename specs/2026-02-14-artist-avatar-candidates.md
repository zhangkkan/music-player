# Artist Avatar Candidates

## 目标
- 艺术家详情页支持拉取多候选头像并供用户选择。
- 用户任何头像操作后锁定该艺术家，后续不再自动刷新。
- 自动头像仅在艺术家首次出现时附着一次。

## 范围
- 影响艺术家头像获取与详情页交互。
- 涉及文件：
  - `MusicPlayer/Core/Services/ArtistImageService.swift`
  - `MusicPlayer/Core/Data/Models.swift`
  - `MusicPlayer/Core/Data/ArtistAvatarRepository.swift`
  - `MusicPlayer/Features/Library/LibraryViewModel.swift`
  - `MusicPlayer/Features/Library/LibraryView.swift`

## 关键改动点
- iTunes Search 拉取最多 100 条候选并展示网格。
- 任何头像操作后设置 `isLocked = true`，禁止自动刷新。
- 自动附着仅在艺术家首次出现时触发一次。

## 影响入口
- 艺术家详情页：`MusicPlayer/Features/Library/LibraryView.swift`

## 验收清单
- “获取更多头像”能展示候选网格并可选择。
- 选择或上传头像后不再自动刷新。
- 新出现艺术家自动附着 1 张头像。

## 风险/回滚点
- 候选过多导致加载慢，可调整 limit 或分页。
- 回滚方式：移除候选逻辑，恢复旧的单头像机制。
