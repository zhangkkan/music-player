# 项目指引（AGENTS）

## 项目概览
- iOS SwiftUI 音乐播放器，核心代码在 `MusicPlayer/`。
- 采用 SwiftData 持久化，播放引擎位于 `MusicPlayer/Core/Audio`，业务服务位于 `MusicPlayer/Core/Services`。
 - 主要能力：本地音乐导入/播放、播放队列、播放列表、歌词与元数据补全、均衡器与可视化、系统控制集成。

## 当前功能特性（速览）
- 音乐库：歌曲/专辑/歌手/流派/收藏多维浏览、导入、收藏、列表统一操作
- 播放：迷你播放器 + Now Playing、播放队列、播放模式切换
- 播放列表：创建/管理、列表页快速收藏、队列一键保存
- 元数据补全：iTunes Search + MusicBrainz（无需 API Key），支持强制刷新与同步结果提示
- 歌词补全：LRCLIB（LRC），导入/播放/手动触发
- 歌词查询会清洗来源标签/域名，提升命中率
- 歌词获取会先等待元数据补全完成，确保使用矫正后的参数
- 歌词查询优先简体标题，其次繁体，并优先使用更宽松的查询组合
- 歌词查询的歌手名也按简体优先、繁体其次的顺序尝试
- 歌词解析支持宽松时间戳与多编码回退，避免解析为空
- 歌词查询前两次严格优先：简体/繁体歌手+歌名，且不带专辑与时长
- 音乐库专辑/艺术家列表自动展示封面/头像（复用歌曲 artwork）
- 专辑/艺术家详情页顶部增加头图展示
- 艺术家头像使用 iTunes Search 结果并本地缓存
- 艺术家头像与歌曲解耦，支持手动替换/刷新/恢复自动
- 艺术家详情页支持拉取多候选头像并选择，任何操作后锁定不再自动刷新
- 艺术家头像仅首次出现自动附着一次，之后仅允许手动选择
- 艺术家候选头像去重且优先高清，选择后自动回到顶部
- 候选头像需显式保存，支持取消与保存失败提示
- 艺术家头像加入 SwiftData Schema，保证持久化
- 头像操作改为下方抽屉，候选列表更大卡片与新头像靠前
- 支持 .zip 备份导入/导出（设置+歌曲+歌单+头像+歌词）
- 数据管理：删除仅移除 App 记录，不删除文件本体；歌曲管理页统一清理

## 开发约定
- 语言：Swift 5.9；UI：SwiftUI；数据：SwiftData。
- 结构：保持 `Features` 下的模块化视图 + ViewModel 组织方式。
- 只在必要时调整 `MusicPlayer.xcodeproj`；常规代码修改集中在 `MusicPlayer/`。
- 新功能优先复用 `Core/Services` 与 `Core/Data`，避免在 View 中堆积业务逻辑。
 - 删除逻辑必须走 `SongRepository`，仅移除 App 记录/关系，**不删除文件本体**。
 - UI 交互尽量复用 `SongRow` 等统一样式，避免各列表出现不一致操作。
 - 补全服务需遵守缓存/节流与来源标记，保持可追溯性（source + time）。

## 常用入口
- 应用入口：`MusicPlayer/App/MusicPlayerApp.swift`
- 根视图：`MusicPlayer/App/ContentView.swift`
- 音频播放：`MusicPlayer/Core/Services/PlaybackService.swift`
 - 数据仓库：`MusicPlayer/Core/Data/SongRepository.swift`
 - 元数据补全：`MusicPlayer/Core/Services/MetadataEnrichmentService.swift`
- 歌词补全：`MusicPlayer/Core/Services/LyricsEnrichmentService.swift`
- 艺术家头像：`MusicPlayer/Core/Services/ArtistImageService.swift`
- 艺术家头像仓库：`MusicPlayer/Core/Data/ArtistAvatarRepository.swift`
- 艺术家头像候选：`MusicPlayer/Core/Services/ArtistImageService.swift`
- 备份服务：`MusicPlayer/Core/Services/BackupService.swift`
 - 播放队列视图：`MusicPlayer/Features/NowPlaying/NowPlayingQueueView.swift`
 - 歌曲管理：`MusicPlayer/Features/Settings/SongManagementView.swift`

## 运行与构建
- 用 Xcode 打开 `MusicPlayer.xcodeproj`，配置签名后运行（iOS 17+）。
- 如需通过 `project.yml` 重新生成工程，请使用 XcodeGen 运行 `xcodegen`。

## 变更留存规范（必须遵守）
- **每个阶段性功能完成后**，需要尝试构建 spec 文件做**多路留存**：
  - 主存档：`specs/`（建议：`specs/YYYY-MM-DD-<feature>.md`）
  - 备份：`docs/specs/` 或 `docs/changes/`（二选一，保持与主存档同名）
- spec 必须包含：目标、范围、关键改动点、影响入口、验收清单、风险/回滚点。
- 若本仓库尚不存在上述目录，请在提交中一并创建并写入首个 spec。

## 对后续 AGENT 的要求
- 新增/修改关键功能或模块后，必须同步更新本文件的“功能特性”和“常用入口”。
- 若引入新的核心服务、入口或数据流，需明确写入对应文件路径与约定。
- 保持描述简洁但可执行，确保后续 AGENT 能快速定位核心路径并遵循规则。

## 说明
- 本仓库当前未提供自动化测试配置；如添加测试，请在 `MusicPlayer` 下新增对应测试目标并补充文档。
