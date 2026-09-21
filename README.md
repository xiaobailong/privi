# 密册

个人使用、完全在本地的 **Android 媒体保险库**。将照片和视频从系统相册中隐藏，支持 **1–3 颗红心**评分、收藏、播放列表，以及**图案 / PIN + 生物识别**锁。仅支持深色主题。仅提供 APK 侧载安装，不使用云存储、账号或分析服务。

**作者：** [kcng0](https://github.com/kcng0) · **许可证：** [MIT](./LICENSE)

---

## 安装（APK）

密册不上架 Google Play。从 GitHub Release 下载 APK 侧载安装：

1. 打开最新的 **[Release](https://github.com/xiaobailong/privi/releases/latest)**。
2. 下载 `privi-<version>.apk`。
3. 如有提示，在手机上允许浏览器或文件管理器安装未知来源应用。
4. 打开 APK 完成安装。

**系统要求：** Android 8.0+（API 26）。所有媒体数据完全保留在设备本地。

> 官方 GitHub Release APK 使用**永久签名密钥**（各版本签名一致）。首次安装新签名应用时，Google Play Protect 可能提示"未知应用"——点击**仍然安装**即可。

---

## 功能

### 双首页

- **Visible（系统图库）**：浏览系统相册文件夹，可直接隐藏入保险库
- **Invisible（私密保险库）**：浏览已隐藏的私密媒体，按自定义相册、合集和系统相册（全部、收藏、回收站）组织

### 媒体管理

- 隐藏 / 还原媒体（原子重命名至隐藏目录 `.privateheart_vault`）
- 红心评分 0–3 ❤️，1 心及以上自动入收藏
- 自定义相册与合集（创建、重命名、排序、解散）
- 回收站（恢复、永久删除，可配保留天数 1/7/30）
- 相册封面、媒体移动、文件名搜索、全局搜索、媒体详情
- 播放次数累计与最近播放记录
- 多条件排序（添加时间、文件名、评分），相册内拖拽排序
- 评分过滤

### 播放器

- 基于 Android Media3 ExoPlayer 的原生播放，支持硬件加速
- 无缝连续播放（顺序 / 按播放次数加权随机）
- 外部播放器调用（如 VLC）
- 变速播放 0.5x–2x，可配快进快退步长、静音、循环
- 幻灯片模式（图片自动切换，可配 1/3/5/10 秒间隔）
- 播放时屏幕常亮
- **画面卡住自愈**：三档看门狗（4s 重挂 Surface → 8s 微 seek → 12s 放弃），仅在「完全没出过帧」时触发
- **32 位 PTS 回绕修复**：一次性探针检测 TS/长视频 PTS 溢出回绕，自动建立 timelineOffset 补偿，确保进度与 seek 精准；普通视频不受影响

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
flutter analyze                           # 静态分析
flutter run                               # 运行
flutter build apk --release               # 构建 Release APK
```

### 一键构建

项目根目录 `build.bat` 自动完成版本递增、代码生成、编译与 Release 发布：

```bash
build.bat           # 完整构建（递增版本 → 代码生成 → 编译 → 发布 Release）
build.bat fast      # 快速构建（跳过代码生成）
build.bat gradle    # 仅 Gradle 编译
build.bat codegen   # 仅代码生成
build.bat release   # 只发布（不重新编译）
build.bat clean     # 清理所有构建产物
```

每次 `build.bat` / `build.bat fast` 自动递增 `pubspec.yaml` 的 build number，输出的 APK 文件名含完整版本号。

首次使用需修改 `build.bat` 顶部的 `JAVA_HOME`、`FLUTTER_HOME`、`ANDROID_HOME` 路径。

发布 Release 依赖 `gh` CLI（`winget install --id GitHub.cli`），未安装或未登录时自动跳过。

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
└── pubspec.yaml
```

---

## 感谢

如果这个工具帮到了您，欢迎随意赞赏！

![赞助](img/pay.jpg)