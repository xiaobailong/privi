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

## 日志与故障排查

Privi 运行时会自动将关键环节的日志写入本地文件，方便排查问题。

### 日志位置

```
/storage/emulated/0/Download/Privi/logs/
```

日志文件按天分卷：`privi_log_YYYY-MM-DD.txt`

### 自动清理

应用启动时自动删除 **7 天前**的日志文件，无需手动管理。

### 日志级别

| 级别 | 含义 | 典型场景 |
|------|------|---------|
| DEBUG | 调试信息 | 播放/暂停操作、状态切换、页面跳转 |
| INFO | 关键流程 | 应用启动、导入开始/完成、视频加载、播放列表切换 |
| WARN | 警告 | 非关键异常、降级处理 |
| ERROR | 错误 | 播放失败、导入失败、文件丢失（含完整堆栈） |

### 日志覆盖的关键环节

- **应用生命周期**：启动、版本号、关闭
- **视频播放器**：`PlayerScreen` 和 `VideoPlayer` 标签详细记录加载、播放、暂停、完成、错误，以及原生 ExoPlayer 的状态变化；`PlayerController` 记录播放列表切换和连续播放逻辑
- **导入流程**：开始导入、每批传输结果、最终统计（成功/跳过/失败）
- **原生层**：Android Kotlin 侧的 ExoPlayer 初始化、准备、缓冲区、错误码、释放等完整状态机

### 排查视频播放问题

如果内置播放器异常或连续播放中断，按以下步骤提取日志：

1. 复现问题后立即用文件管理器打开 `/storage/emulated/0/Download/Privi/logs/`
2. 打开当天 `privi_log_*.txt` 文件
3. 搜索以下标签定位问题：

| 搜索关键词 | 对应问题 |
|-----------|---------|
| `VideoPlayer` | 原生播放器创建、初始化、错误 |
| `PlayerScreen` | UI 层视频加载、控制、文件缺失 |
| `PlayerController` | 播放列表切换、连续播放逻辑 |
| `PriviVideoPlayer` | Kotlin ExoPlayer 状态机、播放错误码 |
| `PriviMain` | 原生通道创建/销毁 |

常见问题定位示例：

- **黑屏/无声**：搜索 `Playback error` → 查看 error code 和 message
- **连播中断**：搜索 `Item completed` + `Next item` → 检查是否正常切换到下一首
- **视频加载失败**：搜索 `Video load failed` + `Video file not found` → 确认文件路径

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

### 一键构建（build.bat）

项目根目录提供了 `build.bat` 一键构建脚本，自动完成版本递增、代码生成、依赖安装和 APK 编译：

```bash
# 完整构建（递增版本号 → 代码生成 → 编译 → 输出带版本名的 APK）
build.bat

# 快速构建（跳过代码生成，仅递增版本并编译）
build.bat fast

# 仅运行代码生成（l10n + Drift）
build.bat codegen

# 清理所有构建产物
build.bat clean
```

#### 版本号管理

每次执行 `build.bat` 或 `build.bat fast` 都会**自动递增 `pubspec.yaml` 中的 build number**：

```
version: 1.0.25+30   →   version: 1.0.25+31
             ↑                              ↑
        build name                    build code 自动 +1
```

构建成功后输出的 APK 文件名包含完整版本号：

```
privi-1.0.25+31.apk
```

#### 首次配置

1. 打开 `build.bat`，修改顶部的三个路径变量：

   ```batch
   set "JAVA_HOME=D:\Tools\DevTools\Java\JDK\jdk-21.0.10-oracle"
   set "FLUTTER_HOME=D:\Tools\DevTools\flutter"
   set "ANDROID_HOME=D:\Tools\DevTools\Android\Sdk"
   ```

2. 确保已安装所需的构建工具：

| 工具 | 版本 | 下载 |
|------|------|------|
| Java JDK | 17+ | https://jdk.java.net/17/ 或 Oracle JDK |
| Flutter SDK | 3.38+ | https://docs.flutter.dev/get-started/install/windows |
| Android SDK | platform 37 | 通过 Android Studio 安装 或 https://developer.android.com/studio#command-line-tools-only |

3. 双击 `build.bat` 开始构建。首次构建会自动生成 `local.properties` 并下载 Gradle 依赖，耗时约 5–10 分钟。

#### 构建流程

脚本按以下顺序执行：

| 步骤 | 操作 |
|------|------|
| 1 | 环境检查（Java / Flutter / Android SDK） |
| 2 | 代码生成：`flutter gen-l10n` + `build_runner build` |
| 3 | 清理：`flutter clean` |
| 4 | 安装依赖：`flutter pub get` |
| 5 | 编译：`flutter build apk --release` |
| 6 | 将 APK 复制到项目根目录 |

构建成功后，APK 文件会出现在项目根目录，文件名格式为 `privi-<版本号>.apk`（如 `privi-1.0.25+31.apk`）。

#### 清理构建产物（clean.bat）

项目根目录提供了 `clean.bat` 一键清理脚本，彻底清除所有构建输出、缓存和临时文件：

```bash
# 清理所有构建产物
clean.bat
```

清理流程：

| 步骤 | 操作 |
|------|------|
| 1 | Flutter clean |
| 2 | 删除 `.dart_tool` 目录 |
| 3 | 删除 `build` 目录 |
| 4 | 删除 `.gradle` 缓存 |
| 5 | 删除根路径下的 `privi-*.apk` / `*.aab` 文件 |

首次配置：打开 `clean.bat`，确保顶部的 `JAVA_HOME`、`FLUTTER_HOME`、`ANDROID_HOME` 路径与 `build.bat` 一致。

#### Release 签名

正式发布时需提供 `key.properties` 签名配置（不会提交到 Git）：

```properties
storeFile=../release.keystore
storePassword=你的密钥库密码
keyAlias=你的密钥别名
keyPassword=你的密钥密码
```

脚本会自动检测 `key.properties`：存在时使用正式签名，不存在时使用 debug 签名（仅用于本地测试）。

### 项目结构

```
├── app/                # Android 应用模块
│   └── src/main/
│       ├── kotlin/     # Android 原生代码（Kotlin）
│       └── res/        # Android 资源
├── lib/                # Dart 源码
│   ├── application/    # 业务逻辑控制器
│   ├── core/           # 工具、主题、常量
│   │   └── utils/
│   │       └── app_logger.dart  # 文件日志系统（7天自动清理）
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