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

### 导入与备份

- 系统分享 Intent 导入、批量隐藏
- 保险库完整导出 / 恢复（数据库 + 文件 + manifest 校验）
- 重装后重新索引隐藏目录媒体

### 维护工具

- 孤文件扫描、EXIF 日期修复、媒体类型自动修正
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

项目根目录 `build.bat` 自动完成版本递增、代码生成、编译与 Release 发布（其依赖的 PowerShell 辅助脚本统一放在 `scripts/` 目录）：

```bash
build.bat           # 完整构建（递增版本 → 代码生成 → 编译 → 发布 Release）
build.bat fast      # 快速构建（跳过代码生成）
build.bat gradle    # 仅 Gradle 编译
build.bat codegen   # 仅代码生成
build.bat release   # 只发布（不重新编译）
build.bat norelease # 构建但不发布 Release（等价于 set SKIP_RELEASE=1）
build.bat clean     # 清理所有构建产物
```

每次 `build.bat` / `build.bat fast` 自动把 `pubspec.yaml` 版本号的最后一段 +1（`1.0.59` → `1.0.60`），产物为 `privi-<version>.apk`（如 `privi-1.0.59.apk`，**不带** `+build` 后缀）；Android `versionCode` 由该版本号推导（`1.0.59` → 10059）。

首次使用需修改 `build.bat` 顶部的 `JAVA_HOME`、`FLUTTER_HOME`、`ANDROID_HOME` 路径。

发布 Release 依赖 `gh` CLI（`winget install --id GitHub.cli`），未安装或未登录时自动跳过。
Release 仅从 `main` 分支发布，且要求当前提交**已推送到 origin**（否则只出包不发 Release，可事后跑 `build.bat release` 补发）。

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

本机实测可用的工具链组合（改 `android/settings.gradle.kts` / wrapper 前先看 `memory-bank/decisions.md`）：

| 组件 | 版本 |
| --- | --- |
| Flutter / Dart | 3.47.4 / 3.13.3（`flutter: ">=3.38.0"`） |
| JDK | 21（`build.bat` 顶部路径；Gradle 内 `sourceCompatibility = 17`） |
| AGP / Gradle | 9.1.0 / 9.3.1（`android/gradle.properties` 里 `android.newDsl=false`） |

### 项目结构

```
├── app/src/main/kotlin/  # Android 原生代码（ExoPlayer、隐私保护等）
├── lib/
│   ├── application/      # 业务逻辑控制器（Riverpod）
│   ├── core/             # 工具、主题、常量
│   ├── data/             # 数据层（Drift DB、仓库、服务）
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

如果这个工具帮到了您，欢迎随意赞赏！

![赞助](img/pay.jpg)