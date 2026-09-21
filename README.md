# 密册

个人使用、完全在本地的 **Android 媒体保险库**。将照片和视频从系统相册中隐藏，支持 **1–3 颗红心**评分、收藏、播放列表，以及**图案 / PIN + 生物识别**锁。仅支持深色主题。仅提供 APK 侧载安装，不使用云存储、账号或分析服务。

**作者：** [kcng0](https://github.com/kcng0) · **许可证：** [MIT](./LICENSE)

---

## 安装（APK）

密册不上架 Google Play。从 GitHub Release 下载 APK 侧载安装：

1. 打开最新的 **[Release](https://github.com/kcng0/privi/releases/latest)**。
2. 下载 `privi-<version>.apk`。
3. 如有提示，在手机上允许浏览器或文件管理器安装未知来源应用。
4. 打开 APK 完成安装。

**系统要求：** Android 8.0+（API 26）。所有媒体数据完全保留在设备本地。

> 官方 GitHub Release APK 使用**永久签名密钥**（各版本签名一致）。首次安装新签名应用时，Google Play Protect 可能提示"未知应用"——点击**仍然安装**即可。

---

## 功能

### 双首页

- **Visible（系统图库）**：浏览系统相册文件夹（需要存储权限），照片与视频混合展示，可直接隐藏入保险库
- **Invisible（私密保险库）**：浏览已隐藏的私密媒体，按用户自定义相册、合集和系统相册（全部、收藏、回收站）组织
- **马赛克/列表视图** 独立记忆：Visible 和 Invisible 首页各自保存独立的布局偏好（mosaic / list）

### 媒体管理

- **隐藏媒体**：从系统相册中移除选定媒体文件，以原子重命名方式转移到隐藏目录（`.privateheart_vault`），磁盘文件不丢失
- **统一媒体类型识别**：以文件容器扩展名为准判定图片 / 视频（覆盖 `.mp4` `.mkv` `.ts` `.m2ts` `.wmv` `.flv` `.rm` `.rmvb` 等 30+ 种视频容器），不依赖系统相册上报的 MIME，避免视频被误判为照片
- **Unhide 还原**：将已隐藏的媒体恢复到系统图库（下载目录或已知原路径）
- **红心评分（0–3 ❤️）**：为每个媒体文件评分，1 心及以上自动加入收藏（Favorites）
- **自定义相册**：创建、重命名、删除用户相册（删除相册不删除媒体文件）
- **合集（AlbumGroup）**：创建合集分组，添加相册到合集，重命名、拖拽排序、无损解散合集
- **相册置顶**：将常用相册固定到 Invisible 首页顶部
- **私密相册类型**：新建私密相册时选择「仅照片」或「仅视频」，首页相册卡片显示类型徽标；旧相册与系统相册保持照片+视频混合显示
- **回收站**：删除的媒体先进入回收站，支持恢复或永久删除，可配置保留天数（1 / 7 / 30 天）
- **相册封面**：为用户相册和收藏夹自定义设置封面
- **媒体移动**：将媒体文件移动到其他相册
- **媒体搜索**：在相册网格中按文件名搜索
- **全局搜索**：私密首页 ⋮ → 搜索，按文件名搜索全部未锁定媒体（照片与视频同时匹配）
- **媒体详情**：查看文件的名称、类型、MIME、尺寸、分辨率、评分、播放次数、最近播放、日期、路径等详细信息
- **播放记录**：自动累计每个照片/视频的播放次数（Viewer 与播放器中被打开即计数），并按记录时间记录最近一次播放
- **媒体排序**：支持按添加时间、文件名、评分排序（支持多条件组合），相册支持自定义拖拽排序
- **评分过滤**：按红心数（⭐ / ❤️❤️ / ❤️❤️❤️）、收藏、未评分过滤

### 播放器

- **内置 ExoPlayer 播放器**：基于 Android Media3 ExoPlayer 的原生视频播放，支持硬件加速
- **无缝连续播放**：视频播放结束后自动切换到下一首（顺序或随机）
- **按播放次数随机**：随机播放按播放次数加权——播放越多出现概率越低（权重 1/(1+次数)²），可设为「播放满 3 / 5 / 10 / 20 次后基本不出现」；默认开启，也可关闭为完全等概率随机
- **外部播放器**：可调用手机安装的第三方播放器（如 VLC），并追踪播放结果
- **幻灯片模式**：图片浏览时支持自动幻灯片切换，可配置间隔（1 / 3 / 5 / 10 秒）；视频播放完自动切换
- **播放速度控制**：支持 0.5x / 0.75x / 1x / 1.25x / 1.5x / 1.75x / 2x 变速播放
- **快进/快退**：可配置跳跃步长（3 / 5 / 10 / 15 秒）
- **静音 / 循环播放**：内置播放器支持静音切换，Viewer 支持单视频循环
- **播放时屏幕常亮**：播放视频和幻灯片时保持屏幕唤醒
- **画面卡住自愈**：若「已在播放但一帧都没上屏」（典型故障：拖进度条有图、正常播放画面不动），看门狗按 **4 秒 / 8 秒 / 12 秒** 三档补救——重挂 Surface → 微 seek（当前位置 +100ms）→ 放弃并记录日志；每档最多各触发一次，且只在「完全没出过帧」时动作，正常播放、暂停、缓冲期间不受影响
- **32 位 PTS 回绕修复**：部分视频（尤其长视频、TS 切片）的 32 位 PTS 会溢出回绕，导致播放器在数秒内判定「已播完」而跳过。播放器启动时通过一次性探针（300ms 不可见前推）自动判断时间轴基准，检测到回绕后建立偏移补偿（`timelineOffset`），确保进度正确和 seek 精准；普通视频行为完全不受影响
- **长按视频选择播放方式**：在媒体网格（Invisible / Visible）中长按视频弹出底部菜单，可选择「外部播放器」「应用内播放」或进入选择模式；外部播放不可用时该项置灰并显示原因

### 安全

- **图案锁**（默认）或**PIN 锁**（兼容旧版），支持生物识别（指纹/面部）快速解锁
- **隐私保护**：可选 `FLAG_SECURE` 防截图录屏，或应用预览遮挡
- **自动锁定**：可配置离开应用后自动锁定时间（立即 / 30 秒 / 1 分钟 / 5 分钟）
- **全局路由恢复锁**：覆盖所有页面和页签，仅追踪中的外部媒体应用返回可临时绕过

### 导入与备份

- **分享导入**：支持通过系统分享 Intent 将图片和视频导入密册
- **批量导入**：从 Visible 系统图库批量选择并隐藏媒体
- **保险库导出**：将完整保险库（数据库 + 媒体文件）导出到本地文件夹，附带 manifest 校验
- **保险库恢复**：从本地备份文件夹恢复保险库数据
- **重装后恢复**：重新索引仍在隐藏目录中的媒体文件，可选同时 Unhide 还原到图库

### 维护工具

- **孤文件扫描**：扫描保险库隐藏目录中未被数据库记录的文件
- **日期修复**：从 EXIF / 视频元数据提取原始拍摄日期，修正排序
- **媒体类型修复**：启动维护时逐条核对记录的图片 / 视频类型与扩展名是否一致，自动更正历史误判（含回收站中的媒体）
- **日志诊断**：自动将运行日志写入 `/Download/密册/logs/`，按天分卷，7 天自动清理，支持开关；视频播放会额外输出一行式 `VDIAG[...]` 诊断（容器 / 编码 / 实际解码器 / 色彩位深 / 是否出过第一帧 / 丢帧数），用于只凭用户日志定位「黑屏」「画面不动」
- **播放记录管理**：设置页可一键清除全部播放次数与最近播放时间，清除后所有媒体重新回到等概率随机

### 其他

- 完全离线，所有媒体数据保存在设备本地，无云存储、账号或分析服务
- 仅支持深色主题
- 多语言：系统默认 / English / 简体中文（zh_CN）/ 繁體中文香港（zh_HK）
- 网格列数可配置（2–5 列），相册列数可配置（3–4 列）

---

## 日志与故障排查

密册运行时会自动将关键环节的日志写入本地文件，方便排查问题。

### 日志位置

```
/storage/emulated/0/Download/密册/logs/
```

日志文件按天分卷：`密册_log_YYYY-MM-DD.txt`

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
- **视频播放诊断（VDIAG）**：以单行 `VDIAG[...]` 汇总视频轨事实——容器与编码（`avc1` / `hvc1` / `av01` / `mp4v` 等）、实际选中的解码器（硬件/软件）与初始化耗时、色彩位深与 HDR、视频轨是否被设备支持、`firstFrameRendered`（第一帧是否真的上屏）、`renderedFrames` / `droppedFrames`；打开文件前还会记录一行文件事实 `Source file: ...`（大小 / mtime / 前 64 字节 / `moov` 是否在文件尾）
- **导入流程**：开始导入、每批传输结果、最终统计（成功/跳过/失败）
- **原生层**：Android Kotlin 侧的 ExoPlayer 初始化、准备、缓冲区、错误码、释放等完整状态机

### 排查视频播放问题

如果内置播放器异常或连续播放中断，按以下步骤提取日志：

1. 复现问题后立即用文件管理器打开 `/storage/emulated/0/Download/密册/logs/`
2. 打开当天 `密册_log_*.txt` 文件
3. 搜索以下标签定位问题：

| 搜索关键词 | 对应问题 |
|-----------|---------|
| `VideoPlayer` | 原生播放器创建、初始化、错误 |
| `PlayerScreen` | UI 层视频加载、控制、文件缺失 |
| `PlayerController` | 播放列表切换、连续播放逻辑 |
| `密册VideoPlayer` | Kotlin ExoPlayer 状态机、播放错误码 |
| `密册Main` | 原生通道创建/销毁 |
| `VDIAG` | 视频轨与解码事实汇总（容器/编码/解码器/首帧/丢帧） |
| `Source file:` | 打开视频前的文件事实（大小 / mtime / 头部字节 / `moov` 位置） |
| `VDIAG[dart-position-stall]` | Dart 侧检测到播放位置 3 秒不动 |

常见问题定位示例：

- **黑屏/无声**：搜索 `Playback error` → 查看 error code 和 message
- **连播中断**：搜索 `Item completed` + `Next item` → 检查是否正常切换到下一首
- **视频加载失败**：搜索 `Video load failed` + `Video file not found` → 确认文件路径
- **随机播放总重复同一批媒体**：搜索 `playCountMode` + `skipThreshold` → 确认「按播放次数随机」的模式与阈值是否生效，必要时在设置中清除播放记录
- **画面不动但声音正常 / 拖进度条才有图**：搜索 `VDIAG` → 按下表判断是片源问题还是渲染问题

### 画面不动 / 黑屏：只用 `VDIAG` 就能定性

复现一次（正常播放 10 秒 → 拖一次进度条 → 退出），然后搜 `VDIAG`，对照下表：

| 日志里看到 | 说明 | 处理方向 |
|-----------|------|---------|
| `vTrackSupported=false` | **设备不支持这条视频轨**：音频照放、画面永远黑、且不会有任何 error | 片源问题，需转码（如 H.264 High → Main，10bit → 8bit） |
| `bitDepth=10/10`、`hdr=true` | 10bit / HDR（PQ、HLG）片源，硬解常拒绝或只能软解 | 同上 |
| `vDecoder=... (software)` 且 `droppedFrames` 暴涨 | 落在软解上、跟不上播放速度 | 同上 |
| `firstFrameRendered=false@-1ms`、`renderedFrames=0` | 解码可能在做，但**一帧都没上屏**（就是「拖进度条才有图」） | 渲染/帧投放问题：看有没有 `VDIAG[stall-4s/8s/12s]`，以及自愈后是否出现 `VDIAG[first-frame]` |
| `fps` 异常（0、几百、几万） | 时间戳/采样率表坏了，帧会被当迟到帧全部丢掉 | 片源问题 |
| `decoderInits` 反复增长 | 解码器反复重建（格式反复变化 / 解码器崩溃重启） | 片源或解码器问题 |
| `loadErrors` 增长、`Source file: size=0` | 文件读取层面出错（权限、下载被截断） | 文件问题，与播放器无关 |

自愈动作会留下对应日志：`VDIAG[stall-4s]`（重挂 Surface）、`VDIAG[stall-8s]`（微 seek +100ms）、`VDIAG[stall-12s]`（放弃恢复，只保留证据）。正常播放则不该出现这三个标签。

---

## 开发

### 前置要求

| 工具 | 说明 |
|------|------|
| Flutter 3.38+ | Flutter SDK |
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

项目根目录提供了 `build.bat` 一键构建脚本，自动完成版本递增、代码生成、依赖安装、APK 编译和 Release 发布：

```bash
# 完整构建（递增版本号 → 代码生成 → 编译 → 输出带版本名的 APK）
build.bat

# 快速构建（跳过代码生成，仅递增版本并编译）
build.bat fast

# 仅 Gradle 编译（跳过版本递增与代码生成，改 Dart 代码后快速迭代用）
build.bat gradle

# 仅运行代码生成（l10n + Drift）
build.bat codegen

# 发布 Release（不重新构建，把根目录已有 APK 推到 GitHub Release）
build.bat release

# 构建但不发布 Release（也可写成 build.bat fast norelease）
build.bat norelease

# 清理所有构建产物
build.bat clean
```

#### 版本号管理

每次执行 `build.bat` 或 `build.bat fast` 都会**自动递增 `pubspec.yaml` 中的 build number**：

```
version: 1.0.29+44   →   version: 1.0.29+45
             ↑                              ↑
        build name                    build code 自动 +1
```

构建成功后输出的 APK 文件名包含完整版本号：

```
privi-1.0.29+45.apk
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
| 0 | 内存回收：`build_mem.ps1` 结束残留的 JVM（Gradle / Kotlin 守护进程）并打印可用内存快照 |
| 1 | 代码生成：`flutter gen-l10n` + `build_runner build` |
| 2 | 递增版本号：`pubspec.yaml` 的 build number +1 |
| 3 | 清理：`flutter clean` |
| 4 | 安装依赖：`flutter pub get` |
| 5 | 编译：`flutter build apk --release`（R8 全模式压缩前再回收一次内存） |
| 6 | 将 APK 复制到项目根目录 |
| 7 | 发布 GitHub Release：用 `gh` 推送 APK 与 `.sha256` 校验和（未安装 / 未登录 `gh` 时自动跳过，见下） |

构建成功后，APK 文件会出现在项目根目录，文件名格式为 `privi-<版本号>.apk`（如 `privi-1.0.29+45.apk`）；日志里每一步都带 `[N/7]` 前缀，最后一步会直接把 Release 链接打出来。

> 根目录的 `privi-*.apk` 与 `privi-*.apk.sha256` 是**本地构建产物，已在 `.gitignore` 里忽略**——APK 只通过 Release 分发，不提交进仓库。

#### 发布 Release（构建成功后自动，gh CLI）

完整构建（`build.bat` / `build.bat fast`）的最后一步就是**自动发布 GitHub Release**，不需要再手动上网页传包。改了说明文字想重发时，用下面这条（不重新编译）：

```bash
build.bat release          # 把根目录已有的 privi-<版本号>.apk 直接推到 Release
```

> **先 push 再发布**：新建 tag 用的是当前 `HEAD` 提交，`git push` 之前发布，tag 会指向远端还不存在的提交而失败。正常顺序是「改代码 → `git push` → `build.bat release`」。

| 项目 | 取值 |
|------|------|
| 目标仓库 | `origin` 远程（当前是公开 fork `xiaobailong/privi`） |
| tag | `v<完整版本号>`，如 `v1.0.29+45`——**带 build number**，所以每次构建都是一个独立 Release，不会互相覆盖 |
| 标题 | `密册 v<完整版本号>` |
| 资产 | `privi-<完整版本号>.apk`、`privi-<完整版本号>.apk.sha256`（一行 64 位小写十六进制 SHA-256，格式与上游 Release 一致） |
| 说明 | 项目根可选的 `release_notes.md`（有就用它当正文）＋ 自动追加的元信息：版本 / 构建时间 / 提交 / 分支 / 字节数 / SHA-256 / 本次签名方式 |
| 标记 | `--latest`，所以 `/releases/latest` 永远指向最新一次构建 |

首次准备（每台机器只需一次）：

```bash
gh auth login          # 浏览器授权；gh 自带的 token 已含 repo scope
gh auth status         # 确认已登录
```

若机器上没装 `gh`：`winget install --id GitHub.cli`。`build.bat` 会依次从 `PATH`、`%ProgramFiles%\GitHub CLI`、`%LOCALAPPDATA%\Programs\GitHub CLI`、`%USERPROFILE%\scoop\shims` 里找 `gh.exe`；也可以用环境变量 `GH_EXE` 直接指定。

若 `gh` 报网络错误（例如 `github.com` 直连超时、只有代理能通），先设好代理环境变量再跑（端口按自己用的客户端填：Clash Verge 混合端口默认 `7897`，Clash for Windows 默认 `7890`）：

```bash
set HTTPS_PROXY=http://127.0.0.1:7897
set HTTP_PROXY=http://127.0.0.1:7897
```

`gh` 走的是 `api.github.com`（上传资产走 `uploads.github.com`），与浏览器/系统代理是两套设置，登录能通不代表 `gh` 就能通。注意 `build.bat` 里给 Gradle/pub 用的代理检测只认 `7890`（`PROXY_AVAILABLE`），与 `gh` 的代理互不影响。

**这些情况会自动跳过发布并打印原因**——发布失败不会把「已经编好的 APK」判成构建失败：

| 情况 | 脚本行为 |
|------|---------|
| 没装 `gh` | 提示 `winget install --id GitHub.cli`，跳过 |
| `gh` 未登录 | 提示 `gh auth login`，跳过 |
| `build.bat norelease`，或先 `set SKIP_RELEASE=1` | 直接跳过 |
| 计算 SHA-256 失败 | 跳过（产物必须可校验，宁可不发） |
| 提交还没 `git push` | 新建 tag 会失败并提示「先 git push，再 build.bat release」 |
| 同一版本发第二次 | 走 `gh release upload --clobber` + `gh release edit`，替换资产与说明，不报 tag 冲突 |

发布结果可以直接核对：

```bash
gh release list                                # 本仓库所有 Release
gh release view v1.0.29+45                     # 某个 Release 的资产与说明
gh release download v1.0.29+45 -p "*.sha256"   # 只下校验和
```

> **签名提醒**：本机没有 `android/key.properties` 时，Release APK 用 **debug 密钥**签名（`android/app/build.gradle.kts` 在缺少 `key.properties` 时回落到 `signingConfigs.debug`）。这种 APK **不能覆盖安装**官方 Release 版本（签名不同），需要先卸载；对外分发前应当在 `android/key.properties` 配好正式签名密钥，届时自动生成的说明里「签名」一行会改成 `release 密钥`。

> **与上游的关系**：官方 Release 在上游作者仓库 [`kcng0/privi`](https://github.com/kcng0/privi/releases)（永久签名密钥，各版本签名一致）。本仓库是 fork，自动发布只用于自测与内部分发，`gh` 只会往 `origin` 推，不会也不能往上游推。

#### 内存配置与 R8（不要把这些堆大小调回去）

Release 走 R8 全模式压缩（`app/build.gradle.kts` 里 `isMinifyEnabled=true`），JVM 申请的是「物理内存 + 页面文件」的**提交内存**。旧配置 `-Xmx8G -XX:MaxMetaspaceSize=4G` 会把提交上限榨干——JVM 连 `Chunk::new` 的 1.5MB 都申请不到，Gradle 守护进程直接消失，日志里只留下：

```
The message received from the daemon indicates that the daemon has disappeared.
JVM crash log found: ... android/hs_err_pid*.log
```

（崩溃日志中的证据：`arena.cpp:168` OOM + `TotalPageFile size 54340M (AvailPageFile size 23M)`——是系统提交内存耗尽，不是堆溢出。）

因此：

- `android/gradle.properties` 把 Gradle 守护进程固定为 `-Xmx4G -XX:MaxMetaspaceSize=1G`，Kotlin 编译守护进程（独立 JVM，默认堆上限跟随物理内存且常驻数小时）另限 `-Xmx2G`；堆转储路径指向 `build/`，避免崩溃日志散落在 `android/`。
- `build.bat` 在构建开始、以及 R8 压缩前各调一次 `build_mem.ps1 -StopDaemons`：只结束由 `%JAVA_HOME%` 启动、且已运行超过 120 秒的 `java` 进程，不会误杀 VS Code / Android Studio 的 JVM；同时打印构建起点的可用内存，便于和崩溃日志对照。
- `build_mem.ps1` 用 `kernel32!GlobalMemoryStatusEx` 取内存（本机 WMI / `jps` / `Get-Counter` 都可能静默挂死），因此它比常规手段更可靠。

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
| 5 | 删除根路径下的 `密册-*.apk` / `*.aab` 文件 |

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
├── app/                    # Android 应用模块
│   └── src/main/
│       ├── kotlin/         # Android 原生代码（Kotlin：ExoPlayer、隐私保护等）
│       └── res/            # Android 资源
├── lib/                    # Dart 源码
│   ├── application/        # 业务逻辑控制器（Riverpod Notifier / Provider）
│   │   ├── backup/         # 保险库备份/恢复控制器
│   │   ├── import/         # 导入流程控制器
│   │   ├── lock/           # 锁屏 / 生物识别控制器
│   │   ├── media/          # 评分、排序、选择偏好控制器
│   │   ├── player/         # 播放器 / 外部播放器协调器
│   │   ├── settings/       # 应用设置控制器
│   │   └── update/         # 应用更新 / 重启接口
│   ├── core/               # 工具、主题、常量
│   │   ├── theme/          # 深色主题定义
│   │   └── utils/          # 日志、媒体/相册查询工具
│   ├── data/               # 数据层
│   │   ├── db/             # Drift 数据库（SQLite ORM）
│   │   ├── repositories/   # 媒体/相册数据仓库
│   │   └── services/       # 各类服务（导入、备份、安全、缩略图、媒体类型识别等）
│   ├── domain/             # 领域模型（MediaItem、Album、Playlist 等）
│   ├── l10n/               # 多语言资源
│   └── presentation/       # UI 页面和组件
│       ├── common/         # 通用组件（评分条、菜单、详情页等）
│       ├── grid/           # 保险库媒体网格
│       ├── home/           # 首页壳（双首页页签 + 相册/合集展示）
│       ├── import/         # 导入进度/结果页面
│       ├── lock/           # 锁屏页面（图案/PIN/生物识别）
│       ├── player/         # 视频播放器页面
│       ├── settings/       # 设置页面
│       ├── viewer/         # 全屏滑动查看器
│       └── visible/        # 系统图库浏览页面
├── assets/branding/        # 应用图标
├── drift_schemas/          # 数据库迁移 Schema（v2–v8）
└── pubspec.yaml            # Flutter 项目配置
```

## 感谢

如果这个工具帮到了您，欢迎随意赞赏，无论多少都是对我最大的鼓励！

![赞助](img/pay.jpg)