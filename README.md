# Privi

个人使用、完全在本地的 **Android 媒体保险库**。将照片和视频从系统相册中隐藏，支持 **1–3 颗红心**评分、收藏、播放列表，以及**图案 / PIN + 生物识别**锁。仅支持深色主题。仅提供 APK 侧载安装，不使用云存储、账号或分析服务。

**作者：** [kcng0](https://github.com/kcng0) · **许可证：** [MIT](./LICENSE)

---

## 安装（APK）

Privi 不上架 Google Play。从 GitHub Release 下载 APK 侧载安装：

1. 打开最新的 **[Release](https://github.com/kcng0/privi/releases/latest)**。
2. 下载 `privi-<version>.apk`。
3. 如有提示，在手机上允许浏览器或文件管理器安装未知来源应用。
4. 打开 APK 完成安装。

**系统要求：** Android 8.0+（API 26）。所有媒体数据完全保留在设备本地。

> 官方 GitHub Release APK 使用**永久签名密钥**（各版本签名一致）。首次安装新签名应用时，Google Play Protect 可能提示"未知应用"——点击**仍然安装**即可。

### 热更新

打开 **设置 → 检查更新**，会先检查 GitHub 最新稳定版 Release，再检查当前版本对应的 Shorebird 热更新通道。发现新版本 Release 时显示确认对话框并跳转到 GitHub Release 页面；有签名的 Dart 补丁时，Privi 在下载前会请求确认。补丁下载成功后自动重启使补丁立即生效。

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
- **内置 ExoPlayer 播放器**：基于 Android Media3 ExoPlayer 的原生视频播放，支持**无缝连续播放**（视频结束后自动切换到下一首）
- **外部播放器支持**：可调用手机安装的第三方播放器（如 VLC），并追踪播放结果
- **图案 / PIN + 生物识别**锁，可选 `FLAG_SECURE`（禁止截图录屏）
- **全局路由恢复锁**：覆盖所有页面和页签，仅追踪中的外部媒体应用返回可临时绕过
- **分享导入**：支持通过系统分享 Intent 将图片和视频导入 Privi
- 完全离线，所有数据保存在设备本地

---

## 开发

### 前置要求

| 工具 | 说明 |
|------|------|
| Flutter 3.44+ | Flutter SDK |
| JDK 17+ | Android Gradle 构建所需 |
| Android SDK | platform 37、build-tools、cmdline-tools |

> 本项目仅支持 Android 平台。

### 常用命令

```bash
# 安装依赖
flutter pub get

# 代码生成（l10n + Drift）
flutter gen-l10n
flutter pub run build_runner build

# 静态分析
flutter analyze

# 运行到已连接设备
flutter run

# 构建 Release APK
flutter build apk --release
```

### 项目结构

```
├── app/                # Android 应用模块
│   └── src/main/
│       ├── kotlin/     # Android 原生代码（Kotlin）
│       └── res/        # Android 资源
├── lib/                # Dart 源码
│   ├── application/    # 业务逻辑控制器
│   ├── core/           # 工具、主题、常量
│   ├── data/           # 数据层（数据库、服务、仓库）
│   ├── domain/         # 领域模型
│   ├── l10n/           # 多语言
│   └── presentation/   # UI 页面和组件
├── assets/branding/    # 应用图标
├── drift_schemas/      # 数据库迁移 Schema
├── gradle/             # Gradle Wrapper
├── build.gradle.kts    # Android 根构建脚本
├── settings.gradle.kts # Android 项目设置
└── pubspec.yaml        # Flutter 项目配置
```

## 感谢

如果这个工具帮到了您，欢迎随意赞赏，无论多少都是对我最大的鼓励！

![赞助](img/pay.jpg)