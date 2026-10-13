# 审计追踪

> 记录每轮审计覆盖的文件和结论，避免重复踩坑。
> 状态: ✅ 已审查无新问题 | 🔧 发现问题已修复 | ⚠️ 发现问题未修复 | ⬜ 未审计

## 核心数据路径（按文件）

| 文件 | 状态 | 最后审计轮次 | 备注 |
|------|------|-------------|------|
| `data/services/import_service.dart` | ✅ | R6 | 导入流水线：chunk原子性 OK；PIT-044 crash窗口(未修) |
| `data/services/import/vault_transfer_runner.dart` | ✅ | R5 | Native转移+恢复逻辑 OK |
| `data/services/import/vault_reveal_runner.dart` | ✅ | R5 | 解密导出+chunk原子性 OK |
| `data/services/import/hide_preparer.dart` | ✅ | R5 | 路径准备 OK |
| `data/services/import/media_recorder.dart` | ✅ | R5 | DB批量插入 OK |
| `data/services/import/thumbnail_generator.dart` | ✅ | R5 | 异步缩略图 OK |
| `data/services/media_encryption_service.dart` | 🔧 | R3 | JPEG魔数修复(PIT-035) |
| `data/services/encryption_key_manager.dart` | 🔧 | R5 | clearMemory()新增(PIT-047) |
| `data/services/security_service.dart` | ✅ | R6 | 凭据存储 OK；注意clearCredential不删encryption_salt（设计如此） |
| `data/services/biometric_service.dart` | ✅ | R6 | 薄封装 native local_auth OK |
| `data/services/native_crypto_service.dart` | ✅ | R6 | 薄封装 native AES-256-GCM |
| `data/services/media_rename_service.dart` | ✅ | R6 | 薄封装 native hide/unhide |
| `data/services/media_store_service.dart` | ✅ | R6 | 薄封装 native MediaStore |
| `data/services/maintenance_service.dart` | ✅ | R5 | 孤儿恢复+批量加密 OK |
| `data/services/gallery_service.dart` | ✅ | R6 | VisibleState追踪 OK |
| `data/services/vault_storage_service.dart` | ✅ | R6 | 文件I/O OK |
| `data/services/vault_backup_service.dart` | ✅ | R6 | 导出+导入 OK; staging+rollback OK |
| `data/services/vault_backup_export.dart` | ✅ | R6 | 分阶段提交+回滚 OK |
| `data/services/vault_backup_restore.dart` | ✅ | R6 | preflight+install OK |
| `data/services/vault_backup_restore_install.dart` | ✅ | R6 | .part临时文件+rename OK |
| `data/services/share_intent_service.dart` | ✅ | R6 | 分享队列 OK |
| `data/services/video_resume_service.dart` | ✅ | R6 | 简单 SharedPreferences OK |
| `data/repositories/media_repository.dart` | 🔧 | R5 | purgeMany修复(PIT-043); softDelete OK |
| `data/repositories/album_repository.dart` | ✅ | R6 | 纯DB操作 OK |
| `data/db/database.dart` | ✅ | R5 | SQLite事务 OK |
| `data/db/tables.dart` | ✅ | R6 | Schema OK |
| `application/lock/lock_controller.dart` | 🔧 | R5 | DEK旋转修复(PIT-038-040); biometric修复(PIT-047) |
| `application/lock/biometric_ui.dart` | ✅ | R6 | UI层 OK |
| `application/backup/vault_backup_controller.dart` | ✅ | R6 | UI状态管理 OK |
| `application/import/import_controller.dart` | ✅ | R6 | UI+委托 OK |
| `application/import/share_queue_controller.dart` | ✅ | R6 | 简单队列 OK |
| `application/settings/settings_controller.dart` | ✅ | R6 | SharedPreferences OK |
| `presentation/viewer/viewer_screen.dart` | 🔧 | R4 | 并发去重修复(PIT-041); 失败状态修复(PIT-037) |
| `presentation/settings/settings_screen.dart` | 🔧 | R4 | 死参数移除(PIT-042) |

## Native Kotlin 层

| 文件 | 状态 | 最后审计轮次 | 备注 |
|------|------|-------------|------|
| `CryptoHandler.kt` | ✅ | R7 | AES-256-GCM H/W加速；encrypt原子rename+备份回滚；decrypt验证auth tag |
| `VaultFileHandler.kt` | ✅ | R7 | hideToVault原子move→stream copy→拷贝后删原始(失败仅重复)；unhide对称安全 |
| `MediaStoreIndexHandler.kt` | ✅ | R7 | hide标记IS_PENDING→删索引(文件已移走时)；scan恢复索引+日期修复 |
| `ThumbnailHandler.kt` | ✅ | R7 | 纯读->写新文件；不修改原始媒体 |
| `MediaMetadataHandler.kt` | ✅ | R7 | 纯读EXIF/MediaStore；无副作用 |
| `MainActivity.kt` | ✅ | R7 | MethodChannel委托+IO线程池+crash日志；无直接数据操作 |
| `ExternalPlayerHandler.kt` | ✅ | R7 | 外部播放器Intent启动器；读操作 |
| `PlayerHandler.kt` | ✅ | R7 | 播放器接口；无文件操作 |
| `VlcPlayerHandler.kt` | ✅ | R7 | VLC播放；读操作 |
| `VideoPlayerHandler.kt` | ✅ | R7 | ExoPlayer播放；读操作 |
| `VideoTimestampNormalizer.kt` | ✅ | R7 | 时间戳工具 |
| `VideoPlaybackDiagnostics.kt` | ✅ | R7 | 诊断日志 |

## 未审计区域（不影响数据完整性）

| 区域 | 原因 |
|------|------|
| `lib/presentation/*` (除viewer/settings) | UI层，无数据操作 |
| `lib/core/*` | 工具/主题/常量 |
| `lib/l10n/*` | 国际化字符串 |
| `lib/domain/models/*` | 数据模型定义 |
| `lib/data/services/platform/*` (adapters) | 薄适配器，无逻辑 |

## 已知未修复问题

| 编号 | 描述 | 风险等级 |
|------|------|---------|
| PIT-044 | encryptFile→updateEncryptedDek crash窗口DEK丢失 | 极低概率/高影响 |
| PIT-045 | enterAppAfterSetup PBKDF2竞态KEK为空 | 极低概率 |
| PIT-046 | unlock先解锁后派生1-2s KEK空窗期 | 低UX影响 |

---

最后更新: 2026-10-13 R7（第七轮审计 — Native Kotlin 全遍历）