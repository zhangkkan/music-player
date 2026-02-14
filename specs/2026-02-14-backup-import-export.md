# Backup Import/Export

## 目标
- 提供 .zip 备份导入/导出，包含设置、歌曲/歌单数据、艺术家头像与歌词文件。
- 支持 fileBookmark 以便恢复外部文件权限。

## 范围
- 影响设置页 UI 与数据备份服务。
- 涉及文件：
  - `MusicPlayer/Core/Services/BackupService.swift`
  - `MusicPlayer/Core/Services/SimpleZip.swift`
  - `MusicPlayer/Features/Settings/SettingsView.swift`

## 关键改动点
- 使用自定义 zip 读写器生成/解析备份包。
- 备份内容包含：UserDefaults 设置、Songs、Playlists、PlaylistSongs、ArtistAvatar、LRC 文件。
- 导入时覆盖当前数据，并重建歌词与头像。

## 影响入口
- 设置页：`MusicPlayer/Features/Settings/SettingsView.swift`

## 验收清单
- 导出生成 .zip；导入后数据与设置可恢复。
- 头像与歌词文件可恢复显示。
- 外部文件 bookmark 仍可用于访问。

## 风险/回滚点
- 自定义 zip 仅支持本 App 生成的备份。
- 回滚方式：移除备份入口与相关服务。
