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

## ISSUE-033 「加密已有文件」几千个文件太慢：单文件串行 + 原生 crypto 只能 3 线程并发
- 状态: 已修复（Dart 侧拆成 N 条队列 + 原生专用 crypto 线程池；吞吐待真机复核）
- 症状 / 现场: 保险库里有 6 000+ 个明文文件时，点「设置 → 加密已有文件」，进度条一格一格走，
  整个流程要几十分钟量级；日志里只有逐项的 `Encrypted with pre-saved DEK: …`，没有任何汇总行。
- 复发判据（5 秒定论）: 设备日志搜 `BatchEncryptionService` —— 修复后一定有
  `batch encrypt pass done: … queues=<N>`（N ≥ 6）。若只看到逐项 `Encrypted with pre-saved DEK:`
  而没有 `pass done`（旧版逐项日志的 logger 是 `SettingsScreen`）⇒ 又跑回串行了。
  静态等价判据: `git grep -n "BatchEncryptionService" -- lib/presentation/settings/settings_screen.dart` 必须有命中。
- 根因（两条叠加，缺一条都慢）:
  ① **Dart 层完全串行**：`SettingsScreen._showEncryptProgress` 的 `run()` 里
     `for (final item in items)` 逐个 await —— 每项 = 读 32 字节文件头 + 纯 Dart 包 DEK +
     一次 sqflite 写 + 一次 MethodChannel 原生加密；6 000 项 × 每项几十毫秒 = 分钟级。
  ② **原生侧天花板只有 3 线程**：`MainActivity.runIo()` 把 crypto 调用丢到
     `ioExecutor = Executors.newFixedThreadPool(3)`（原本是给 metadata / libVLC parse 用的），
     所以 Dart 侧就算开 24 条队列，真正同时加密的文件也永远 ≤ 3。
- 证据（改前）: `lib/presentation/settings/settings_screen.dart:597-656`（`for (final item in items)` 逐个 await）；
  `android/app/src/main/kotlin/com/privi/app/MainActivity.kt:31`（`newFixedThreadPool(3)`），
  以及三处 crypto 调用全部走 `runIo`（`MainActivity.kt:522 / 532 / 541`）。
- 修法:
  1. 新增 `lib/data/services/batch_encryption_service.dart`：N 条队列（默认 `2 × 核数`，clamp 到 `6…24`，
     且不超过待处理项数）**共用一个游标**领任务；单项逻辑 `encryptOne()` 保持 `PIT-051` 的顺序
     （包 DEK → 落库 → 加密文件；失败时仅当"确认仍是明文"才回滚 DEK）。
  2. `settings_screen.dart` 的 `_showEncryptProgress` 改为调用该服务；进度回调**节流 100 ms** 才
     `setDialogState`；`_batchEncryptInFlight` 与 `started` 两道重入守卫原样保留（ISSUE-030）。
  3. `MainActivity.kt` 新增专用 `cryptoExecutor`（`availableProcessors().coerceIn(4, 8)`）+ `runCrypto()`
     （catch `Throwable`，避免最坏情况下 Dart future 永久 pending），三个 crypto 方法改走它；
     `onDestroy` 里按 `ioExecutor` 的方式 `shutdown()` + 1s `awaitTermination`。
- 反例 / 易误判:
  - 只加 Dart 并发、不动原生线程池 ⇒ 速度几乎不变（并发被 `ioExecutor(3)` 吃掉），见 `PIT-060`
  - 以为"慢"是加密算法慢 —— 单块 1 MiB 的 GCM 是硬件加速的；瓶颈是**每项一次的 DB 写 +
    跨平台往返**以及这些等待全被串起来
  - 把队列数开到几十却不限原生池 ⇒ 只是把文件排进 3 线程队列，还多占内存（每项并发 ~2 MiB，`ISSUE-032`）
- 相关文件: `lib/data/services/batch_encryption_service.dart`（新增）、`lib/application/providers.dart`、
  `lib/presentation/settings/settings_screen.dart`、`android/app/src/main/kotlin/com/privi/app/MainActivity.kt`
- 真机实测基线（2026-10-13 用户日志 `密册_log_2026-10-13.txt`，**修复前的串行版**）:
  `21:04:00.958` → `21:05:14.494` 共 **73.5 秒**处理 **179 项**（178 成功 + 1 失败）
  = **≈0.41 s/项** ⇒ 6 000 项约 **41 分钟**，"有点慢"的体感由此而来。
  该日志里**没有** `BatchEncryptionService` / `pass done` 行、逐项 logger 是 `SettingsScreen`，
  即这仍是串行版；并行版上线后应改为看 `pass done … queues=<N>` 并对比同一批文件的耗时。
  同一条日志还暴露了**另一个独立缺陷**（长文件名 `ENAMETOOLONG`）→ 见 `ISSUE-034`
- 相关条目: `ISSUE-030`（重入守卫）、`PIT-051` / `PIT-044`（DEK 顺序）、
  `ISSUE-032` / `PIT-058` / `ADR-038`（内存上限）、`PIT-060`、`ADR-039`（为什么是 N 队列 + 原生池 4~8）、
  `ISSUE-034`（另一个"只剩 1 个失败"的原因，与并发无关）
- 首次记录: 2026-10-13

## ISSUE-034 批量加密永远剩一个失败项：临时文件名拼在媒体名之后 ⇒ `ENAMETOOLONG`
- 状态: 已修复（临时短名 + 超长名走"无备份槽原子覆盖"；待真机复核）
- 症状 / 现场: 「加密已有文件」跑完后只有 **1 项失败**（178 成功 / 1 失败），每次重跑都还是它。
  应用日志（旧串行版）:
  ```
  ERROR [SettingsScreen] batch encrypt 1e795213-…: Exception: Native encryption failed:
  /storage/emulated/0/.privateheart_vault/图片/1e795213_[到圆形〇线的主要街道！ !! ] Paipan无毛，…第3部分.mp4_20231114_205900169.jpg.enc_tmp-6405650a-1c48-4ca3-ae13-b7e377518ee8:
  open failed: ENAMETOOLONG (File name too long)
  #0 MediaEncryptionService.encryptFileWithDek (media_encryption_service.dart:186)
  #1 SettingsScreen._showEncryptProgress.…run (settings_screen.dart:636)
  ```
- 复发判据（5 秒定论）: 应用日志搜 `ENAMETOOLONG`（或 `File name too long`）；命中即本条。
  等价静态判据: `git grep -n '"$filePath.enc_tmp' -- android/` 必须**无命中**；
  `git grep -n "tempFileFor" -- android/` 应有命中（CryptoHandler）。
- 根因: `CryptoHandler.encryptFile` 的临时文件写成 `File("$filePath.enc_tmp-${UUID.randomUUID()}")`
  ⇒ 名字 = 媒体名 + 45 字节（`.enc_tmp-` 9 + UUID 36）。Linux（ext4/f2fs）单文件名上限 **255 字节**
  （按 UTF-8 字节算，中文/日文每字 3 字节），媒体名一长就撞上上限 ⇒ `FileOutputStream` 打不开临时文件。
- 证据（本机从日志原文实测）: 该媒体名 **227 字节**（109 个字符），加后缀后 **272 字节**；
  `delta=45 bytes`、`255 < 272` ⇒ 必然 `ENAMETOOLONG`。同一目录其它名字短的媒体都成功。
- 修法（`CryptoHandler.kt`）:
  1. 新增 `TEMP_PREFIX = ".enc_tmp-"` 与 `tempFileFor(inputFile)`：临时文件放在**媒体所在目录**
     （同文件系统 ⇒ 最终 `renameTo` 仍原子，`PIT-034`），名字固定为 `.enc_tmp-<uuid>`（45 字节，与媒体名无关）。
  2. `deleteStaleTemps(inputFile)` 由"按 `媒体名 + .enc_tmp` 前缀匹配"改为
     "**同目录 + `TEMP_PREFIX` + mtime 早于 1 小时**"：新命名匹配不到旧前缀，而**绝不能**删掉并发在写的临时文件
     （那正是 `ISSUE-030` 的 0 字节事故）。旧命名残留交给启动自愈（`maintenance_service` 用
     `name.contains('.enc_tmp')`，两种命名都能清）。
  3. `.enc_bak` **保持**"媒体名 + `.enc_bak`"（启动自愈靠 `<name>.enc_bak` → `<name>` 反推，不能改名）——
     副作用已写进 KDoc：媒体名 ≥ 248 字节时这一步会失败，但属**安全失败**（主文件未动，
     返回 `Failed to back up original file`）。
  4. **复发 2026-10-13（第二次真机日志 `密册_log_2026-10-13.txt`）**: 临时名修好后，同一根因的另一半暴露 ——
     `<name>.enc_bak`（媒体名 + 8 字节）同样会超 255：日志里
     `ERROR [BatchEncryptionService] batch encrypt acc1b3a3-… / a31b0a87-…: Exception: Native encryption failed:
     Failed to back up original file` 共 **6 次**（同 2 个 id 各 3 次 ⇒ 每次重跑都失败，用户看到的"还是有失败项"）。
     这两项**明文安全**（rename 失败发生在改名之前，主文件没被动过）。修法：`encryptFile` 增加
     `useBackupSlot`（`bakFile.name` 的 UTF-8 字节数 ≤ `MAX_FILE_NAME_BYTES`=255）—— 超长时**不建备份槽**，
     直接 `tmp.renameTo(原文件)` 原子覆盖（DEK 已由 Dart 侧先落库 ⇒ 崩溃后要么明文原件、要么完整密文）；
     该路径下"长度校验失败"分支**绝不删主文件**（没有备份可恢复），改为报错并保留。
     **反例**：把 `.enc_bak` 也改成短名 ⇒ 启动自愈无法把备份映射回原文件（救援能力丢失）；
     正确做法是"只在超长名时退化成无备份槽"，而不是换命名规则。
- 反例 / 易误判:
  - 以为"1 个失败"是并发/权限/存储问题 —— 报错原文 `ENAMETOOLONG` 才是判据（与并发、磁盘、DEK 全无关）
  - 以为把临时文件挪到 `cacheDir` 就行 —— 跨文件系统 `rename` 不再是原子替换，`PIT-034` 的保障会丢
  - 顺手把"同目录所有 `.enc_tmp*`"都删掉当清理 —— 会删掉并发加密正在写的临时文件（`ISSUE-030` 复发）
  - 顺手把 `.enc_bak` 也改成短名 —— 启动自愈将无法把备份映射回原文件（救援能力丢失）
- 该文件的当前状态: 仍是**明文**、DEK 已被回滚（native 失败时主文件未被改动，Dart catch 里
  `looksEncrypted == false` ⇒ `updateEncryptedDek(id, null)`）⇒ 修复后重跑一次「加密已有文件」即可成功加密它
- 相关文件: `android/app/src/main/kotlin/com/privi/app/CryptoHandler.kt`、
  `lib/data/services/maintenance_service.dart`（启动自愈，命名兼容性）
- 相关条目: `PIT-056`（临时名唯一性，本条是它的"长度"补充）、`PIT-034`（原子替换）、`PIT-061`、
  `ISSUE-030`（并发误删临时文件）、`ISSUE-033`（同一条日志，另一类问题：慢）
- 首次记录: 2026-10-13（用户真机日志 `密册_log_2026-10-13.txt`）


## ISSUE-035 幻灯片（播放列表页）里的加密图片**一片黑**：`_buildImage` 回退到密文路径
- 状态: 已修复（待真机复核）
- 症状 / 现场: 「播放」入口的幻灯片（`slideshowSeconds` 自动切图）中，加密图片**全黑**，
  每张都黑、连续黑；日志里每切一张就有一条 `ERROR [FlutterError] image resource service: Exception: Invalid image data`，
  堆栈 `ImageDescriptor.encoded → instantiateImageCodecWithSize → FileImage._loadAsync`
  （即 Flutter 真的去解码了那个文件）；`PlayerScreen` 日志显示 `Showing <id> (image)` 之后 **14ms** 就报错，
  快到来不及解密（native 解密一张图要几十 ms）。
- 复发判据（5 秒定论）: app 日志搜 `Invalid image data`，且伴随 `PlayerScreen … Showing <id> (image)`；
  对照 `git grep -n "cachedPath ?? item.privatePath" -- lib/` 若**有命中**即命中本条
  （修复后该表达式必须不存在）。
- 根因: `player_screen.dart._buildImage()` 写的是
  ```dart
  final file = File(cachedPath ?? item.privatePath);   // ← 加密项没有缓存时回退到密文
  if (!file.existsSync()) { ...转圈/裂图... }
  return ... Image.file(file ...);
  ```
  加密项的 `privatePath` **存在**（就是密文文件），所以 `existsSync()` 恒为 true ⇒ 跳过"还没解密→转圈"分支
  ⇒ 直接把密文喂给 `Image.file` ⇒ 解码失败 ⇒ 黑帧。而"启动解密"的 `_ensureDecrypted(item)` 恰恰**只在**
  那个 `!existsSync()` 分支里调用 ⇒ 幻灯片里的加密图片**永远不会被解密**（视频路径用的是 `_resolveMediaPath()`，是对的）。
- 证据: 用户真机日志 `密册_log_2026-10-13.txt`（22:26:16 / 22:26:55 / 22:27:05 三次切图，各一条
  `Invalid image data`，均紧跟 `Showing <id> (image) (N/5440), playing=true`）。
- 修法（`lib/presentation/player/player_screen.dart`）: 拆分两条路径 ——
  加密项**只看解密缓存**，没缓存就 `_ensureDecrypted()` + 转圈（`_decryptFailedIds` 才显示裂图），
  **绝不回退到 `privatePath`**；未加密项才用 `privatePath`（不存在 → 裂图）。两处共用一个新的
  `_imageView(File)`（`GestureDetector` + `InteractiveViewer` + `Image.file`）。
- 反例 / 易误判:
  - 以为"是图片损坏 / 缩略图没生成 / 解码器不支持" —— `Invalid image data` + **秒级延迟**才是判据（解密都还没跑）
  - 以为"`_buildImage` 已经有解密兜底" —— 兜底写在"文件不存在"分支里，对密文文件**永远不会执行**
  - 只给 `Image.file` 加 `errorBuilder` 掩盖黑屏 —— 掩盖后用户看到的是裂图，图片依然打不开
- 相关文件: `lib/presentation/player/player_screen.dart`（`_buildImage` / `_imageView`）
- 相关条目: `ISSUE-029`①（PlayerScreen 接解密层，同一文件）、`ISSUE-024`⑥（ViewerScreen 的密文竞争）、
  `PIT-037`（解密失败仍转圈）、`ADR-036`（每个展示入口都要有解密层）
- 首次记录: 2026-10-13（用户真机日志）

## ISSUE-036 重装后导入密钥无效：KEK 是"密码+本机 salt"派生的，解锁会把它覆盖掉
- 状态: 已修复（新增「导出/导入加密密钥」+ 解锁路径支持"导入 KEK 优先"；待真机复核）
- 症状 / 现场（用户需求）: 卸载重装后，即便拿回旧密钥文件，"基于导入的密钥加解密"也不成立 ——
  本机 `encryption_salt` 已随卸载消失，`deriveEncryptionKey()` 会**新建随机 salt**，
  于是解锁时派生出的是**另一个 KEK**；此时：
  - 旧文件（DEK 用旧 KEK 包裹）解密必定失败（表现为打不开/黑屏/`Decryption failed`）；
  - 新加密的文件用的是新 KEK，与旧文件**不通用**。
- 复发判据（5 秒定论）: 日志搜 `LockController` 的
  `unlock: using the imported vault key (key package)` —— 导入后解锁**必须**出现该行；
  若看到 `KEK derivation` 覆盖了导入（无该行），或 `KeyBackupService` 的
  `import refused: …` 出现，即为本条现场。
  静态判据: `git grep -n "isImportedKey" -- lib/application/lock/lock_controller.dart` 必须有命中。
- 根因（架构层面）: 本仓库 KEK **不是**随机生成后包裹存储，而是 `PBKDF2(密码|图案, encryption_salt)`
  的确定性派生（`ADR-033` ①）。派生型密钥在"同一 salt + 同一密码"下可重现，但换了安装/生成新 salt 就失配。
- 修法:
  1. 新增 `lib/data/services/key_backup_service.dart`：密钥包 JSON
     `{format:'privi-key-backup', version:1, createdAt, encryptionSalt, kek(b64)}`；
     `buildPackage()`（要求已解锁）、`validatePackage()`（**只校验不写入**）、
     `importPackage()`（写入 salt + KEK）、`matchesVault(kek)`（用库里的 `encryptedDek` 实测能否解出 DEK）。
  2. `EncryptionKeyManager`：新增 `privi_kek_source_v1` 标志（`derived` / `imported`）+
     `setImportedKey` / `markDerivedKey` / `isImportedKey` / `loadPersistedKey`；`clear()` 一并删标志。
  3. `LockController._deriveAndStoreEncryptionKey()`：**导入标志为真时优先加载持久化 KEK，不再派生**
     （否则解锁就把导入的 KEK 覆盖掉）；`changePattern` / `changePin` / `migratePinToPattern`
     在"派生新 KEK + 旋转全部 DEK"成功后调 `markDerivedKey()` 结束导入态
     （这两条路径自洽：KEK 变了，但 DEK 也全部重新包裹了）。
  4. 设置 → 安全：新增「导出加密密钥」「导入加密密钥」，导出前/导入前各有明确警告；
     导入**先校验再确认**，被拒绝的包不会留下任何半成品状态。
- 安全约束（务必保留）:
  - 密钥包是**明文 KEK**（等同全部文件的钥匙）⇒ UI 必须警告"离线/加密网盘保存"，不得分享；
  - **本机已有不同 salt 时拒绝导入**（`saltConflict`），否则本机已加密文件会全部失效
    （沿用 `SecurityService.adoptEncryptionSaltIfAbsent` 的规则，见 `ISSUE-029`③）；
  - 导入前用 `matchesVault()` 实测（最多 8 条 `encryptedDek`），不匹配就拒绝
    （避免"导入成功但全部打不开"）。
  - **密钥包会随"改密码"过期**：`changePattern` / `changePin` / `migratePinToPattern` 会派生新 KEK
    并把**所有 DEK 旋转**到新 KEK（`ADR-034`）⇒ 旧密钥包里的 KEK 再也解不开库里的 `encrypted_dek`；
    导入旧包会被 `matchesVault()` 拒绝（保护生效），但那意味着"这份备份已过期"——
    **改完图案/密码请重新导出一次**（导出警告文案里已写明）。
- 反例 / 易误判:
  - 以为"导出密钥 = 导出密码/图案" —— 密钥包里没有密码，导入后**可用任意新图案解锁**（这是它的价值）
  - 以为"导入后要重设成原密码才能解密" —— 不需要；但也意味着**密钥文件泄露 = 保险库全开**
  - 直接覆盖 salt 图省事 ⇒ 本机原有加密文件全部变孤儿
- 相关文件: `lib/data/services/key_backup_service.dart`（新增）、`lib/data/services/encryption_key_manager.dart`、
  `lib/application/lock/lock_controller.dart`、`lib/presentation/settings/settings_screen.dart`、
  `lib/l10n/app_localizations.dart`
- 相关条目: `ADR-033`（KEK/DEK 双层架构）、`ADR-041`（密钥包格式与"导入优先"的取舍）、
  `ISSUE-029`③（备份里的 `encryptionSalt`）、`PIT-057` / `ADR-035`（安全存储后端策略）、
  `PIT-036` / `ISSUE-025`（DEK 旋转）
- 首次记录: 2026-10-13（用户需求 + 代码排查）

## ISSUE-037 导出备份时日志报 `Bad state: Vault backup dialog requires an operation state.`
- 状态: 未修复（待决；已定位到断言位置，未改行为）
- 症状 / 现场: 备份导出/恢复过程中日志出现
  ```
  ERROR [FlutterError] widgets library: Bad state: Vault backup dialog requires an operation state.
  #0  VaultBackupProgressDialog.build (vault_backup_progress_dialog.dart:65)
  ```
  用户界面未见异常（对话框本身没崩），只是日志被污染（`密册_log_2026-10-13.txt:6005`，22:15:56，
  紧跟在指纹解锁 + 一次备份操作之后）。
- 复发判据（5 秒定论）: 日志搜 `Vault backup dialog requires an operation state`；命中即本条。
- 根因: `VaultBackupProgressDialog.build()` 第 63-66 行是**主动断言**：
  ```dart
  if (!state.dialogVisible) {
    throw StateError('Vault backup dialog requires an operation state.');
  }
  ```
  操作结束（`dialogVisible=false`）与对话框路由出栈之间有一帧窗口，此时路由仍会 rebuild ⇒ 命中断言。
  属"调用点没有按 visible 控制是否 push/保留对话框"的生命周期问题，不是数据/加密问题。
- 证据: `lib/presentation/settings/vault_backup_progress_dialog.dart:63-66`；
  调用点见 `lib/presentation/settings/settings_screen.dart` 的备份入口（`vaultBackupControllerProvider`）。
- 修法（**尚未实施**，实施时二选一，并真机复核）:
  ① 调用点改为按 `dialogVisible` 决定是否展示（`if (!visible) return const SizedBox.shrink();`
     或先 pop 再清状态），把"可见性"收在一个地方；
  ② 或让对话框在不可见时返回空 widget **并同时**由 controller 触发 pop（避免留下空白对话框）。
  不要只是把 `throw` 删掉 —— 会留下一个空白对话框。
- 反例 / 易误判: 以为"备份失败/数据损坏" —— 该断言不影响备份结果；也**不要**当成加密链路问题排查。
- 相关文件: `lib/presentation/settings/vault_backup_progress_dialog.dart`、
  `lib/application/backup/vault_backup_controller.dart`、`lib/presentation/settings/settings_screen.dart`
- 相关条目: `ISSUE-029`③（备份 manifest 带密钥材料）、`PIT-055`（一次性任务守卫）
- 首次记录: 2026-10-13（用户真机日志，报告时未处理）

## ISSUE-038 「加密已有文件」支持"只加密文件名"：弹框双选项 + 改名迁移（ADR-042 阶段 1 落地）
- 状态: 已实现（待真机复核）
- 需求 / 现场: 库里 5 400+ 个文件**内容已经加密**，只想补做"加密文件名"（避免被按扩展名扫描的程序认出）。
  原实现只有内容加密一条路径，且 `unencrypted.isEmpty` 会直接早退（提示"所有文件都已加密"）⇒ **根本没有入口**做改名。
- 判据（5 秒定论）: 设备日志搜 `FilenameEncryptionService` —— 改名跑过一定有
  `filename encryption pass done: N renamed, … queues=K`；静态判据：
  `git grep -n "pendingItems" -- lib/` 与 `git grep -n "updatePrivatePath" -- lib/` 都必须有命中。
- 实现:
  ① 确认弹框改为 `_EncryptOptionsDialog`：两个勾选项「加密文件内容」「加密文件名」，各自带数量副标题，
     数量为 0 的项**禁用**；默认策略 = 有明文就勾内容；**全部已加密时不勾内容、勾文件名**（正是"补做"场景）。
     **校验**：一项都没勾 ⇒ 「确定」禁用 + 红字 `请至少选择一项`，`_batchEncrypt` 里再兜底判断一次。
  ② 执行顺序：阶段 1 内容加密（`BatchEncryptionService`，勾了才跑）→ 阶段 2 **重新读取** `listEncrypted()`
     取"命名仍是原样"的项再改名 ⇒ 阶段 1 新加密的文件也会一起改名。
  ③ 改名逻辑（新增 `FilenameEncryptionService`）：只处理 `encrypted_dek != null` 的项（明文项**拒绝改名**）；
     新名 = 32 位随机 hex、**无扩展名**、同目录（原子 rename）；**先校验**（目标存在 + 字节数一致）再更新 DB；
     DB 更新失败就把文件改回原名；已是随机名 → 跳过（幂等，可重跑）。
  ④ 进度对话框：标题与状态按阶段切换（`正在加密文件名，第 N 项（共 M 项）…`），结束的 SnackBar 同时给出
     内容加密与改名结果；完成后 `ref.invalidate(albumsProvider / vaultSizeBytesProvider)` 刷新缓存路径。
- 反例 / 易误判:
  - **给明文项改名** ⇒ 用户在其它入口看到"没有扩展名的怪文件"、失去"这是照片/视频"的线索；
    所以前置条件是"有 DEK"，且判断放在**服务内部**（不依赖 UI 勾选顺序）
  - 改名成功但 DB 没更新 ⇒ 启动维护按 DB 路径比对会把它当孤儿（`ISSUE-030` 的自愈逻辑）
  - 以为"改名后查看/播放要重新解密" ⇒ 不需要：显示与播放本来就走"解密到临时文件"
  - 以为"还原到相册会变成随机名" ⇒ 不会：还原用 `original_name`
- 相关文件: `lib/data/services/filename_encryption_service.dart`（新增）、`lib/presentation/settings/settings_screen.dart`、
  `lib/data/db/database.dart`、`lib/data/repositories/media_repository.dart`、`lib/l10n/app_localizations.dart`
- 相关条目: `ADR-042`（方案；阶段 1 已落地）、`ISSUE-033`（并行队列模式复用）、
  `ISSUE-034`（长名上限，随机名顺带根除）、`PIT-063`（改名三步一致性）
- 首次记录: 2026-10-13（用户需求）


## ISSUE-039 「解密所有文件」+「修复加密记录」：两个反向操作落地
- 状态: 已实现（待真机复核）
- 需求 / 现场: ① 设置里要一个与「加密已有文件」相反的操作，同样是两个复选项（解密文件内容 / 解密文件名）；
  ② 早期 bug 留下 4 条"记录了已加密、文件其实仍是明文"的失效记录，需要一个功能把它们清掉
  （这类记录会让查看器/播放器把明文当密文去解，表现为打不开）。
- 判据（5 秒定论）: 日志搜 `BatchDecryptionService`（内容解密）与 `EncryptionRecordRepairService`（记录扫描）——
  跑过一定有 `decrypt pass done: … keyLost=…` / `record scan done (apply=…): …`；静态判据：
  `git grep -n "pendingItems\|renamedItems" -- lib/` 与 `git grep -n "staleDek" -- lib/` 都必须有命中。
- 实现:
  ① 入口：设置 → 存储「解密所有文件」（紧挨「加密已有文件」）；设置 → 存储（维护组）「修复加密记录」
     （与「扫描孤立隐藏文件」「修复拍摄时间」并列）。
  ② 解密内容（`BatchDecryptionService.decryptOne`）：解 DEK → native 解密到**同目录** `.dec_tmp-<id>` →
     校验非空 → 原子替换（密文 → `.dec_bak`，明文 → 原路径，再删备份）→ **最后**才
     `updateEncryptedDek(id, null)`。
  ③ 解密文件名（`FilenameEncryptionService.restoreNames`）：只处理 32 位随机名；目标名 = DB 的
     `original_name`（sanitize 掉路径分隔符/控制字符）；重名退避 `<id8>_<name>` → `<name>-2` → … → 随机名；
     同样 rename → 校验字节数 → 更新 DB，失败改回（`PIT-063`）。
  ④ 修复记录（`EncryptionRecordRepairService.scan`）：逐项比对"是否有 DEK"与"文件头是否像密文"
     （`looksEncrypted`，只读 32 字节）：
     - 有 DEK + 明文 = **失效记录** → 清 `encrypted_dek`（先 `apply:false` 只统计，供确认框显示条数）；
     - 无 DEK + 密文 = **不可恢复孤儿** → 只统计、**绝不改**（删记录只会掩盖问题）；
     - 其余一致 / 文件缺失 → 计数。
  ⑤ 加密与解密**互斥**（`_encryptionFlowBusy()`）：两者都会原地改写同一批文件，同时跑等于`ISSUE-030` 重演。
- 反例 / 易误判:
  - 把"解密"写成"先清 DEK 再解密" ⇒ 崩在中途就是"密文 + 无 DEK"= **永久孤儿**（见 `PIT-064`）
  - 以为"无 DEK 的密文"也能靠这个功能救回 ⇒ 只能从备份/相册原件找回
  - 以为文件名解密会处理历史命名 `<id8>_原名.jpg` ⇒ 那种名字是**可读**的，本功能只动 32 位随机名
    （UI 文案已写明"随机文件名将恢复"）
  - 把解密输出写到系统临时目录 ⇒ 与 vault 可能不同卷，`rename` 非原子；本条用**同目录** tmp 规避
- 相关文件: `lib/data/services/batch_decryption_service.dart`（新增）、
  `lib/data/services/encryption_record_repair_service.dart`（新增）、
  `lib/data/services/filename_encryption_service.dart`（新增反向方法）、
  `lib/presentation/settings/settings_screen.dart`、`lib/application/providers.dart`、`lib/l10n/app_localizations.dart`
- 相关条目: `ISSUE-038`（加密方向）、`PIT-064`（崩溃窗口该放哪一侧）、`ADR-043`（设计）、
  `ISSUE-030`（并发写同一文件）、`PIT-034`（原子替换）、`ISSUE-032`（解密内存上限）
- 首次记录: 2026-10-13（用户需求）


## ISSUE-040 导入私密相册即"加密文件名"（ADR-042 阶段 2 落地）
- 状态: 已实现（待真机复核）
- 需求 / 现场: 导入时不只加密内容，还要**同时加密文件名** —— 否则"密文 + 原扩展名"仍会被
  按扩展名扫描的程序认出这是媒体。
- 判据（5 秒定论）: 导入若干文件后看保险库目录：文件名应是 **32 位 hex、无扩展名**；
  DB 里 `private_path` 指向随机名、`original_name` 仍是原名（查看/播放/还原不受影响）。
  静态判据: `git grep -n "encryptedFileName" -- lib/` 应命中 `hide_naming.dart` /
  `vault_storage_service.dart` / `filename_encryption_service.dart`；
  `git grep -n "isEncryptedFileName" -- lib/data/services/maintenance_service.dart` 必须有命中。
- 实现:
  ① 命名**唯一来源**：`HideNaming.encryptedFileName()` / `isEncryptedFileName()`（32 hex、无点、无扩展名）；
     `FilenameEncryptionService.isEncryptedName/generateName` 改为委托它，避免两套格式漂移。
  ② `VaultStorageService.hiddenDestPath(..., encryptFileName: bool)`：true → 随机名（含 5 次碰撞重试，
     避免同卷 rename 覆盖同名文件）；false → 保持 `<id8>_<原名>`。
  ③ `HidePreparer` 注入 `EncryptionKeyManager`，判据 = **准备时 KEK 是否已在内存**：
     已解锁导入 → 随机名（随后必定加密）；保险库锁定导入 → 保留可读名（明文状态保持可读更合理，
     之后在「加密已有文件」勾「加密文件名」即可补做，`ISSUE-038`）。
  ④ 配套改动（换命名必须同步，否则静默漏文件，见 `PIT-065`）：
     - `maintenance_service._looksLikeMedia`：把"32 位随机名"也算媒体候选 ⇒ 否则**重装恢复会漏掉**这些文件；
     - `vault_backup_export`：包内文件名原用 `p.extension(privatePath)`，随机名没有扩展名 ⇒ 退回
       `originalName` 的扩展名（恢复只认 manifest，不影响正确性，只为包内条目可读）。
- 已知限制: 随机名孤儿（重装后没有 DB 行）无法判断图片/视频（`_isVideoName` 依赖扩展名）⇒ 恢复时按图片处理；
  若以后需要，可在恢复前用文件头嗅探定类型。
- 相关文件: `lib/data/services/hide_naming.dart`、`lib/data/services/vault_storage_service.dart`、
  `lib/data/services/import/hide_preparer.dart`、`lib/data/services/import_service.dart`、
  `lib/data/services/maintenance_service.dart`、`lib/data/services/vault_backup_export.dart`
- 相关条目: `ADR-042`（阶段 2）、`ISSUE-038`（历史文件的迁移/补做）、`ISSUE-034`（长名上限，随机名根除）、
  `PIT-065`（换命名要同步"按名字识别"的地方）
- 首次记录: 2026-10-13（用户需求）


## ISSUE-041 「取消隐藏」批量链路：被解密拦下的文件仍被原生批量搬走（密文出库、DB 行保留）+ 失败不落日志
- 状态: 已修复（2026-10-14）
- 症状 / 现场: 用户报「取消隐藏不能用了；大多数时候直接显示失败而且图片没有到常规相册；
  偶尔图片正常到了常规相册却显示失败」。批量取消隐藏后只弹一句「已取消隐藏 N · 失败 M」，
  设备日志里**一个字也查不到**（这条链路改前完全没有 AppLogger 调用）
- 复发判据:
  ① 代码级（5 秒定论）: `git grep -n "_batchResults(chunk)" -- lib/` **有命中** ⇒ 本条未修
     （必须是 `_batchResults(movable)`，且 index 兜底映射也用 `movable`）
  ② 现场级（读 app 日志）: `findstr /i "unhide failed reveal skipped skip decrypt" tmp\<日志>.txt`
     - `reveal skipped <id>: source missing` ⇒ 源文件已不在保险库（见根因 ②）
     - `unhide failed <id>` ⇒ 原生搬运失败，同一行有 `error=` / `needManageStorage=` / `dest=`（见根因 ③）
     - `skip decrypt <id>: already plaintext` ⇒ DB 记着 DEK 但文件已明文（`ISSUE-039` 那类残留）
- 根因（同一条链路 3 处）:
  ① `VaultRevealRunner.run()` 的 chunk 循环：解密被拒的项只记进 `blockedIds`（结果归因时 `continue` 跳过），
     但**原生批量搬运仍收到整块 chunk**（`_batchResults(chunk)`）⇒ 这些项的文件是**密文**，照样被
     `Files.move` 搬进相册；结果处理又跳过它们 ⇒ **相册多一个打不开的文件、DB 行与 DEK 留在库里**，
     正是 `PIT-052` 那条不可逆损坏路径（设计意图见 `ISSUE-029`④）
  ② prepare 阶段 `_resolveTarget` 返回 null（源文件不存在）时**静默 `failed++`** —— 不写日志、不设 `lastError`
  ③ 原生搬运失败分支只更新计数器，不写日志 ⇒ 现场只能看到"失败"两个字
- 证据: 改前 `lib/data/services/import/vault_reveal_runner.dart:239` 是 `final results = await _batchResults(chunk);`，
  紧接着 `for (final job in chunk) { if (blockedIds.contains(job.item.id)) continue; ... }`；
  `android/.../VaultFileHandler.kt:452` 对批量里的每个 entry 无条件调用 `unhideFromVault`（只判断文件在不在，不判内容）
- 修法（`lib/data/services/import/vault_reveal_runner.dart`，三处）:
  ① 只把未被拦下的项交给原生，并按同一个列表做兜底映射：
     ```dart
     final movable = <_PreparedReveal>[
       for (final job in chunk) if (!blockedIds.contains(job.item.id)) job,
     ];
     final results = movable.isEmpty
         ? const <MediaRenameResult>[]
         : await _batchResults(movable);
     ```
  ② prepare 失败补 `AppLogger.w('reveal skipped <id>: source missing at <privatePath>')` + `lastError='missing_source'`
  ③ 原生失败补 `AppLogger.w('unhide failed <id> (<name>): error=… method=… needManageStorage=… dest=…')`
- 反例 / 易误判:
  - "反正原生自己会失败" —— **不会**：原生只搬文件，不判密文/明文（`VaultFileHandler.unhideFromVault` 只看存在与长度）
  - 把"失败"一律当成文件权限问题 —— `reveal skipped`（源文件没了）与 `unhide failed`（搬运失败）是两码事
- 相关文件: `lib/data/services/import/vault_reveal_runner.dart`、
  `android/app/src/main/kotlin/com/privi/app/VaultFileHandler.kt`
- 相关条目: `ISSUE-029`④、`PIT-052`、`ISSUE-039`、`ISSUE-042`、`ADR-044`
- 首次记录: 2026-10-14（用户报"取消隐藏不能用了"，本轮定位并修复）

## ISSUE-042 私密网格「每隔十几项一个黑缩略图」（**根因未定位**，已列出 3 条候选与判定方法）
- 状态: 未定位（2026-10-14）
- 症状 / 现场: 用户报「缩略图还是有点问题，每间隔十几个列表项就有一个黑的」。
  网格里的"黑" = 深色底：`ThumbnailTile` 在 `_provider == null` 时就是深色 `surfaceAlt`
  （加载中没有转圈，所以看起来就是一块黑）
- 复发判据（先分清"占位"还是"解码失败"，两者现象一样）:
  ① 占位: `git grep -n "_Broken\|_VideoPlaceholder\|surfaceAlt" -- lib/presentation/grid/thumbnail_tile.dart`
  ② 解码失败: `_provider != null` 但字节不是图片 —— `Image(...)` 没有 `errorBuilder`，同样画成深色
  ③ 查日志定性: `findstr /i "ThumbnailGenerator thumb" tmp\<日志>.txt`
     - `thumb <id>: encrypted but vault key not loaded — skipped` ⇒ 候选 ①（KEK 不在内存）
     - `thumb decrypt <id>: …` ⇒ 候选 ①（KEK/DEK 解不开）
     - `video thumb: …` / `file thumb: …` ⇒ 候选 ②（取帧/解码失败，例如 >8MB 图片）
     - 一行都没有 ⇒ 候选 ③（磁盘缓存里本来就是密文字节）
- 已知证据（**代码事实，尚未与现场对应**）:
  - `thumbnail_generator.dart:221` `if (await _files.length(playablePath) > 8 * 1024 * 1024) return null;`
    ⇒ **>8MB 的图片永远生成不出海报**，而图片**没有**任何启动修复（只有视频有 `repairOutdatedVideos`）
  - `thumbnail_generator.dart:267-271`（KEK 不在内存 ⇒ 加密且无海报的项直接 skip）只在 `AppLogger.d` 留痕
  - `grid_thumbnail_service.dart:70-72`：`encrypted_dek == NULL` 的"孤儿密文"仍走
    `readAsBytes(privatePath)` ⇒ 密文喂给解码器（深色）+ **写进磁盘缓存**（第二个污染点，另一个是 `PIT-052`）
  - `thumbnail_cache.dart` 的 `cacheVersion` 只能作废"旧字节"，**修不了**"produce 返回 null"的深色 tile
- 下一步验证（按顺序，约 5 分钟）:
  1) 把手机日志 `.../logs/<app>_log_YYYY-MM-DD.txt` 拷到 `tmp\` 跑 ③ 的 findstr，先定"占位"还是"解码失败"
  2) 若命中 `vault key not loaded`：用图案/PIN 解锁一次再看同一批 tile 是否恢复 ⇒ 命中 KEK 缺失（`ISSUE-031`/`PIT-049`）
  3) 若怀疑缓存污染：`cacheVersion` +1 后**杀进程重启**（内存缓存不跨进程，磁盘缓存会）
  4) 若怀疑 8MB 上限：看这几项详情页的文件体积是否 >8MB
- 修法: 待定位后再定 —— 本轮**不做**猜测性改动
- 相关文件: `lib/presentation/grid/thumbnail_tile.dart`、`lib/data/services/grid_thumbnail_service.dart`、
  `lib/data/services/import/thumbnail_generator.dart`、`lib/data/services/thumbnail_cache.dart`
- 相关条目: `ISSUE-029`②、`ISSUE-039`、`ISSUE-031`、`PIT-049`、`ADR-044`
- 首次记录: 2026-10-14



## ISSUE-043 个别图片"隐藏进库后 app 内打不开、导出到相册却能正常看" = 明文文件 + DB 记着 DEK（状态不一致）
- 状态: 未修复（待决）—— 本轮只补了可判定的诊断日志，**没有**改判定逻辑（改法要按实际文件格式定）
- 症状 / 现场: 只有**个别**图片异常（用户实测 2 张）：导出/还原到常规相册能正常打开，
  但在私密库里：查看器打不开、缩略图是深色块、取消隐藏报失败；同一批隐藏的其他图片全部正常
- 复发判据:
  ① 日志判据（本轮新加，5 秒定论）: `findstr /i "Kept saved DEK decrypt failed decrypt-to-bytes" tmp\<日志>.txt`
     - `Kept saved DEK for <id>: the file looks encrypted … (bytes=…, header=…)` ⇒ 隐藏时"加密被判成已加密 → DEK 白留库"
     - `decrypt failed for <path> (bytes=…, header=…)` ⇒ 每次查看/取消隐藏时解密失败，**看 header 就能定性**：
       `42 4d` = BMP、`49 49 2a 00` / `4d 4d 00 2a` = TIFF、`00 00 01 00` = ICO ⇒ **明文被误判成密文**（白名单缺这种格式）
  ② 状态判据（设置页只读扫描）: 「修复加密记录」若把这两项计入 `consistent` 而不是 `stale`，
     说明它与加密判定用的是同一个 `looksEncrypted` 误判 ⇒ **修不了**（这点必须知道，别白跑）
- 根因: `MediaEncryptionService.looksEncrypted()` 是**明文白名单**反推（`_looksLikePlainMedia` 只认
  JPEG / PNG / GIF8 / `ftyp@4` / RIFF+AVI·WEBP / WebM / MKV）。白名单外的明文媒体（BMP、TIFF、ICO、WBMP…）
  被判为"密文"，于是：
  - **隐藏导入**：`encryptFileWithDek` 先抛 `StateError('File already appears encrypted')`
    （`media_encryption_service.dart:171-175`）⇒ catch 里回滚判据 `stillPlain = !looksEncrypted(...)` 是同一个误判 false
    ⇒ 走 else **保留已落库的 DEK**（`import_service.dart:440-475`）⇒ **文件是明文、DB 记着 DEK**
  - 之后 app 内一切"解密"路径全挂（AES-GCM auth tag 失败）：viewer / 播放器 / 幻灯片 / 缩略图海报生成 / 取消隐藏
  - 取消隐藏旧构建里**照样把明文搬进相册**（`ISSUE-041`）⇒ 相册里能正常看、界面报失败 —— 用户看到的就是这个
  - 同形状的历史来源（旧 bug 相关）：`MaintenanceService._repairEncryptionArtifacts`
    把 `<name>.enc_bak`（**明文**备份）还原成主文件时**不清该行的 DEK**（`maintenance_service.dart:142-158`）
- 证据:
  - 用户实验：同一批里其他图正常；这 2 张导出到相册能正常看 ⇒ **库内文件内容是完好的明文**（真密文导出后不可能可读）
  - `_looksLikePlainMedia` 签名清单见 `media_encryption_service.dart:335-373`（无 BMP/TIFF/ICO）
  - 本轮新加诊断：`MediaEncryptionService.headerHex` / `lengthOrMinusOne` + 三处日志
    （`decryptFile` 失败、`decryptToTempFileWithDek` 的 DEK 缺失与文件解密失败、`decryptFileToBytes` 失败），
    另在 `import_service` 的"保留 DEK"分支与 `EncryptionRecordRepairService` 的孤儿分支打印 header + bytes
- 修法（待定，两条路，**必须先拿到实际文件头/扩展名**）:
  1. 补白名单（首选，副作用最小）：只加 **≥4 字节且碰撞概率可忽略**的签名 —— TIFF `49 49 2A 00` /
     `4D 4D 00 2A` 安全；BMP 不能用 2 字节 `42 4D`（`PIT-050`），要 `42 4D` + offset 6 起 4 字节全 0 联合判断
  2. 若格式确实无法可靠识别（例如 v1 裸密文也像）⇒ 在「修复加密记录」里加**显式**入口：
     "这些项我确认打不开，按明文处理（清 DEK）"，由用户逐项确认（清 DEK 不可逆，必须由人拍板）
- 反例 / 易误判:
  - 把"打不开"一律当成"图片被加密 bug 弄坏了" —— 先看能否导出后正常打开：能打开就是**记录问题**，不是文件损坏
  - 在 `stillPlain==false` 时**无条件**回滚 DEK（看着像"顺手修好"）：真密文会被孤儿化，属 `PIT-052` 级损坏
  - 靠 2 字节签名（`BM` / `II`）来"修白名单"：误判成明文 ⇒ **二次加密** ⇒ 真丢数据（`PIT-050`）
  - 以为「修复加密记录」能修它：扫描判据同源，会算成 `consistent`（见复发判据 ②）
- 相关文件: `lib/data/services/media_encryption_service.dart`、`lib/data/services/import_service.dart`、
  `lib/data/services/encryption_record_repair_service.dart`、`lib/data/services/maintenance_service.dart`（`_repairEncryptionArtifacts`）
- 相关条目: `PIT-050`、`PIT-067`、`ISSUE-039`（同一状态的另一来源）、`ISSUE-030`、`ISSUE-041`、`ISSUE-042`
- 首次记录: 2026-10-14（用户报"两张图隐藏后打不开、导出到相册正常"）

## ISSUE-044 取消隐藏只报「失败」且日志全是 `Authentication failed`：隐藏时"已像密文→跳过加密"却把**新 DEK 留库**（密钥与文件内容不匹配）→ 新增「加解密修复」选择操作
- 状态: 已修复（2026-10-14：新增「加解密修复」+ 补齐明文白名单）
- 症状 / 现场: 用户报「取消隐藏失效；文件被移到常规相册后打不开」。日志
  （`密册_log_2026-10-14.txt`，176 行，13:05:30–13:06:22）里
  `[MediaEncryptionService] File decryption failed: Exception: Native decryption failed: Authentication failed: file may be corrupted or tampered with`
  反复出现，紧跟 `[VaultRevealRunner] decrypt before reveal <id>`；UI 只有「失败 1 项」
- 复发判据:
  ① 日志级（5 秒定论）: `findstr /i "Kept saved DEK Authentication failed decrypt before reveal" tmp\<日志>.txt`
     — 同一 id 既出现 `Kept saved DEK` 又出现 `Authentication failed` ⇒ 本条形态（DEK 与文件内容不匹配）
  ② 代码级: `git grep -n "mediaCryptoRepairServiceProvider" -- lib/` 有命中 ⇒ 修复动作已落地
- 根因（两步叠加，都不是"按钮坏了"）:
  ① `ImportService._encryptRecordedFiles` 的顺序是「生成 DEK → 存 DB → 加密文件」(PIT-044)，而
     `encryptFileWithDek` 在 `looksEncrypted(file)` 为真时抛
     `StateError('File already appears encrypted')` ⇒ 隐藏导入时**新 DEK 落库、文件一个字节没动**；
     catch 里的回滚判据 `stillPlain = !looksEncrypted(...)` 用的是**同一个误判**，于是走 else「保留 DEK」
     （`import_service.dart:440-476`）
  ② 之后该文件的所有解密路径（查看器 / 缩略图 / 幻灯片 / 取消隐藏）都拿这把**从未用过**的 DEK 去解，
     AES-GCM auth tag 必然失败；`VaultRevealRunner._decryptIfNeeded` 抛错 ⇒ `reveal()` 按设计 `return false`
     （「宁可不搬」，`ISSUE-029`④、`ADR-044`）⇒ 用户只看到"失败"
  ⇒ 只要文件**在隐藏前就不是明文白名单里的格式**（真密文，或 BMP/TIFF 这类白名单外明文），就会进入这个状态
- 证据（`密册_log_2026-10-14.txt`）:
  - 13:06:03.939 `_encryptRecordedFiles failed for feea8dc6…: Bad state: File already appears encrypted: …/.privateheart_vault/我/5e5f0b54…`
  - 13:06:03.940 `Kept saved DEK for feea8dc6…: the file is already encrypted even though the encrypt call failed`
  - 13:06:03.982 / 07.896 / 09.355 / 10.721 / 16.682 / 18.262 全部 `Authentication failed`
    （堆栈显示来自 `decryptToTempFileWithDek`，即"DEK 能解开、文件解不开"）
  - 13:06:10.799 同一路径 `FileSystemException: File not found` ⇒ 文件已被原生批量搬运带出保险库
    （用户机上还是 `ISSUE-041` ① 修复前的构建）⇒ 相册里留下未解密的字节，DB 行与 DEK 留在库里
  - 13:06:18.262 `[ViewerScreen] Decrypt returned null for 7db8cfc8… — DEK or auth tag mismatch`（同一形态的第二个 id）
  - 日志里 `decryptFile` 失败行**没有** `bytes=/header=` ⇒ 该 APK 早于 `ISSUE-043` 那批诊断改动（构建比工作区旧）
- 修法（本轮）:
  ① 新增文件选择操作「加解密修复」：**两个网格**的选择胶囊都加（`visible_media_grid` 可见 + `media_grid_screen` 私密）
     → `lib/presentation/common/crypto_repair_action.dart`（互斥守卫 + 进度弹窗 + 分项结果汇总）
     → `lib/data/services/media_crypto_repair_service.dart`，逐个文件：
     明文嗅探 → 命中且 DB 有 DEK ⇒ **只清失效记录**（不碰文件）；否则按
     「本行 DEK → 同名/同大小行的 DEK（≤6 个；>512 MiB 的文件只试本行）」逐个试解 →
     成功则**原地原子替换 + 清 DEK**；全失败则保持原样，并把 `bytes=/header=` 落日志
  ② 补齐明文白名单（`ISSUE-043` 的推荐路径）：`_looksLikePlainMedia` 增加 TIFF 族（`49 49 2A 00` / `4D 4D 00 2A`）、
     BMP（`42 4D` + offset 6 起 4 字节全 0，不破 `PIT-050` 的"2 字节禁令"）、ASF/WMV GUID、`FLV\x01`；
     并把 `looksEncrypted` 传给判定函数的缓冲区截成实读长度（原来是 32 字节零填充）
  ③ 临时/备份文件用 `.enc_tmp-repair-<哈希>` / `<path>.enc_bak` ⇒ 保险库内崩溃可由
     `MaintenanceService._repairEncryptionArtifacts` 自愈（`ISSUE-030`）；名字走哈希，不碰 255 字节上限（`PIT-061`）
- 反例 / 易误判:
  - 把「取消隐藏失败」当成权限/搬运问题 —— 先看日志有没有 `Authentication failed`；那是**密钥不匹配**
  - 以为「修复」能把文件搬回来 ⇒ 它**只在原路径原地改写**，不搬文件、不改名
  - 以为「修复」能救「密文 + 无 DEK」⇒ 没有任何钥匙可试，只会报 `noKey`（与 `ISSUE-039` 的孤儿同类）
  - 在"明文误判"分支里顺手清 DEK 而不先确认文件头 —— 真密文会被孤儿化（`PIT-052` 级损坏）
- 相关文件: `lib/data/services/media_crypto_repair_service.dart`（新增）、
  `lib/presentation/common/crypto_repair_action.dart`（新增）、`lib/data/services/media_encryption_service.dart`、
  `lib/presentation/grid/media_grid_screen.dart`、`lib/presentation/visible/visible_media_grid.dart`、
  `lib/application/providers.dart`、`lib/l10n/app_localizations.dart`
- 相关条目: `ISSUE-041`（失败项仍被搬走）、`ISSUE-043`（同一状态的白名单来源）、`ISSUE-029`④、`ADR-044`、
  `ADR-045`（本动作的设计取舍）、`PIT-044`、`PIT-051`、`PIT-064`
- 首次记录: 2026-10-14（用户提供日志 + 需求「加解密修复」）

## ISSUE-045 【2026-10-14】日志里 `√ Built …app-release.apk` 却报「构建失败！Flutter exit code=-196608」（APK 不复制、Release 不发布）
- 状态: 已修复
- 症状 / 现场: `build\build_full.log` 末尾先出现 `√ Built build\app\outputs\flutter-apk\app-release.apk (122.3MB)`，
  紧接着 `[警告] 构建失败！Flutter exit code=-196608`；`build\build_exit.log` = `BUILD_FAILED=1 … NEW_VER=1.0.97`；
  根目录**没有** `privi-1.0.97.apk`（步骤 6/7 被跳过，只剩旧的 `privi-1.0.95.apk`）；
  [4/7] 段里夹着 `The argument 'D:\WorkSpace\test\privi\tools\build_pub_get.ps1' to the -File parameter does not exist`
- 复发判据（5 秒定论，静态两条；动态一条看日志；**写进 .bat 时 `%` 要写成 `%%`**，见 `PIT-007`）:
  ① `findstr /n /c:"%~dp0tools" scripts\build.bat` **必须无输出**（工具脚本路径必须走 `%SCRIPT_DIR%`）；
  ② `findstr /n /c:"set BUILD_EXIT=%ERRORLEVEL%" /c:"set PUB_EXIT=%ERRORLEVEL%" scripts\build.bat` **必须无输出**
     （块内必须 `!ERRORLEVEL!`）；反向确认：`findstr /n /c:"=!ERRORLEVEL!" scripts\build.bat` 应出现 **10 行**
     （WMI_RC / BUMP_EXIT / PUB_EXIT / MEM_EXIT / GH_AUTH_RC / REL_EXIT×2 / BUILD_EXIT / PUB_EXIT / BUILD_EXIT）；
  ③ 构建日志 [4/7] 段必须有 `[pub] 执行: flutter pub get --verbose` + `[pub] 结束: 退出码 0`；
     只看到 `to the -File parameter does not exist` ⇒ 复发。
- 根因（三件事叠加，缺一不可）:
  ① **`shift` 会改 `%0`**：tee 包装器用 `--log` 把自己重启一次，内层执行 `shift` 后 `%0` 变成裸参数 `--log`，
     此时 `%~dp0` 解析出来是**当前工作目录**（实测，见 `PIT-073`）。于是[4/7]（顶层、`goto :build` 到的流程）
     里的 `%~dp0tools\build_pub_get.ps1` 变成 `<cwd>\tools\build_pub_get.ps1` → 文件不存在。
     *为什么同一文件里 `:codegen`/`:preflight`/`:reclaim_memory`/`:increment_version` 没事*：那些是
     `call :label` 子例程，cmd 会把 `%0` 恢复成脚本路径 ⇒ 只有顶层这一处（第 1006 行）指错。
  ② Windows PowerShell 5.1 在 `-File` 指向**不存在**的脚本时退出码 = **-196608（0xFFFD0000）**（实测，见 `PIT-074`）。
  ③ `set PUB_EXIT=%ERRORLEVEL%` / `set BUILD_EXIT=%ERRORLEVEL%` 写在 `( )` 块里 ⇒ 取的是**进块前**的旧值（`PIT-007`）：
     PUB_EXIT 拿到 0 ⇒ 打出「pub get 完成。」（静默放过看门狗失败）；而 `call :save_state` 里的 `echo > file`
     不会重置 ERRORLEVEL ⇒ -196608 一直留到 [5/7] 块的 `set BUILD_EXIT=%ERRORLEVEL%` ⇒ 被当成 flutter 的退出码。
- 证据: `build\build_full.log` 113-119 行（PowerShell banner + `-File ... does not exist` + 随后仍打印「pub get 完成。」）、
  199-201 行（`Flutter exit code=-196608`）；`build\build_exit.log`（`BUILD_FAILED=1 NEW_VER=1.0.97`）与
  `build\app\outputs\flutter-apk\app-release.apk` 的 mtime `18:33:42` 同为一次构建（说明 APK 确实产出了）。
  实测复现（tmp 下）：`shift` 后 `%~dp0` = cwd（`[IN-SUB]` 里反而正常）；`powershell -File <不存在>` → `-196608`；
  块内 `set S=%ERRORLEVEL%` = 进块前值、`set S=!ERRORLEVEL!` = 当前值。
- 修法（`scripts\build.bat`）:
  ① 文件开头（任何 `shift` 之前）固化 `SCRIPT_DIR` / `PROJECT_ROOT`，全文 22 处 `%~dp0…` 改写为这两个变量；
     `cd /d "%PROJECT_ROOT%"` 不再依赖 cwd（顺带修掉"从仓库根跑会把 cwd 退到上一级"的隐患）；
  ② 块内退出码一律 `!ERRORLEVEL!`，并统一加引号 `set "X=!ERRORLEVEL!"`；
  ③ 新增**辅助脚本自检**（5 个 ps1 缺任一 ⇒ `[错误]` + `BUILD_FAILED=1` + 终止，禁止静默跳过）+ [4/7] 调用前
     `if not exist …` 硬失败 + 显式识别 `-196608` 并给出提示；
  ④ 包装器 `finally` 里补 `exit $LASTEXITCODE`：以前结尾是裸 `exit /b`，内层结果被丢掉、脚本永远返回 0
     （用户看到的 `Process finished with exit code 0` 就是这么来的）。
- 验证（沙箱全流程，不碰真实项目）: 真 `build.bat` + 真 `scripts\tools\*.ps1` + 假 `flutter/dart`（存在 tmp\sandbox），
  修复前 = 同样的假失败；修复后 = `BUILD_FAILED=0`、脚本退出码 0、[4/7] 出现 `[pub] 结束: 退出码 0`、
  `APK: privi-1.0.99.apk` 已复制到项目根、`构建成功！`；故意删掉 `build_mem.ps1` ⇒ 自检报 `[错误] 缺少辅助脚本` 且退出码 = 1。
- 反例 / 易误判: 以为「flutter 真的失败」（它已打印 √ Built，且 APK mtime 就是这次构建的时间）；
  以为「pub get 成功了」（看门狗根本没启动）；以为 `PIT-007` 只坑 `&` 链（`( )` 块里同样中招）；
  用 `%ERRORLEVEL%`（要写 `!ERRORLEVEL!`）去读"刚跑完的子进程"退出码。
- 相关文件: `scripts\build.bat`（第 5-12 行脚本目录固化、第 104-124 行自检、第 1036-1100 行 [4/7]/[5/7]）
- 相关条目: `PIT-007`（块的解析期展开）、`PIT-073`（shift 改 %0）、`PIT-074`（-196608）、`PIT-075`（运行中改写 bat）、
  `ISSUE-007`（"目录里有 APK 就算成功"的假绿，本次是反向的假红）、`ISSUE-011`（防护静默跳过）、`ADR-046`
- 首次记录: 2026-10-14 ／ 最近复核: 2026-10-14（沙箱复跑全绿 + 自检反向用例通过）

## ISSUE-046 【2026-10-14】控制栏「循环播放」点了没反应（viewer / 可见库预览的单视频不循环）
- 状态: 已修复（待真机复验）
- 症状 / 现场: 视频播放窗口底栏点「循环播放」（`Icons.repeat`）后图标会变色，但视频播完**仍停在最后一帧**、
  不从头重播；日志里只有 `Video ended, staying on this item (no auto-advance)`（ViewerScreen）/
  `GalleryPreviewScreen` 的同款行，**没有任何循环相关日志**
- 复发判据: 复现后读 app 日志（设备 `Download/密册/logs/密册_log_<date>.txt`）搜
  `Looping enabled: replaying from the beginning`：
  - 命中 ⇒ 循环生效（已走「播完重建」）；
  - 只出现 `Video ended, staying on this item (no auto-advance)` ⇒ 界面又漏了 `_looping` 分支
- 根因（两层叠加）:
  ① `NativeVideoController.setLooping()` 是**空实现**（旧代码只有一行注释
     `// Not directly supported by our simple player; ignore for now`）—— 原生 libVLC / ExoPlayer 都没接循环开关；
  ② 单视频循环只能由界面在 `onCompleted` 里「重建播放器 + 从 0 起播」实现，而**只有 `PlayerScreen` 写了**这段
     （`if (_looping) { _replayItemId=…; _replayStartMs=0; 重建播放器 }`），
     `ViewerScreen._onVideoEnded` / `GalleryPreviewScreen._onNativeVideoEnded` 都只做「停在最后一帧」
  ⇒ 点按钮只改了 `_looping` 状态与图标颜色，播放行为零变化
- 证据: `lib/data/services/native_video_controller.dart` 旧 775-777 行（空实现）；
  `viewer_screen.dart` 旧 413-423、`gallery_preview_screen.dart` 旧 268-278（无 `_looping` 分支）；
  `player_screen.dart:676-685`（有分支，作对照）；用户日志 `密册_log_2026-10-14.txt` 20:09:01.672 → 20:09:14
  走的就是 viewer 的非循环路径
- 修法:
  1. `viewer_screen.dart` `_onVideoEnded`：补 `if (_videoId != itemId) return;`（回调是异步的，中途可能已切 item）
     + `if (_looping) { 记日志 'Looping enabled: …'; unawaited(_replayFromPosition(Duration.zero)); return; }`
  2. `gallery_preview_screen.dart` `_onNativeVideoEnded`：同上（校验用 `_current.id != itemId`）
  3. `native_video_controller.dart` `setLooping`：保持空实现但**写一条 DEBUG 日志**
     （`setLooping(...): looping is owned by the UI, the native input has no loop flag`），
     doc 注释写明「循环归界面层」，免得将来又把它当成"已支持"
  - 重建走 `_replayFromPosition()`（`_detachVideo()` + `_syncVideo()`，`_pendingStartMs = 0`），与
    `ISSUE-022` 的「播完后重播」同一条已验证链路，**不引入新的原生行为**（见 `ADR-031`）
- 反例 / 易误判:
  - 以为循环该在原生做（给 libVLC 加 playlist / 复播）—— 与 `ADR-031` 冲突，且没在真机验证过
  - 只修一处界面 —— `viewer` / `gallery_preview` / `player` 三个入口必须同步（`PIT-033` 同类坑）
  - 把循环分支写进 `_onSpuriousCompletion` —— 起播竞态的"重建继续播"不是循环
  - 以为 `_looping` 没保存 —— 它本来就只在当前界面会话内有效（与 `_fitMode` 等一致），不是本条根因
- 相关文件: `lib/presentation/viewer/viewer_screen.dart`、`lib/presentation/visible/gallery_preview_screen.dart`、
  `lib/data/services/native_video_controller.dart`、`lib/presentation/player/video_player_controls.dart`（按钮与高亮）、
  `lib/presentation/player/player_screen.dart`（对照实现）
- 决策: `ADR-031`（循环沿用「重建式重播」）
- 首次记录: 2026-10-14

## ISSUE-047 【2026-10-14】VLC 引擎下进度条一打开就满格、不随播放变化（原生把越界位置裁成 duration，掐死 Dart 的时间轴归一化）
- 状态: 已修复（待真机复验）
- 症状 / 现场: VLC 引擎点开某个视频，**进度条从第一帧起就满格停在结尾**、左端时间恒等于总时长，
  画面/声音正常，约 23.8 秒后才真正 `STATE_ENDED`；日志反复出现
  `VDIAG[dart-position-stall] position stuck at 23797ms while isPlaying=true`（23797ms 就是该文件的 duration）
- 复发判据（读 app 日志，二选一即可定论）:
  - 命中本条：`VDIAG[dart-position-stall]` 里 `position == duration`、`completed=false`、`timelineOffset=0 ms`，
    且**全程没有** `seekTo` / `Restoring resume position`；
  - 不是本条：出现早期 `STATE_ENDED` / `Vout event: voutCount=0` / `VDIAG[spurious-end]` ⇒ 那是 `ISSUE-023`；
  - 修复生效的正面证据：出现 `VDIAG[timeline-offset] native position …ms is past duration …ms`，进度条从 0 增长
- 根因: **VLC 引擎把「媒体时间轴越界的位置」裁剪成 duration，而 Dart 的时间轴归一化恰恰要靠越界值**：
  - 原生（旧）`VlcPlayerHandler.getPosition()` = `clampPosition(mp.time)`，
    而 `clampPosition = if (durationMs > 0) positionMs.coerceIn(0, durationMs) else …`；
    `TimeChanged` 与 `seekTo` 走同一函数 ⇒ 上报给 Dart 的每个采样都被压进 `[0, duration]`；
  - Dart 侧 `_contentPositionMs()`（`ISSUE-009` 的归一化）只在 `raw > duration` 时才 latch `_timelineOffsetMs`；
  - 该文件带**前导时间轴偏移**（首帧 PTS 落在 duration 附近/之后），原生从起播第一次采样起就只报 duration
    ⇒ offset 永远 latch 不到 ⇒ `value.position` 恒 = duration ⇒ 进度条满格、不随播放变化、左端时间不动；
  - **决定性对照**：ExoPlayer 侧 `VideoPlayerHandler.getPosition()` = `player?.currentPosition`（**从不裁剪**）、
    `seekTo` 也不裁 ⇒ 同一套 Dart 归一化在 exo 引擎正常，只在 vlc 引擎失效
    ⇒ 是 `VlcPlayerHandler` 与 ExoPlayer 口径不一致（实现偏差），不是文件/解码问题
- 证据: 用户日志 `密册_log_2026-10-14.txt`（设备 `Download/密册/logs/`，`engine=vlc`，`duration=23797ms`）
  - 20:08:27（textureId=0）、20:08:36（textureId=1，点重播重建）、20:09:17（textureId=2，重新打开）三次都在
    起播 ~3.8s 后打 `VDIAG[dart-position-stall] … duration=23797ms position=23797ms size=1920x1080
    timelineOffset=0 ms seekNeedsTimelineOffset=true (no error text) |
    native ready=true playing=true position=23797ms duration=23797ms size=1920x1080`；
  - 三次都**没有** `seekTo(content=…)`、**没有** `Restoring resume position`（20:09:17 那次 `savedMs` 已被
    `VideoResumeService` 的 95% 规则删除、不续播）⇒ 满格不是 seek 造成的；
  - 真正播完在 20:09:01.602 `STATE_ENDED`（起播 23.8s 之后）⇒ 起播阶段没有 EndReached ⇒ `isEnded == false`
    ⇒ 只剩"`clampPosition(mp.time)` 被裁到 duration"这一条路径能解释
- 修法: `android/app/src/main/kotlin/com/privi/app/VlcPlayerHandler.kt`
  —— `clampPosition` 改成 `sanitizePosition`（只 `coerceAtLeast(0L)`，**不裁上界**），
  `getPosition()` / `TimeChanged` / `seekTo` 三处改用它（与 ExoPlayer 口径一致）。
  `seekTo` 不裁上界是**必须的**：offset latch 后 `_probeSeekAxis()` 会传时间轴坐标（> duration），
  若仍被裁回 duration，播放位置会直接跳到结尾
- 待证实（下次真机日志定论）: 日志里只留下"被裁剪后的"位置，**没能直接读到原始 `mp.time`**，
  所以"文件带前导偏移"是排除法推断。修复后：
  - 出现 `VDIAG[timeline-offset] … is past duration` ⇒ 推断成立、问题闭环；
  - 若仍是 `VDIAG[dart-position-stall]`（position 恒 = duration、`timelineOffset=0`）⇒ 说明是 VLC 在该文件上
    `mp.time` 本身就恒等于 duration（时间读取异常），需另案（先用 exo 引擎对照同一文件）
- 反例 / 易误判:
  - 当成 `ISSUE-023`（起播竞态）复发 —— 那条有 `VDIAG[spurious-end]` + `voutCount=0` 早于 `STATE_ENDED`，本条没有
  - 当成"进度条 UI 没刷新" —— 左端时间标签也恒为总时长，是数据层 `position` 不动
  - 当成 `VideoResumeService` 续播到结尾 —— 日志里无 `Restoring resume position`，且 95% 规则已删记录
  - 只改 `getPosition()` 不改 `seekTo` —— 进度条会动，但探针 seek 被打回 duration
  - 把 `clampPosition` 的裁剪当成"防止异常大值"的护栏 —— 它正是 `ISSUE-009` 归一化唯一的数据来源
- 相关文件: `android/app/src/main/kotlin/com/privi/app/VlcPlayerHandler.kt`、
  `lib/data/services/native_video_controller.dart`（`_contentPositionMs` / `_probeSeekAxis` / `_trackPositionProgress`）、
  `android/app/src/main/kotlin/com/privi/app/VideoPlayerHandler.kt`（对照：不裁剪）
- 关联: `ISSUE-009`（同一套时间轴归一化）、`ISSUE-022`（`isEnded` 分支保留不动）
- 真机复核 2026-10-14（1.0.99 用户日志）: **修复生效** —— 日志出现
  `VDIAG[timeline-offset] native position 47720499ms is past duration 23797ms: treating 47720499ms as the clip
  start (leading edit / 32-bit PTS wrap)`（≈ `2^32/90000`，正是 `ISSUE-009` 的特征值），
  进度条恢复 0→duration 正常推进（`dart-position-stall` 不再出现）。
  同一次日志还暴露两个后续项：①`_probeSeekAxis()` 在这么大的偏移下会实测 seek、并把坐标系误判成 content
  ⇒ 本轮已修（见 `ISSUE-048` 末段）；②循环重播后画面不刷新（`ISSUE-048`）
- 首次记录: 2026-10-14

## ISSUE-048 【2026-10-14】循环重播后画面不刷新、一直显示沙漏图标，点一下屏幕才出现（渲染条件只读了 `value` 快照）
- 状态: 已修复（待真机复验）
- 症状 / 现场: `ViewerScreen` 开着「循环播放」，每轮播完自动重建，原生侧一切正常
  （`Creating native player` → `video surface attached` → `Vout voutCount=1` → `STATE_READY` → `onPlaying`
  都在 ~200ms 内到齐），但**画面不出来**：播放区一直盖着 `Icons.hourglass_top`（有缩略图时是缩略图 + 沙漏），
  可见库预览则是转圈；用户手点一下屏幕（控制条显隐 → setState）画面立刻出现 ⇒ 数据层没问题，是 UI 没重建
- 复发判据: 日志里 `Looping enabled: replaying from the beginning` 之后跟着完整的
  `Creating native player` / `STATE_READY` / `onPlaying`（都正常），**同时**用户看到沙漏；
  对照 `PlayerScreen`：它有 `Native value changed: item=…, textureId=…, initialized=true` 这行日志
  （`_onNativeVideoValueChanged` 的 listener），viewer / gallery 从来不打这行 ⇒ 命中
- 根因: **`initialized` 是异步事件，而"要不要显示画面"只在 build 时读了一次 `value` 快照，之后没有任何东西触发重建**：
  - `viewer_screen.dart` 旧 `_videoPage()`：`if (… || !video.value.isInitialized) { 沙漏占位 }`（快照）；
    `_syncVideoBody()` 里那次 setState 在 `await c.play()` 之后，而原生 `STATE_READY` → `initialized`
    比它晚 ~100ms（日志：`play` 21:36:07.579 → `Initialized [event]` 21:36:07.684）⇒ 那次判定
    `isInitialized=false`（落到沙漏），事件到了却**没人再 setState**；
  - `_videoBottomBar` 包在 `ValueListenableBuilder` 里，所以控制栏/进度条正常出现，进一步掩盖了
    "只有画面不刷新"；用户点屏幕 → `_toggleChrome` → setState → 重新判定 → 画面出现；
  - `gallery_preview_screen.dart` 的 `_pageContent()` 同款写法（`video.value.isInitialized`），同样中招；
  - **`player_screen.dart` 早就修过这个坑**（`_onNativeVideoValueChanged` + 注释
    "Without this listener the second video of a folder autoplay keeps spinning forever"），
    本轮只是另外两个界面没跟上（`PIT-033` 同类：改一个界面忘了另一个）
- 修法:
  - `viewer_screen.dart`：`_videoPage()` 的"沙漏 ↔ 画面"判定改为**订阅** controller ——
    `ValueListenableBuilder<NativeVideoValue>(valueListenable: video, builder: (c, value, child) =>
    value.isInitialized ? child! : _videoPlaceholder(item, active), child: <画面子树>)`；
    `child:` 让 Texture 子树在 250ms 一次的位置刷新时不重建；沙漏/缩略图分支抽成 `_videoPlaceholder()`
  - `gallery_preview_screen.dart`：`_pageContent()` 同样改成 `ValueListenableBuilder`（未初始化时显示原有转圈）
  - `PlayerScreen` 的 listener 写法不动（两种都对，本轮只补齐缺的两处）
- 顺带修的次生缺陷（同一次日志暴露）: `_probeSeekAxis()` 在 32 位 PTS 回绕文件上会**实测 seek**：
  `VDIAG[timeline-offset] … 47720499ms` → `seekTo: textureId=…, positionMs=300`（content 坐标）→
  `VDIAG[seek-axis] readback=47720701ms`（第 1 遍）/ `47720499ms`（第 2 遍）/ `300ms`（第 3 遍，**误判成 content 坐标**）
  —— 回读值三种都出现过，最后那种会让 `_seekNeedsTimelineOffset=false`，之后用户拖进度条全部落错位置。
  修法：偏移超过 `_kProbeOffsetCeilingMs`（1 小时）时**不做实测**，直接认定 timeline 轴，并打
  `VDIAG[seek-axis] offset=…ms is far beyond the clip: assuming the timeline axis without a probe seek`
- 反例 / 易误判:
  - 当成"原生没出帧/黑屏"（`ISSUE-008`）：本次 `Vout voutCount=1` 正常，是 Flutter 没重建；
  - 当成"引擎起不来"（`ISSUE-014` 的 15s 看门狗）：看门狗没超时，且点击就能出画面；
  - 只在 `_syncVideoBody()` 里补一次 `setState`（或在 `initialized` 事件里硬塞回调）——
    正确做法是让**渲染条件订阅** `NativeVideoController`（它本来就是 `ValueNotifier`），
    否则以后任何"异步改变渲染条件"的事件都会再犯；
  - 用 `ValueListenableBuilder` 时忘写 `child:`，每 250ms 的位置刷新都会重建 Texture 子树
- 相关文件: `lib/presentation/viewer/viewer_screen.dart`、`lib/presentation/visible/gallery_preview_screen.dart`、
  `lib/presentation/player/player_screen.dart`（既有正确写法，对照）、`lib/data/services/native_video_controller.dart`（`_probeSeekAxis`）
- 关联: `ISSUE-047`（上一件：VLC 裁剪掐死时间轴归一化；`timeline-offset` 能 latch 正是它修好的）、
  `ISSUE-046`（循环按钮）、`ISSUE-009`（前导偏移）、`PIT-033`（改一处忘另一处）
- 首次记录: 2026-10-14

## ISSUE-049 密钥包只带走 salt+KEK：重装后密文"能解密却没名字、没 DEK 记录" ⇒ 导出/导入改为 SQLite 数据库
- 状态: 已实现（待真机复核）
- 症状 / 现场（用户需求）: 「导出加密密钥」导出的 v1 JSON 只有
  `{format, version, createdAt, encryptionSalt, kek}`。重装后即使导入成功也只能拿回 KEK：
  metadata DB 是空的 ⇒ 文件名是 32 位随机名（`ADR-042`，原名只在 DB 的 `original_name`），
  且没有 `encrypted_dek`（每文件 DEK 的包裹副本）⇒ 文件在库里"看得见但打不开"、原名不可恢复。
  用户要求：一次导出/导入**所有与加解密相关的信息（尤其文件名映射）**，并改用 SQLite 便于存更多信息。
- 复发判据（5 秒定论）: 用任意 SQLite 工具打开导出的包，`sqlite_master` 里必须有
  `meta` / `key_material` / `media_keys` 三张表；`key_material` 恰好 1 行（`length(kek) = 32`），
  `media_keys` 行数 = 导出时保险库有效条目数。
  静态判据: `git grep -n "CREATE TABLE media_keys" -- lib/data/services/key_backup_service.dart` 必须有命中。
- 根因: v1 包只定义"密钥材料"，把"文件名映射 + 每文件 DEK"留在了 app 的 DB 里；而重装/换机丢掉的正是这份 DB。
- 证据: 旧 `buildPackage()` 只写 5 个字段（见 `ISSUE-036` 修法 ①）；
  `media_items.encrypted_dek` / `original_name` 当时没有任何导出通道。
- 修法:
  ① 包格式 v2 = 独立 SQLite 数据库（`.db`），schema 见 `key_backup_service.dart` 的 `_schemaSql`
     （`meta` / `key_material` / `media_keys`，后者带 `private_path`、`original_path`、`original_name`、
     `encrypted_dek`、`content_digest` 等，决策见 `ADR-047`）；
  ② 导出 `exportToDirectory()`：`meta` 写 format/version/createdAt/fileCount/encryptedFileCount/warning；
     `key_material` 写 `encryption_salt` + 原始 KEK（BLOB）+ `kek_source`；
     `media_keys` 逐行来自 `MediaRepository.listActive()`；
     `PRAGMA journal_mode = DELETE`（不产生 `-wal/-shm` 附属文件），任何异常都删掉半成品文件再 rethrow；
  ③ 导入 `importPackage(path)`：`inspectPackage()`（只读，返回 `KeyPackageSummary` 供确认框显示条数）→
     `validatePackage()`（salt 冲突 / KEK 实测，规则完全沿用 `ADR-041`）→ 写 salt + `setImportedKey()` →
     `_restoreFileMapping()`：只给**本机确实存在**的文件建行（先按 `private_path`，再按 basename 索引兜底路径变化），
     已存在的行只做两件事：`private_path` 修正、以及**从未记录** DEK 且本地文件 `looksEncrypted` 时补上 DEK
     （绝不覆盖已有 DEK —— 文件可能在本包之后被重新加密过）；返回 恢复/更新/跳过 三个计数给 UI；
  ④ 兼容：首字符 `{` 的 v1 JSON 包继续可导入（仅密钥，无映射）。
- 反例 / 易误判:
  - 以为"导入后文件就会出现在库里" ⇒ 只有把保险库文件也拷回原路径/同名，才会建行；找不到文件的条目计为"跳过"；
  - 以为包里多带 DEK 就"更安全" ⇒ 包内 KEK 本来就是明文，DEK 不改变安全边界（**文件 + 包 = 全开**，警告文案已写明）；
  - 无条件插入 `media_keys` 全部行 ⇒ 没拷回文件的设备会出现一堆打不开的空条目（本条明确禁止）；
  - 拿"本机已有加密行"去校验新包：本机为空（刚重装）时必须退回用**包内自己的 DEK** 自检，否则永远 `keyMismatch`。
- 相关文件: `lib/data/services/key_backup_service.dart`（重写）、
  `lib/data/services/vault_storage_service.dart`（新增 `mediaRoots()`）、`lib/application/providers.dart`、
  `lib/presentation/settings/settings_screen.dart`、`lib/l10n/app_localizations.dart`、`pubspec.yaml`（直接依赖 `sqlite3`）
- 相关条目: `ISSUE-036`（v1 语义与拒绝规则）、`ADR-041`、`ADR-042`（随机文件名）、`ADR-047`（本格式决策）
- 首次记录: 2026-10-21（用户需求）

