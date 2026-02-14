# Artist Avatar Refactor

## 目标
- 艺术家头像与歌曲封面彻底解耦，仅与艺术家本身相关。
- 艺术家列表增删时自动拉取/清理头像。
- 头像持久缓存，支持手动替换、手动刷新与恢复自动。

## 范围
- 影响艺术家头像数据模型、缓存与 UI 交互。
- 涉及文件：
  - `MusicPlayer/Core/Data/Models.swift`
  - `MusicPlayer/Core/Data/ArtistAvatarRepository.swift`
  - `MusicPlayer/Core/Services/ArtistImageService.swift`
  - `MusicPlayer/Features/Library/LibraryViewModel.swift`
  - `MusicPlayer/Features/Library/LibraryView.swift`
  - `MusicPlayer/Info.plist`

## 关键改动点
- 新增 `ArtistAvatar` 模型，头像数据持久化（externalStorage），记录来源与更新时间。
- 新增 `ArtistAvatarRepository` 管理头像数据增删改查。
- `ArtistImageService` 只负责 iTunes 拉取，去掉文件缓存。
- 列表增删触发头像增量拉取/删除；头像不再用歌曲封面兜底。
- 详情页新增头像操作：选择照片/文件、刷新、恢复自动。

## 影响入口
- 音乐库：`MusicPlayer/Features/Library/LibraryView.swift`

## 验收清单
- 首次进入艺术家列表时头像逐步出现，无歌曲封面兜底。
- 新增/删除艺术家时，头像缓存自动增量更新。
- 手动头像持久保存，退出重进仍存在。
- 刷新头像仅覆盖自动来源，手动头像需先恢复自动。

## 风险/回滚点
- iTunes 匹配可能不准，需依赖手动替换纠正。
- 回滚方式：移除 ArtistAvatar 模型与相关逻辑，恢复旧的头像展示。
