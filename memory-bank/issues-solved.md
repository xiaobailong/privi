# 已排查问题（issues-solved）

> 追加式记录：**永远不要删旧条目**（状态可以改）。编号连续递增，模板见 `README.md` §5。
> 每条的「复发判据」必须是一条能 5 秒定论的命令 —— 下次遇到同现象先跑它，别重新排查。

## ISSUE-001 WMI 无响应 → 所有 flutter 命令静默挂死
- 状态: 已规避（根因在本机 WMI 服务，不可控）
- 症状 / 现场: `build.bat` 停在第 1 个 `flutter --version` 或 `[1/3] flutter pub get`；
  `build\pub_get_codegen.log` **0 字节**；`dart.exe` 常驻但 CPU≈0；无任何输出、进程杀不掉
- 复发判据: `powershell -NoProfile -ExecutionPolicy Bypass -File scripts\build_wmi_guard.ps1 -FlutterRoot "D:\Tools\DevTools\flutter"`
  → **退出码 0 = 正常；5 = WMI 挂死；4 = 找不到 dart.exe**。构建里由 `build.bat :preflight` 自动跑，日志出现 `[错误] WMI 无响应` 即是它
- 根因: Windows 上 Dart 把 `Platform.operatingSystemVersion` 实现成 **COM/WMI 查询（wbemuuid.lib，无超时）**，
  而 `flutter.bat` 每次启动都读它；`winmgmt` 显示 RUNNING 但就是不回 `Win32_OperatingSystem`
- 证据: `build\build_full.log` 最后一行停在 `[Flutter 版本] 正在获取…`；同探针里其它属性（numberOfProcessors、
  resolvedExecutable…）全部正常，只有 OS 版本那一条永不返回；`build_exit.log` 为空
- 修法: `scripts\build_wmi_guard.ps1`（用 `dart.exe` 直接跑一行探针，硬超时 15s，超时 → 退出码 5）
  + `build.bat :preflight` 在 `:codegen` / `:do_build` / `:gradle_only` / `:clean` 前统一调用，
  `WMI_FAILED=1` 时**终止构建**并提示 `重启机器` / `winmgmt /resetrepository`
- 反例 / 易误判: 曾误判为「网络慢 / 依赖下载慢 / Gradle 出问题」而干等；
  也曾在 Flutter SDK 里硬编码 `hostOsVersion` 绕行 → **无效**（阻塞点更深），已全部回滚
- 相关文件: `scripts\build_wmi_guard.ps1`、`scripts\build_pub_get.ps1`、`build.bat`(`:preflight`)
- 过程详见: `docs/HANDOFF-Flutter工具WMI挂死诊断.md`
- 附带事实校正: 2026-09-22 实测 `taskkill /T /F` 正常（0.7s 返回），
  09-21 记录的「taskkill 一律挂死」**未复现**，保底杀进程仍可用 `Stop-Process`
- 首次记录: 2026-09-21 ／ 最近复核: 2026-09-22（`OK: WMI 1945ms OSVER= Windows 11 10.0 Build 26100`）

## ISSUE-002 pub get 无限期挂起，看不出是「慢」还是「死」
- 状态: 已规避
- 症状 / 现场: 日志 0 字节、进程永不返回、控制台一行提示都没有（人会一直等下去）
- 复发判据: 日志出现 `[pub] 判定卡死: 日志连续 300 秒无增长`，退出码 **124**；或直接看 `build\pub_*.log` 是否 0 字节
- 根因: 原来 `call flutter pub get > log` 没有任何超时兜底；卡在 `dart.exe` 启动阶段时无法区分
  「依赖下载慢」与「被安全软件/WMI 拦死」
- 修法: `scripts\build_pub_get.ps1` —— 子进程执行 + 心跳（默认 20s）+ **日志零增长 300s 即判卡死**，
  `taskkill /PID <pid> /T /F` 杀掉整棵进程树并 `exit 124`；`build.bat` 两处 pub get 都改走它
- 反例 / 易误判: 曾把「日志没涨」当成下载慢而无限等待（正确做法是等看门狗给结论）
- 相关文件: `scripts\build_pub_get.ps1`、`build.bat`（`:codegen` 与步骤 4 两处）

## ISSUE-003 pub get 失败被当成成功（退出码读成空 → 被当 0）
- 状态: 已修复
- 症状 / 现场: pub get 实际失败，构建却继续往下跑，随后 Gradle 报一堆「莫名其妙的错」
- 复发判据: 看 `build\pub_*.log` 结尾是否有 `[pub-exit] N`；N≠0 时 `build.bat` 必须判失败
- 根因: 本机 `Start-Process -PassThru` 返回对象读 `$proc.ExitCode` 得到**空值**，
  而 `exit $null` 被 PowerShell 当成 **0** ⇒ 失败被静默放过
- 修法: 命令行追加 `& echo [pub-exit] !ERRORLEVEL!` 让 cmd 自己回显退出码，再解析该 marker；
  解析不到一律 `exit 125`（按失败处理），绝不默认成功
- 反例 / 易误判: 依赖 `$proc.ExitCode`；用 `%ERRORLEVEL%`（整行一次性解析，会取到执行前的旧值）
- 相关文件: `scripts\build_pub_get.ps1`（`[pub-exit]` 解析段）

## ISSUE-004 release 构建在 R8 阶段 JVM 崩溃（提交内存被榨干）
- 状态: 已规避（依赖机器内存，不做根治）
- 症状 / 现场: `The message received from the daemon indicates that the daemon has disappeared.` /
  `JVM crash log found: ... android/hs_err_pid58400.log`；crash log 里
  `Out of Memory Error (arena.cpp:168)`、`Native memory allocation (malloc) failed to allocate 1577504 bytes for Chunk::new`、
  `TotalPageFile size 54340M (AvailPageFile size 23M)`
- 复发判据: 看 `build\mem_report.log` 最后一段 `MEM ...` 行 → `FreeCommitMB` **< 1500** 或出现 `MEM LOW_COMMIT` 即高危
- 根因: `isMinifyEnabled=true` 的 R8 全模式 + Kotlin 编译守护进程长期存活占内存 →
  系统提交内存（物理 + 页面文件）耗尽，JVM 连 1.5MB 都申请不到
- 修法: `scripts\build_mem.ps1`：编译前回收**本机 JDK 启动且存活 >120s** 的 JVM（不动 VS Code / Android Studio 的 JVM），
  并用 `kernel32!GlobalMemoryStatusEx` 打印物理/提交内存快照到 `build\mem_report.log`
- 反例 / 易误判: 以为是 `-Xmx` 太小；用 WMI / `jps` / `Get-Counter` 查内存（本机会挂死，见 `PIT-011`）
- 相关文件: `scripts\build_mem.ps1`、`build.bat`(`:reclaim_memory`)、`android/app/build.gradle.kts`(`isMinifyEnabled`)

## ISSUE-005 版本号漂移：`.BUILD_NUM` 涨了但 `pubspec.yaml` 没变
- 状态: 已修复
- 症状 / 现场: 打出来的 APK versionCode 是旧的；历史上多次「版本号漂移」
- 复发判据: 手动跑 `powershell -NoProfile -ExecutionPolicy Bypass -File scripts\bump_version.ps1 -BuildNumber 999 -Path build\_selftest_pubspec.yaml`
  （先复制 pubspec.yaml 到该路径）→ 期望输出 `OK=...` 且文件里的 `version:` 真的变了
- 根因: 本机端点安全策略**静默拦截**命令行里含正则 `(\+)\d+` 的 `powershell -Command`：
  `powershell.exe` 以退出码 **786** 静默退出、什么都不输出，`pubspec.yaml` 没被修改
- 修法: 逻辑放进 `scripts\bump_version.ps1`，用 `-File` 调用；`build.bat` 事后**回读校验**，
  只有校验通过才回写 `.BUILD_NUM`
- 反例 / 易误判: 用 `powershell -Command` 一行式替换版本号；只看脚本退出码不看文件内容
- 相关文件: `scripts\bump_version.ps1`、`build.bat`(`:increment_version`)

## ISSUE-006 断点续传误判：跳过编译、复用上一版 APK
- 状态: 已修复
- 症状 / 现场: 日志出现 `The system cannot find the path specified.`；切回旧提交后「打包失败」或直接复用旧 APK；
  构建快得异常（一步都没跑）
- 复发判据: 看 `build\.build_state` 是否存在且 `HASH_CODE_GEN=` / `HASH_GRADLE=` 非空；
  日志出现 `[断点续传] 无法计算代码哈希，取消续传，从头构建` 说明保护生效
- 根因（三个叠在一起）: ①哈希计算原先放在含正则的 `powershell -Command` 里 → 被 786 拦截 → 哈希恒为空，
  **空值比较 ⇒ 误判「代码未变更」**；②`flutter clean` 删掉 `build\` 后状态文件重定向失败（路径不存在）；
  ③`SAVED_STEP=6` 时所有 `if !RESUME_STEP! lss N` 都不成立 ⇒ 一步都不执行
- 修法: 哈希逻辑移入 `scripts\build_hash.ps1`（`-File` 调用）；哈希为空 → 删状态文件、`RESUME_STEP=0`；
  `:save_state` 前补建 `build\`；**续传上限 2**（步骤 3/4/5 = clean / pub get / 编译 每次必跑）
- 反例 / 易误判: 拿空哈希去比较（会把「算不出哈希」当成「代码没变」）
- 相关文件: `scripts\build_hash.ps1`、`build.bat`(`:load_state` / `:save_state`)

## ISSUE-007 「目录里有 APK 就算成功」的假绿
- 状态: 已修复
- 症状 / 现场: 编译失败，但 `build\app\outputs\flutter-apk\app-release.apk` 还是上一次的产物 → 被判为构建成功
- 复发判据: 日志里应先出现「先删掉上次构建留下的 APK」；失败时必须同时出现
  `[警告] 构建失败！Flutter exit code=`，且 `build\build_exit.log` 里 `BUILD_FAILED=1`
- 根因: 只判断产物文件是否存在，不看 flutter/gradle 退出码
- 修法: 编译前先删除目标 APK；**退出码非 0 一律判失败**（即使目录里还留着旧 APK）；
  结尾统一写 `build\build_exit.log`（`BUILD_FAILED` / `WMI_FAILED` / `NEW_VER`）
- 相关文件: `build.bat`(`:gradle_only` / `:do_build`)

## ISSUE-008 VLC 引擎黑屏 / 纯色（ExoPlayer 引擎正常）
- 状态: 已修复
- 症状 / 现场: `playerEngine=vlc` 时画面全黑或纯色，无 error 事件；切 ExoPlayer 正常
- 复发判据: `--verbose=2` 看 display.c 这几行：`using opaque` / `using ANWP` / `using ANW`、
  `PoolAlloc: request N frames`、`got N frames` —— **一条都没有，只剩 gles2 相关行 ⇒ 根因仍在**
- 根因: `IVLCVout.attachViews()` 的监听器是**参数**不是 setter；不传监听器 ⇒ `canSetVideoLayout=false`
  ⇒ capability 260(`android-display`)/280(`android-opaque`) 主动放弃 ⇒ 退化 gles2 = 黑屏。
  另外缓冲区几何没有任何别人会设，只能由 `SurfaceTexture.setDefaultBufferSize()` 兜住
  （`AWindow` / `AWindow$SurfaceTextureThread` 里没有 `setBuffersGeometry`）
- 修法: `attachViews(IVLCVout.OnNewVideoLayoutListener { ... })`；在回调里**同步**调用
  `setDefaultBufferSize()`（禁止 `mainHandler.post{}`，会与第一帧抢时序导致开头黑屏）；
  探测几何宽度**上取整到 4 的倍数**（RGB32 pitch=4），而布局回调给的值**照抄、不要再取整**
- 反例 / 易误判: 以为要改 native 层 `setBuffersGeometry`；把监听器当 setter 调（旧代码根本编译不过）
- 相关文件: `android/app/src/main/kotlin/com/privi/app/VlcPlayerHandler.kt`
- 过程详见: `docs/HANDOFF-VLC播放黑屏根因.md`

## ISSUE-009 视频点开「秒完」并自动跳到下一项（32 位 PTS 回绕）
- 状态: 已修复
- 症状 / 现场: 某 mp4 点开就「播完」、列表自动下一个；同一文件在外部播放器正常
- 复发判据: 日志搜 `VDIAG[timeline-offset]`（出现即命中）；
  特征数值：原生 `getPosition()` 首次返回 ≈ `47,721,845 ms`（= `2^32 / 90000`，32 位 90kHz 回绕点），`duration` 只有 12 分钟
- 根因: 文件首帧 PTS 自带 32 位回绕偏移；Media3 `currentPosition` 是**媒体时间轴**坐标，
  而 `duration` 是**内容长度**，两者差一个恒定偏移 ⇒ 位置一开始就 > duration ⇒ 判定「已完成」⇒ 触发「播完自动下一个」
- 修法: Dart 侧 `_timelineOffsetMs` + `_contentPositionMs(raw)` 归一化（无偏移时原样返回，普通文件**行为不变**）；
  `seekTo` 的坐标系用一次性 0.3s 探针 `_probeSeekAxis()` 判定（打 `VDIAG[seek-axis]`）
- 反例 / 易误判: 先怀疑解码器/容器不支持（实际解码完全正常，问题在时间轴）
- 相关文件: `lib/data/services/native_video_controller.dart`
- 过程详见: `docs/HANDOFF-视频播放诊断日志.md` §8

## ISSUE-010 某些视频在应用里永远是「图片」、打不开
- 状态: 已修复
- 症状 / 现场: 用户报「视频无法识别 / 无法播放」；这些文件在系统相册里正常
- 复发判据: 启动维护日志出现 `fixed N media kinds`；或直接比对 DB 行的 `isVideo`/`mimeType`
  与 vault 文件真实扩展名是否一致
- 根因: mime/扩展名表太窄（`.ts` `.wmv` `.rmvb` `.flv` `.mpg` `.vob` `.divx` `.dv` `.m2ts` 都不在表内）
  → 回退成 `image/jpeg` → **入库时就写成图片**，之后永远识别/播放不了
- 修法: 新增 `lib/data/services/media_kinds.dart` 作为全应用唯一真源；
  `maintenance_service._repairMediaKinds()` 启动时按 vault 真实扩展名修正（**必须排在视频缩略图修复之前**，
  否则刚改回视频的行拿不到封面）
- 反例 / 易误判: 一处一处补扩展名表（散落多处、继续漏）；把「识别错」当成「播放器 bug」
- 相关文件: `lib/data/services/media_kinds.dart`、`lib/data/services/maintenance_service.dart`、
  `lib/data/services/import/hide_preparer.dart`、`lib/data/db/database.dart`
- 过程详见: `docs/HANDOFF-媒体类型重构.md`

## ISSUE-011 【2026-09-22】ps1 搬到 `scripts\` 后 build.bat 未同步 → 所有前置防护静默跳过
- 状态: 已修复
- 症状 / 现场: **没有任何报错**，但 WMI 自检 / 内存回收 / pub get 看门狗 / 三种哈希 / 版本号自增**全都不执行**；
  日志里出现 `[警告] 未找到 build_hash.ps1`、`[跳过] 未找到 build_wmi_guard.ps1`、`[内存] 未找到 build_mem.ps1`
- 复发判据: ①`findstr /n /c:"%~dp0build_" /c:"%~dp0bump_" build.bat` **必须无输出**；
  ②`dir /b scripts\*.ps1` 必须是 **7 个**；③构建日志应在开头出现 `[WMI 自检] rc=0 OK` 与 `MEM OK`
- 根因: 脚本搬进 `scripts\` 后 `build.bat` 里仍是 `if not exist "%~dp0build_hash.ps1"` ⇒ 条件命中 ⇒
  走「警告/跳过」分支而不是失败 ⇒ 防护全部失效（最危险的一类"静默降级"）
- 修法: `build.bat` 全部引用改 `%~dp0scripts\...`（29 处，含告警文案/注释/复现命令提示）；
  搬迁文件后**必须 grep 旧路径**；解释器层的相对路径不受影响（`-File` 调用继承 cmd 当前目录，
  已在 `scripts\` 布局下实测哈希/内存/WMI/pub get/版本号全部正常）
- 反例 / 易误判: 只改了 `-File` 调用行，忘了 `if not exist` 的探测行；只搬文件不 grep
- 相关文件: `build.bat`、`scripts\*.ps1`（7 个）

## ISSUE-012 【未修复·待决】AGP 9.1.0 新 DSL 与 `extraGenSnapshotOptions` 不兼容
- 状态: 未修复（与脚本搬迁无关，2026-09-22 复现）
- 症状 / 现场: `flutter build apk --release` →
  `e: file:///.../android/app/build.gradle.kts:84:5: Unresolved reference 'extraGenSnapshotOptions'.`；
  末尾 `BUILD FAILED in 40s` / `Gradle task assembleRelease failed with exit code 1`
- 复发判据: 日志出现 `Unresolved reference 'extraGenSnapshotOptions'` 就是它
  （**不是** WMI 挂死、**不是**内存不足、**不是**依赖缺失）
- 根因: `android/settings.gradle.kts` 固定 `com.android.application 9.1.0` + Gradle `9.3.1`
  （AGP 9 默认 `android.newDsl=true`），而 `android/app/build.gradle.kts` 里
  `flutter { extraGenSnapshotOptions.add("--no-strip") }` 在新 DSL 下解析不到；
  同时 `android { }` 块被标记 deprecated（AGP 10 会移除）
- 证据: `build\build_full.log` 两次构建输出完全相同（2026-09-22 16:35 与 16:46），
  均为第 33/47/58 行那三条；`build\build_exit.log` = `BUILD_FAILED=1 WMI_FAILED=0`；第二次 `BUILD FAILED in 29s`
- 复核记录: 2026-09-22 16:46 重跑 `build.bat gradle` → 同一条 `Unresolved reference 'extraGenSnapshotOptions'`
  （证明与 `scripts\` 搬迁、`memory-bank/` 改动**无关**；前置环节 WMI 自检 rc=0、MEM OK 均正常）
- 下一步（二选一）: ①回退 AGP / Kotlin / Gradle 组合到该属性可用；
  ②按 AGP 9 新 DSL 改写该 `flutter {}` 块（`--no-strip` 的诉求见 `ISSUE-004` / `ADR-009`，是为了降 gen_snapshot 峰值内存）
- 相关文件: `android/settings.gradle.kts`、`android/app/build.gradle.kts:80-85`、
  `android/gradle/wrapper/gradle-wrapper.properties`

## ISSUE-013 flutter 工具链初始化阶段阻塞（doctor / --version 触发下载卡死）
- 状态: 已规避
- 症状 / 现场: 构建卡在 `[Flutter 版本]` / `flutter doctor` 相关步骤，无输出
- 复发判据: `build_full.log` 末尾停在 `[Flutter 版本] 正在获取…` 之类；CPU≈0、无输出
- 根因: `flutter doctor` / `flutter --version` 会触发 SDK 组件下载或工具快照重建，本机曾在此静默挂死
  （与 `ISSUE-001` 同型但触发点不同）
- 修法: `build.bat :checkenv` 主动**跳过**这两步并明确打印「跳过以触发工具链下载阻塞」，
  版本信息交给后续 `pub get` / `build` 自然输出
- 相关文件: `build.bat`(`:checkenv`)、commit `533800f` / `9473cac`

## ISSUE-014 【2026-09-22】viewer / gallery 两个视频入口无看门狗、无错误态、无引擎回退 → 黑屏永久转圈
- 状态: 已修复
- 症状 / 现场: 引擎设为 libVLC 时，从「隐藏库 viewer」或「可见库 gallery 预览」打开视频会**永远黑屏/转圈**：
  `viewer_screen` 停在 hourglass 占位图，`gallery_preview_screen` 停在 `_loading = true`，
  既没有错误提示，也不会自愈（`PlayerScreen` 同一文件正常，因为它有 watchdog + 回退）
- 复发判据: 日志（`AppLogger`，tag `VideoEngineFallback`）出现
  `VLC produced no frame within 15s, retrying with exoPlayer: <itemId>` = 防护在生效；
  **若界面一直转圈且日志里一条 `VideoEngineFallback` 都没有 ⇒ 某个入口又退化成裸调用了**
- 根因: 两个入口都直接裸读设置后建控制器，没有任何兜底：
  `final engine = settings.playerEngine == PlayerEngine.vlc ? 'vlc' : 'exoPlayer';`
  而 VLC 侧**没有** ExoPlayer 的 `frameWatchdog` / `reattachSurface` 自愈（surface 丢了就一直是黑屏，
  只能重建整个播放器）⇒ 引擎一旦起不来，UI 侧就只会一直等
- 修法: 新增 `lib/presentation/player/engine_fallback.dart`（mixin `VideoEngineFallbackState`：
  `engineFor` 引擎选择 + `armLoadWatchdog` 15s 看门狗 + `fallbackToDefaultEngineIfPossible` 单次回退 +
  `useEngineFallback`），三个入口统一接入：
  - `player_screen.dart`：把原有 watchdog/回退集合改成复用 mixin（**语义不变**，仅去重）
  - `viewer_screen.dart`：新增 `_videoError`/`_videoErrorItemId` + `_retryVideoLoad`，
    超时先换引擎重建，再失败显示错误图标+文案（原来没有错误态）
  - `gallery_preview_screen.dart`：新增 `_retryVideoLoad`，超时沿用已有 `_error`/`_loading` 落到错误态
  - 三处重试路径都带请求序号校验（`_videoRequest` / `_loadRequest`），避免旧加载覆盖新状态
- 反例 / 易误判: ①把"黑屏"一律当成 VLC 的 Kotlin 根因（`ISSUE-008`）没修好 —— 这两个入口的问题在 Dart 侧
  没有回退；②以为"同一引擎再试一次"能自愈 —— 同一文件同一引擎重试大概率同样结果，只有换引擎才可能出画面
- 相关文件: `lib/presentation/player/engine_fallback.dart`、`player_screen.dart`、
  `viewer_screen.dart`、`gallery_preview_screen.dart`
- 过程详见: `docs/HANDOFF-VLC引擎收尾与剩余项.md` 第 3 节
- 首次记录: 2026-09-22 ／ 验证: `frontend_server` 全包编译（`lib/main.dart`）末行 `... build\_dartcheck.dill 0` +
  `DARTCHECK_EXIT=0`；`flutter analyze` 全仓 149.2s、除历史遗留 warning 外无 error
  （过程中先抓到 1 处漏改的 `_loadWatchdog` 引用并修复，另清掉本次改动引入的 2 个 unused import）
