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
- 复发 2026-09-22 19:02:47（本轮）: 完整构建的 preflight 里 `scripts\build_wmi_guard.ps1` 返回 **5**，
  `build_full.log` 打印 `[错误] WMI 无响应`，构建在 **22 秒**内终止（`build_exit.log` = `WMI_FAILED=1`）
  —— 守卫按设计生效（对比首次事故：直接挂死 5~10 分钟）；
  **同一天 18:53 的构建 WMI 还是 `rc=0 OK: WMI 1286ms`**，19:02 就挂了，19:06/19:07 连续复测仍 `rc=5`
  ⇒ 本机 WMI 是"时好时坏"，与构建脚本、代码改动无关，别去改脚本
- 复测手法（重要，别再踩坑）: 守卫**必须放独立窗口**跑，否则会被下一条终端命令掐断、
  输出文件停在 0 字节，看起来像"守卫本身没输出"：
  ```
  start "" /min cmd /c "cd /d D:\WorkSpace\test\privi && powershell -NoProfile -ExecutionPolicy Bypass -File scripts\build_wmi_guard.ps1 -FlutterRoot D:\Tools\DevTools\flutter > tmp\wmi_probe.txt 2>&1"
  ```
  然后 `read_files tmp\wmi_probe.txt`：`HANG:` 开头 = 仍挂死；`OK: WMI ...ms` = 已恢复
- 处置: 重启机器最有效；或管理员 `winmgmt /resetrepository`（本机未执行，属系统级变更）
- 影响: WMI 挂死期间 `build.bat` 与 `build.bat gradle` **都跑不了**（后者内部也是 `flutter build apk`，`build.bat:848`），
  但 **git commit / push 不受影响**
- 复发 2026-09-22 19:02→19:16（本轮，连续第 2 次爆发）: 从 19:02:47 起 **8 次以上**探测全部 `rc=5`，
  **15 分钟未自愈**；期间两次真实构建（19:14:17 完整构建、19:16:18 在 `main` 上重跑）都在
  **21~23 秒**内以 `[错误] WMI 无响应` 终止（`build_exit.log` = `BUILD_FAILED=1 WMI_FAILED=1 NEW_VER=` 为空）
  ⇒ 同一台机器 **18:53 还是 `rc=0 OK: WMI 1286ms`**，说明这是"时好时坏、一旦挂了要等很久"的机器级问题
- 环境补充（本轮实测）: 本会话 shell **有管理员权限**（`net session` 退出码 0）⇒ 需要时可直接执行
  `net stop winmgmt /y` → `winmgmt /verifyrepository` → `winmgmt /resetrepository` → `net start winmgmt`
  （**未执行**：属机器级变更、会影响其它依赖 WMI 的程序，等用户决定；首选仍是重启机器）
- 结论: 遇到它**不要**去改构建脚本或怀疑代码 —— 先 `read_files` 看 `build\build_exit.log` 是否 `WMI_FAILED=1`，
  是就停下等环境恢复

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

### 复发记录 2026-09-22 17:36（R8 阶段，当时 `-Xmx4G`）
- 现场: `build.bat gradle` 已越过 Kotlin DSL 编译（`ISSUE-012` 已修）后，在 `assembleRelease` 第 **303 秒**崩溃：
  `Gradle build daemon disappeared unexpectedly` + `JVM crash log found: android/hs_err_pid51552.log`
- 崩溃日志原文（`android/hs_err_pid51552.log:1-33`）：
  ```
  # There is insufficient memory for the Java Runtime Environment to continue.
  # Native memory allocation (mmap) failed to map 765460480 bytes for G1 virtual space
  #  Out of Memory Error (os_windows.cpp:3604), pid=51552
  # Time: Tue Sep 22 17:36:47 2026 elapsed time: 303.714730 seconds
  # Host: AMD Ryzen 7 8745H ... 16 cores, 27G, Windows 11
  ```
  ⇒ 与 09-21 的 `arena.cpp` 是**同一根因的两种表现**：这次卡在「把堆扩到 `-Xmx` 上限」的预留上
- **重要反例**: 本次构建前 `MEM OK ... FreeCommitMB=6289`（远高于 1500 阈值）**仍然崩了** ⇒
  该阈值只能抓"一开始就很紧张"，抓不到"R8 中途膨胀"；**不要把 `MEM OK` 当安全保证**
- 缓解（本次采用，`ADR-006` 已更新）:
  ① 构建前 `scripts\build_mem.ps1 -StopDaemons` 回收残留 Kotlin 守护进程（本次释放 580MB，commit free 5549→6534MB）；
  ② `org.gradle.jvmargs` 的 `-Xmx` 4G→**3G**；③ `kotlin.daemon.jvmargs` 的 `-Xmx` 2G→**1G**
- 复发判据（补）: 崩溃日志出现 `for G1 virtual space` / `os_windows.cpp:3604` ⇒ 同一根因；
  只要看到 `daemon has disappeared`，先按本节处置，别去怀疑业务代码
- 处置后验证: **2026-09-22 17:42:30** `build.bat gradle` → `BUILD_FAILED=0`，
  耗时 252s 走完 `assembleRelease` 并产出 `app-release.apk`（同一次会话里 `-Xmx4G` 那次 303s 崩溃）

### 复发记录 2026-09-22 19:01（`-Xmx3G` 已生效、事前还回收过内存，仍然崩）
- 现场: 完整构建（`build.bat norelease`）走到 `assembleRelease` 第 **295.6 秒**，
  `JVM crash log found: android/hs_err_pid20124.log` + `Gradle build daemon disappeared unexpectedly`
- 崩溃日志原文（`android/hs_err_pid20124.log`）:
  ```
  # Native memory allocation (malloc) failed to allocate 2288720 bytes for Chunk::new
  #  Out of Memory Error (arena.cpp:168), pid=20124
  # Memory: 4k page, system-wide physical 28422M (1912M free)
  # TotalPageFile size 54340M (AvailPageFile size 69M)
  # current process WorkingSet (physical memory assigned to process): 4145M, peak: 4145M
  ```
  ⇒ 与 09-21 首次事故**同型**（`arena.cpp` + 申请量同一量级）
- **重要反例（第二次出现）**: 本次构建前 `MEM OK ... FreeCommitMB=6029`（是 1500 阈值的 4 倍）**仍然崩**；
  事前还按本节缓解跑过 `-StopDaemons`（Killed=1、释放 581MB、commit free 5808→6702MB），**重试仍崩**
  ⇒ 阈值判据不可依赖。决定成败的不是"开局有多少余量"，而是"R8 跑到第 5 分钟时，**别的进程**有没有把提交内存吃掉"：
  崩溃瞬间物理只剩 1912MB、页面文件只剩 **69MB**，而本机物理 28422M ⇒ 约 26GB 被其它进程占用
- 反例的反面（本次能确认的好消息）: 崩溃**不在 Kotlin 编译阶段** —— 同一次运行里
  `:app:compileReleaseKotlin` 已成功（R8 已写出 `build/app/outputs/mapping/release/{usage,seeds}.txt`），
  所以"改完 Kotlin 先跑一次构建"能拿到编译级验证，即使后面 R8 崩在内存上
- 本轮处置: `scripts\build_mem.ps1 -JavaHome <JDK> -StopDaemons` 回收后重试（见 `ISSUE-001` 复发：本轮重试被 WMI 挡住）
- 下一步（**未验证**，条件合适时再做）: ①`org.gradle.jvmargs` `-Xmx` 3G→2560m、`-XX:MaxMetaspaceSize` 1G→768m
  （降预留，与 17:36 那次 "G1 virtual space 预留失败" 同方向）；②构建前关掉 VS Code 的 Java 扩展 / 浏览器等大头进程，
  或调大系统页面文件（本机提交上限 54340M ≈ 物理 28422M×1.9，R8 峰值需要 5GB 以上余量）
- 复发判据（补，两条任选）: `findstr /c:"arena.cpp" android\hs_err_pid*.log` 命中 ⇒ 本条目；
  `findstr /c:"G1 virtual space" android\hs_err_pid*.log` 命中 ⇒ 本条目（同一根因的另一种表现）

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

## ISSUE-012 【已修复】`flutter { extraGenSnapshotOptions }` 在 Flutter 3.47 已被移除（AGP 9.1.0 下报 Unresolved reference）
- 状态: 已修复（2026-09-22；与脚本搬迁无关，曾连续两次复现）
- 症状 / 现场: `flutter build apk --release` →
  `e: file:///.../android/app/build.gradle.kts:84:5: Unresolved reference 'extraGenSnapshotOptions'.`；
  末尾 `BUILD FAILED in 40s` / `Gradle task assembleRelease failed with exit code 1`
- 复发判据: 日志出现 `Unresolved reference 'extraGenSnapshotOptions'` 就是它
  （**不是** WMI 挂死、**不是**内存不足、**不是**依赖缺失）
- 根因: **Flutter 3.47.4 的 `flutter {}` 扩展里已经没有 `extraGenSnapshotOptions` 属性**（DSL 已被上游移除）。
  该值现在改为读 **Gradle project property**：`flutter_tools/gradle/FlutterPlugin.kt` 用
  `project.findProperty("extra-gen-snapshot-options")` 取值，再经 `tasks/BaseFlutterTaskHelper.kt`
  以 `--ExtraGenSnapshotOptions=<值>` 传给 flutter tool。
  本仓库 `android/gradle.properties` **早就设了** `android.newDsl=false`，所以这不是 newDsl 开关的问题；
  日志里 `android { }` 那两行 deprecation 只是伴随信息，不是失败原因
- 证据: `build\build_full.log` 两次构建输出完全相同（2026-09-22 16:35 与 16:46），
  均为第 33/47/58 行那三条；`build\build_exit.log` = `BUILD_FAILED=1 WMI_FAILED=0`；第二次 `BUILD FAILED in 29s`
- 复核记录: 2026-09-22 16:46 重跑 `build.bat gradle` → 同一条 `Unresolved reference 'extraGenSnapshotOptions'`
  （证明与 `scripts\` 搬迁、`memory-bank/` 改动**无关**；前置环节 WMI 自检 rc=0、MEM OK 均正常）
- 修法（2026-09-22）: ①删掉 `android/app/build.gradle.kts` 里那行 `extraGenSnapshotOptions.add("--no-strip")`
  （保留 `flutter { source = "../.." }`，并在原处留注释说明别再写回来）；
  ②在 `android/gradle.properties` 加 `extra-gen-snapshot-options=--no-strip`，
  保住 `ADR-009` 的"降 AOT 峰值内存"诉求（`--no-strip` 仍是有效选项，`gen_snapshot --help` 里列着 `[--strip]`）
- 复发判据（补）: `findstr /c:"extraGenSnapshotOptions" android\app\build.gradle.kts` **必须无输出**；
  `findstr /c:"extra-gen-snapshot-options" android\gradle.properties` **必须有 1 行**。
  注意 `build.bat :config_gradle_proxy` 只过滤 `systemProp.*.proxy` 行，不会吞掉该键
- 验证: **2026-09-22 17:42:30** 重跑 `build.bat gradle` → `BUILD_FAILED=0`，
  产出 `build\app\outputs\flutter-apk\app-release.apk`（+ `.sha1`）；`assembleRelease` 全程走完，DSL 报错不再出现
- 决策: 见 `ADR-018`（`ADR-016` 据此结案）
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

## ISSUE-015 切片过快时进程级崩溃（上一段日志停在 `onPlaying`，下一段直接是新 session，零错误行）
- 状态: 已修复（VLC 引擎；已定位 + 已加固，真机复现路径待用户回归验证）
- 症状 / 现场: 用户报"偶现崩了一次"。当天 `密册_log_2026-09-22.txt` 里有三次会话启动：
  `session=hmioqbag88`(11:34) → `hmizyyp08b`(18:22) → **`hmj05e4e7h`(18:28:46)**；
  第三次出现在 `18:28:35.027 [VideoPlayer.native] onPlaying: textureId=9` 之后约 11 秒，
  中间**一条 Dart 错误行都没有**（`FlutterError` / `UncaughtError` / `Exception` / `error` 全零命中），
  也**没有** `onDestroy: releasing N video players` ⇒ 进程是被"当场带走"的
- 复发判据: `findstr /n /c:"session=" 密册_log_<日期>.txt` —— 每出现一行
  `[AppLogger] probe dir=... session=xxx` 就是一次进程重建；再对照**每段末尾是不是正常行**
  （`onPlaying` / `STATE_READY` / `build:`）：
  ① 是正常行、且中间没有任何 ERROR/异常行 ⇒ 进程级崩溃（原生或 Java/Kotlin 线程），**别在 Dart 侧找原因**；
  ② 同时看 `Download/密册/logs/` 有没有 `密册_crash_<日期>.txt`：
     有 ⇒ 是 Java/Kotlin 线程未捕获异常（堆栈就在文件里）；
     没有而日志仍然断掉 ⇒ native SIGSEGV，需连电脑 `adb logcat -b crash`（本机 `adb` 在
     `D:\Tools\DevTools\Android\Sdk\platform-tools\adb.exe`）
- 根因: `VlcPlayerHandler` 把 libvlc 的 **MediaPlayer 事件回调**和 **vout 布局回调**都用
  `mainHandler.post { ... }` 投到主线程，lambda 里捕获了该轮播放的 `MediaPlayer mp`；
  而 `resetPlayer()` / `release()` 会 `mp.release()` 并把字段置空 ——
  **已经排进主线程队列、或正在 libvlc 线程上执行到一半的回调没有任何身份校验**，
  于是会在 release 之后继续执行 `mp.length` / `mp.time` / `mp.isPlaying`。
  这三个是 **native 方法**，`VLCObject.release()`（refCount→0 时）只会
  `setEventListener(null)`（nativeDetachEvents）并释放 native 句柄，**不会**让之后的 native 访问变安全
  ⇒ 在已释放的 native 句柄上做 JNI 调用 = 进程崩溃（释放/调用交错时"偶现"，因为内存可能还没被复用）
- 证据:
  ① 日志时间线（`tmp\密册_log_2026-09-22.txt` 第 490-547 行）: 18:28:23.5 → 18:28:35.0 之间连续
     创建/销毁 **3 个播放器**（textureId 7→8→9），最后一次 `onPlaying: textureId=9` 后日志断掉；
     这段正是"事件已入队、播放器马上被 release"的时间窗（用户快速切片）
  ② 全文 690 行里 `ERROR|Exception|Uncaught|FlutterError` **零命中**（`tmp\grep_log.txt`）
     ⇒ 排除 Dart 层异常；UI 侧真有异常时 `main.dart` 的 `FlutterError.onError` / `PlatformDispatcher.onError`
     一定会写日志
  ③ `javap -p -c` 反编译 `.gradle_home\...\libvlc-all-3.6.4.aar!/classes.jar`（过程见 `tmp\javap_*.txt`）:
     `public native long getTime()` / `public native long getLength()` / `public native boolean isPlaying()`；
     `VLCObject.release()` 在引用计数归零时 `invokevirtual setEventListener(null)`；
     `VLCObject.setEventListener(null)` 会 `nativeDetachEvents()` ⇒ 传 null 是既定 detach 用法
  ④ 文件里既有的 `probeVideoSizeAsync()` 早就写了 `if (mediaPlayer !== mp) return@post`
     —— 说明同类隐患此前已经被踩到过，只是事件/布局这两处漏了
- 修法:
  `android/app/src/main/kotlin/com/privi/app/VlcPlayerHandler.kt`
  ① 事件回调 + 布局回调里的 `mainHandler.post{...}` 均加身份校验
     `if (mediaPlayer !== mp) return@post`（与 `probeVideoSizeAsync` 一致）；
  ② 布局回调同步段开头加 `if (mediaPlayer !== mp) return@OnNewVideoLayoutListener`
     （别往已释放的 SurfaceTexture 写几何）；
  ③ `onMediaPlayerEvent()` 入口兜一层 `if (mp !== mediaPlayer) return`（防将来新增调用点）；
  ④ libvlc 事件监听器整段 `try/catch`（它跑在 libvlc 事件线程上，异常逃出去同样是进程崩溃）；
  ⑤ `resetPlayer()` 在 `stop()` 之后显式 `setEventListener(null)`，减少"入队即过期"的回调
  `android/app/src/main/kotlin/com/privi/app/MainActivity.kt`
  ⑥ 新增进程级崩溃兜底 `installCrashLogger()`：`Thread.setDefaultUncaughtExceptionHandler`
     → 堆栈落盘 `Download/密册/logs/密册_crash_<日期>.txt`（保留原 handler，不改变崩溃行为）；
  ⑦ `onDestroy()` 改为 `ioExecutor.shutdown()` + `awaitTermination(1s)` **之后**再
     `VlcPlayerHandler.releaseLibVlc()`（后台 `media.parse()` 用的是同一个 native libvlc 实例）
- 反例 / 易误判: ①"app 回到解锁页"当成系统杀后台/LMK —— 本次同一时刻日志里**一条 onDestroy 都没有**，
  且 11 秒后就重建进程，是崩溃后的自动重启；②被 `VDIAG[dart-position-stall]`（位置停在片尾）
  这类既有 WARN 带偏 —— 它和本次崩溃点无关；③只盯 Dart 的 `engine_fallback`/看门狗 ——
  Dart 进程内的异常一定会留日志，**没有日志就是原生侧**
- 相关文件: `android/app/src/main/kotlin/com/privi/app/VlcPlayerHandler.kt`、
  `android/app/src/main/kotlin/com/privi/app/MainActivity.kt`
- 决策: 见 `ADR-020`
- 首次记录: 2026-09-22 ／ 验证（本次）:
  ① **Kotlin 编译级验证已通过**：19:01 那次 `build.bat norelease` 里 `assembleRelease` 已经走到 R8
     （`build\app\outputs\mapping\release\{usage,seeds}.txt` 已写出）⇒ `:app:compileReleaseKotlin` 成功，
     即本次改动**语法/API 层面无问题**（`return@post` / `return@OnNewVideoLayoutListener` /
     `mp?.setEventListener(null)` / `Thread.setDefaultUncaughtExceptionHandler` 全部编译通过）
  ② **完整构建（装 APK）尚未跑通**，被两条既有环境问题挡住，与本次改动无关：
     `ISSUE-004`（R8 第 295.6 秒 `arena.cpp` OOM，`hs_err_pid20124.log`）+
     `ISSUE-001`（重试时 WMI 守卫 rc=5，构建 22 秒即终止）
  ③ 待办验证: 机器重启（或 `winmgmt /resetrepository`）后跑
     `build.bat norelease`（或完整 `build.bat`）→ 期望 `BUILD_FAILED=0` + 产出
     `build\app\outputs\flutter-apk\app-release.apk`；装到手机上再按"快速连点下一集"复现路径回归，
     崩溃不再出现、且 `Download/密册/logs/密册_crash_*.txt` 始终不生成即为通过
