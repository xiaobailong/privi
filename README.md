# Privi

[简体中文](./README.md) · [English](./README.zh-CN.md) · [繁體中文（香港）](./README.zh-HK.md)

个人使用、完全在本地的 **Android 媒体保险库**。将照片和视频从系统相册中隐藏，支持 **1–3 颗红心**评分、收藏、播放列表，以及**图案 / PIN + 生物识别**锁。仅支持深色主题。仅提供 APK 侧载安装，不使用云存储、账号或分析服务。

**作者：** [kcng0](https://github.com/kcng0) · **许可证：** [MIT](./LICENSE) · **支持：** [Buy Me a Coffee](https://buymeacoffee.com/kcng0)

这是一个个人项目，优先保持简单，不做功能堆叠。

---

## 安装（APK）

Privi 不上架 Google Play。从 GitHub Release 下载 APK 侧载安装：

1. 打开最新的 **[Release](https://github.com/kcng0/privi/releases/latest)**。
2. 下载 `privi-<version>.apk`（可选下载 `SHA256SUMS` 校验文件）。
3. 在电脑上校验文件完整性：
   ```bash
   sha256sum -c SHA256SUMS
   ```
4. 如有提示，在手机上允许浏览器或文件管理器安装未知来源应用。
5. 打开 APK 完成安装。

每个 Release 包含：

| 文件 | 用途 |
|------|------|
| `privi-<version>.apk` | 侧载安装包 |
| `SHA256SUMS` / `.sha256` / `CHECKSUMS.txt` | 完整性校验 |
| **源代码（zip / tar.gz）** | GitHub 根据 tag 自动附加 |

**系统要求：** Android 8.0+（API 26）。所有媒体数据完全保留在设备本地。

> 官方 GitHub Release APK 使用**永久签名密钥**（各版本签名一致）。首次安装新签名应用时，Google Play Protect 可能提示"未知应用"——点击**仍然安装**即可，建议保持有害应用检测开启。

### 热更新

从 **v1.0.4** 起，更新完全由用户手动控制。打开 **设置 → 检查更新**，会先检查 GitHub 最新稳定版 Release，再检查当前版本对应的 Shorebird 热更新通道。发现新版本 Release 时显示确认对话框并跳转到 GitHub Release 页面；有签名的 Dart 补丁时，Privi 在下载前会请求确认。自 **v1.0.5** 起，补丁下载成功后自动重启使补丁立即生效。关于页面可查看基础版本号、构建号和已应用补丁编号。

Android 原生代码、插件、权限、内置资源和 Flutter 引擎相关的变更仍需安装新 APK。网络请求仅在用户手动检查更新时发生，保险库媒体数据始终保留在本地。

---

## 功能

- **Visible | Invisible 双首页**：浏览系统相册文件夹或私密保险库
- **马赛克/列表视图独立记忆**：每个首页页签分别保存自己的布局偏好
- **隐藏文件夹**：从系统相册中移除媒体，磁盘文件不丢失
- **一致高清封面**：隐藏前后使用同一张 768px 视频帧
- **稳定日期排序**：隐藏后文件夹仍保持原始拍摄时间顺序
- **红心评分（0–3）** + 收藏、相册排序、拖拽手动整理
- **合集管理**：创建、重命名、整理成员、无损解散（不删除媒体文件）
- **内置 ExoPlayer 播放器**：基于 Android Media3 ExoPlayer 的原生视频播放，支持**无缝连续播放**（视频结束后自动切换到下一首），格式兼容性远超系统 MediaPlayer
- **外部播放器支持**：可调用手机安装的第三方播放器（如 VLC），并追踪播放结果
- **图案 / PIN + 生物识别**锁，可选 `FLAG_SECURE`（禁止截图录屏）
- **全局路由恢复锁**：覆盖所有页面和页签，仅追踪中的外部媒体应用返回可临时绕过
- **分享导入**：支持通过系统分享 Intent 将图片和视频导入 Privi
- 完全离线，所有数据保存在设备本地

### 关键词

`android photo vault` · `hide photos from gallery` · `private gallery app` ·
`video vault` · `offline media locker` · `pattern lock gallery` ·
`biometric photo lock` · `sideload apk vault` · `flutter media vault` ·
`hide videos android` · `no cloud gallery` · `exoplayer video player`

GitHub 主题标签：`flutter` `android` `photo-vault` `video-vault` `private-gallery`
`hide-photos` `biometric-lock` `privacy` `offline` `sideload` `apk` `exoplayer` `mit-license`

---

## 截图

以下截图来自当前 **Privi v1.0.25** Flutter UI，使用合成文件夹、相册、合集和内置应用图标生成。未使用任何个人媒体或真实设备，展示的是实际发布的深色主题及最新 Visible/Invisible/合集流程。

维护者无需 Android 设备即可重新生成：
`flutter test tool/readme_screenshots_test.dart --update-goldens`

| Visible 马赛克 | Visible 列表 | Invisible 马赛克 |
|:--------------:|:------------:|:----------------:|
| <img src="assets/screenshots/01_visible_mosaic.png" width="200" alt="Visible 系统文件夹马赛克视图"> | <img src="assets/screenshots/02_visible_list.png" width="200" alt="Visible 系统文件夹列表视图"> | <img src="assets/screenshots/03_invisible_mosaic.png" width="200" alt="Invisible 相册和合集马赛克视图"> |

| Invisible 列表 | 合集马赛克 | 合集列表 |
|:--------------:|:--------:|:------:|
| <img src="assets/screenshots/04_invisible_list.png" width="200" alt="Invisible 相册和合集列表视图"> | <img src="assets/screenshots/05_collection_mosaic.png" width="200" alt="合集成员马赛克视图"> | <img src="assets/screenshots/06_collection_list.png" width="200" alt="合集成员列表视图"> |

| 合集管理 | 设置 | 锁设置 |
|:--------:|:----:|:------:|
| <img src="assets/screenshots/07_collection_management.png" width="200" alt="合集成员管理菜单"> | <img src="assets/screenshots/08_settings.png" width="200" alt="安全、显示和播放设置"> | <img src="assets/screenshots/09_lock_setup.png" width="200" alt="图案锁设置页面"> |

- **Visible 马赛克/列表**：按页签隔离保存的首页视图切换
- **Invisible 马赛克/列表**：保险库相册、评分、数量和合集
- **合集页面**：成员马赛克/列表视图及增删改查管理
- **设置/锁**：安全、显示、播放和首次图案设置

---

## 开发

### 前置要求

| 工具 | 说明 |
|------|------|
| Flutter **3.44.6** | 推荐使用 FVM（`.fvmrc` 锁定精确版本） |
| JDK 17+ | Android Gradle 构建所需 |
| Android SDK | platform **37**、build-tools、cmdline-tools，需接受 licenses |
| 设备 / 模拟器 | Android 8.0+（API 26） |

> **注意：** 本项目已移除 iOS 支持，仅构建 Android 版本。

### Ubuntu / WSL2 一键设置

```bash
git clone https://github.com/kcng0/privi.git
cd privi

# 可选：安装 Flutter、Android SDK 及 licenses
./scripts/install-toolchain.sh && source ~/.bashrc

# 生成原生脚手架、安装依赖、运行代码生成
./scripts/bootstrap.sh

# 在已连接设备上运行
make run
```

### 日常命令

```bash
make run       # 在已连接设备上启动
make test      # 单元测试 + widget 测试
make analyze   # 静态分析
make format    # dart format lib test
make gen       # build_runner 代码生成（Drift + Riverpod）
make watch     # 代码生成 watch 模式
make apk       # 生成侧载 Release APK
make help      # 列出所有 Make 目标
```

不使用 `make` 时，可使用 `fvm flutter …`（未安装 FVM 则直接用 `flutter`）。

完整环境说明、故障排查和 CI 细节见 **[DEVELOPMENT.md](./DEVELOPMENT.md)**。

### 仓库结构

```
├── lib/           # Dart 源码（按功能组织）
├── test/          # 单元测试和 widget 测试
├── android/       # Android 宿主工程
├── assets/        # 品牌 / 图标 / 截图
├── scripts/       # bootstrap + 工具链安装器
├── .github/       # CI + Release 工作流
├── pubspec.yaml
├── Makefile
└── DEVELOPMENT.md
```

---

## Release 与 CI

| 工作流 | 触发条件 | 内容 |
|--------|---------|------|
| [CI](./.github/workflows/ci.yaml) | push / PR 到 `main` | format、codegen、analyze、test |
| [Release](./.github/workflows/release.yml) | tag `v*` 或手动触发 | Shorebird 基础 APK、校验和与 GitHub Release |
| [Patch](./.github/workflows/patch.yml) | 在 `main` 上手动触发 | 现有基础版本的签名 Dart 补丁 |

从干净的 `main` 创建 Release：

```bash
# 修改 pubspec.yaml 版本号（例如 0.1.0+1 → 0.1.1+2），提交后执行：
git tag v0.1.1
git push origin v0.1.1
```

也可以通过 **Actions → Release APK → Run workflow** 手动触发。仅包含 Dart 代码的修复无需新 APK，通过 PR 合并后运行 **Actions → Shorebird Patch**，指定准确的基础版本即可（例如 `1.0.4+5`）。

---

## 支持

如果 Privi 对你有所帮助，欢迎支持开发：

**[Buy Me a Coffee](https://buymeacoffee.com/kcng0)**

## 社区

- **[Linux do](https://linux.do)**

## 许可证

[MIT](./LICENSE) — Copyright (c) 2026 [kcng0](https://github.com/kcng0)