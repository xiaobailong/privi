[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

# 密册

个人使用、完全在本地的 **Android 媒体保险库**。将照片和视频从系统相册中隐藏，支持 **1–3 颗红心**评分、收藏、播放列表，以及**图案 / PIN + 生物识别**锁。仅支持深色主题。仅提供 APK 侧载安装，不使用云存储、账号或分析服务。

**许可证：** [MIT](./LICENSE)

---

## 安装（APK）

密册不上架 Google Play。从 GitHub Release 下载 APK 侧载安装：

1. 打开最新的 **[Release](https://github.com/xiaobailong/privi/releases/latest)**。
2. 下载 `privi-<version>.apk`。
3. 如有提示，在手机上允许浏览器或文件管理器安装未知来源应用。
4. 打开 APK 完成安装。

**系统要求：** Android 8.0+（API 26）。所有媒体数据完全保留在设备本地。

> **⚠️ 纯血鸿蒙（HarmonyOS NEXT / HarmonyOS 5.0 及以上，含 HarmonyOS 7）不支持安装 APK。**
> 这类设备使用 **HDC** 调试协议（不是 ADB，`adb devices` 看不到它），应用包格式为 `.hap/.hsp/.app`，
> `hdc install` 也只接受这三种包。本仓库只产出 Android APK，请安装到 Android 手机 / 平板，
> 或 Android 模拟器。华为设备只有系统仍为 Android 底座（HarmonyOS 4.x 及更早）时才能侧载 APK。
> 详见 [memory-bank ISSUE-018](./memory-bank/issues-solved.md)。

> 官方 GitHub Release APK 使用**永久签名密钥**（各版本签名一致）。首次安装新签名应用时，Google Play Protect 可能提示"未知应用"——点击**仍然安装**即可。

---

## 功能

### 双首页

- **Visible（系统图库）**：浏览系统相册文件夹，可直接隐藏入保险库
- **Invisible（私密保险库）**：浏览已隐藏的私密媒体，按自定义相册、合集和系统相册（全部、收藏、回收站）组织

### 媒体管理

- 隐藏 / 还原媒体（原子重命名至隐藏目录 `.privateheart_vault`）
- **滑动操作（私密相册与可见库都支持）**：把任意图片 / 视频项**向左滑动**，右侧露出「操作」「删除」两个按钮 ——
  「删除」删除本项（私密：普通相册移入回收站、回收站内永久删除；可见库：确认后从设备删除），
  「操作」进入多选；同一时刻只有一行展开，收起时按钮完全不可见，
  点已展开的行或长按其它项会先收起
- 红心评分 0–3 ❤️，1 心及以上自动入收藏
- 自定义相册与合集（创建、重命名、排序、解散）
- 回收站（恢复、永久删除，可配保留天数 1/7/30）
- 相册封面、媒体移动、文件名搜索、全局搜索、媒体详情
- 播放次数累计与最近播放记录
- 多条件排序（添加时间、文件名、评分），相册内拖拽排序
- 评分过滤

### 播放器

- 基于 Android Media3 ExoPlayer 的原生播放，支持硬件加速；可在设置切换 **libVLC**（FFmpeg，格式更全）
- **引擎自动回退**：某文件在当前引擎 15 秒内没画面时，自动换回默认引擎重试一次；仍失败就给出明确错误，不再无限转圈。该回退机制覆盖全部三个视频入口（PlayerScreen / ViewerScreen / GalleryPreviewScreen），每个 item 只回退一次，避免来回重建播放器
- **长按视频「打开方式」**：长按视频可选择外部播放器、内部默认引擎（ExoPlayer）、内部 VLC 引擎（针对默认引擎解不了的片子）。两条内部引擎入口分别绑定固定引擎，不受设置影响，避免重复项；进多选请用行左滑「操作」或 ⋮ 菜单「选择」
- **进度条两端显示时间**：左端为当前播放进度（拖动进度条时实时跟随手指），右端为视频总时长，横竖屏都显示；该控制条同时用于播放器页、私密查看器与可见库预览
- **播放区横向滑动快进 / 快退**：在播放器页画面上**右滑快进、左滑快退**（每滑过一档 = 设置里的「快进/快退步长」，画面中央实时显示方向与目标时间，松手才真正跳转；拖动过程中不动播放位置）
- **视频续播**：关闭视频时自动保存播放进度，再次打开同一视频从上次位置继续播放（看完 95% 视为已完成，下次从头开始）
- 无缝连续播放（顺序 / 按播放次数加权随机）
- 外部播放器调用（如 VLC）
- 变速播放 0.5x–2x，可配快进快退步长、静音、循环
- 幻灯片模式（图片自动切换，可配 1/3/5/10 秒间隔）
- 播放时屏幕常亮
- **画面卡住自愈**：三档看门狗（4s 重挂 Surface → 8s 微 seek → 12s 放弃），仅在「完全没出过帧」时触发
- **32 位 PTS 回绕修复**：一次性探针检测 TS/长视频 PTS 溢出回绕，自动建立 timelineOffset 补偿，确保进度与 seek 精准；普通视频不受影响
- **VLC 崩溃留痕**：libVLC 原生层未捕获异常自动落盘到 `Download/密册/logs/密册_crash_<日期>.txt`，方便离线排查

### 安全

- 图案锁 / PIN 锁 + 生物识别（指纹/面部）
- 可选 `FLAG_SECURE` 防截图录屏，或应用预览遮挡
- 可配离开后自动锁定时间
- **AES-256-GCM 文件加密**（仿华为保密柜双层密钥架构）：
  - 导入私密仓库的媒体文件自动加密；设置页可批量加密已有未加密文件、批量解密所有文件
  - KEK（密钥加密密钥）由用户密码经 PBKDF2 派生 → 加密保护 DEK（数据密钥，存数据库）→ DEK 加密媒体文件
  - Android 硬件加速（AES-NI / ARMv8 crypto extensions），1 MiB 分块流式加解密，多队列并发批量处理
  - 密钥仅存内存，锁屏时立即清除；KEK 持久化到 `FlutterSecureStorage`（Android Keystore 硬件保护），双后端容错
  - 临时文件 + 原子 rename，加解密中途崩溃不损坏原始文件
  - 向后兼容：无 `encrypted_dek` 的旧文件视为明文，正常浏览
- **密钥环与文件级密钥记录**：每个已加密文件在数据库里记录包裹其 DEK 的密钥 id（`encryption_key_id`）。导入的密钥登记为「额外密钥」，**不覆盖本机默认密钥**，因此新建密钥后再导入也不会冲突，不同密钥加密的文件各自可解密；升级后首次启动会为历史空白关系补入本机密钥 id（幂等，补过就不再写）
- 完整密钥随「保险库数据」一起导出/导入，不再有独立的密钥包入口；旧版 `.db` 密钥包仍可导入
- **文件名加密**：将已加密文件的文件名改为随机字符串，隐藏原始文件名与扩展名，防止"按扩展名扫描"的程序认出文件类型（支持批量加密/恢复文件名）
- **加密记录修复**：扫描并修复数据库加密标记与磁盘文件不一致的行（清除残留的失败加密记录）

### 导入与备份

- 系统分享 Intent 导入、批量隐藏
- **保险库数据（导出 / 导入）**：设置页唯一的备份入口，密钥导入导出已合并进来。导出为单个 `privi_manifest.json`（v6），包含媒体记录（含回收站与播放历史）、相册 / 分组 / 归属、完整密钥环、以及全部应用设置；**不含媒体文件本体**（已在手机存储里，单独拷贝）。导入时按文件名把记录重新关联到本机媒体文件；找不到文件的条目不再直接丢弃，而是记入「待恢复」标记（只记归档目录绝对路径），媒体文件就位后自动重连（启动维护后 + 添加保险库目录成功后各尝试一次，幂等，成功后清除标记）；密钥登记为额外密钥，不覆盖本机密钥
  > ⚠️ 数据文件内含**明文保险库密钥**：任何同时拿到数据文件与保险库目录的人都能解密全部文件，请存到加密网盘或离线介质，不要分享。
  > 兼容：旧版含 `media/` 文件夹的备份、以及旧 `.db` 密钥包仍可导入。
- **多保险库管理**（设置 → 存储）：可把手机上任意目录指定为额外保险库，与内置 `.privateheart_vault` **并行使用**；可切换「当前使用」的库（新隐藏的媒体写入该库）、移除登记（只删记录不删文件）。添加目录会校验不与已有库嵌套、不是存储卷根或公共媒体根目录
  > 迁移顺序：先把旧手机的保险库文件夹拷到本机 → 在管理页添加该目录 → 再导入保险库数据，媒体记录会按文件名自动匹配。
  > 顺序反过来（先导入数据、后拷媒体）也兼容：缺失媒体会记入「待恢复」，文件就位后自动关联，无需重新导出 / 导入。
- 重装后重新索引隐藏目录媒体

### 维护工具

- 孤文件扫描、EXIF 日期修复、媒体类型自动修正
- 加密记录修复：扫描数据库加密标记与磁盘文件状态不一致的行，清除失败/残留的加密记录
- 日志诊断：自动写入 `/Download/密册/logs/`，按天分卷，7 天自动清理
- VDIAG 一行式视频诊断（容器/编码/解码器/首帧/丢帧），支持开关

### 其他

- 完全离线，无云存储或分析
- 深色主题，多语言（系统默认 / English / 简体中文 / 繁體中文香港）
- 网格列数可配 2–5，相册列数可配 3–4

---

## 日志排查

日志位置：`/storage/emulated/0/Download/密册/logs/`，按天分卷，自动保留 7 天。

- **应用日志**：`密册_log_YYYY-MM-DD.txt` — 播放、导入、生命周期等全链路日志
- **崩溃日志**：`密册_crash_YYYY-MM-DD.txt` — libVLC 原生层未捕获异常（进程级崩溃时唯一留痕，正常运行时该文件为空）

视频播放问题搜 `VDIAG` 即可定位：
- `vTrackSupported=false` → 设备不支持该编码，需转码
- `firstFrameRendered=false`、`renderedFrames=0` → 一帧未上屏（典型"拖进度条才有图"）
- `vDecoder=... (software)` + 丢帧暴涨 → 软解跟不上
- `VDIAG[stall-4s/8s/12s]` → 自愈动作记录，正常播放不应出现

---

## 数据与文件路径

### 数据库

| 路径 | 说明 |
|------|------|
| `<app_documents>/privi.sqlite` | SQLite 数据库（Drift，schema v10），存储媒体索引、相册、合集、播放记录、加密 DEK 与 `encryption_key_id`（文件↔密钥关系）等全部元数据 |

> `<app_documents>` 为 Android `getApplicationDocumentsDirectory()` 返回的路径，通常为 `/data/data/com.privi.app/app_flutter/`。

### 文件存储

| 路径 | 说明 |
|------|------|
| `<app_documents>/vault/` | 应用私有仓库（`thumbs/` 缩略图、`share_staging/` 导入暂存、`media/` 媒体暂存、`staging/` 导出暂存） |
| `/storage/emulated/0/.privateheart_vault/` | **内置保险库**：共享存储隐藏根目录（隐藏的媒体文件存放于此，含 `.nomedia` 防系统媒体扫描；同一卷下 rename 即隐藏，无需拷贝） |
| 用户指定目录（`SharedPreferences: vault_libraries_v1`） | **额外保险库**：可添加多个，与内置库并行；其中一个为「当前使用」，新隐藏的媒体写入该库 |
| `<app_documents>/pending_restore/pending_restore.json` | 「待恢复」标记：导入数据时缺媒体文件，记归档目录绝对路径；媒体就位后自动重连并清除（只存路径，不存密钥 / manifest） |

### 密钥存储

| 路径 | 说明 |
|------|------|
| Android Keystore（`FlutterSecureStorage`） | 默认 KEK 与**密钥环**（历史 / 导入的额外密钥）持久化，硬件保护，双后端写入防读取失败（ISSUE-031） |
| `<app_documents>/privi.sqlite` | 每个文件的 `encrypted_dek` 及其 `encryption_key_id`，记录该文件由哪把密钥加密 |
| 用户选择的文件夹 / `privi_manifest.json` | 「保险库数据」导出文件，含全部元数据、密钥环与应用设置（不含媒体文件） |

### 日志

| 路径 | 说明 |
|------|------|
| `/storage/emulated/0/Download/密册/logs/` | 日志目录，按天分卷（`密册_log_YYYY-MM-DD.txt`），7 天自动清理 |

---

## 加解密架构

### 双层密钥体系（仿华为保密柜）

```
用户密码/图案 ──PBKDF2──► KEK（密钥加密密钥）──加密──► DEK（数据密钥，存数据库）
                                                              │
                                                     AES-256-GCM │
                                                              ▼
                                                         媒体文件密文
```

- **KEK（Key Encryption Key）**：256 位，由用户密码/图案经 PBKDF2 派生，持久化到 `FlutterSecureStorage`（Android Keystore 硬件保护）。仅存内存，锁屏时立即清除
- **DEK（Data Encryption Key）**：每个文件独立的 256 位随机密钥，由 KEK 加密后以 Base64 存数据库 `encrypted_dek` 字段
- **文件加密**：DEK 经 AES-256-GCM 加密/解密媒体文件，使用 Android `javax.crypto.Cipher` 硬件加速（AES-NI / ARMv8 crypto extensions），1 MiB 分块流式处理
- **文件格式（PRV2）**：`[nonce:12][ciphertext:N][auth_tag:16]`
- **原子写入**：加解密先写临时文件，完成后原子 rename 替换，中途崩溃不损坏原始文件
- **密钥管理**：修改密码/图案后自动旋转所有 DEK（用新 KEK 重新加密）；锁屏清除内存 KEK，解锁后从 SecureStorage 加载
- **密钥环**：导入 / 历史 KEK 按指纹 id 登记为额外密钥，解密时按每行的 `encryption_key_id` 取对应 KEK（空值回退当前默认密钥）；多把密钥互不覆盖，因此「新建密钥后再导入」不再冲突

### 加解密服务

| 服务 | 源码 | 职责 |
|------|------|------|
| `MediaEncryptionService` | `lib/data/services/media_encryption_service.dart` | 单文件加解密核心：DEK 生成、DEK 加解密（Dart cryptography 库）、文件加解密调度 |
| `NativeCryptoService` | `lib/data/services/native_crypto_service.dart` | 通过 MethodChannel 桥接 Android `CryptoHandler.kt`（`javax.crypto.Cipher`） |
| `BatchEncryptionService` | `lib/data/services/batch_encryption_service.dart` | 批量加密已有明文文件（设置页「加密已有文件」），多队列并发，支持暂停/恢复 |
| `BatchDecryptionService` | `lib/data/services/batch_decryption_service.dart` | 批量解密恢复明文（设置页「解密所有文件」），DEK 先解密后清除，崩溃安全 |
| `FilenameEncryptionService` | `lib/data/services/filename_encryption_service.dart` | 文件名加密/恢复：将文件名改为随机字符串，隐藏原始文件名与扩展名 |
| `EncryptionKeyManager` | `lib/data/services/encryption_key_manager.dart` | KEK 生命周期（派生、持久化、加载、清除）+ 密钥环（`keyForId` / `registerKey` / `listKeys`），双 SecureStorage 后端容错 |
| `EncryptionKeyLinkBackfill` | `lib/data/services/encryption_key_link_backfill.dart` | 启动时按空白行数幂等补入历史文件的 `encryption_key_id` |
| `KeyBackupService` | `lib/data/services/key_backup_service.dart` | 旧版 `.db` 密钥包的只读兼容导入（新导出已并入「保险库数据」） |
| `VaultBackupService` | `lib/data/services/vault_backup_service.dart` | 「保险库数据」v6 导出 / 导入：元数据 + 密钥环 + 全量设置，不含媒体文件 |
| `VaultLibraryRegistry` | `lib/data/services/vault_library_registry.dart` | 多保险库注册表（添加 / 当前库 / 移除） |
| `EncryptionRecordRepairService` | `lib/data/services/encryption_record_repair_service.dart` | 修复加密记录不一致（DB 标记已加密但文件为明文等），设置页「清除失败加密记录」 |

---

## 开发

### 前置要求

| 工具 | 说明 |
|------|------|
| Flutter 3.38+ | Flutter SDK |
| JDK 17+ | Android Gradle 构建 |
| Android SDK | platform 37、build-tools、cmdline-tools |

> 本项目仅支持 Android 平台。

### 常用命令

```bash
flutter pub get                           # 安装依赖
flutter gen-l10n                          # 代码生成（l10n）
flutter pub run build_runner build        # 代码生成（Drift）
flutter analyze                           # 静态分析（本机可能挂死，见 memory-bank PIT-014 / PIT-020）
flutter run                               # 运行
flutter build apk --release               # 构建 Release APK
```

### 一键构建

构建脚本在 `scripts\build.bat`（依赖的 PowerShell 辅助脚本在 `scripts/tools/`）：

```bash
scripts\build.bat           # 完整构建 + 递增版本 + 发布 Release
scripts\build.bat fast      # 跳过代码生成（其余步骤照跑）
scripts\build.bat gradle    # 仅 Gradle 编译（不递增版本、不出根目录 APK）
scripts\build.bat codegen   # 仅代码生成
scripts\build.bat release   # 只发布已有 APK，不重新编译
scripts\build.bat norelease # 构建但不发布 Release（等价于 set SKIP_RELEASE=1）
scripts\build.bat clean     # 清理所有构建产物
```

实际顺序是 `[1/7] 代码生成 → [2/7] 递增版本 → [3/4] 清理与 pub get → [5/7] 编译 → [6/7] 复制 APK → [7/7] 发布 Release`。
`fast` / `gradle` / `clean` / `codegen` 的跳转发生在 `norelease` 参数扫描之前，因此**不要**写 `fast norelease`；用 `scripts\build.bat norelease` 或先 `set SKIP_RELEASE=1`。

每次完整 / fast 构建自动把 `pubspec.yaml` 版本号的 patch +1（`1.1.0` → `1.1.1`），满 99 进位（`1.0.99` → `1.1.0`）；产物为 `privi-<version>.apk`（如 `privi-1.1.1.apk`，**不带** `+build` 后缀）；Android `versionCode` 由该版本号推导（`1.1.1` → 10101）。构建会改脏 `pubspec.yaml`，构建成功后需单独提交这次版本递增（ADR-021 / ADR-026）。

首次使用需修改 `scripts\build.bat` 顶部的 `JAVA_HOME`、`FLUTTER_HOME`、`ANDROID_HOME` 路径。

发布 Release 依赖 `gh` CLI（`winget install --id GitHub.cli`），未安装或未登录时自动跳过。
Release 仅从 `main` 分支发布，且要求当前提交**已推送到 origin**（否则只出包不发 Release，可事后跑 `scripts\build.bat release` 补发）。

### 安装到手机（Android）

```bash
adb devices -l                        # 确认设备在线（需开启 USB 调试并授权）
adb install -r privi-<version>.apk    # 覆盖安装（保留数据）
adb install -r -d privi-<version>.apk # 允许版本号降级
```

> 纯血鸿蒙（HarmonyOS NEXT / HarmonyOS 5.0 及以上）**不支持 ADB 与 APK**，
> `adb devices` 永远看不到它（它走 HDC），只能用 Android 设备安装 —— 详见上文的鸿蒙提示与 `ISSUE-018`。

### 构建排查

构建脚本内置几道防「卡死 / 静默失败」的保险：WMI 自检（Dart 读 OS 版本）、`pub get` 看门狗、
编译前内存回收、产物与哈希校验。过程日志 `build/build_full.log`，结论 `build/build_exit.log`
（看 `BUILD_FAILED=` / `WMI_FAILED=`）。

**已知问题、复发判据与排查方法集中在 [memory-bank/](memory-bank/README.md)**，遇到问题先查那里，避免重复排查：

| 现象 | 条目 |
| --- | --- |
| 构建「卡住不动」、日志 0 字节、进程杀不掉 | `ISSUE-001`（本机 WMI 无响应 → 所有 flutter 命令静默挂死） |
| Gradle 报 `Unresolved reference 'extraGenSnapshotOptions'` | `ISSUE-012` / `ADR-018`（Flutter 3.47 已移除该 DSL，改用 Gradle project property） |
| `pubspec.yaml` 版本号不递增 | `ISSUE-005` |
| 私密相册滑动操作 / 进度条时间显示的取舍 | `ADR-024` / `ADR-025` |
| Gradle 守护进程消失 / `OutOfMemoryError (arena.cpp)` | `ISSUE-004`（编译前内存回收） |
| 加密文件打不开/播放器崩溃 / 批量加密 OOM | `ISSUE-024` / `PIT-031` / `ADR-033` |

本机实测可用的工具链组合（改 `android/settings.gradle.kts` / wrapper 前先看 `memory-bank/decisions.md`）：

| 组件 | 版本 |
| --- | --- |
| Flutter / Dart | 3.47.4 / 3.13.3（`flutter: ">=3.38.0"`） |
| JDK | 21（`build.bat` 顶部路径；Gradle 内 `sourceCompatibility = 17`） |
| AGP / Gradle | 9.1.0 / 9.3.1（`android/gradle.properties` 里 `android.newDsl=false`） |

### 项目结构

```
├── app/src/main/kotlin/  # Android 原生代码（CryptoHandler 硬件加解密、ExoPlayer、隐私保护等）
├── lib/
│   ├── application/      # 业务逻辑控制器（Riverpod）
│   ├── core/             # 工具、主题、常量、路径定义（VaultPaths）
│   ├── data/
│   │   ├── db/           # Drift 数据库（schema v10：媒体索引、DEK、密钥 id 等）
│   │   ├── repositories/ # 仓库层
│   │   └── services/     # 服务层（加解密、导入导出、备份、维护）
│   ├── domain/           # 领域模型
│   ├── l10n/             # 多语言资源
│   └── presentation/     # UI 页面和组件
├── assets/branding/      # 应用图标
├── drift_schemas/        # 数据库迁移 Schema
├── scripts/              # 构建辅助脚本（PowerShell：哈希 / 内存 / pub get 看门狗 / WMI 守卫 / 版本号）
├── tmp/                  # 本地临时目录（Cline 工作产物，gitignored、可整目录删除；约定见 .clinerules/tmp-files.md）
├── memory-bank/          # 跨会话知识库：已排查问题 / 踩坑记录 / 技术决策（见 memory-bank/README.md）
└── pubspec.yaml
```

---

## 感谢

> This is an optional voluntary donation to support project development.
> Donation is NOT required to use this software and grants no commercial license.

如果这个工具帮到了您，欢迎随意赞赏！

![赞助](img/pay.jpg)

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.