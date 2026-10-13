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
| `data/services/media_encryption_service.dart` | 🔧 | R9 | PIT-035(JPEG魔数) + PIT-048(_bytesMatch拒绝3字节JPEG头) |
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

## application 层（R8 补充）

| 文件 | 状态 | 最后审计轮次 | 备注 |
|------|------|-------------|------|
| `application/gallery/gallery_controller.dart` | ✅ | R8 | Riverpod providers，委托 GalleryService ✅ |
| `application/media/selection_controller.dart` | ✅ | R8 | 薄封装 SelectableGridController ✅ |
| `application/media/selectable_grid_controller.dart` | ✅ | R8 | 纯选择集合管理 ✅ |
| `application/media/rating_controller.dart` | ✅ | R8 | 委托 mediaRepository ✅ |
| `application/player/player_controller.dart` | ✅ | R8 | 播放计数/自动播放/外部交接，日志完善 ✅ |
| `application/player/external_player_coordinator.dart` | ✅ | R8 | 锁屏+外部播放器协调 ✅ |
| `application/player/external_player_gateway.dart` | ✅ | R8 | 接口定义 ✅ |
| `application/platform/*` (5 files) | ✅ | R8 | 全部为接口定义 ✅ |
| `application/update/*` (2 files) | ✅ | R8 | 接口定义 ✅ |

## presentation 层（R8 补充）

| 文件 | 状态 | 最后审计轮次 | 备注 |
|------|------|-------------|------|
| `presentation/lock/lock_screen.dart` | ✅ | R8 | 状态管理/busy守卫/生物识别触发 OK |
| `presentation/lock/pattern_lock.dart` | ✅ | R8 | 纯 UI 手势绘制，无数据操作 |
| `presentation/lock/pin_pad.dart` | ✅ | R8 | 纯 UI 数字键盘 |
| `presentation/player/player_screen.dart` | ✅ | R8 | 复杂但架构扎实：stale load保护/看门狗/引擎回退/起播竞态恢复 ✅ |
| `presentation/player/engine_fallback.dart` | ✅ | R8 | 三屏共用引擎回退 mixin，设计清晰 |
| `presentation/player/video_player_controls.dart` | ✅ | R8 | 纯 UI 控件 |
| `presentation/player/video_player_surface.dart` | ✅ | R8 | 纯 UI 纹理渲染 |
| `presentation/player/video_swipe_seek.dart` | ✅ | R8 | 纯 UI 手势 |
| `presentation/home/home_shell.dart` | ✅ | R8 | 导航+UI，数据委托 repository |
| `presentation/home/album_card.dart` | ✅ | R8 | 纯 UI |
| `presentation/home/arrange_albums_screen.dart` | ✅ | R8 | UI 排序界面 |
| `presentation/home/group_screen.dart` | ✅ | R8 | UI 分组界面 |
| `presentation/grid/media_grid_screen.dart` | ✅ | R8 | UI+数据委托，引擎回退模式 OK |
| `presentation/grid/thumbnail_tile.dart` | ✅ | R8 | 纯 UI |
| `presentation/common/keep_vault_unlocked.dart` | ✅ | R8 | 自动锁定抑制，正确配对 suppress/release |
| `presentation/common/swipe_action_cell.dart` | ✅ | R8 | 纯 UI 手势 |
| `presentation/common/*` (其余12文件) | ✅ | R8 | 纯 UI 组件 |
| `presentation/import/*` (2文件) | ✅ | R8 | 纯 UI 进度/消息 |
| `presentation/visible/gallery_preview_screen.dart` | ✅ | R8 | 同 player_screen 引擎回退模式 OK |
| `presentation/visible/*` (其余3文件) | ✅ | R8 | 纯 UI + 简单缓存 |

## core 层（R8 补充）

| 文件 | 状态 | 最后审计轮次 | 备注 |
|------|------|-------------|------|
| `core/utils/album_query_utils.dart` | ✅ | R8 | 纯排序/比较逻辑 ✅ |
| `core/utils/media_query_utils.dart` | ✅ | R8 | 纯过滤/排序逻辑 ✅ |
| `core/utils/media_chronology.dart` | ✅ | R8 | 纯日期比较 ✅ |
| `core/utils/app_logger.dart` | ✅ | R8 | 健壮：重试/反压/目录回退/永不抛异常 ✅ |
| `core/constants.dart` | ✅ | R8 | 纯常量 ✅ |
| `core/app_build_info.dart` | ✅ | R8 | 纯值对象 ✅ |
| `core/media_thumbnail_spec.dart` | ✅ | R8 | 纯常量 ✅ |
| `core/theme/*` (2文件) | ✅ | R8 | 纯主题定义 |
| `core/l10n.dart` | ✅ | R8 | 薄封装 |

## data/services 补充（R8）

| 文件 | 状态 | 最后审计轮次 | 备注 |
|------|------|-------------|------|
| `data/services/hide_naming.dart` | ✅ | R8 | 路径操作工具 ✅ |
| `data/services/native_video_controller.dart` | ✅ | R8 | 复杂但设计扎实：registry/时间轴偏移/seek轴探测 ✅ |
| `data/services/secure_window_service.dart` | ✅ | R8 | 薄封装 FLAG_SECURE ✅ |
| `data/services/thumbnail_cache.dart` | ✅ | R8 | LRU缓存+磁盘回退 ✅ |
| `data/services/vault_backup_manifest*.dart` (4文件) | ✅ | R8 | 编解码+校验，part文件 ✅ |
| `data/services/vault_backup_models.dart` | ✅ | R8 | 数据模型 ✅ |
| `data/services/vault_backup_support.dart` | ✅ | R8 | 文件操作+哈希校验 ✅ |
| `data/services/grid_thumbnail_service.dart` | ✅ | R8 | 委托 ThumbnailCache ✅ |
| `data/services/intent_service.dart` | ✅ | R8 | 薄封装 ✅ |
| `data/services/media_kinds.dart` | ✅ | R8 | 枚举工具 ✅ |
| `data/services/media_thumbnail_service.dart` | ✅ | R8 | 委托 ThumbnailCache ✅ |
| `data/services/playback_display_service.dart` | ✅ | R8 | 薄封装 ✅ |
| `data/services/platform/*` (5 adapters + gateways) | ✅ | R8 | 全部为薄适配器/接口 ✅ |

## domain 层（R8 补充）

| 文件 | 状态 | 最后审计轮次 | 备注 |
|------|------|-------------|------|
| `domain/enums.dart` | ✅ | R8 | 纯枚举定义 ✅ |
| `domain/models/*` (8文件) | ✅ | R8 | 纯数据类/值对象 ✅ |

## l10n 层（R8 补充）

| 文件 | 状态 | 最后审计轮次 | 备注 |
|------|------|-------------|------|
| `l10n/app_localizations.dart` | ✅ | R8 | 国际化委托，无逻辑 ✅ |

## 已知未修复问题

*（无）*

---

最后更新: 2026-10-13 R11（加密链路补修：`PlayerScreen` 解密、缩略图取帧前解密、备份带
`encryptionSalt`+`encryptedDek`、导入 KEK 缺失提示、卸载全损警告；详见 `ISSUE-029` 补修段）