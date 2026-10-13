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
- 复发判据: 先 `copy /y pubspec.yaml tmp\_selftest_pubspec.yaml`，再跑
  `powershell -NoProfile -ExecutionPolicy Bypass -File scripts\bump_version.ps1 -Path tmp\_selftest_pubspec.yaml`
  → 期望输出 `OK=1.0.59->1.0.60`（旧格式输入则是 `OK=1.0.30->1.0.31`）且文件里的 `version:` 真的变了
- 根因: 本机端点安全策略**静默拦截**命令行里含正则 `(\+)\d+` 的 `powershell -Command`：
  `powershell.exe` 以退出码 **786** 静默退出、什么都不输出，`pubspec.yaml` 没被修改
- 修法: 逻辑放进 `scripts\bump_version.ps1`，用 `-File` 调用；`build.bat` 事后**回读校验**，
  只有校验通过才回写 `.BUILD_NUM`
- 反例 / 易误判: 用 `powershell -Command` 一行式替换版本号；只看脚本退出码不看文件内容
- 相关文件: `scripts\bump_version.ps1`、`build.bat`(`:increment_version`)
- 修订 2026-10-07（版本方案改版，见 `ADR-026`）: 「第二个版本来源」`.BUILD_NUM` 已**整体删除**
  （文件本体 + `.gitignore` 条目 `/.BUILD_NUM` + `scripts\build_probe_procs.ps1` 第 53 行的探测项）。
  `bump_version.ps1` 去掉 `-BuildNumber` 参数，改为把 `pubspec.yaml` 版本的最后一段 +1
  （`1.0.59` → `1.0.60`）；`build.bat :increment_version` 的校验从「等于期望的 build number」
  改成「递增前后回读 pubspec，版本号必须真的变了」。上面那版 `-BuildNumber 999` 的复发判据已失效，按新命令判。
  实测: 新格式 `OK=1.0.59->1.0.60`；旧格式输入 `OK=1.0.30->1.0.31`（`+59` 后缀被丢弃、写成三段式）。
  注意: 去掉 `+build` 会连带触发 `PIT-027`（versionCode 回退成 1），所以 gradle 侧必须同步改。

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

## ISSUE-016 VLC 引擎下非 16:9 的视频只显示「一小块」画面（几何被裁）
- 状态: 已修复（`ADR-022`；真机回归待用户确认）
- 症状 / 现场: 用户报"第一个视频画面显示不完整，只有一小块"。日志
  （`密册_log_2026-10-01.txt`）三个视频都是 `engine=vlc`：
  * #1 `39cd4cc5_I_love_sex_toy_000449-000902.mp4` = **720x960**（3:4 竖屏）→ 画面异常
  * #2 `8a632efc_Babe_...mp4` = 1920x1080 → 正常
  * #3 `c7242eaf_Sexy_Japanese_...mp4` = 1920x1080 → 正常
- 复发判据（一条命令，先把日志 copy 成 ASCII 名再 `findstr`，见 `PIT-024`）:
  `findstr /n /c:"video surface attached" /c:"probed video size" tmp\log.txt` →
  **`attached ... at` 恒为 `1920x1080`、且与该 textureId 的 `probed video size` 不一致**
  ⇒ 同一根因仍在（修复后应为该视频的真实尺寸，竖屏片是 `720x960`，并出现新的
  `probed video size (before attach): ...` 行）
- 根因: 几何有两个来源、**顺序反了**：
  ① `initialize()` 立刻用常量 `FALLBACK_BUFFER_WIDTH/HEIGHT = 1920x1080` 调
     `surfaceTexture.setDefaultBufferSize()` + `vout.setWindowSize()` 并 `attachViews()`；
  ② 之后才由 io 线程 `media.parse()` 探测出真实尺寸，`applyVideoSize()` 把**缓冲区**
     改成 720x960 —— 而 vout 已在 1920x1080 的窗口上定型（`PoolAlloc()` →
     `AndroidWindow_Setup()`），此后每帧只校验 `sw.buf.width < fmt.i_width`，
     **不会重算布局** ⇒ 画面按 1920x1080 摆放，只有左上角一块落在 720x960 的缓冲里。
  同时 Dart 拿到的是**可视**尺寸 720x960（`STATE_READY ... size=720x960`），
  Flutter 侧按 3:4 取样整块缓冲 ⇒ 两边理解不一致、画面被裁。
  设计上本该由布局回调（`OnNewVideoLayoutListener`）统一这两个值，但本机
  **整份日志零 `video layout:` 行** ⇒ 该回调从未送达，兜底路径成了唯一来源。
- 证据:
  ① `tmp\log.txt`（原 `密册_log_2026-10-01.txt`）第 11/19/21 行（视频 #1）:
     `video surface attached to textureId=1 at 1920x1080` →
     `probed video size: 720x960, sar=1:1, textureId=1`（+141ms）→
     `STATE_READY: textureId=1, duration=253109ms, size=720x960 (buffer 720x960)`；
  ② #2/#3 的 `probed video size` 与兜底常量**一致**（1920x1080）⇒ 只有 #1 发生
     "缓冲区被改小"，也只有 #1 出问题，相关性完全吻合；
  ③ 全日志 `findstr /c:"video layout"` **零命中**（三个视频都没有）；而同一天
     `Vout event: voutCount=1` 说明 vout 是打开的 ⇒ 不是 `ISSUE-008` 那种全黑；
  ④ C 侧依据（缓冲区不得小于 fmt / `AndroidWindow_SetupANW()` 的 `setBuffersGeometry`
     指针可能为空）在 `VlcPlayerHandler` 原注释里已有记录 → 见 `ADR-022`。
- 修法: `android/app/src/main/kotlin/com/privi/app/VlcPlayerHandler.kt`
  ① `initialize()` 不再立刻挂视图：建好 `MediaPlayer`/`Media` 后调 `probeSizeThenAttach()`；
  ② `probeSizeThenAttach()` 在 **io 线程** `media.parse()` 拿尺寸 → 回主线程
     `applyVideoSize()`（宽度对齐 4）→ `attachViewsAndPlay()`；探测失败/超时
     （`PROBE_TIMEOUT_MS = 2000`）才用常量兜底先挂；
  ③ `attachViewsAndPlay()` 用**同一份** `videoWidth/Height` 调 `setDefaultBufferSize()`
     与 `setWindowSize()`，几何只定一次；
  ④ 探测期间 `play()` / `pause()` 只写 `attachPending` / `playRequested`，挂上视图后统一起播
     （不再出现"还没有 vout 就 play"）；
  ⑤ 删掉旧的 `probeVideoSizeAsync()` 与只为它服务的 `layoutSizeKnown`；布局监听器提取成
     `newVideoLayoutListener(mp)`（行为不变，仍带 `mediaPlayer !== mp` 身份校验）。
- 反例 / 易误判: ①当成 `ISSUE-008`（黑屏/纯色）复发 —— 本次画面**有内容**，只是被裁；
  ②以为 Dart 侧 `AspectRatio` 算错 —— Dart 收到的 720x960 本身没错，错的是原生
  缓冲/窗口几何；③把"布局回调没来"当成 vout 没打开（`Vout event: voutCount=1` 明确说明开着）。
- 相关文件: `android/app/src/main/kotlin/com/privi/app/VlcPlayerHandler.kt`
- 决策: `ADR-022`
- 首次记录: 2026-10-01 ／ 最近复核: 2026-10-01（本轮构建验证通过）
- 验证（2026-10-01 10:06，`build.bat norelease`）:
  `build\build_exit.log` = `BUILD_FAILED=0 WMI_FAILED=0 NEW_VER=1.0.30+56`；
  `Running Gradle task 'assembleRelease'... 712.1s` → `build\app\outputs\flutter-apk\app-release.apk`
  （121.7MB，根目录副本 `privi-1.0.30+56.apk`）；
  `build\app\tmp\kotlin-classes\release\com\privi\app\VlcPlayerHandler.class` 已产出
  ⇒ 本次 Kotlin 改动**编译级通过**；R8 `mapping\release\{seeds,usage}.txt` 已写出、
  `android\hs_err_pid*.log` 无新增（`ISSUE-004` 未复发）
- 待真机回归（唯一未验证项）: 装 `privi-1.0.30+56.apk` → 打开那个 720x960 的竖屏视频，
  画面应完整（不再只有一小块）；导出日志应出现
  `probed video size (before attach): 720x960...` 且 `video surface attached ... at 720x960`
  （不再是 `at 1920x1080`）

## ISSUE-017 长按菜单里两条「内部播放」在设置为 libVLC 时变成同一个引擎（看着像重复项）
- 状态: 已修复
- 症状 / 现场: 用户报"默认设置里就是 VLC 时，两个内部播放器的引擎选项都是 VLC"，
  长按菜单出现两条内容一样的选项
- 复发判据: 把 `播放引擎` 设置成 **libVLC**，长按任意视频 →
  「内部播放（默认引擎）」的副标题必须是 `ExoPlayer（系统解码器）`、
  「内部播放（VLC 引擎）」必须是 libVLC；两条副标题相同即复发
  （代码级判据：`video_open_target_sheet.dart` 里两条入口都必须传固定引擎，
  `findstr /c:"kSheetDefaultEngine" /c:"kExoPlayerEngine" /c:"kVlcEngine" lib\presentation\common\video_open_target_sheet.dart lib\presentation\grid\media_grid_screen.dart lib\presentation\visible\visible_media_grid.dart`）
- 根因: 第一版实现让「默认引擎」那条**跟随 `settings.playerEngine`**，只用副标题显示
  引擎名来消歧 —— 设置本来就是 libVLC 时，两条入口的引擎相同、名字却不同 ⇒ 用户看到重复项
- 修法: 两条入口的引擎**写死**，不再读设置：
  - `video_open_target_sheet.dart` 新增 `const PlayerEngine kSheetDefaultEngine = PlayerEngine.exoPlayer`，
    副标题固定显示它；`showVideoOpenTargetSheet()` 去掉 `defaultEngine` 参数
  - `media_grid_screen.dart` / `visible_media_grid.dart`：`internalDefaultEngine` →
    `forcedEngine: kExoPlayerEngine`，`internalVlcEngine` → `forcedEngine: kVlcEngine`
    （经 `initialForcedEngine` 落到 `VideoEngineFallbackState.forceEngineForItem`）
- 反例 / 易误判: 把"两条一样"当成 `VideoEngineFallbackState` 的强制值失效（其实强制值没问题），
  或去改设置页的引擎选项（设置页本就应该跟随用户选择）
- 相关文件: `lib/presentation/common/video_open_target_sheet.dart`、
  `lib/presentation/grid/media_grid_screen.dart`、`lib/presentation/visible/visible_media_grid.dart`
- 决策: `ADR-023`（含 2026-10-01 修订）
- 首次记录: 2026-10-01 ／ 验证: `build.bat gradle` →
  `build\build_exit.log` = `周四 2026/10/01 10:27:47.51 BUILD_FAILED=0 WMI_FAILED=0 NEW_VER=`，
  产出 `build\app\outputs\flutter-apk\app-release.apk`（127,631,021B）；
  Dart 侧 `frontend_server` 末行 `... tmp\_dartcheck.dill 0`（0 error）

## ISSUE-018 纯血鸿蒙手机（HarmonyOS 7 / HDC）在 Windows 上 `adb devices` 永远为空，而且装不了 APK
- 状态: 已规避（根因是设备/系统事实：装 APK 只能用 Android 设备）
- 症状 / 现场: 手机已开调试、插好 USB，`adb devices -l` 只有 `List of devices attached` 一行、**无设备**；
  重启 adb server（`kill-server` / `start-server`）无效；Windows 里看到的是
  `USB\VID_12D1&PID_1101\8HH0226911023008` = "USB Composite Device"（华为 VID_12D1），
  其 `DEVPKEY_Device_BusReportedDeviceDesc` = **`HDC Device`**（不是 ADB Interface）
- 复发判据（5 秒定论）: 两条命令对照 —— `hdc list targets` **有设备序列号**、`adb devices` **为空**
  ⇒ 本条目（鸿蒙原生设备），不要再折腾 adb / USB 驱动 / USB 模式
  （辅助判据：`Get-PnpDevice` 查 `DEVPKEY_Device_BusReportedDeviceDesc`，输出 `HDC Device`；
  注意别用 `powershell -Command` 一行式，会被静默拦 —— 见 `PIT-001`，存成 `.ps1` 用 `-File` 跑）
- 根因: 纯血鸿蒙（HarmonyOS NEXT 系列，本次实测 HarmonyOS **7.0.0.109 / API 26**）**不含 AOSP 层**，
  调试协议是 **HDC**（HarmonyOS Device Connector）而**不暴露 ADB 接口**；
  应用包格式是 `.hap/.hsp/.app`，**系统不认 APK**（不是"驱动没装好"）
- 证据（2026-10-07 实测）: `hdc list targets` → `8HH0226911023008`；
  `hdc shell param get const.product.model` → `HLS-AL00`（HUAWEI Mate 60）；
  `const.product.software.version` → `HLS-AL00 7.0.0.109(SP9C00E109R5P4)`；
  `const.ohos.apiversion` → `26`；`const.product.devicetype` → `phone`；
  `hdc help` 的 install 段原文：`src examples: single or multiple packages and directories (.hap .hsp .app)`
- 修法 / 规避:
  ① 安装 APK 只能换 **Android 设备 / 平板 / 模拟器**（`adb install -r privi-<ver>.apk`）；
  ② 本机 hdc 全路径 = `D:\Tools\DevTools\hmos\command-line-tools\sdk\default\openharmony\toolchains\hdc.exe`
     （`where hdc` **找不到**，PATH 里没有；查鸿蒙设备必须用全路径）；
  ③ 真要在纯血鸿蒙上用这个应用，得另做 **HarmonyOS 原生（.hap）** 版本 —— 本仓库只有 Flutter/Android 构建，不产出 hap
- 反例 / 易误判: ①以为「调试模式没开 / USB 驱动缺失 / USB 模式不对」，反复重启 adb、装驱动、切 USB 模式（全是白费）；
  ②把 `hdc` 当 adb 用（`hdc install xxx.apk` 直接报不支持）；
  ③看到设备管理器里有华为设备就以为"已经连上了"
- 相关文件: 无（环境事实）；README 的「安装（APK）」已加鸿蒙提示
- 首次记录: 2026-10-07

## ISSUE-019 设置里的「双击跳转」秒数对播放**没有任何影响**（双击手势从未实现）
- 状态: 已修复（2026-10-07：该值改为「快进/快退步长」，驱动播放区横向滑动）
- 症状 / 现场: 设置 → 播放设置 →「双击跳转 3/5/10/15s」，改了以后播放视频时**双击画面什么都不发生**；
  该秒数对进度条拖动、对任何 seek 步进也都不起作用（纯摆设）
- 复发判据: `findstr /s /n /c:"playerSeekSeconds" /c:"onDoubleTap" lib\*.dart`
  → 改动前只有：`settings_controller.dart`（读写）+ `player_screen.dart` / `viewer_screen.dart` /
  `gallery_preview_screen.dart` 里把 `settings.playerSeekSeconds` 传给**设置弹框**自用；
  `onDoubleTap` 全仓库只命中 `zoomable_media_image.dart`（图片缩放，与视频无关）；
  Kotlin 侧 `findstr /i /c:"doubleTap" android\app\src\main\java\*.kt` **零命中**
  ⇒ 没有任何代码消费它 = 无实现（不是"被别的功能覆盖了"）
- 根因: 第一版「双击跳转」功能的遗留 —— 设置项、持久化、设置弹框都做完了，
  但**双击手势本身从未接上**（`PlayerScreen` 画面层当时只有 `onTap: _toggleChrome`）
- 修法: **不新增设置项**，把这一个值复用为「快进/快退步长」：播放区横向滑动每滑过
  `videoSwipeSeekStepPx`(48dp) 算一档、一档 = `settings.playerSeekSeconds` 秒；
  设置页文案 `doubleTapSeek = '双击跳转'` → `seekStepSeconds = '快进/快退步长'`（getter 同步改名）
- 反例 / 易误判: ①以为"设置项存在 ⇒ 功能生效"（存下来 ≠ 有人读）；
  ②以为要**新建**一个「滑动步长」设置（同一个语义，再建一个就又多了个来源，正是 `ADR-026` 反对的模式）
- 相关文件: `lib/application/settings/settings_controller.dart`、
  `lib/presentation/player/player_screen.dart`、`lib/presentation/player/video_player_controls.dart`、
  `lib/presentation/viewer/viewer_screen.dart`、`lib/presentation/visible/gallery_preview_screen.dart`
- 决策: `ADR-028`
- 首次记录: 2026-10-07

## ISSUE-020 build_runner 里 drift_dev 报「This parameter should be a simple class name」= 外键被**静默丢弃**（analyzer ≥10.2.0）
- 状态: 已修复（dev 依赖钉 `analyzer` 10.1.0；上游 drift_dev 2.32.1 也修了）。**2026-10-08 由真机构建实测确认 FK 已回归**（见下"复核"）
- 症状 / 现场: `build.bat` 的 build_runner 阶段打印两条警告，然后照常写 `Built with build_runner/aot in 172s; wrote 242 outputs.` ⇒ 看起来"只是警告、构建成功"：
  ```
  W drift_dev on lib/data/db/tables.dart:
    line 84, column 47 of package:privi/data/db/tables.dart: This parameter should be a simple class name
      84 │   TextColumn get albumId => text().references(Albums, #id, onDelete: KeyAction.cascade)();
       │                                               ^^^^^^
  （line 85 同样一条，指向 .references(MediaItems, #id, ...)）
  ```
  同一次日志开头还有一条 `W SDK language version 3.13.0 is newer than `analyzer` language version 3.12.0. Run flutter packages upgrade.`（见 `ADR-029` ③，那条不处理）
- 复发判据: `findstr /c:"REFERENCES" lib\data\db\database.g.dart`
  → **零命中 = 已复发/FK 仍缺失**；正确状态是 `album_id`、`media_id` 两个 `GeneratedColumn` 里各有一条
  `defaultConstraints: GeneratedColumn.constraintIsAlways('REFERENCES albums (id) ON DELETE CASCADE')`
  （`media_id` 对应 `… media_items (id) …`）—— 实测正确形态见 `database.g.dart:1507-1521`。
  （也可在构建日志里搜 `should be a simple class name`，出现即命中）
- 根因: drift_dev 2.31.0 解析 `references(表类, #列)` 时用 `final first = args.first; if (first is! Identifier) { 报错; break; }`
  （`drift_dev\lib\src\analysis\resolver\dart\column.dart:268`，`break` 直接跳出、**不生成约束**）；
  **analyzer 10.2.0 起（解析器随之升到 `_fe_analyzer_shared` 96.0.0）该位置的裸类名被解析成 `TypeLiteral` 而不是 `Identifier`**
  ⇒ 判断恒成立、外键既不报错也不生效，从生成代码里彻底消失。
  上游 drift_dev 2.32.1 的修法（已下载 2.32.1 源码对照）正是同时接受两种节点：
  `switch (args.first) { Identifier(:final element?) => element, TypeLiteral(:final type) => type.element, _ => null }`
- 证据:
  - 构建日志两条 W（`tables.dart:84/85`）；这条消息在 drift_dev 2.31.0 里**只此一处**，且紧跟 `break`（丢弃约束）
  - `pubspec.lock`: drift 2.31.0 / drift_dev 2.31.0 / analyzer **10.2.0** / `_fe_analyzer_shared` 96.0.0
    （drift_dev 2.31.0 只要求 `analyzer >=8.1.0 <11.0.0`，所以 pub 把它升到了 10.2.0）
  - 修法前（analyzer 10.2.0 那次构建）：`database.g.dart` 里 `album_id` / `media_id` 的 `GeneratedColumn`
    **没有** `defaultConstraints`（对照 `drift_dev\lib\src\writer\utils\column_constraints.dart:50-72`：
    `references()` 会拼出 `REFERENCES <表> (<列>) ON DELETE CASCADE`）
  - drift_dev CHANGELOG 2.32.1: "Fix parsing references() with analyzer 10.2.0 and later."
  - **复核 2026-10-08（真机构建 `privi-1.0.62`，构建时间 23:49）**：`pubspec.lock` =
    `analyzer 10.1.0` + `_fe_analyzer_shared 95.0.0`；`build\build_full.log` 里
    `should be a simple class name` **零命中**；`database.g.dart:1507-1521` 两条
    `defaultConstraints: GeneratedColumn.constraintIsAlways('REFERENCES albums (id) ON DELETE CASCADE')` /
    `… media_items (id) …` ⇒ **FK 已回归，本条目闭环**
- 修法: `pubspec.yaml` 的 `dev_dependencies` 里加 `analyzer: 10.1.0`（附注释说明为什么不能升）；
  之后按常规流程手工构建一次 —— `build.bat` 里的 `flutter pub get` 会把 lock 里的 analyzer 降回 10.1.0
  （`_fe_analyzer_shared` 96.0.0 → 95.0.0），build_runner 重新生成 `database.g.dart` 时 FK 应该回来。
- 反例 / 易误判:
  - 把这两条 W 当"无关紧要的 lint"忽略 —— 它代表 `album_media` 的 **FOREIGN KEY 真的没了**，
    而 `database.dart:56` 还开着 `PRAGMA foreign_keys = ON`（等于外键约束全废）
  - 以为"删相册/删媒体本来就会级联"：当前其实靠 `database.dart:468/475/988` 的显式 delete 兜着，
    一旦新增依赖级联的路径就会出问题
  - 顺手 `flutter pub upgrade`（analyzer 又被升回 ≥10.2.0）⇒ 静默复发（`ADR-029` 约束）
  - 只盯着"构建成功/242 outputs"下结论 —— 生成器报 W 时也可能**少生成内容**
- 相关文件: `pubspec.yaml`、`lib/data/db/tables.dart`、`lib/data/db/database.dart`、`lib/data/db/database.g.dart`（生成物，gitignore）
- 决策: `ADR-029`（为什么不直接升 drift/drift_dev）
- 首次记录: 2026-10-07

## ISSUE-021 「左右滑动快进/快退」真机上完全没生效（功能只在 PlayerScreen，而用户看视频的界面是 ViewerScreen）
- 状态: 已修复（改法见下；**待手工构建后在真机验证**）
- 症状 / 现场: 装 `privi-1.0.61` / `privi-1.0.62` 后在**查看器**（私密库点视频进入的全屏查看器）里
  左右滑动画面：既不快进/快退，**也不翻页**（`ViewerScreen` 在视频时把 `PageView` 设成
  `NeverScrollableScrollPhysics`）⇒ 看着像"这个功能根本不存在"
- 复发判据: 先分清"在哪个界面"，再看同一次滑动：
  1) 日志里**没有任何 `PlayerScreen` 行** ⇒ 用的是 `ViewerScreen` / `GalleryPreviewScreen`
     （这两个界面平时不打日志）；
  2) 搜 `Swipe seek gesture end`：**一行都没有** ⇒ 手势没到播放层（该界面没挂这一层 / 命中测试问题）；
     有这行但 `horizontal=false` 或 `steps=0` ⇒ 位移/方向判定问题（阈值 12dp、一档 48dp）；
  3) 有 `Swipe seek:` 而没有位置变化 ⇒ 问题在原生 seek（与本条无关，查 `seekTo` 链路）
- 根因（两层）:
  ① **功能只做在 `PlayerScreen` 上**（`ADR-028` 当年的取舍），而看私密视频的正常路径是
     `私密相册 → media_grid_screen.dart:175 → ViewerScreen`；真机日志证明用户走的就是 Viewer；
  ② `ADR-028` 的前提"viewer 的横滑已被 `PageView` 占用"**对视频不成立**：
     `viewer_screen.dart:503` / `gallery_preview_screen.dart:424` 是
     `item.isVideo ? NeverScrollableScrollPhysics` —— 视频时 `PageView` 根本不接管横滑，
     那条路径上的横滑**一直空着没人用**；
  ③ 另有历史毛病（`1004a89` 那版，即使只在播放列表页也不该那样）：`GestureDetector` 默认
     `deferToChild` ⇒ 只有"视频画面矩形"能命中，上下黑边/控制条缝隙落空；`onHorizontalDrag*`
     走手势竞技场可能被抢；且**没有任何日志**，出问题只能靠猜
- 证据:
  - `C:\Users\766698\Downloads\密册_log_2026-10-08.txt`（131 行）：`findstr /c:"PlayerScreen"` **0 命中**、
    `findstr /c:"Swipe seek"` **0 命中**；同时 `[Main] Version: 1.0.62 (versionCode 10062)`
    ⇒ 构建是新的、但手势一行日志都没有（= 那版代码里 Viewer 没有这一层）
  - 同日志里视频都是 `[VideoPlayer] Creating native player … engine=vlc`、路径在
    `/storage/emulated/0/.privateheart_vault/new/`（私密库）⇒ 走的是 Viewer 那条入口
  - 两次 `[VideoPlayer] seekTo(...)` 前**没有** `Swipe seek:` 行 ⇒ 那是查看器底部进度条划出来的，不是滑动
  - `viewer_screen.dart:503`、`gallery_preview_screen.dart:424`（`NeverScrollableScrollPhysics`）；
    `TextureBox.hitTestSelf => true`（`flutter\lib\src\rendering\texture.dart:95`）
- 修法: 把滑动逻辑抽成**共用层** `lib/presentation/player/video_swipe_seek.dart` 的 `VideoSwipeSeekLayer`
  （`Listener` + `HitTestBehavior.opaque` + 原始指针事件 + 方向锁 12dp + 只跟第一根手指 +
  长度未知时只提示不跳转 + 每次滑动一行诊断日志），然后三处视频界面都挂上：
  `PlayerScreen`、`ViewerScreen`、`GalleryPreviewScreen`（各自外面仍套原来的
  `GestureDetector(onTap: _toggleChrome)`，跳转接各自的 `_seekTo`）；
  图片仍交给 `PageView` 翻页，视频路径本来就不翻页 ⇒ 互不冲突。
- 反例 / 易误判:
  - 只看"`PlayerScreen` 里改好了"就以为修完 —— **先确认用户实际操作的是哪个界面/入口**
    （日志里有没有 `PlayerScreen` 行），否则改的是用户根本不用的界面（本轮就绕了一圈）
  - 以为"viewer 的横滑被 `PageView` 抢"（视频时 physics = `NeverScrollableScrollPhysics`，不抢）
  - 以为"`Texture` 不吃手势所以整块死的"（错：`hitTestSelf=true`）
  - 手势类改动**必须真机滑一次** —— `dart analyze` 覆盖不到（`ADR-027`）
- 相关文件: `lib/presentation/player/video_swipe_seek.dart`（共用层）、
  `lib/presentation/player/player_screen.dart`、`lib/presentation/viewer/viewer_screen.dart`、
  `lib/presentation/visible/gallery_preview_screen.dart`、
  `lib/presentation/player/video_player_controls.dart`（`videoSwipeSeekStepPx` / 提示）
- 决策: `ADR-028`（两次修订：先换原始指针 + `opaque`；再抽成共用层覆盖三个界面）
- 首次记录: 2026-10-07 ／ 最近复核: 2026-10-08（据真机日志定位到"界面不对"，并覆盖三个界面）

## ISSUE-022 视频播完后拖进度条回开头：不播放、进度条自己弹回结尾（`VDIAG[dart-position-stall]`）
- 状态: 已修复（改法见下；**待手工构建后在真机验证**）
- 症状 / 现场: 一个视频播完（`STATE_ENDED`）后把进度条拖到起始位置，期望重新播放，
  结果**不播**、进度条直接跳回结尾；再按播放也没反应。日志尾部是
  `play: textureId=2` 之后什么都没有 + `VDIAG[dart-position-stall] position stuck at 31724ms while isPlaying=true`
- 复发判据（5 秒定论，读 app 日志即可）: 在日志里搜 `STATE_ENDED`，其后若出现
  `seekTo(content=0ms`（或任意位置）→ `play: textureId=N` → **没有** `onPlaying` / `Event playingChanged`
  且紧跟 `position stuck at <duration>ms while isPlaying=true` ⇒ 就是本条；
  一票否决项：若 `seekTo` 之后有 `onPlaying`（原生重新起播），则**不是**本条
- 根因（三层，缺一个都修不干净）:
  ① **原生 input 播完就"死了"**：libVLC 的 `EndReached`（ExoPlayer 的 `STATE_ENDED`）之后
     `MediaPlayer` 的 input 已经结束，`mp.time = 0` + `mp.play()` **不会**重新起播
     —— 日志证据：`play: textureId=2` 之后 3 秒内没有任何 `Playing`/`Vout` 事件，
     `getStatus` 一直 `isPlaying=false`（`VlcPlayerHandler.play()` 里 `mp.play()` 是空转）
  ② **原生 `getPosition()` 说谎**：`VlcPlayerHandler.getPosition()` 写成
     `if (isEnded) return durationMs`，而 `isEnded` 只在 `resetPlayer()`（initialize/release）
     里清 ⇒ 播完后**任何**位置都被报成结尾；Dart 侧 `play()` 会重启 250ms 位置轮询
     （`_startPositionTimer`）⇒ 刚拖到 0 的位置被下一次轮询覆写回 duration
     ⇒ 用户看到"**直接跳到结尾**"
  ③ **Dart 侧的"重播要重建播放器"分支被自己跳过**：
     `gallery_preview_screen._playFromCurrentPosition` 用 `value.isCompleted` 判断"已播完"，
     但进度条拖动先调了 `seekTo()`，而 `native_video_controller.seekTo()` 会重算
     `isCompleted = contentMs >= durationMs`（=false）⇒ 重建分支被跳过，
     掉进 plain `video.play()`（配合 ① 就是"按了播放没反应"）
- 证据（`C:\Users\766698\Downloads\密册_log_2026-10-10.txt`，同型共 3 次：11:11 / 11:50 / 12:05）:
  ```
  11:50:40.935 INFO [VideoPlayer.native] STATE_ENDED: textureId=2, position=31724
  11:50:40.935 INFO [VideoPlayer] Playback completed, textureId=2
  11:50:43.756 DEBUG [VideoPlayer] seekTo(content=0ms, native=0ms, timelineOffset=0 ms) -> textureId=2
  11:50:44.805 DEBUG [VideoPlayer] play() -> textureId=2
  11:50:44.806 INFO  [VideoPlayer.native] play: textureId=2
  11:50:45.060 WARN  [VideoPlayer.diag] VDIAG[dart-position-stall] position stuck at 31724ms while isPlaying=true, textureId=2
  11:50:45.063 WARN  [VideoPlayer.diag] VDIAG[...] playing=true ... position=31724ms | native ready=true playing=false position=0ms
  11:50:56.532 DEBUG [GalleryPreviewScreen] Saved resume position (stop): item=392, pos=31724ms, dur=31724ms
  ```
  ↳ `native ... position=0ms` 说明**原生侧其实收到过 seek**（`mp.time` 已是 0），
    只是 `getPosition()`（走 `isEnded` 分支）把它报成了 31724，并且 input 根本没起播
- 修法（3 处，互相补齐）:
  1. `android/app/src/main/kotlin/com/privi/app/VlcPlayerHandler.kt`
     —— `getPosition()` 的 `isEnded` 分支改成回 `lastPositionMs`（EndReached / seekTo /
     TimeChanged 共同维护的"最后一次已知位置"：播完没拖动时等于 duration，行为不变；
     拖动后就是用户拖到的值）；`status()` 的 `position` 改用 `getPosition()` 保持同口径
  2. `lib/data/services/native_video_controller.dart`
     —— 新增**每实例闩锁** `bool get mediaEnded`（`completed` 事件与 `applyStatus` 置位，
     `seekTo`/`play` 都**不清**），语义 = "这条原生 input 已经结束，想再看必须重建播放器"
  3. 三个视频界面统一"重建式重播"（新代码一律不要用 `seekTo(0)+play()`）:
     - `gallery_preview_screen` / `viewer_screen`: 新增一次性 `int? _pendingStartMs`，
       `_seekTo()` 里 `if (video.mediaEnded && position < duration) → _replayFromPosition(position)`
       （"播完后拖回前面" = 重建 + 从目标位置起播），`_playFromCurrentPosition()` 也改用
       `mediaEnded` 判定并重建（位置还在结尾之前就从那儿继续，否则从 0）
     - `player_screen`: 播完后 `_seekTo()` 只记 `_replayItemId/_replayStartMs`
       （本屏播放状态归播放列表控制器，不在 seek 里改状态），等用户按播放走到
       `_loadVideoInner` 的重建分支时，用这个起点**优先于**持久化的续播位置
     - 重建路径本身是本仓库已验证的路径（`_stopVideo()+_loadCurrent()` /
       `_detachVideo()+_syncVideo()` / `_disposeNativeVideo()+loadVideo()`），
       和正常打开视频完全同一条链路，不依赖任何未验证的 libVLC 行为
- 反例 / 易误判:
  - 以为"seek 没生效"或"进度条 UI 没刷新" —— 实际是 `getPosition()` 报的假位置 + input 真的没起播
  - 以为 `seekTo(0)` + `play()` 能续播（旧 `ViewerScreen._playFromCurrentPosition` 就是这么写的，
    一样是废的）；也**不要**顺手在原生里加 `stop()+play()` 去"复活" input
    —— 那条路没在真机验证过（理由见 `ADR-031`）
  - 只盯 `value.isCompleted` 判定"是否已播完" —— 进度条拖动会把它清掉（根因 ③）
  - 顺手把 `_mediaEnded` 清掉（比如在 `play()` 里）—— 会让界面重新掉回"seek+play 空转"的老路
- 相关文件: `android/app/src/main/kotlin/com/privi/app/VlcPlayerHandler.kt`、
  `lib/data/services/native_video_controller.dart`、`lib/presentation/visible/gallery_preview_screen.dart`、
  `lib/presentation/viewer/viewer_screen.dart`、`lib/presentation/player/player_screen.dart`
- 决策: `ADR-031`（为什么"重建"而不是"复活原生 input"）
- 首次记录: 2026-10-10

## ISSUE-023 打开视频后进度条**一开始就在结尾**（原生 input 起播约 0.1~0.35s 就报 EndReached）
- 状态: 已规避（应用层自愈；**原生侧根因未定位**）
- 症状 / 现场: 单击打开一个视频，进度条**一上来就停在结尾**（既不是开头、也不是续播记忆位置），
  画面不动。旧构建里表现为"点开秒完、自动跳到下一个文件"——以前被**自动连播**掩盖，
  2026-10-10 去掉自动连播（`ADR-032`）后才以"停在结尾"的形态暴露出来。
  随机复现：实测同一文件 8 次打开里 3~4 次
- 复发判据（读 app 日志，5 秒定论）:
  1) 本修复后（1.0.74+）: 搜 `VDIAG[spurious-end]` / `Spurious end right after start`
     ⇒ 命中（若同时出现 `Spurious end repeated ... accepting it as finished`，
     说明同一个 item 连续两次触发、自愈已放弃）；
  2) 任何版本都适用: 一次加载里 `STATE_READY`/`onPlaying` 之后 **20~260ms** 就出现
     `Vout event: voutCount=0` + `STATE_ENDED`，且 `voutCount=0` 在 `STATE_ENDED` **之前**
     ⇒ 命中。**真播完**的顺序相反：先 `STATE_ENDED`，`voutCount=0` 在**其后**
     （例：`密册_log_2026-10-10.txt` 14:17:18.387 ENDED → 14:17:18.434 vout=0）
- 根因: **未定位**（设备/VLC 层随机竞态）。已确认的事实：
  - **与 seek 无关**：11:11:22 那次（旧构建、**完全没有任何 seek**）同样复现；
    1.0.73 的 14:15:39（应用刚启动、首次打开、seek 0、无续播）也复现
  - **与本次改动无关**：新旧构建都有；旧构建里它被自动连播掩盖成"播完自动下一个"
  - 时序特征：`probed video size` → `video surface attached` → `play()` → `length changed`
    → `Vout voutCount=1` → `STATE_READY/onPlaying` → **`Vout voutCount=0` → `EndReached`**；
    而起播正常的那几次是 `… onPlaying → Vout voutCount=1`（vout 重建/确认）后继续播
  - 注意 `STATE_ENDED` 里的 `position=<duration>` 是**代码自己打印的 `durationMs`**
    （`EndReached` 分支里 `lastPositionMs = durationMs`），**不能**当成"input 真走到结尾"的证据
  - 推测（**未验证**）：起播瞬间的 vout/ES 竞态（`--no-audio-time-stretch` + 安卓 AWindow 几何 +
    尺寸探测/挂 vout 时序）让视频 ES 起不来 ⇒ 没有可播的 ES ⇒ VLC 立刻按 EOF 结束 input；
    与 100% 复现的"首帧 PTS 回绕"（`ISSUE-009`）**不是**同一回事
- 修法（应用层自愈）:
  1. `lib/data/services/native_video_controller.dart`：新增 `onSpuriousCompletion` 回调
     与 `_isStartupGlitch(pos)` —— **`completed` 事件的 position 离结尾还很远时不当成"播完"**
     （真播完时 250ms 的位置轮询保证 position 就在 duration 附近；判定 = 差 > 1.5s 且 < 90%），
     打 `VDIAG[spurious-end]`，把事件交给界面；不置 `isCompleted`、不动 `position`
  2. 三个视频界面接到"**重建播放器 + 从 `video.value.position`（续播目标 / 0）继续播**"
     （gallery/viewer 用 `_replayFromPosition`；player screen 用 `_replayItemId/_replayStartMs`
     + `_completedForId` 触发重建），每个 item **只自动救一次**（`_spuriousRecoveredIds`），
     第二次起回到原行为（gallery/viewer = 停在最后一帧；player screen = 跳下一个），
     避免坏文件无限重建
- 反例 / 易误判:
  - 把 `STATE_ENDED: position=<duration>` 当成"input 真走到结尾"（那是自己打印的 `durationMs`）
  - 以为"是 `seekTo` / 续播逻辑把播放搞坏的"（旧构建无 seek 也复现）
  - 以为"是 Cline 这次改动引入的"（新旧构建都有，只是旧构建被自动连播掩盖）
  - 只开一次没复现就以为修好了 —— 它是随机的，要**连开 5~10 次**统计
- 下一步（要真正定位原生根因时）: 临时把 `VlcPlayerHandler.getLibVlc()` 的 libvlc 日志级别
  改成 `-vvv`（verbose=2）抓一次复现；**注意该类注释里明确写了 verbose=2 会把每条 libvlc 日志
  经 MethodChannel 转发给 Dart、刷爆通道并拖慢解码，抓完立刻改回 0**。重点看
  `android-display` / `android-opaque` / `avcodec` / `no suitable decoder` 之类的行；
  另外确认这两个 mp4 是否**没有音轨**（无音轨 + 视频 ES 起不来 = 立即 EOF）
- 相关文件: `lib/data/services/native_video_controller.dart`、
  `lib/presentation/visible/gallery_preview_screen.dart`、`lib/presentation/viewer/viewer_screen.dart`、
  `lib/presentation/player/player_screen.dart`（改动）；
  `android/app/src/main/kotlin/com/privi/app/VlcPlayerHandler.kt`（**未改**，仅用于对照时序）
- 相关条目: `ISSUE-022`（播完后重播要重建）、`ADR-031`、`ADR-032`（去掉自动连播后本问题才显形）、
  `ISSUE-009`（另一种"秒完"：首帧 PTS 回绕，100% 复现，已修复）
- 首次记录: 2026-10-10

## ISSUE-024 加密文件查看链路三个临界缺陷：KEK 缺失返回密文→播放器崩溃、`looksEncrypted` 全量读文件→OOM、锁屏后 KEK 竞态注入
- 状态: 已修复（2026-10-13 排查并修复，均为加密功能上线前的 proactive 隐患扫描）
- 症状 / 现场:
  ① 锁屏/指纹未加载 KEK 时，viewer 打开加密文件 → 播放器拿到密文字节流 → 解码画面全噪点或崩溃；
  ② 批量加密前检查 `looksEncrypted(file)` → 35GB 视频 `readAsBytesSync()` 撑爆内存 → OOM；
  ③ PBKDF2 密钥派生异步回调在用户锁屏**之后**完成 → `setKey(kek)` 把 KEK 注入已锁定的内存 → 状态不一致。
- 复发判据（一条命令定论）:
  ```bash
  # 缺陷①：_resolveDisplayPath 返回类型是否为 Future<String?>、null 分支是否每个调用方都处理
  git grep -n "Future<String> _resolveDisplayPath\|return item.privatePath" lib/presentation/viewer/
  # 缺陷②：looksEncrypted 是否用了 readAsBytesSync
  git grep -n "readAsBytesSync" lib/data/services/media_encryption_service.dart
  # 缺陷③：lock() 后是否有 gen counter 防异步注入
  git grep -n "_kekGen" lib/application/lock/
  ```
- 根因:
  ① `_resolveDisplayPath` 原返回类型 `Future<String>`，KEK 缺失/解密失败时"兜底"
     `return item.privatePath`（密文路径）→ 调用方（`_syncVideoBody` / `_openExternal`）无感知；
  ② `looksEncrypted()` 只需判断前 12 字节（AES-GCM nonce），但实现用 `file.readAsBytesSync()`
     把整个文件读进 `Uint8List`——文件多大内存就多大；
  ③ `lock()` 调用 `encryptionKeyManager.clear()` 同步清内存 KEK，但 `security.deriveEncryptionKey(secret)`
     是异步的（PBKDF2 210k 迭代约 0.5-2s），`.then()` 回调可能在 lock 之后把 KEK 写回内存。
- 修法:
  ① `_resolveDisplayPath` → `Future<String?>`，所有失败路径 `return null`；
     `_syncVideoBody`: null → 设 `_videoError` + 错误提示不走 `NativeVideoController.create`；
     `_openExternal`: null → SnackBar 提示 + return；
     `initState` 的 pre-resolve（`line 105`）：null 静默跳过（后续 `_syncVideo` 会二次尝试并展示错误）。
  ② `looksEncrypted` 改用 `RandomAccessFile` 只读 32 字节（`openSync` + `readIntoSync`），
     提取 `_looksLikePlainMedia()` 静态方法统一判 JPEG/PNG/MP4/WebM/MKV 魔数，语义翻转
     （原 returns `false` = 明文 → 现 `_looksLikePlainMedia` returns `true` = 明文，外层取反）。
  ③ `LockController` 新增 `int _kekGen = 0` generation counter：
     `lock()` 第一行 `_kekGen++`（在 `clear()` 之前）；`_deriveAndStoreEncryptionKey` 里
     `final gen = ++_kekGen` → `.then()` 里 `if (gen != _kekGen) return;` 丢弃过期回调。
  ④ 附加修复：临时文件名加 8 位安全随机数后缀（`Random.secure().nextInt(0xFFFFFFFF).toRadixString(16)`），
     防同毫秒并发碰撞。
- 反例 / 易误判:
  - "返回类型改成 nullable 太麻烦，不如回到前面加个判断"——原来的 `if (kek == null) return item.privatePath`
    正是这种"判断后绕过"的思路，它让调用方永远不知道发生了失败；
  - "`readAsBytesSync()` 就一行，改它干啥"——一行能让 35GB 文件 OOM；
  - 把 KEK 竞态当"理论上的问题"——PBKDF2 210k 迭代慢机可到 2 秒，期间用户完全可能切后台/自动锁屏，
    竞态窗口真实存在。
- 相关文件: `lib/presentation/viewer/viewer_screen.dart`、`lib/data/services/media_encryption_service.dart`、
  `lib/application/lock/lock_controller.dart`
- 首次记录: 2026-10-13
- **2026-10-13 二次审计追加**（同一天全链路复审发现的新隐患，均已修复）:
  ④ **非原子文件替换**：`CryptoHandler.kt encryptFile` 和 `VaultRevealRunner._decryptIfNeeded`
     都是 `delete(original)` → `rename(temp, original)` 两步，中间崩溃窗口 = 文件永久丢失
     （→ PIT-034，修复为 backup→rename→delete 三步安全替换）
  ⑤ **首次设置密码不派生 KEK**：`setupPattern`/`setupPin`/`enterAppAfterSetup` 三个入口在
     解锁后都没调用 `_deriveAndStoreEncryptionKey` → 首次导入的文件不会加密（KEK 为 null 时
     `_encryptRecordedFiles` 静默跳过）→ 用户需手动锁屏再解锁或手动跑"Encrypt Existing Files"
     （修复：三个入口全部补上 KEK 派生/加载逻辑）
  ⑥ **加密图片首次渲染密文竞争**：`_mediaPage` 用 `_decryptedTempPaths[item.id] ?? item.privatePath`
     但 `_resolveDisplayPath` 是异步的 → 解密未完成时直接用密文路径渲染 → 图片花屏/解码崩溃
     （修复：`hasEncryptedDek && cachedPath==null` 时显示 loading 圆圈；解密完成后 `.then()` 触发 `setState`）

## ISSUE-025 第三次审计：changePattern DEK 旋转缺失 + JPEG 误判 + UI 死锁 + recovery 数据孤岛
- 摘要: 密码修改链路缺少 DEK 重加密，改密码 = 丢文件；`looksEncrypted` JPEG 魔数过严导致
  带 EXIF 的照片永不加密；`_resolveDisplayPath` 失败后 UI 永远转圈；恢复密码时已加密文件
  彻底成孤儿
- 根因（按发现顺序）:
  ① **`looksEncrypted` JPEG 误判**：`_looksLikePlainMedia` 的 JPEG 魔数包含 JFIF 特化字节
     `E0 00 10 4A 46`，但相机 JPEG 用 EXIF (`E1`) 打头 → 不匹配 → `looksEncrypted=true`
     → 加密跳过 → （`PIT-035`，修复：改 8 字节为 3 字节 SOI `FF D8 FF`）
  ② **`_resolveDisplayPath` null → 无限 spinner**：返回 null 后 `_decryptedTempPaths` 无记录
     → `hasEncryptedDek && cachedPath==null` 永真 → spinner 永转
     → （`PIT-037`，修复：新增 `_decryptFailedIds` 集合，已失败时显示 `broken_image` 图标）
  ③ **`changePattern`/`changePin`/`migratePinToPattern` 不旋转 DEK**：改完凭证后旧 KEK 仍可用
     （因为没更新），但下次锁屏再解锁 = 新 KEK → 旧 DEK 全废 → （`PIT-036`）
     （修复：三个入口全部加入 DEK 旋转逻辑，提取 `_rotateAllDeks` 共享方法；
      DB/Repository 新增 `listEncrypted` / `listEncryptedActiveMediaRows`）
  ④ **`recoverWithSystemAuth` 无加密警告**：忘记图案走系统验证恢复后，所有加密 DEK 成为孤儿
     （修复：`forgotPatternBody` l10n 文案加 ⚠️ 警告）
- 教训: 双层密钥架构（KEK→DEK→File）中，任何 KEK 变更都是全量数据重加密事件；
  改密码 = 改 KEK，必须遍历所有 DEK 做旋转。忘记密码 = KEK 不可恢复 = DEK 全损。
  忘记了这一层关系写出 `changePattern` 只调 `setPattern` 就返回，是体系性盲区。
- 相关文件: `lock_controller.dart`、`media_encryption_service.dart`、`viewer_screen.dart`、
  `database.dart`、`media_repository.dart`、`app_localizations.dart`
- 首次记录: 2026-10-13（第三次全量审计，已修复）

## ISSUE-026 第四次审计：DEK 旋转原子性+幂等性+有序性缺陷
- 摘要: `_rotateAllDeks` 在三个维度上存在断层：oldKek 可为 null → 静默跳过旋转；
  非幂等 → 中断重入时用新 KEK 加密已旋转的条目；三个改密入口 `setNewCredentials` 先于
  `_rotateAllDeks` → 旧 KEK 先被覆盖 → 旋转必然失败
- 根因（按发现顺序）:
  ① **PIT-038 oldKek 为空时静默跳过**：当 KEK 只在 FlutterSecureStorage 中而
     `keyManager.getKey()` 不在内存时，`_rotateAllDeks` 读到 null → return → DEK 未旋转
  ② **PIT-039 非幂等**：重入时 `keyManager.getKey()` 已更新为新 KEK，用新 KEK 解密旧 DEK
     → 失败 → 该条目被跳过 → 旧 DEK 永远不可解 → 文件丢失
  ③ **PIT-040 顺序错误**：`changePattern`/`changePin`/`migratePinToPattern` 先调
     `setNewCredentials`（覆盖旧 KEK 派生参数）→ 再调 `_rotateAllDeks` →
     此时 `_deriveNewKek` 派生的新 KEK ≠ 当前 `keyManager.getKey()` 的旧 KEK →
     旋转失败率极高
  ④ **PIT-041 并发解密临时文件泄漏**：viewer 同时刷新多张预览图 → `_decryptPathInternal`
     无去重 → 同文件并发解密 → 临时文件互相覆盖 → 解码失败
  ⑤ **PIT-042 死参数**：`_batchEncrypt` 传入 `kek` 参数但循环内重新读 `keyManager.getKey()`
- 修复:
  - `_rotateAllDeks` 增加 `oldKek==null` 检查 → `retrievePersistedKek()` 回退
  - 幂等实现：先试 `newKek` 解密（已旋转），再试 `oldKek` 解密（未旋转）
  - 三个改密入口重新排序为：验证凭证 → 派生新 KEK → 旋转 DEK → 更新凭证
  - Viewer 新增 `_decryptFutures` Map 去重并发调
  - 移除 `_showEncryptProgress` 死参数 `kek`
- 教训: 状态变更操作（改密码）有三个铁律：
  1. 可回滚操作在前（验证旧凭证），不可逆操作在后（写入新凭证）
  2. 幂等性 = 中断安全 = 可重试
  3. 所有读取旧状态的代码必须在状态变更前执行完
- 相关文件: `lock_controller.dart`、`viewer_screen.dart`、`settings_screen.dart`
- 首次记录: 2026-10-13（第四次全量审计，已修复）

## ISSUE-027 第五次审计：生物识别解锁瘫痪 + 孤儿文件 + KEK 竞态
- 摘要: `lock()` 删除持久化 KEK → 生物识别解锁永久不可用；
  `purgeMany` 删除文件失败仍删 DB 行 → 孤儿文件残留；
  `_encryptRecordedFiles` crash 窗口期 DEK 永久丢失（理论风险）；
  `unlockWithPattern` KEK 派生异步竞态 → UX 抖动
- 根因（按发现顺序）:
  ① **PIT-042 (v5) lock() 删除持久化 KEK → 生物识别解锁永久不可用**：
     `lock()` → `keyManager.clear()` → 删除 FlutterSecureStorage 中的 KEK →
     每次 auto-lock 或手动 lock 后，`unlockWithBiometric` → `retrievePersistedKek()`
     返回 null → KEK 加载失败，加密媒体不可访问，必须用图案/PIN 重新解锁
  ② **PIT-043 purgeMany 文件删除失败后仍删除 DB 行**：
     遍历删除所有文件 → 无论成败一律 `hardDeleteMediaMany(ids)` → 
     文件删除失败 = DB 行被删除 = 文件残留在 vault 无人引用
  ③ **PIT-044 crash 窗口期 DEK 永久丢失**（未修复，已标记）：
     `encryptFile` 成功 → 在 `updateEncryptedDek` 写入 DB 前 crash → DEK 随进程消失
  ④ **PIT-045 enterAppAfterSetup PBKDF2 竞态**（未修复，已标记）：
     `setupPattern(unlockNow: false)` 启动异步 PBKDF2 → 生物识别对话框跳过 →
     `enterAppAfterSetup` 时 KEK 未写入 → vault unlocked 但无 KEK
  ⑤ **PIT-046 unlockWithPattern KEK 派生先于状态**（未修复，已标记）：
     先 `state = unlocked` → 再 fire-and-forget PBKDF2 → 1-2s 窗口内 `getKey() == null`
- 修复:
  - `EncryptionKeyManager` 新增 `clearMemory()`（仅清空内存）与 `clear()` 分离
  - `lock()` 改用 `clearMemory()`，保留持久化 KEK 供生物识别解锁
  - `purgeMany` 逐个 try/catch 文件删除，仅成功删除的 id 执行 DB 清理
  - PIT-044/045/046 难度或风险较大，暂不修复，标记为后续专项
- 教训: 
  1. `lock()` 的职责是「锁定界面、清空内存密钥」，不是「注销凭据」
  2. 任何「先删除再记录」的操作都必须考虑删除部分成功/部分失败的情形
  3. 生物识别依赖于持久化存储中的 KEK——删除它就是删掉生物识别功能
- 相关文件: `encryption_key_manager.dart`、`lock_controller.dart`、`media_repository.dart`
- 首次记录: 2026-10-13（第五次全量审计，已修复 3/6，标记 3/6）

## ISSUE-028 指纹"无法正常解锁"：弹窗验证通过却原地不动（KEK 缺失被静默吞掉）
- 状态: 未定位（应用层已补可见反馈与诊断日志，见「修法」；**KEK 为何缺失**待设备日志坐实）
- 症状 / 现场: 锁屏指纹弹窗弹出、验证通过，但**不解锁也没有任何提示**（点指纹图标同样没反应）；
  用户只能改用图案/PIN —— 用图案解锁一次后，指纹立即恢复正常。
  高发场景：**从旧版本升级上来、长期只用指纹解锁、从未输入过图案**的设备
- 复发判据（读设备日志，5 秒定论；日志在 `Download/密册/logs/密册_log_YYYY-MM-DD.txt`）:
  1) 出现 `Biometric OK but no persisted KEK found` ⇒ 命中本条（KEK 缺失）
  2) 指纹弹窗**根本不出现** / 设置页开关灰掉 ⇒ 看 `biometric status: supported=… canCheck=… types=…`
     或 `biometric hw: …`（硬件/录入分支）
  3) 弹窗出现但验证失败 ⇒ 看 `biometric authenticate result=false` /
     `biometric auth platform: code=…`（NotEnrolled、LockedOut、PermanentlyLockedOut…）
- 根因: **未定位**（KEK 缺失本身的原因未坐实）。已确认的代码事实：
  ① `unlockWithBiometric()` 在 `retrievePersistedKek() == null` 时**保持锁定并裸 `return false`**
     （`lock_controller.dart`，`f812d9d` 之后的现状）
  ② 该行为由 `f812d9d fix(PIT-049)` 引入：之前是"验证成功即置 `unlocked`"（半解锁），
     所以同一台设备在 1.0.80 及以前"指纹能进 app"，升到 1.0.81 变成"指纹没反应"
     （本机最新构建 `build\app\outputs\apk\release\app-release.apk` 时间戳 2026-10-13 18:48，
     晚于该提交的 18:02 ⇒ 症状与构建对得上）
  ③ KEK 只在 `_deriveAndStoreEncryptionKey()` 里持久化，而它只被
     `setupPattern` / `setupPin` / `unlockWithPattern` / `unlock(pin)` 调用
     ⇒ **一直只用指纹解锁的用户从未写过 KEK**（历史版本连 KEK 概念都没有）
  ④ `SecurityService.deriveEncryptionKey()` 与 `EncryptionKeyManager.retrievePersistedKek()` 均为 catch 后返回 null（静默）
- 证据:
  - `git show f812d9d`（唯一改动点，+10/-7）
  - `lib/application/lock/lock_controller.dart` → `unlockWithBiometric()` 的 null 分支原先只有一条 `AppLogger.e`
  - `lib/data/services/security_service.dart` → `deriveEncryptionKey()` catch 后 `return null`
  - `lib/data/services/encryption_key_manager.dart` → `retrievePersistedKek()` catch 后 `return null`
- 修法（本轮，应用层）:
  - `VaultLockErrorCode` 新增 `kekUnavailable`；`unlockWithBiometric()` 在 KEK 缺失时设该错误码（仍保持锁定）
  - `lock_screen._mapLockError` + l10n `biometricKekUnavailable`：锁屏直接告诉用户
    "指纹验证通过，但加密密钥尚未就绪 —— 请先用图案解锁一次，之后指纹即可正常使用"
  - `_deriveAndStoreEncryptionKey()`：`kek == null` 时补 `AppLogger.e`（此前派生失败完全静默）
  - `EncryptionKeyManager` 类注释订正：锁屏只清内存（`clearMemory()`），`clear()` 只用于凭据重置；
    后端选项**不要**改（理由见 `ADR-035`）
- 反例 / 易误判:
  - 怀疑"指纹硬件/驱动坏了、Activity 不是 FragmentActivity" —— **已排除**：
    `MainActivity` 继承 `FlutterFragmentActivity`，Manifest 里 `USE_BIOMETRIC`/`USE_FINGERPRINT` 齐全
  - 怀疑"是 `lock()` 又把持久化 KEK 删了"（`PIT-042` 的老症状）—— 现场 `lock()` 用的是 `clearMemory()`，**不是** `clear()`，
    该条已修复，别重复排查
  - 想到"清数据/重装 app 试试" —— 重装会清掉 `FlutterSecureStorage`，KEK 缺失只会**更确定**
- 下一步验证（坐实根因）:
  1. 复现一次后取当日 `密册_log_*.txt`，确认命中 `Biometric OK but no persisted KEK found`
  2. 同文件搜 `biometric status:` 与 `biometric authenticate result=`，排除"没弹窗 / 验证失败"两个分支
  3. 若确为 KEK 缺失：用图案解锁一次 → 立刻锁屏 → 再试指纹，应恢复正常（= 自愈验证）
  4. 若要"升级后直接可用指纹"（不要求先输一次图案）：需把 KEK 的持久化时机前移到
     `setBiometricEnabled(true)`（当前只做开关 + 一次身份确认，不碰 KEK）—— 属后续专项
- 相关文件: `lib/application/lock/lock_controller.dart`、`lib/presentation/lock/lock_screen.dart`、
  `lib/l10n/app_localizations.dart`、`lib/data/services/encryption_key_manager.dart`
- 相关条目: `ISSUE-027`①（`PIT-042` 老症状）、`PIT-045`、`PIT-046`、`PIT-049`、`ADR-035`
- 首次记录: 2026-10-13

## ISSUE-029 第十轮审计：图片/视频加解密 + "加密已有文件"链路的 7 个缺陷（4 个数据丢失级）
- 状态: 已修复（第二轮 R11 已将 5 项全部落地；仅剩 1 项技术债：`PlayerScreen` 与 `ViewerScreen`
  是两份等价解密实现，见「补修」①）
- 审计范围: `media_encryption_service.dart`、`native_crypto_service.dart`、`CryptoHandler.kt`、
  `encryption_key_manager.dart`、`settings_screen._batchEncrypt`、`import_service._encryptRecordedFiles`、
  `vault_reveal_runner._decryptIfNeeded`、`viewer_screen._resolveDisplayPath`、`import/thumbnail_generator.dart`、
  `vault_backup_*`、`maintenance_service.scanOrphanHiddenFiles`
- 已修复（本轮）:
  ① **`ftyp` 魔数判断写错 ⇒ MP4/MOV/HEIC 永远无法加密**（`media_encryption_service._looksLikePlainMedia`）：
     原代码 `_bytesMatch(bytes.sublist(4, 12), [00 00 00 20 66 74 79 70])` 把"4 字节 box size + `ftyp`"
     当成 offset 4 处的 8 字节签名 ⇒ **永不匹配** ⇒ `looksEncrypted()` 对每个 MP4 返回 true ⇒
     `encryptFileWithDek` 抛 `StateError` ⇒ 加密流水线永久跳过所有 MP4（`PIT-050`，与 `PIT-048` 同类）。
     修法：只匹配 offset 4 的 `ftyp` 4 字节标签；补 `GIF8`、`RIFF`+`AVI `、`RIFF`+`WEBP`（签名都 ≥4 字节，
     避免把随机密文误判成明文而二次加密）。
  ② **批量加密"先加密文件、后写 DEK"**（`settings_screen.dart` 原 569→573 行）：崩溃窗口 = 文件已密文、
     DEK 未落库 = 永久丢失（`PIT-051`）。修法：`generateDek → encryptDek → updateEncryptedDek → encryptFileWithDek`，
     与 `PIT-044` 的导入路径对齐。
  ③ **导入加密的 catch 无条件清空 DEK**（`import_service._encryptRecordedFiles`）：native 已换掉文件、只是结果回传
     失败（Activity 重建/通道异常）时清 DEK = 永久孤儿。修法：仅当 `!looksEncrypted(file)`（确实还是明文）才回滚。
  ④ **还原时 KEK/DEK 拿不到却静默放行**（`vault_reveal_runner._decryptIfNeeded` 的三处 `return`）⇒ 密文被当媒体
     移出保险库，随后 DB 行连同 DEK 一起被删 ⇒ 数据永久损坏（`PIT-052`）。修法：改抛 `StateError`；单项 `reveal()`
     返回 false；批量按 `blockedIds` 跳过并计失败。
  ⑤ **外部播放器被喂密文**（`media_grid_screen._openExternally`、`player_controller._onItemEntered`）：
     直接把 `item.privatePath` 交给其它 app。修法：加密项不再外放 —— 网格返回 false 后**已有**回退到内置查看器；
     播放列表留在内置播放器（但内置 `PlayerScreen` 仍不解密，见「未修复①」）。
  ⑥ **原生 AES-GCM 三处边界**（`CryptoHandler.kt`，`PIT-053`）：解密侧 `input.skip(12)` 不校验实际跳过字节数
     （`InputStream.skip` 允许少跳 ⇒ 认证失败）；`minLength = 12+16+1` 让 **0 字节明文的 28 字节密文解不开**；
     `finally { bakFile.delete() }` 在"恢复也失败"时会删掉唯一备份。已全部修正，并新增 **crash 自愈**：
     `encryptFile` 开头若主文件缺失而 `.enc_bak` 存在则回填，残留 `.enc_tmp` 直接清掉。
- 补修（同日第二轮，R11 —— 5 项全部落地）:
  ① **PlayerScreen 接上解密层**（原症状：加密图片 broken_image、加密视频黑屏）：
     `player_screen.dart` 新增 `_decryptedPaths` / `_decryptFutures` / `_decryptFailedIds` 与
     `_resolveMediaPath()` / `_decryptToTemp()` / `_ensureDecrypted()` / `_cleanupDecryptedPaths()`；
     `_loadVideoInner` 改用解析后的 `playbackPath`（解不开就明确报错，不再黑屏），
     `_buildImage` 读缓存路径、未就绪时转圈，`dispose()` 清理临时文件。
     **技术债**：与 `ViewerScreen._resolveDisplayPath` 是两份等价实现，第三个入口出现前应抽共享 mixin。
  ② **缩略图取帧前先解密**（原症状：加密媒体永远没缩略图 + 每次启动 8s 空转）：
     `ThumbnailGenerator` 注入 `MediaEncryptionService` / `EncryptionKeyManager`，新增 `_plaintextPathFor(job)`
     （重读该行取 `encryptedDek` → KEK → `decryptToTempFileWithDek`）；`makeThumbnail` 一律用明文路径取帧，
     `finally` 删临时文件；KEK 未加载时立刻返回 null（不再空转 8s）。
  ③ **备份带密钥材料**（原症状：换机/重装后加密文件永久不可读）：manifest 顶层新增 `encryptionSalt`、
     每个媒体条目新增 `encryptedDek`（都是**可选**字段，`manifestVersion` 仍为 5 ⇒ 旧备份照常解析、
     旧版本 app 也能读新备份）；`SecurityService` 新增 `readEncryptionSalt()` / `adoptEncryptionSaltIfAbsent()`；
     导出写入 salt，还原写回每行 `encrypted_dek`，且**仅当本机没有 salt 时**才采用备份的 salt
     （有则保留并 warn）⇒ 重装/换机后用同一图案解锁即可解密，同机合并式还原不会破坏本机密钥。
  ④ **导入未加密不再静默**：`_encryptRecordedFiles` 返回"未能加密"条数 →
     `ImportErrorCode.encryptionSkippedVaultLocked` → `import_result_message` → l10n
     （`app.dart` 与可见库两处入口在 `imported == 0` 时直接展示该 detail）。
  ⑤ **卸载全损警告**：`encryptConfirmationBody` 追加"加密密钥只保存在本机：卸载应用或清除应用数据后，
     已加密文件将无法解密，请先做好备份"。
- 补修后的验证: 20 个改动文件 `dart format` 无 parse 错误；`dart analyze` **0 error**
  （仅剩 2 条既有 warning：`lock_controller.dart` 的 2 个 unused import，HEAD 版本同样存在）
- 仍未做（明确记债，不是遗漏）:
  - PlayerScreen / ViewerScreen 解密逻辑抽共享 mixin（会动已验证的 viewer 路径，单独一轮做）
  - 备份"跨机恢复"保证的是"同一图案/PIN + 备份里的 salt"；若用户**已改过密码**再恢复，
    需先用导出时的密码解锁一次（或先还原 salt 再改密码）
  - BMP/TIFF 等未列入签名的格式仍会被判"已加密"从而跳过加密（安全方向：漏加密，不是损坏）
- 复发判据（各一条命令，5 秒定论）:
  - MP4 是否仍被判"已加密"：`git grep -n "sublist(4, 12)" -- lib/` 应无命中
  - 批量加密顺序：`git grep -n "updateEncryptedDek" -B 8 -- lib/presentation/settings/settings_screen.dart` ⇒ DEK 必须先于 `encryptFileWithDek`
  - 还原 fail-open：`git grep -n "if (kek == null) return" -- lib/data/services/import/vault_reveal_runner.dart` 应无命中
  - 原生边界：`git grep -n "GCM_TAG_LENGTH / 8 + 1L" -- android/` 应无命中
- 证据: 上文逐条的 `文件:行`；本轮 6 个 Dart 改动文件 `dart analyze` = **No issues found**（`ANALYZE_RC=0`）
- 相关文件: `lib/data/services/media_encryption_service.dart`、`lib/data/services/import_service.dart`、
  `lib/data/services/import/vault_reveal_runner.dart`、`lib/presentation/settings/settings_screen.dart`、
  `lib/presentation/grid/media_grid_screen.dart`、`lib/application/player/player_controller.dart`、
  `android/app/src/main/kotlin/com/privi/app/CryptoHandler.kt`
- 相关条目: `PIT-034`（原子替换）、`PIT-044`（DEK crash 窗口）、`PIT-048`（魔数误判）、
  `ISSUE-024`（解密链路）、`ADR-033`、`ADR-036`
- 首次记录: 2026-10-13（第十轮审计）

## ISSUE-030 批量加密并发重入 → 同一文件被并发加密 ⇒ 0 字节 / 文件消失（**已造成数据损坏**）
- 状态: 已修复（应用层 + native 双侧加固 + 启动自愈救援）
- 症状 / 现场: 用户点「设置 → 加密已有文件」后：
  - 同一文件在几十毫秒内被**重复处理几十次**（日志里同一 id 连续 `Bad state: File already appears encrypted`）
  - 部分文件被"加密"成 **0 字节**：`MediaEncryptionService Encrypted with pre-saved DEK: …(472687 → 0 bytes)`
  - 紧接着同一文件报 `Native encryption failed: File not found: …`
  - 界面侧：`UncaughtError ... Bad state: No element`（`Navigator.pop`）+ `Null check operator used on a null
    value`（对已 dispose 的 `StatefulBuilder` 调 `setState`）各上百次
  - 观感：加密"大量失败"，且这些媒体在网格/查看器里**打不开（一片黑）**
- 复发判据（读设备日志，5 秒定论）:
  1) `Select-String 'Encrypted with pre-saved DEK'` 出现 `→ 0 bytes` ⇒ 命中
  2) 同一 `batch encrypt <uuid>` 在 1 秒内出现 ≥3 次 ⇒ 命中（正常只应 1 次）
  3) `Bad state: No element` / `Null check operator` 伴随 `SettingsScreen._showEncryptProgress` 堆栈 ⇒ 命中
- 根因（三个叠加）:
  ① **`_showEncryptProgress` 的 `run()` 被并发重入**：`builder` 里
     `WidgetsBinding.instance.addPostFrameCallback((_) => run());` 没有守卫，而 `run()` 每处理完一项就
     `setDialogState(() {})` → 触发 rebuild → builder 再注册一个 **新的 run()** ⇒ 并发 run() 数量逐项增长，
     每个 run() 都从 `items[0]` 开始 ⇒ 同一文件被多个循环同时加密。
  ② **native `encryptFile` 的临时文件名是固定的** `"$filePath.enc_tmp"`，且入口先
     `if (tmpFile.exists()) tmpFile.delete()` ⇒ 并发循环互相**删掉对方正在写的临时文件**，最后 rename 出一个
     0 字节文件（或直接把原文件搞没）。
  ③ 一次加密"成功"后（`472687 → 472715`），3ms 后另一个 run() 又把**密文**再加密一遍（`799115 → 0 bytes`）。
- 证据: `密册_log_2026-10-13.txt`（1.0.82，19:54:48–19:56:37）
  - `19:54:48.556 … (43132 → 43160 bytes)` → `19:54:48.592/.614/.629/.649/.663/.678/.691/.711/.727/.746/.758/.776/.794`
    同一 id 连续 `File already appears encrypted`
  - `19:54:48.963 … 4adc3c8d….jpg (472687 → 0 bytes)`；`19:54:49.030/.031 File not found: 4adc3c8d….jpg`
  - `19:54:48.930 batch encrypt 4adc3c8d…: Failed to back up original file`
  - `19:54:49.159 batch encrypt 4adc3c8d…: Failed to replace original file; it was preserved as 4adc3c8d_….jpg.enc_bak`
  - `19:54:55.549 (799087 → 799115 bytes)` → `19:54:55.578 (799115 → 0 bytes)`（同一文件，相隔 29ms）
  - 统计：`0 bytes` 15 次、`File not found` 535 次、`already appears encrypted` 199 次、`UncaughtError` 182 次
- 修法（本轮）:
  1. `settings_screen.dart`：模块级 `_batchEncryptInFlight` 守卫 + `_batchEncrypt` 用 `try/finally` 复位；
     `_showEncryptProgress` 里加 `started` 守卫（`run()` 只启动一次）、`if (ctx.mounted) setDialogState(() {})`、
     并把"文件不存在 / 已是密文无 DEK / 真正失败"分成 `missing / undecryptable / failed` 三类计数与文案
  2. `CryptoHandler.kt`：`encryptFile` 用 `synchronized(lockFor(filePath))` **按路径串行**；
     临时文件改为唯一名 `"$filePath.enc_tmp-${UUID.randomUUID()}"`；残留 `.enc_tmp*` 统一清理；
     **结果长度校验**：`encryptedLength < originalLength + 12 + 16` ⇒ 视为失败，删掉坏文件并**从 `.enc_bak` 恢复原文**
  3. `maintenance_service.dart`：启动自愈 `_repairEncryptionArtifacts()` —— 删除残留 `.enc_tmp*`；
     `.enc_bak` 在主文件缺失或为 0 字节时**恢复为主文件**（救回原始媒体），主文件正常时删除多余备份
- 反例 / 易误判:
  - 以为"批量加密失败是因为文件损坏/权限" —— 其实是**同一个文件被并发加密**（看时间戳密度即可分辨）
  - 以为"`File not found` 是文件真被删了" —— 多数是并发 swap 造成的中间态（`.enc_bak` 里可能还有原件）
  - **在修复前切勿再点「加密已有文件」**，每点一次都会再损坏一批文件
- 残留影响（需用户处理）: 已经变成 0 字节、且**没有 `.enc_bak` 残留**的文件，明文已不可恢复（只能从相册原件/备份找回）；
  "已是密文但 DB 无 DEK"的文件无法解密也无法再加密，新 UI 会明确告知
- 相关文件: `lib/presentation/settings/settings_screen.dart`、`android/app/src/main/kotlin/com/privi/app/CryptoHandler.kt`、
  `lib/data/services/maintenance_service.dart`、`lib/l10n/app_localizations.dart`
- 相关条目: `PIT-034`（原子替换）、`PIT-044`（DEK 顺序）、`PIT-055`、`PIT-056`、`ISSUE-029`
- 首次记录: 2026-10-13（用户真机日志定位）

## ISSUE-031 指纹解锁一直无效：图案解锁后 KEK 仍"不存在"（两个 secure storage 后端不一致）
- 状态: 已修复（待真机复核）
- 症状 / 现场: 锁屏指纹弹窗验证通过，但**不解锁**；日志每次都是
  `ERROR [LockController] Biometric OK but no persisted KEK found`。
  用户改用图案解锁后**再次**指纹解锁仍然同样报错（19:54:06 / 19:56:38 / 19:57:09 三次）
- 复发判据（读设备日志）: 搜 `Biometric OK but no persisted KEK`；
  同时**不应**出现 `Failed to persist KEK` —— 若两者都出现，说明写入抛异常（另一条分支）
- 根因: `EncryptionKeyManager` 用的是 `const FlutterSecureStorage()`（**默认后端**），而 `SecurityService`
  用 `AndroidOptions(encryptedSharedPreferences: true)`（**EncryptedSharedPreferences 后端**）。
  两个后端在该设备上**一个写不进/读不出**：`setKey` 不抛异常（所以没有 `Failed to persist KEK`），
  但 `retrievePersistedKek()` 读回来是空 ⇒ 指纹解锁永远拿不到 KEK。
  内存 KEK 正常（所以图案解锁后能进 app、批量加密也能跑），只有"持久化 → 读回"这一环断了
- 证据: 日志 15/20/25/30/37/52/57/68/83/5556/5567 行全部为同一条错误；`Failed to persist KEK` = 0 次；
  同一会话内 19:54 之后用户已解锁成功（有批量加密动作）却仍然读不到持久化 KEK
- 修法: `EncryptionKeyManager` 改为**双后端成对读写**：
  - `setKey` 写入**两个**后端（默认 + `encryptedSharedPreferences: true`），任一成功即可，全部失败打 error
  - `retrievePersistedKek` 依次尝试两个后端，取第一个非空值；都为空时打 warn（含尝试个数）
  - `clear` 两个后端都删；构造仍支持注入单实例（测试用）
- 反例 / 易误判:
  - 以为"是 `lock()` 又把 KEK 删了"（`PIT-042`）—— 现场 `lock()` 用的是 `clearMemory()` ✔ 已排除
  - 以为"用户没解锁过"—— 内存 KEK 存在（批量加密能跑）说明解锁过，问题在持久化
  - 不要"简化"回单后端（`PIT-057`）
- 验证要点（真机）: 图案解锁一次 → 锁屏 → 指纹解锁应直接进入；日志不再出现
  `Biometric OK but no persisted KEK`
- 相关文件: `lib/data/services/encryption_key_manager.dart`、`lib/application/lock/lock_controller.dart`
- 相关条目: `ISSUE-028`（同一现象的上一轮修复：只补了"可见提示"）、`PIT-042`、`PIT-057`、`ADR-035`
- 首次记录: 2026-10-13（真机日志定位）

## ISSUE-032 批量加密大视频时进程崩溃：单流 AES-GCM 在 Conscrypt 上一次申请 ≈2× 文件大小 ⇒ OutOfMemoryError
- 状态: 已修复（改用分块 GCM v2 容器；v1 只读兼容；OOM 不再杀进程）
- 症状 / 现场: 批量加密跑到大文件时 app **直接崩溃**（Flutter 侧无异常，日志停在加密中途）。
  `密册_crash_2026-10-13.txt`：
  ```
  java.lang.OutOfMemoryError: Failed to allocate a 140444664 byte allocation with 25165824 free bytes
      and 109MB until OOM, target footprint 313194672, growth limit 402653184
    at com.android.org.conscrypt.OpenSSLAeadCipher.reset(OpenSSLAeadCipher.java:140)
    at com.android.org.conscrypt.OpenSSLAeadCipher.doFinalInternal(OpenSSLAeadCipher.java:377)
    at javax.crypto.Cipher.doFinal(Cipher.java:1938)
    at ii0.c(r8-map-id-…)     ← R8 混淆后的 CryptoHandler
    at db.run(…)              ← MainActivity 的 ioExecutor 线程池
  ```
  应用日志最后一条正是 `Encrypted with pre-saved DEK: …e191852e_5月6日.mp4 (7041101 → 7041129)`、
  `…26902194_5月12日.mp4 (43449841 → 43449869)`、`…657bfd9d_…mp4 (71810706 → 71810734)`（71.8MB），
  0.5 秒后崩溃 ⇒ **下一个大文件在 `doFinal` 申请 134MB 失败**
- 复发判据（5 秒定论）:
  1) `密册_crash_*.txt` 出现 `java.lang.OutOfMemoryError` + `OpenSSLAeadCipher` ⇒ 命中本条
  2) 应用日志搜 `Encrypted(v2)`：**修复后**必须出现该字样；若仍是 `Encrypted:`（无 v2）说明还在跑旧容器
- 根因: 容器 v1 是**单个 GCM 流** `[nonce12][ciphertext][tag16]`。Conscrypt 的 AEAD 实现要在
  `Cipher.doFinal` 里同时持有明文与输出（tag 校验通过前不能交付明文），因此对 N 字节文件一次性申请
  **≈2N** 字节：71.8MB → ~140MB；而该次运行堆上限 384MB、基线已占 313MB ⇒ 必然 OOM。
  另外 `catch (e: Exception)` **抓不到** `OutOfMemoryError`（Error 不是 Exception）⇒ 进程直接死。
- 修法（`CryptoHandler.kt`）:
  ① 新增**分块 GCM 容器 v2**：`[magic 'PRV2'][baseNonce 8][plaintextSize 8][chunkSize 4]` + 每块
     `ciphertext(≤1MiB) + tag16`，块 nonce = `baseNonce || int32be(index)`；加解密都按块 `doFinal`
     ⇒ 峰值内存恒定 ~2MiB，**与文件大小无关**
  ② 解密按 magic 自动分流 v2 / v1（v1 老文件仍然能解）
  ③ 三处 native 入口（encrypt / decryptFile / decryptFileToBytes）全部新增 `catch (e: OutOfMemoryError)`
     ⇒ 返回错误而不是崩溃进程；加密失败时从 `.enc_bak` 恢复原文
  ④ `decryptFileToBytes` 同样支持 v2（分块 + `ByteArrayOutputStream`）
- 反例 / 易误判:
  - 以为"是磁盘满/权限/并发" —— 崩溃日志里的 `OpenSSLAeadCipher` 才是判据（与 `ISSUE-030` 的并发损坏不同类）
  - 以为 `update()` 循环 + 末尾一次 `doFinal()` 就是"流式、不会爆内存" —— **对 AEAD 不成立**
  - 以为 `catch (e: Exception)` 能兜住 —— 必须**单独** catch `OutOfMemoryError`
  - 把"512MiB 上限校验"当内存保护 —— 它只是拒绝更大的文件，不解决 2N 分配
- 遗留（需用户操作）: 已存在的 **v1 大文件**（约 >100MB）解密仍可能 OOM（格式决定，应用层无法消除）；
  现在会明确报错而不是崩溃。建议：**重启 app 后立刻**（堆最干净时）把这些文件解密回相册，再重新加密（自动用 v2）
- 相关文件: `android/app/src/main/kotlin/com/privi/app/CryptoHandler.kt`（Dart 侧接口未变，无需改动）
- 编译复核 2026-10-13: 首次构建报 `CryptoHandler.kt:480 Unresolved reference 'filePath'` —— v2 解密完成后的
  日志行误用了 `$filePath`，而 `decryptV2File` 的形参是 `inputFile`（`filePath` 只存在于 `encryptFile` /
  `decryptFile` / `decryptFileToBytes`）⇒ 已改为 `${inputFile.path}`；随后把全文件 24 处 `filePath` 引用
  逐一核对，确认都落在对应函数作用域内（"改完必须回读"的又一次实践，见 `PIT-028`）
- 相关条目: `ISSUE-030`（并发损坏，另一类）、`PIT-044`、`PIT-058`、`ADR-038`、`ADR-033`
- 首次记录: 2026-10-13（真机 crash 日志定位）