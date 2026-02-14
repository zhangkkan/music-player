# Artist Avatar Persistence Fix

## 目标
- 修复艺术家头像保存后无法持久化的问题。

## 范围
- 影响 SwiftData 模型容器的 schema 配置。
- 涉及文件：`MusicPlayer/App/MusicPlayerApp.swift`

## 关键改动点
- 将 `ArtistAvatar` 加入 SwiftData Schema，以确保持久化生效。

## 影响入口
- 应用启动：`MusicPlayer/App/MusicPlayerApp.swift`

## 验收清单
- 选择头像并保存后，返回列表仍显示新头像。
- 重启应用后头像仍存在。

## 风险/回滚点
- 旧数据无需迁移；如出现异常可移除新模型并恢复原 schema。
