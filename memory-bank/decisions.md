# 技术决策（decisions / ADR）

> 记录**取舍**：为什么这么定、放弃了什么、后续改动要注意什么。模板见 `README.md` §5。
> 状态只有三种：`已采纳` / `已废弃（被 ADR-xxx 取代）` / `待决`。

## ADR-001 构建辅助 PowerShell 脚本统一放 `scripts\`
- 日期: 2026-09-22 | 状态: 已采纳
- 背景: 7 个 `.ps1`（`build_hash` / `build_mem` / `build_pub_get` / `build_wmi_guard` /
  `build_probe_procs` / `build_probe_toolchain` / `bump_version`）平铺在仓库根，和 `build.bat`、
  `clean.bat`、`upgrade.bat`、APK、`pubspec.yaml` 混在一起
- 决策: 全部 `git mv` 进 `scripts\`（保留重命名历史），`build.bat` 里 29 处引用统一改 `%~dp0scripts\...`
- 理由: 根目录只保留「入口脚本 + 工程文件」；脚本集中便于同步编码规范、检索与搬迁；`git mv` 保历史
- 备选与为何不选: `tools\`（与其它工具语义混淆）、`build\`（会被 `flutter clean` 删，见 `PIT-017`）、
  `scripts\ps1\`（多一层无收益）
- 影响 / 约束: 新增脚本必须放 `scripts\`；改脚本路径要**同时**改调用行和 `if not exist` 探测行
  （漏改即「静默降级」，见 `ISSUE-011`）；脚本内相对路径以 **cmd 当前目录（工程根）** 为基准，
  但 `build_mem.ps1` 的默认日志目录改为「脚本目录的上一级」，否则日志会落在 `scripts\build\`

## ADR-002 含正则/管道的 PowerShell 逻辑一律脚本化 + `-File` 调用
- 日期: 2026-09-22（沿用 09-21 结论） | 状态: 已采纳
- 背景: 本机端点安全策略静默拦截含正则/管道的长 `powershell -Command`（退出码 786、无输出），
  导致哈希为空、版本号不更新（`ISSUE-005` / `ISSUE-006`）
- 决策: 一切「正则替换 / 文件改写 / 哈希计算」都写成 `.ps1`，用
  `powershell -NoProfile -ExecutionPolicy Bypass -File <脚本> -参数` 调用
- 理由: 拦截只针对命令行文本；换成脚本文件即不受影响（已验证）
- 备选与为何不选: 把一行式写短（不可控，仍可能命中）；改用 cmd 原生 `for/f`（做不了正则与 `.NET` IO）
- 影响 / 约束: 新脚本必须 **UTF-8 BOM + CRLF**（`PIT-002`）；调用方必须检查退出码/输出，
  不能假设"没报错就是成功"

## ADR-003 WMI 守卫前置，且失败**直接终止构建**（不是仅警告）
- 日期: 2026-09-22 | 状态: 已采纳
- 背景: `ISSUE-001` —— WMI 无响应时所有 flutter 命令静默挂死，表面像"网络慢"
- 决策: `build.bat :preflight` 在 `:codegen` / `:do_build` / `:gradle_only` / `:clean` 之前统一调用
  `scripts\build_wmi_guard.ps1`；退出码 5 → `WMI_FAILED=1` → 终止（`goto :end`），并在结尾再次提示根因
- 理由: 挂死路径没有可用降级方案，早失败 1 秒出结论 ≫ 白等 5~10 分钟
- 备选与为何不选: 仅警告继续（会挂死）；修复 WMI（需重启/管理员，本机不可控）；
  在 SDK 里硬编码 `hostOsVersion`（09-21 试过，无效，已回滚）
- 影响 / 约束: 被 `call` 的例程里用 `goto :eof` 让调用方收口（避免 `:end` 执行两遍）；
  每次构建只跑一次（`WMI_GUARDED` 去重）

## ADR-004 pub get 一律走「看门狗执行器」`scripts\build_pub_get.ps1`
- 日期: 2026-09-22 | 状态: 已采纳
- 背景: `ISSUE-002`（无限期挂起）与 `ISSUE-003`（失败被当成功）
- 决策: 两处 pub get 都改为调用 `build_pub_get.ps1`：子进程执行 + 20s 心跳 +
  **日志零增长 300s ⇒ 杀进程树 + exit 124**；退出码通过 `[pub-exit] N` 回显解析，解析不到按失败处理
- 理由: 需要「超时兜底」+「可靠退出码」两件事，cmd 自身做不到
- 备选与为何不选: 直接用 cmd 重定向（无超时、退出码不可靠）；用 `timeout` 包装（不会杀进程树）
- 影响 / 约束: 日志固定为 `build\pub_get_codegen.log` / `build\pub_get_build.log`；
  失败判定以 marker 为准；`-IdleTimeoutSec` 可按网络情况调大

## ADR-005 断点续传上限只到步骤 2（`clean` / `pub get` / 编译 每次必跑）
- 日期: 2026-09-22 | 状态: 已采纳
- 背景: `ISSUE-006` —— 续传把编译跳掉，导致复用旧 APK / 切提交后打包失败
- 决策: `:load_state` 中 `RESUME_STEP` 最大为 2；代码哈希变化 → 从头开始；
  Gradle 配置哈希变化 → 从步骤 3 开始
- 理由: 缓存能省时间，但「跳过编译」的代价是**发错包**，不可接受
- 备选与为何不选: 完全取消续传（每次全跑，最稳但最慢）；完全信任 `SAVED_STEP`（出过空跑事故）
- 影响 / 约束: 改这段务必用 `!VAR!` 延迟展开（整块是 `call` 之前一次性解析的，`%VAR%` 取旧值）；
  `:save_state` 前必须补建 `build\`（`flutter clean` 会删掉它）

## ADR-006 内存数据源用 P/Invoke `GlobalMemoryStatusEx`；回收只限「本 JDK 启动且存活 >120s」的 JVM
- 日期: 2026-09-22 | 状态: 已采纳
- 背景: `ISSUE-004`（R8 阶段 OOM）；本机 WMI / `jps` / `Get-Counter` 会挂死（`PIT-011`）
- 决策: `scripts\build_mem.ps1` 用 kernel32 `GlobalMemoryStatusEx` 取内存（与 `hs_err` 日志同口径）；
  `-StopDaemons` 只结束由 `%JAVA_HOME%\bin` 启动、存活 >120s 的 `java/javaw`；
  默认日志 = **工程根** `build\mem_report.log`（不是脚本目录）
- 理由: 数据同口径便于与崩溃日志对照；按可执行文件路径过滤可避免误杀 VS Code / Android Studio 的 JVM
- 备选与为何不选: WMI / jps（挂死）；无条件杀 `java.exe`（会误伤编辑器）
- 影响 / 约束: `MinFreeCommitMB=1500` 只是**警告**阈值，不阻塞构建；
  换 JDK 目录后 `-JavaHome` 传参（`build.bat` 已传 `%JAVA_HOME%`）
- 2026-09-22 调整（复现见 `ISSUE-004` 的复发记录）: 1500MB 阈值不足以预警「R8 中途膨胀」
  —— 本次开局 `FreeCommitMB=6289` 仍崩；同时把内存预算收紧：
  `org.gradle.jvmargs` `-Xmx4G`→`-Xmx3G`、`kotlin.daemon.jvmargs` `-Xmx2G`→`-Xmx1G`，
  并在构建前用 `-StopDaemons` 回收残留 Kotlin 守护进程（本次回收 580MB）

## ADR-007 Release 发布用 `gh` CLI；前置条件不满足一律「跳过」，不算构建失败
- 日期: 2026-09-22 | 状态: 已采纳
- 决策: 无 `gh` / 未登录 / 非 `main` 分支 / `SKIP_RELEASE=1` → 打印原因并跳过；
  同版本已存在 → `release upload --clobber` + `release edit`；新建 → `release create --target <sha> --latest`
- 理由: 发布是"分发"环节，失败不该把已经编好的 APK 判成构建失败
- 备选与为何不选: 直接调 GitHub API 传 token（要管理密钥）；发布失败即构建失败（体验差）
- 影响 / 约束: `GH_EXE` 允许外部预置（自测可用假 gh）；tag 规则 `v<version>`；
  补发用 `build.bat release`（不重新编译）

## ADR-008 产物命名 / 校验：`privi-<version>.apk` + 同名 `.sha256`，APK 不入库
- 日期: 2026-09-22 | 状态: 已采纳
- 决策: 编译成功复制到仓库根 `privi-<version>.apk` 并生成 `privi-<version>.apk.sha256`
  （内容为单行小写 SHA-256，与上游 Release 资产一致）；两者都上传 Release；`.gitignore` 忽略
- 理由: 侧载安装需要稳定命名与可校验性；APK 进库会让仓库膨胀
- 备选与为何不选: 只在 Release 侧生成（本地无法校验/回归）
- 影响 / 约束: `clean.bat` 与 `build.bat` 都会清理 `privi-*.apk*`；
  本机无 `android/key.properties` 时是 debug 密钥，日志里会明确提示签名差异

## ADR-009 AOT 峰值内存：`extraGenSnapshotOptions.add("--no-strip")`
- 日期: 2026-09-21 | 状态: 已采纳（**当前被 AGP 9 阻塞**，见 ISSUE-012）
- 背景: `ISSUE-004` —— gen_snapshot/strip 阶段提交内存耗尽，Gradle 守护进程直接消失
- 决策: 在 `android/app/build.gradle.kts` 的 `flutter { }` 块里加 `--no-strip`
- 理由: 跳过 strip 大幅降低 AOT 峰值内存；代价是 APK 大 1~3MB（比构建崩溃好得多）
- 备选与为何不选: 加内存/加页面文件（机器侧不可控）；关掉 `isMinifyEnabled`（影响功能与体积）
- 影响 / 约束: 与 AGP 9 新 DSL 冲突（`Unresolved reference`）⇒ 迁移 AGP 时必须保留该诉求；
  改动前先看 `scripts\build_mem.ps1` 的内存阈值与 `build\mem_report.log`

## ADR-010 主动跳过 `flutter doctor` / `flutter --version`
- 日期: 2026-09-22（commit `9473cac` / `533800f`） | 状态: 已采纳
- 背景: `ISSUE-013` —— 这两条会触发 SDK 组件下载 / 工具快照重建，本机曾在此静默挂死
- 决策: `build.bat :checkenv` 明确跳过两步并打印「跳过以避免触发工具链下载阻塞」
- 理由: 版本信息在后续 `pub get` / `build` 输出里自然可见，没必要为它冒挂死风险
- 备选与为何不选: 加超时包装（能拿到结论但不必要，且仍可能污染 flutter 缓存）
- 影响 / 约束: 环境诊断改用 `scripts\build_probe_toolchain.ps1`（带硬超时，可单独跑）

## ADR-011 播放器双引擎：ExoPlayer 默认、libVLC 备选，失败自动回退
- 日期: 2026-09-21/22 | 状态: 已采纳
- 背景: 部分容器/编码 ExoPlayer 播不了；libVLC 兼容性更好但接法更脆（`ISSUE-008`）
- 决策: 保留两套引擎（`VideoPlayerHandler` = ExoPlayer，`VlcPlayerHandler` = libVLC），
  设置里可选引擎；播放失败按 `_preferredEngineFor` / `_engineFallbackItemIds` 回退到另一引擎，
  播放器页有 15s watchdog
- 理由: 单一引擎无法覆盖全部素材；回退机制把"播放失败"从死路变成自动降级
- 备选与为何不选: 只用 ExoPlayer（兼容性不够）；只用 VLC（接法与体积代价大，且黑屏类问题更隐蔽）
- 影响 / 约束: 改任一 Handler 都要考虑另一引擎的行为对等；VLC 侧必须传
  `attachViews(listener)` 并同步 `setDefaultBufferSize()`（`ISSUE-008`）

## ADR-012 媒体类型单一真源 `MediaKinds`；删除全局「图片/视频」过滤模式
- 日期: 2026-09-21 | 状态: 已采纳
- 背景: `ISSUE-010`（mime 表分散、太窄 ⇒ 视频入库成图片）；全局过滤模式带来大量分叉代码
- 决策: ①新增 `lib/data/services/media_kinds.dart` 作为扩展名→mime 的唯一真源，
  所有判断委托它；②删除 `MediaKindFilter` 全局模式，**只保留相册类型**（`AlbumKind`）作为过滤手段；
  ③启动维护增加 `_repairMediaKinds()` 修正历史错行（排在视频缩略图修复之前）
- 理由: 真源唯一才能不漏；"全局模式"与"相册类型"语义重叠，删掉可少一半状态与空态文案
- 备选与为何不选: 继续在各处补扩展名表（会继续漏）；保留全局模式（状态爆炸）
- 影响 / 约束: 新增媒体类型只改 `MediaKinds`；`_repairMediaKinds()` 的执行顺序不能动；
  空态文案已换成 `noMediaFolders` / `noMediaInFolder`

## ADR-013 PTS 回绕在 Dart 侧归一化，不动 Kotlin
- 日期: 2026-09-21 | 状态: 已采纳
- 背景: `ISSUE-009` —— 首帧 PTS 带 32 位回绕偏移 ⇒ 位置 > duration ⇒ 被判「已播完」
- 决策: 在 `native_video_controller.dart` 内做：`_timelineOffsetMs` 记录偏移 +
  `_contentPositionMs()` 归一化（无偏移时 no-op）+ `_probeSeekAxis()` 一次性探针确定 `seekTo` 坐标系
- 理由: 问题在"两条时间轴不一致"，属 Dart 侧语义；Kotlin 侧保持"原样上报"更简单也更好复用；
  无偏移文件行为完全不变，回归风险最低
- 备选与为何不选: 在 Kotlin `getPosition()` 里减偏移（会污染原生层语义、影响其它调用方）；
  按文件特征猜测（不可靠）
- 影响 / 约束: 新增任何"读位置"的代码路径都必须走归一化；`VDIAG[timeline-offset]` /
  `VDIAG[seek-axis]` 是排查入口

## ADR-014 诊断日志 `VDIAG` 写入用户可见目录，按天分卷保留 7 天
- 日期: 2026-09-21 | 状态: 已采纳
- 背景: 用户报播放问题时拿不到日志（没有 adb、不方便复现）
- 决策: `AppLogger` 写 `/storage/emulated/0/Download/密册/logs/密册_log_YYYY-MM-DD.txt`
  （不可写时退到应用私有目录并在日志里写明路径）；播放链路输出单行 `VDIAG[...]` 汇总，
  开关在「设置 → 诊断 → 诊断日志」
- 理由: 用户可直接把 txt 发回来定位，不需要现场复现
- 备选与为何不选: 只写 logcat（需要 adb）；写应用私有目录（用户取不到）
- 影响 / 约束: 新增诊断字段要同时更新文档；日志开关关闭时一行都不写（排查前先确认开关）

## ADR-015 知识库制度：`memory-bank/` + `.clinerules` 强制「开工先读、收工必写」
- 日期: 2026-09-22 | 状态: 已采纳
- 背景: 同一批问题（WMI 挂死、786 拦截、编码、AGP…）被反复重新排查；`docs/HANDOFF-*.md` 是
  一次性长文且被 `.gitignore` 忽略，跨会话不可复用
- 决策: 建立 `memory-bank/`（`README.md` 协议与索引 + `issues-solved.md` + `pitfalls.md` + `decisions.md`），
  在 `.clinerules/` 里强制"任务开始先查库、结束必须回填"，条目统一模板、编号递增、永不删旧条目
- 理由: 结论与「复发判据」沉淀成可检索的短条目，比重新读日志/长文快一个数量级
- 备选与为何不选: 全靠 `docs/HANDOFF-*.md`（gitignore、不进 git、篇幅长难检索）；
  只写 `.clinerules`（规则里塞不下历史结论）；上外部 wiki（本仓库是单人本地项目）
- 影响 / 约束: **任何任务结束都要更新 memory-bank**；发现老条目与现场矛盾时更新原条目而不是新建；
  不写 token/密钥；`docs/` 仍作为过程记录保留

## ADR-018 Flutter 3.47 移除 `extraGenSnapshotOptions` DSL ⇒ 改用 Gradle project property
- 日期: 2026-09-22 | 状态: 已采纳
- 背景: `ISSUE-012` —— `flutter build apk --release` 在 `android/app/build.gradle.kts` 的
  `flutter { extraGenSnapshotOptions.add("--no-strip") }` 处报 `Unresolved reference`，release 构建恒失败；
  而 `--no-strip` 正是 `ADR-009` 为压 AOT 峰值内存加的（`ISSUE-004` 的 OOM 缓解）
- 决策: ①删掉该 DSL 调用（保留 `flutter { source = "../.." }`，并在原处留注释禁止写回）；
  ②把 `--no-strip` 配置到 `android/gradle.properties`：`extra-gen-snapshot-options=--no-strip`
- 理由: Flutter 3.47 起 flutter-gradle-plugin 改为
  `project.findProperty("extra-gen-snapshot-options")`（`FlutterPlugin.kt:640`）取值，
  再经 `BaseFlutterTaskHelper.kt:140` 以 `--ExtraGenSnapshotOptions=` 传给 flutter tool；
  gradle.properties 的键本身就是 project property ⇒ 改动最小、不动 AGP/Gradle 版本、与原来行为一致
- 备选与为何不选: ①回退 AGP/Kotlin/Gradle 组合（改动面大、要重下依赖，且 AGP 8 与 Gradle 9 不兼容）；
  ②改从命令行传 `-P`（`build.bat` 里稳定注入很脆）；③干脆不要 `--no-strip`（会退回 `ISSUE-004` 的 OOM 风险）
- 影响 / 约束: **不要再往 `flutter { }` 里加已删除的 DSL 属性**；升级 Flutter 后若键名变化，
  以 SDK 源码里的 `project.findProperty(...)` 为准；`android.newDsl=false` 与本条无关（本就设着）

## ADR-019 Cline 工作临时产物统一放仓库根 `tmp\`
- 日期: 2026-09-22 | 状态: 已采纳
- 背景: 任务过程中的中间产物（命令输出重定向、临时 ps1/bat、状态/轮询文件、探针日志）此前散落在**仓库根**：
  本次会话前后在根目录生成过 40+ 个文件（`_apply_*.ps1`、`_enc_*.ps1`、`ps1refs*.txt`、`git_*.txt`、
  `st*.txt`、`cpu*.txt`、`push*.txt`…），每轮都要人工辨认+逐个删除；交接文档的收尾清单里也专门有一条
  「删掉仓库根目录的一次性产物」（`PIT-022`）。`git status` 噪声大，且存在误删业务文件的风险
- 决策:
  ① 规则写入 `.clinerules/tmp-files.md`，并在 `.clinerules/rules.md` 加一条强制引用；
  ② 一切中间文件写 `tmp\`（相对路径 `tmp\x.txt`，绝对路径 `D:\WorkSpace\test\privi\tmp\x.txt`），
  **禁止**散落在仓库根 / `lib\` / `android\` / `scripts\` / `docs\` / `memory-bank\`；
  ③ `.gitignore` 加 `/tmp/`（整目录忽略、不入库，可放心当垃圾桶）；
  ④ `clean.bat` 与 `build.bat clean` 都增加「整目录删除 `tmp\`」的清理步骤
- 理由: 集中目录 ⇒ `git status` 只看真实改动、清理是一条命令、不会误删业务文件；
  且 `tmp\` 与 `build\`（同样是可丢弃产物目录）语义一致，符合本仓库既有习惯
- 备选与为何不选: ①继续放根目录（就是现在的问题）；②放 `build\`（`flutter clean` 会删、且会被误当构建产物，
  见 `PIT-017`）；③放系统临时目录（跨会话找不到、也无法随仓库一起清理）；④放 `docs\`（是"留存文档"的语义）
- 影响 / 约束:
  - 规范**例外**（不是临时文件，不要往 `tmp\` 塞）：构建脚本自身日志 → `build\`；知识库 → `memory-bank\`；
    交接文档 → `docs\HANDOFF-*.md`；长期复用的脚本 → `scripts\`（新增脚本要同步 `build.bat` 路径，见 `ISSUE-011`）
  - 任务收尾必须清空 `tmp\`，并在回复里说明是否已清空
  - 验证方式：`git check-ignore -v tmp\x.txt` 命中 `.gitignore:/tmp/`；`git status` 不应出现 `tmp\` 内文件

## ADR-016 AGP 9.1.0 / Gradle 9.3.1 / Kotlin 2.4.0 版本组合与 `newDsl` 迁移
- 日期: 2026-09-22 | 状态: **已结案**（2026-09-22；版本组合保持不变，只改配置点，见 `ADR-018`）
- 背景: `android/settings.gradle.kts` 固定 AGP 9.1.0 + Kotlin 2.4.0，
  `gradle-wrapper.properties` 指向 Gradle 9.3.1；AGP 9 默认 `android.newDsl=true`，
  `android { }` 旧 DSL 被废弃（AGP 10 移除），`flutter { extraGenSnapshotOptions }` 解析失败
- 候选方案: ①**回退** AGP/Kotlin/Gradle 到 `--no-strip`（ADR-009）可用的组合，先恢复可发布状态；
  ②**前向迁移**：按 AGP 9 新 DSL 改写 `android/app/build.gradle.kts`，并找 `--no-strip` 的等价做法
  （可能要在 `flutter build` 参数或 Gradle 侧另找落点）
- 决策前必须做: 先跑通一次 `flutter build apk --release` 拿到绿；把结论回填为本条目的正式决策
- 影响 / 约束: 在此之前 **release 构建恒失败**（`BUILD_FAILED=1`，与 WMI/内存无关），
  自测时不要把它误判成搬迁或环境问题

## ADR-017 三个视频入口统一「15s 看门狗 + 单次引擎回退」，实现抽成 mixin
- 日期: 2026-09-22 | 状态: 已采纳
- 背景: `ISSUE-014` —— `PlayerScreen` 有 watchdog + VLC→ExoPlayer 回退，另外两个入口（viewer / gallery 预览）
  是裸调用，同一份代码在三个入口行为不一致；Kotlin 侧根因（`ISSUE-008`）修完也救不了没有回退的入口
- 决策: 新增 `lib/presentation/player/engine_fallback.dart`，用 mixin `VideoEngineFallbackState`
  统一三件事：`engineFor(itemId)`（引擎选择 + 回退集合）、`armLoadWatchdog`（15s，可替换上一个）、
  `fallbackToDefaultEngineIfPossible`（单次回退决策）；三处 `ConsumerState` 统一 `with ...` 复用；
  **回退策略 = 第一次超时就直接换引擎**，并把该 item 记进集合（每 item 只换一次）；
  各屏自己的"重试后怎么显示"保留在屏内（viewer 新增错误态、gallery 复用 `_error`/`_loading`）
- 理由: 只有行为一致，用户才不会因为"从哪个入口进去"而看到不同结果；同引擎重试大概率同样结果；
  每 item 只换一次可避免在黑屏/重建之间来回摆；mixin 只抽公共状态与计时器，状态机仍留在各屏，风险最小
- 备选与为何不选: ①各屏各写一份（必然漂移，这次就是漂移的结果）；②把整段 retry 流程也抽走
  （三个屏的请求序号/播放列表/错误 UI 差异大，抽走反而更难维护）；③在 Kotlin 侧统一兜底
  （VLC 侧没有 surface 自愈，无法覆盖"根本没出帧"）
- 影响 / 约束: **新增/修改任何视频入口都必须 `with VideoEngineFallbackState<X>` 并走 `engineFor(itemId)`**，
  不要裸读 `settings.playerEngine`（`player_screen.dart` 里已留注释提示）；
  重试路径必须带请求序号校验；错误文案目前与 `PlayerScreen` 一致用英文
  （l10n 暂无对应 key，属已知欠账，改动 l10n 需要同步 `app_localizations.dart`）

## ADR-020 VLC 回调一律"按当前这一轮播放"做身份校验；libvlc 线程异常就地吞；崩溃留痕
- 日期: 2026-09-22 | 状态: 已采纳
- 背景: `ISSUE-015` —— 快速切片时偶现**进程级崩溃**（日志里上一段停在 `onPlaying`，下一段就是新 session，
  中间零错误行）。定位到 `VlcPlayerHandler` 把 libvlc 事件/布局回调 `mainHandler.post` 到主线程时，
  lambda 捕获了 `MediaPlayer mp`，而 `release()` 之后**已入队的回调仍会执行**并读
  `mp.length` / `mp.time` / `mp.isPlaying` —— 这三个是 native 方法，在已释放的 native 句柄上做 JNI 调用
- 决策:
  ① 所有跨线程回调（libvlc 事件线程 / vout 线程 → 主线程）**必须**带身份校验
     `if (mediaPlayer !== mp) return@post`，与既有 `probeVideoSizeAsync` 的写法统一；
     `onMediaPlayerEvent()` 入口再兜一层，任何新增调用点都不会绕过；
  ② 回调体（尤其跑在 libvlc 事件线程上的）整段 `try/catch`：那里异常逃出去 = 进程级崩溃；
  ③ `resetPlayer()` 在 `stop()` 之后显式 `setEventListener(null)`（libvlc 的既定 detach 用法，javap 已确认），
     压缩"入队即过期"的回调数量；
  ④ 共享 `LibVLC` 的释放必须在 IO 线程池收尾之后（`ioExecutor.shutdown()` + `awaitTermination(1s)`），
     因为后台 `media.parse()` 用的是同一个 native 实例；
  ⑤ Java/Kotlin 未捕获异常统一落盘到 `Download/密册/logs/密册_crash_<日期>.txt`
     （`Thread.setDefaultUncaughtExceptionHandler`，保留原 handler 不改变崩溃行为）
- 理由: 「偶现崩溃」的排查成本远高于防护成本；而且这类崩溃**没有 Dart 日志**，没有留痕就只能靠猜。
  身份校验是零成本的（一次引用比较），不会改变任何正常路径的行为
- 备选与为何不选: ①把回调都改成 `Handler.removeCallbacksAndMessages(null)` 清理
  （resetPlayer 时清队列确实能覆盖本场景，但粒度太粗、会误删其它消息）；
  ②改成在 `release()` 之前 sleep 等回调排空（时序赌博，慢机器上照样崩）；
  ③让 Dart 侧"别切那么快"（治不了偶发，且用户体验倒挂）
- 影响 / 约束:
  - **新增任何 libvlc/ExoPlayer 回调都必须带"当前这一轮播放"的身份校验**，别直接读 native 字段；
  - 崩溃兜底只覆盖 Java/Kotlin 层：**native SIGSEGV 只进 logcat/tombstone**，
    下次若 `密册_crash_*.txt` 没有新增、但日志里又出现"新 session + 上一段无错误行"，
    说明是 native 崩溃，需要连电脑取 logcat（`adb logcat -b crash`）
  - 崩溃日志文件名是 `密册_crash_<日期>.txt`，与 Dart 的 `密册_log_<日期>.txt` 分开放，
    避免两边同时写同一文件

## ADR-021 发布流程：先给 `main` 打 `backup_YYYYMMDD` 快照，再用 `--ff-only` 把 `dev` 提升进 `main`
- 日期: 2026-09-22 | 状态: 已采纳
- 背景: 需要一条固定的"提测/发布"动作：留一份 `main` 的快照，再把 `dev` 的提升上去、在 `main` 上出包。
  本轮实操：`dev` 领先 `main` **24 个提交**（含 `ISSUE-015` 的 VLC 崩溃修复），`main` 是 `dev` 的祖先
- 决策:
  ①提升**之前**先打快照：`git branch backup_YYYYMMDD main` + `git push -u origin backup_YYYYMMDD`
  （日期取当天，如 `backup_20260922`；同名已存在就说明当天已打过，**不覆盖、直接复用**）；
  ②`git checkout main` → `git merge --ff-only dev`（**只允许快进**）；
  ③构建在 `main` 上跑（`build.bat norelease` 跑完整流程但不对外发 Release）；
  ④版本号递增由构建脚本产生（`pubspec.yaml` 的 `version:`），**构建成功后再单独提交 bump**；
  ⑤`git push origin main`，并确认 `git branch -vv` 里三个分支都与 origin 对齐
- 理由: 备份分支给"合错了要回退"留一条 5 秒的退路（`git reset --hard backup_YYYYMMDD` + 强推即可，
  比翻 reflog 靠谱）；`--ff-only` 保证 `main` 永远是 `dev` 历史的子集 ⇒ 线性历史、回滚点唯一、
  不会出现"两个人各造一个 merge commit"的分叉
- 备选与为何不选: ①`--no-ff` 合并提交（多一层无信息量的节点，回滚还要多退一步）；
  ②打 tag 代替分支（tag 不能继续提交，且本节要的是"可对照/可回退的副本"）；
  ③不备份直接合（回退只能靠 reflog）；④把构建出的 APK 一起入库（`.gitignore` 已有 `/privi-*.apk`，
  APK 走 GitHub Release 分发，见 `ISSUE-006`/`ISSUE-007` 的历史决策）
- 影响 / 约束:
  - 备份分支名固定 `backup_YYYYMMDD`，**不要删**（除非用户明确说）；同名冲突时先确认是不是同一天的快照
  - `--ff-only` 失败（说明 `main` 上有 `dev` 没有的提交）时**必须停下来**看 `git log --oneline main..dev` /
    `dev..main`，人工决定是合并还是回退，**不要**改成普通 `git merge` 蒙过去
  - 构建会改 `pubspec.yaml` 的 `version:` ⇒ 绿构建之后**先在当前分支提交 bump 再推送**，
    然后把另一个分支**快进过来**（`git checkout dev && git merge --ff-only main && git push origin dev`），
    让 `main`/`dev` 回到同一提交 —— 否则 bump 提交会让 `main` 领先 `dev`、下轮 `--ff-only` 直接失败
  - 本轮记录: `backup_20260922` = `8903ef1`；`main` 由 `8903ef1` 快进到 `4c280c2`（35 files, +3320/−122），
    随后未加修改地推送（`8903ef1..4c280c2  main -> main`）—— 因为 `ISSUE-001`（WMI 挂死）导致
    `main` 上的构建没跑起来，所以这次没有版本号 bump 提交
  - 2026-10-07 记录（本轮推送，全按本 ADR 走）: 工作区一次性提交 `6f48328`
    （三段式版本号 + versionCode 推导 + 可见库滑动操作 + 记忆库/`.clinerules`，20 files, +386/−168），
    `git push origin main` → `ae4b5e1..6f48328  main -> main`；
    再 `git checkout dev` + `git merge --ff-only main`（`8e1ea91..6f48328  Fast-forward`，26 files）
    + `git push origin dev` → `8e1ea91..6f48328  dev -> dev` ⇒ `main`/`dev` 回到同一提交 `6f48328`
    （此前 `main` 领先 `dev` 6 个提交，这次一并补齐）。
    **没有**新建 `backup_YYYYMMDD`：当天快照 `backup_20261007 = e192268` 已存在，按"同名不覆盖、直接复用"。
    注：本次提交的 `pubspec.yaml` 是 `1.0.60`（上一轮验证 `bump_version.ps1` 的实测运行把 1.0.59 抬到了 1.0.60），
    而已成功构建的产物是 `1.0.59`（versionCode 10059）；版本号只增不减，下次构建产出 `1.0.61`。
- 2026-10-07 记录（第二轮：播放区横向滑动快进/快退）: 工作区一次性提交 `1004a89`
  （`feat: 播放区右滑快进/左滑快退（一档 = 设置的跳转步长）+ memory-bank 回填`，8 files, +268/−3），
  `git push origin main` ⇒ `origin/main` = `1004a89`（`refs/remotes/origin/main` 立刻刷新，可见）；
  再 `git checkout dev` + `git merge --ff-only main`（`8fde665..1004a89  Fast-forward`，同样 8 files）
  + `git push origin dev` ⇒ `refs/remotes/origin/dev` 的 reflog 出现
  `8fde665…1004a89… update by push`（ref 文件滞后十几秒才刷新 —— 复核手法见 `PIT-008` 复核第二轮）；
  最后 `git checkout main` 收尾 ⇒ `main` / `dev` / `origin/main` / `origin/dev` 四者同为 `1004a89`、工作区干净。
  同样**没有**新建 backup 分支（当天 `backup_20261007 = e192268` 已存在，按①复用）；
  本次**没有**版本号 bump（未跑构建）：`pubspec.yaml` 仍是 `1.0.60`，下次构建产出 `1.0.61`。
- 2026-10-07 修订（第三轮推送起，见 `ADR-030`）: 推送约定改为「**只推当前分支**」，
  所以上面①、⑤两步要**拆成单分支多次推**：先 `git push origin main`；需要同步 `dev` 时再单独
  `git checkout dev && git merge --ff-only main && git push origin dev`。
  只推 `main` 时 `dev` / `origin/dev` 落后于 `main` 属**预期**（下轮发版时按上面那条补齐），
  不再是"必须当场对齐"；`backup_*` 的创建/推送仍按①（用 `git push -u origin backup_YYYYMMDD`，属单分支推送）。

## ADR-022 VLC 视频几何：**先探测尺寸、再挂 vout**（几何只定一次）
- 日期: 2026-10-01 | 状态: 已采纳
- 背景: `ISSUE-016` —— VLC 引擎下非 1920x1080 的片子（竖屏 720x960）画面只显示一小块。
  旧顺序是「`initialize()` 里立刻用常量 1920x1080 `setDefaultBufferSize()` +
  `setWindowSize()` 并 attachViews，之后再由后台 `media.parse()` 改尺寸」；而本机实测
  **布局回调（`OnNewVideoLayoutListener`）一条都没来过**（整份日志零 `video layout:` 行），
  几何只剩"常量"和"探测"两个来源，顺序一颠倒就自相矛盾。
- 决策: `initialize()` 拆成「建 MediaPlayer/Media → io 线程探测尺寸 → 主线程
  `attachViewsAndPlay()`」；探测结果先经 `applyVideoSize()` 落到 `videoWidth/Height`，
  **同一个尺寸**同时用于 `setDefaultBufferSize()` 与 `setWindowSize()`；探测失败/超时
  （`PROBE_TIMEOUT_MS = 2000`）才退回常量兜底。探测期间 `play()` / `pause()` 只记录意图
  （`attachPending` / `playRequested`），挂上视图后统一执行。
- 理由: ANativeWindow 的两条 vout 路径都在**开 vout 时**（`AndroidWindow_Setup()`）把布局
  定死，此后每帧只校验缓冲区不小于 fmt —— 缓冲区被改小**不会**触发重算布局，只会裁画面。
  让几何在 vout 存在之前就正确，是唯一不依赖 VLC 内部行为"重算"的方案。
- 备选与为何不选: ①探测回来后 `detachViews()` + `attachViews()` 重挂（要赌 libvlc 是否会按
  新 `setWindowSize` 重建 vout，未验证；还会打断正在播的画面）；②干脆不探测、永远用
  1920x1080（竖屏片被 pillarbox、宽高比也上报错，方向会被锁成横屏）；③在**主线程**同步
  `media.parse()`（ANR 风险，原注释已明确禁止）。
- 影响 / 约束: `initialize()` 的"挂视图 + 起播"变成异步（实测本地文件 33~141ms，最坏到
  `PROBE_TIMEOUT_MS`）；Dart 侧 15s 加载看门狗足以覆盖。**新增任何"改缓冲区尺寸"的代码都
  必须同时改 `setWindowSize()`**，否则又会回到老问题。`layoutSizeKnown` 标志随旧探测路径
  一起删除（它只为"挂上后再探测"服务）。
- 回归观察点（下轮真机日志）: `video surface attached ... at <宽>x<高>` 应该等于该视频的真实
  尺寸（竖屏片应是 `720x960`），而不是恒定的 `1920x1080`；日志应出现
  `probed video size (before attach): ...`。

## ADR-023 长按视频的「打开方式」拆成两个内部入口 + **单条视频**的引擎覆盖
- 日期: 2026-10-01 | 状态: 已采纳
- 背景: 原来长按菜单只有一条「应用内播放」（`VideoOpenTarget.internal`），用设置里的引擎。
  用户需要"就这一个片子用 VLC 在应用内播放"，不想改全局设置。
- 决策: `VideoOpenTarget` 拆成 `internalDefaultEngine` / `internalVlcEngine`，文案
  「内部播放（默认引擎）」/「内部播放（VLC 引擎）」；两条入口的引擎**写死**
  （`kSheetDefaultEngine = PlayerEngine.exoPlayer` / `kVlcEngine`）+ `forceEngineForItem()`，
  **不读** `settings.playerEngine`；入口把 `initialForcedEngine` 传给 `ViewerScreen` /
  `GalleryPreviewScreen`，由它们在 `initState` 里对**当前这一条**注册。
- 修订（2026-10-01，用户反馈）: 第一版让「默认引擎」那条**跟随设置**、并把设置里的引擎名
  放在副标题消歧。设置本来就是 libVLC 时，两条入口引擎相同、只是一条标着"默认" ——
  在用户看来就是**两个重复且一样的选项**。改成两条都写死后，副标题固定显示
  `ExoPlayer（系统解码器）`，任何时候两条都指向不同引擎。
  副作用（有意为之）: 设置里的引擎只影响"点开视频直接播放"与播放列表，
  **不再影响**长按菜单这两条捷径。
- 理由: 覆盖只作用于用户长按的那一条 ⇒ 不写设置、不影响别的视频；`useEngineFallback()` 会
  清掉强制值，所以「强制 VLC ⇒ 15s 拿不到帧 ⇒ 换默认引擎」这条回退**仍然生效**。
- 备选与为何不选: ①按"本次播放会话"覆盖（进入该界面后所有视频都用 VLC）—— 语义模糊、
  会悄悄改变其它视频的行为；②直接把设置改成 VLC（污染全局偏好）；③再加一层
  "仅此一次 / 记住选择"对话框（本轮不需要）。
- 影响 / 约束: 新增视频入口若要支持强制引擎，必须把 `initialForcedEngine` 往下传；
  引擎名文案统一走 `videoEngineLabel()`（设置页仍保留自己的私有实现，未强行合并）。

## ADR-024 私密相册「滑动操作」：自研 `SwipeActionCell` + 「操作」按钮复用长按行为
- 日期: 2026-10-07 | 状态: 已采纳
- 背景: 需求 —— 私密相册里的图片/视频项向左滑动后在**右侧**露出「操作」「删除」两个按钮；
  点「删除」删除本项；点「操作」弹出与长按相同的选项并执行所选功能；
  同时把视频长按弹框里的「选择」项去掉。
- 决策:
  ① **不新增依赖**，自研 `lib/presentation/common/swipe_action_cell.dart`：
     `AnimationController`（0→1 表示滑开程度）+ `Transform.translate` 平移前景，
     按钮层用 `PositionedDirectional(end: 0)` 固定在右侧；打开状态由父级持有
     （`MediaGridScreen._openSwipeId`）⇒ 同屏最多一行展开，手势结束时通过 `onOpenChanged` 回写。
  ② 按钮语义：删除 = 普通相册 `softDeleteMany([id])`（进回收站）、回收站 `purgeMany([id])`（永久删除），
     与选中模式下的浮动胶囊完全一致；「操作」= 直接复用长按入口
     （`_handleItemAction`：视频 → 「打开方式」弹框且只播放这一项；图片 → 进入多选，
     与"长按图片"原行为一致）。
  ③ 「选择」项**只从私密相册**的弹框里去掉：`showVideoOpenTargetSheet` 新增 `showSelection = true`
     参数，`media_grid_screen.dart` 传 `false`；可见库（`visible_media_grid.dart`）保持原样
     （它的「选择」是长按视频时唯一的进多选入口之一，去掉会削弱功能）。
- 理由: 滑动操作是"单项、就地"的交互，与选中模式的多选语义正交 ⇒ 用父级单一 `_openSwipeId` 即可保证
  "同时只开一行"，且不引入依赖；「操作」按钮与长按共用同一个方法，避免两套入口行为漂移。
- 备选与为何不选: ①`flutter_slidable`（新依赖要过 `pub get`，本机 WMI 不稳；网格窄格样式仍要自己调）；
  ②`Dismissible`（只能整项划走/回弹，停不到"露出按钮"的中间状态）；
  ③把「操作」「删除」分放两侧（用户明确要求都在右侧）。
- 影响 / 约束:
  - 多选态下禁用滑动（`enabled: !selecting`），已展开的行在进入多选时自动收起；
  - 网格模式下 cell 宽度只有约 1/3 屏，按钮宽度按 cell 宽度自适应
    （每格 `0.34×宽`，clamp 到 44~88dp，且总宽 ≤ cell 宽的 78%，保证海报仍可见）；
    文案只有 2 字（「操作」/「删除」，回收站为 4 字「永久删除」并用 `FittedBox` 缩放）；
  - 点已展开的行 = 先收起（不打开 viewer）；长按任一项也会先收起已展开的行；
  - `SwipeActionCell` 放在 `presentation/common/`，可见库以后要接滑动可直接复用。
- 首次记录: 2026-10-07
- 修订 2026-10-07（第二轮，用户反馈）:
  ① **「操作」按钮 = 进入多选**，不再复用长按行为：私密相册与可见库统一调 `enter(id)`/`_enterSelect(id)`，
     视频也一样 —— 因为长按弹框的「选择」项被彻底移除（见 ②），长按视频只负责播放选择。
  ② **「选择」项全局移除**：`VideoOpenTarget.selection` 枚举值、`showSelection` 参数、sheet 里的
     ListTile、以及两处 `switch` 的 case 全部删除（可见库也删，不再只针对私密相册）。
     进多选的入口变成：行左滑「操作」/ ⋮ 菜单「选择」/ 长按图片。
  ③ **收起时绝不能看见按钮**（用户能看到底层按钮）：按钮层透明度跟随滑动进度（`Opacity(t)`）
     + 从右边界滑入（`Transform.translate(Offset(strip * (1 - t), 0))`），
     并在 Stack 最底铺一层 `ColoredBox(vaultColors.surface)` —— 列表模式的行本来是
     `Colors.transparent`，没有这层就会透出按钮。
     **按钮层必须仍是 `PositionedDirectional`，不能换成 `Align`**：`ListView` 给 item 的高度约束无界，
     `Align` 会撑到 ∞（列表模式下必炸）。
  ④ 滑动操作已覆盖**两个媒体网格**：`MediaGridScreen`（全部媒体/收藏/回收站/用户相册）与
     `VisibleMediaGrid`（系统相册）；可见库的「删除」沿用原有流程（确认框 + `PhotoManager.editor.deleteWithIds`，
     系统可能再弹一次确认），逻辑抽成 `_deleteAssetIds()` 供选中删除与单行删除共用。
- 修订验证: `dart analyze <4 文件>` → `No issues found!`；`dart format --set-exit-if-changed` 解析通过

## ADR-025 视频进度条两端显示时间：左=当前进度、右=总时长（横竖屏都显示）
- 日期: 2026-10-07 | 状态: 已采纳
- 背景: 需求 —— 视频控制条上"在进度条两端显示时间"：左侧播放进度时间，右侧视频总时长。
  原实现只有一行合并的 `0:12/3:45`（`formatVideoProgress()`），且**只在竖屏**显示
  （`if (!widget.landscape)`）。
- 决策: `NativeVideoBottomControls`（`lib/presentation/player/video_player_controls.dart`）把那一行
  拆成 `Row(mainAxisAlignment: MainAxisAlignment.spaceBetween)` 的两个 `_timeLabel`：
  左侧 `formatVideoTime(_scrubbing ? positionMs : value.position)`（拖动时跟随 scrub 位置），
  右侧 `formatVideoTime(value.duration)`；并**去掉 landscape 条件**，横屏同样显示。
- 理由: 该控件被**三处**播放界面复用（`player_screen.dart:983`、`viewer_screen.dart:677`、
  `gallery_preview_screen.dart:532`）⇒ 改一处即全部生效；`_timeLabel` 已带
  `FontFeature.tabularFigures()`，时间数字等宽、秒数跳动时不抖。
- 备选与为何不选: ①保留 `0:12/3:45` 单标签（正是要改掉的形态）；
  ②只改竖屏（横屏看不到总长，与"进度条两端"不符）；③把文字叠在 `Slider` 上（挡住滑块、影响命中）。
- 影响 / 约束: `formatVideoProgress()` 随之**不再被使用**（保留在 `video_player_surface.dart`，
  与同样未被使用的 `formatVideoDelta()` 并列，未删）；横屏底部控制条因此高约 21dp，
  若嫌挤，恢复 `if (!widget.landscape)` 即可。`widget.landscape` 仍用于图标切换，未变成死字段。
- 首次记录: 2026-10-07

## ADR-026 版本号：`pubspec.yaml` 单一来源的三段式 `1.0.x`（去掉 `+build`），versionCode 由 versionName 推导
- 日期: 2026-10-07 | 状态: 已采纳
- 背景: 产物一直是 `privi-1.0.30+59.apk` 这种「三段式 `+build`」形式（`pubspec.yaml`
  里 `version: 1.0.30+59`）：文件名/tag/设置页三处展示不一致，人看不出哪个才是"版本"。
  要求统一成 `1.0.59`（产物 `privi-1.0.59.apk`），**不带 `+数字`**。
- 决策:
  ① `pubspec.yaml` 只留三段式 `version: 1.0.59`，**不再有 `+build` 后缀**；
  ② `scripts\bump_version.ps1` 改为「最后一段 +1」（`1.0.59` → `1.0.60`），不再需要 `-BuildNumber`；
  ③ `build.bat :increment_version` 删掉 `.BUILD_NUM`（第二个版本来源），校验改成
     「回读 pubspec，版本号必须真的变了」（旧命令 `-BuildNumber 999` 已失效，见 `ISSUE-005` 修订）；
  ④ **Android `versionCode` 在 `android/app/build.gradle.kts` 里由 versionName 推导**：
     `major*10000 + minor*100 + patch`（`1.0.59` → 10059，每次构建单调递增）；
  ⑤ 应用内只显示 `1.0.59`（不再显示 `(buildNumber)`），versionCode 只出现在启动日志里。
- 理由: 版本号只有一个来源（`pubspec.yaml`）才不会有 `ISSUE-005` 那种"两个号漂移"；
  versionCode 必须单调递增，否则覆盖安装/升级会被系统拒绝。
- 备选与为何不选:
  ① **只改文件名、不动 gradle**：pubspec 没有 `+build` 时 `flutter build apk` 会**删掉**
     `local.properties` 里的 `flutter.versionCode`，Flutter Gradle 插件回退成 **1**
     ⇒ 装过 versionCode 59 的手机全部报 `INSTALL_FAILED_VERSION_DOWNGRADE`。
     **这是本次必须改 gradle 的唯一原因**，详见 `PIT-027`；
  ② 保留 `.BUILD_NUM` 当 versionCode、用 `-PbuildNumber=` 传给 gradle：多一个状态文件、多一条漂移路径；
  ③ `versionCode = patch`（59 → 60）：主/次版本一升就回退（`1.1.0` → 0），不可取；
  ④ 继续用 `1.0.30+59`（需求明确不要）。
- 影响 / 约束:
  - 改版本号只动 `pubspec.yaml` 一行；**不要再引入第二个版本来源**；
  - 公式上限：patch ≤ 99、minor ≤ 99，超了要换公式；
  - 旧 `1.0.30+59` 仍可被 `bump_version.ps1` 解析（正则取前三段、丢弃 `+build`），迁移期不会炸；
  - 历史 tag `v1.0.30+59` 保留不动；新 tag 形如 `v1.0.60`（`build.bat` 的 `RELEASE_TAG=v!NEW_VER!` 无需改）；
  - 设置页「关于」与列表项显示 `v1.0.59`；`AppBuildInfo` 的 `buildNumber` 字段已随本次改动移除。
- 验证状态（2026-10-07）:
  - **已实测**: ①`bump_version.ps1` → `OK=1.0.59->1.0.60`，旧格式输入 `OK=1.0.30->1.0.31`；
    ②`flutter build apk` 已把 `android\local.properties` 改成只剩 `flutter.versionName=1.0.59`、
    **`flutter.versionCode` 被删除**（`PIT-027` 的证据，亲眼在文件里确认）；
    ③改动的 `.ps1` 仍是 UTF-8 BOM + CRLF、`.bat` 无 BOM、四个 memory-bank 文件无 BOM + CRLF、`bareLF=0`；
    ④`dart format --output=show` 对比（忽略 EOL）显示本次改的 Dart 代码无额外格式差异。
  - **未完成（收尾时构建仍在跑）** → **已补测通过（同日 20:40 构建完成后）**:
    `build.bat gradle` 实际成功（`build\build_exit.log` = `周三 2026/10/07 20:40:02.73 BUILD_FAILED=0 WMI_FAILED=0`），
    且 `D:\Tools\DevTools\Android\Sdk\build-tools\36.0.0\aapt2.exe dump badging build\app\outputs\flutter-apk\app-release.apk`
    → `package: name='com.privi.app' versionCode='10059' versionName='1.0.59'`
    ⇒ 派生公式、命名链路、覆盖安装的 versionCode 单调性**端到端打通**（不再是 `versionCode='1'`）。
    （收尾途中一度以为构建还没结束，是终端回显滞后导致的误判 —— 以 `build\build_exit.log` 的 mtime/内容为准。）
- 首次记录: 2026-10-07

## ADR-027 构建一律由用户手工执行，Cline 默认不跑构建（自测 = 静态验证）
- 日期: 2026-10-07 | 状态: 已采纳
- 背景: 本仓库构建太慢（全量/首次 15~25 分钟：`build_runner` AOT 200s+、`assembleRelease` 700s 量级），
  本机还常遇 WMI 静默挂死（`ISSUE-001`）；Cline 每轮"改完就跑构建"会把时间几乎全耗在等待/轮询上，
  而且容易和用户手工点的那次构建撞车（互删 `build\`、抢 `build_full.log`，见 `PIT-023`）。
- 决策:
  ① Cline **不主动运行任何构建类命令**（`build.bat` / `build.bat gradle` / `fast` / `norelease` /
     `flutter build apk` / `flutter clean` …），只有用户当场明确要求（"跑一下构建"/"build 一下"）才例外；
  ② 改完的默认自测 = **静态验证**：`dart format --output=none --set-exit-if-changed <改动文件>`（语法）
     + `dart analyze <改动文件>`（类型/静态；实测可用，几秒出 `No issues found!`；
     `dart.exe` 全路径 = `%FLUTTER_HOME%\bin\cache\dart-sdk\bin\dart.exe`，见 `PIT-014`）；
     `.ps1` / `.bat` 改动按 `PIT-002` 校验 BOM 与 CRLF 并用 Parser/静态 grep 自检；
  ③ 需要构建结论时，Cline 明确说"请你手工跑构建"，之后**只读**
     `build\build_exit.log`（`BUILD_FAILED=` / `WMI_FAILED=`）与 `build\build_full.log` 尾部，再分析；
  ④ 发现已有构建在跑（日志 mtime 新 / `java.exe` 在 R8）时**绝不重复启动**。
- 理由: 把最耗时的一步交回用户手里；对 Dart 侧改动而言静态验证的回归能力足够。
- 备选与为何不选: ①继续让 Cline 跑 `build.bat gradle`（3~20 分钟/次，WMI 挂死时纯白等，还会与用户构建冲突）；
  ②只在"大改动"时构建（判定含糊，仍会踩坑）；③用 `flutter analyze` 全量分析（本机易挂，见 `PIT-020`，
  故采用按文件 `dart analyze`）。
- 影响 / 约束:
  - `.clinerules/rules.md` 已改写：原来的"改完必须自测：跑构建…"→"自测 = 静态验证"，
    "构建入口"那条 → "构建一律由用户手工执行，Cline 默认不跑构建"；
  - 验证类条目的"复发判据"若依赖构建日志（如 `ISSUE-011` 判据 ③），**只读日志**，不要自己跑；
  - 用户明确要求构建时不受本约束限制；
  - 没能做编译级验证的改动，回复里必须写明"未做编译验证，请手工构建"。
- 首次记录: 2026-10-07

## ADR-028 播放区横向滑动快进/快退：只加在 `PlayerScreen`，一档 = 已有的「快进/快退步长」
- 日期: 2026-10-07 | 状态: 已采纳
- 背景: 需求 —— 播放视频时在**播放区**右滑快进、左滑快退。
- 决策:
  ① 手势只加在 `PlayerScreen` 的画面层：`_buildVideo` 里给 `NativeVideoViewport` 套
     `GestureDetector`（`onHorizontalDragStart/Update/End/Cancel`），原有的 `onTap: _toggleChrome` 保留
     （tap 与横向拖拽在手势竞技场里互不干扰）；
  ② 拖动过程中**不 seek**：只累计位移 + 显示画面中央提示 `VideoSwipeSeekIndicator`
     （方向图标 + 相对位移 + 「目标/总长」，复用本体已有但一直没人用的
     `formatVideoDelta()` / `formatVideoProgress()`，见 `ADR-025`），**松手才跳一次**；
  ③ 档位映射：`累计位移 ÷ videoSwipeSeekStepPx(48dp)` 四舍五入 = 档数，
     一档 = `AppSettings.playerSeekSeconds`（即 `ISSUE-019` 里那个**以前没人读**的值），
     目标位置裁剪到 `0 ~ duration`，提示里显示的是**裁剪后**的真实位移（到头时显示 `0:00`）；
  ④ 设置页文案 `双击跳转` → `快进/快退步长`（getter `doubleTapSeek` → `seekStepSeconds`），
     与 README「可配快进快退步长」的既有说法对齐。
- 理由: 三个视频界面里 `ViewerScreen` / `GalleryPreviewScreen` 的**横向滑动已经被 `PageView` 用作翻页**，
  抢来做 seek 会直接废掉"滑到上/下一条"；只有 `PlayerScreen`（播放列表页）的横向手势是空的
  ⇒ 加这里收益最大、冲突最小（成本：该手势在这两个界面不生效）。
- 备选与为何不选:
  ① 三个界面都加（与 PageView 打架，要再加"屏幕中部才生效"之类的判定，复杂且易误触）；
  ② 用 `onPanUpdate` 自己判定方向（等于重写手势竞技场，`onHorizontalDrag*` 已足够）；
  ③ 新建一个"滑动步长"设置项（多一个持久化字段 + 多一个 UI 项，与现值语义重复）；
  ④ 拖动中实时 seek（更跟手，但对 ExoPlayer / libVLC 都是每帧一次 seek，体验反而更差）。
- 影响 / 约束:
  - 画面层结构已变为 `GestureDetector → Stack(StackFit.expand)[NativeVideoViewport, IgnorePointer(HUD)]`；
    以后往画面层加浮层要放进这个 Stack；HUD **必须** `IgnorePointer`，否则会吃掉拖拽；
  - 底部控制条（`NativeVideoBottomControls`，含 `Slider`）在 Stack 的**更上层**，它的水平拖动优先，
    未被破坏（`ADR-025` 的时间标签也照旧）；
  - Android 10+ 手势导航的**左右边缘**滑动仍归系统返回，边缘约 20dp 内的滑动不会落到播放器 —— 平台行为；
  - 档数只在 `video.value.isInitialized && duration > 0` 时累计（加载中/出错/时长未知时整段忽略）；
  - 日志：真正跳转时写一条 `PlayerScreen | Swipe seek: item=..., steps=N (Ns each), from=...ms to=...ms`。
- 静态验证（`ADR-027`）: `dart analyze` 三个改动文件 → 仅剩 1 条**既存**告警
  （`player_screen.dart:145 The declaration '_clearOrientationLock' isn't referenced`，
  HEAD 版本同一处也已存在，非本次引入）；新写的段落已按 `dart format --output=show` 的输出对齐
  （见 `PIT-014` 复核 2026-10-07：本仓库任何 Dart 文件跑 `--set-exit-if-changed` 都会报 `Changed`，
  所以只能逐段对照，不能全局重排）。**未做编译/装机验证**，请手工构建。
- 首次记录: 2026-10-07
- 2026-10-07 修订（真机反馈「左右滑动快进/快退没生效」，见 `ISSUE-021`）：
  手势机制由 `GestureDetector(onHorizontalDrag*)` 换成
  **`Listener`（原始指针事件）+ `HitTestBehavior.opaque`** + 方向锁（12dp / 竖向占优不接管）+ 每次滑动一行诊断日志。
  理由：①原挂法只有"视频画面矩形"能命中，上下黑边与控制条缝隙里的滑动全部落空
  （`GestureDetector` 默认 `deferToChild`，而 `TextureBox.hitTestSelf=true` 只管画面本身）；
  ②`onHorizontalDrag*` 走手势竞技场，可能被同方向识别器抢走。
  约束（后续改动必须遵守）：这段逻辑**不要**换回 `GestureDetector` 的 drag 回调；
  向上层（`AutoHideVideoControls` 等）加 `Listener`/`GestureDetector` 时注意别把这段原始指针流吃掉
  （`IgnorePointer`/`translucent` 可以，`AbsorbPointer`/`opaque` 会挡）；改完**必须真机滑一次**，
  只看 `dart analyze` 覆盖不到（本轮教训）。
- 2026-10-08 修订（真机日志证明上面"只加在 `PlayerScreen`"这个决定的前提是错的，见 `ISSUE-021`）：
  滑动快进/快退**不再是 `PlayerScreen` 专属**，抽成共用层
  `lib/presentation/player/video_swipe_seek.dart` 的 `VideoSwipeSeekLayer`，
  在 `PlayerScreen` / `ViewerScreen` / `GalleryPreviewScreen` 三处都挂上。
  为什么能这么改：本节备选①里"与 `PageView` 打架"只对**图片**成立 ——
  `viewer_screen.dart:503` / `gallery_preview_screen.dart:424` 在 `item.isVideo` 时把 `PageView` 的
  physics 设成 `NeverScrollableScrollPhysics`（视频本来就不翻页），那条路径上的横滑一直是空的；
  图片仍交回 `PageView` 翻页，不受影响。
  约束（后续改动必须遵守）：以后任何"全屏播放视频"的界面，视频层直接套 `VideoSwipeSeekLayer`
  （`controller` + `itemId` + `onSeek` + 画面 child），**不要**再各自写一份
  `GestureDetector(onHorizontalDrag*)`；`ISSUE-021` 的复发判据仍按日志文本
  `Swipe seek gesture end` / `Swipe seek:` 搜（日志 tag 从 `PlayerScreen` 改为 `VideoSwipeSeek`）。

## ADR-029 drift 外键缺陷先「钉 dev 依赖 analyzer 10.1.0」止血，暂不升级 drift/drift_dev
- 日期: 2026-10-07 | 状态: 已采纳
- 背景: 构建日志里两条警告（见 `ISSUE-020`）——`drift_dev 2.31.0 + analyzer 10.2.0` 会**静默丢掉**
  `tables.dart` 里 `references()` 声明的外键（`album_media` 的 FK 从生成代码里消失，而 App 还开着
  `PRAGMA foreign_keys = ON`）；同一次日志还有一条 `W SDK language version 3.13.0 is newer than
  analyzer language version 3.12.0`。
- 决策:
  ① 立刻修复**只动 dev 依赖**：`pubspec.yaml` 的 `dev_dependencies` 加 `analyzer: 10.1.0`（钉死 + 注释指向 `ISSUE-020`）。
     运行时代码、主依赖（drift / drift_flutter / sqlite3 / sqlite3_flutter_libs）一律不动。
  ② **本次不升** drift / drift_dev 到 2.32.1（根治方案），作为独立任务另排。
  ③ `SDK language version 3.13.0 ... analyzer language version 3.12.0` 这条 W **不处理**（理由见下）。
  ④ **不回填历史库的外键**：SQLite 无法 `ALTER TABLE` 加 FK（要整表重建），而现有删除路径
     （`database.dart:468/475/988`）已显式清理 `album_media`；新装库在重新生成代码后自带 FK。
- 理由:
  - 升到 drift 2.32.1 + drift_dev 2.32.1 的**级联代价大、且本轮无法验证**（`ADR-027` 下 Cline 不跑构建）：
    drift 2.32.1 要 `sqlite3 ^3.1.5`、drift_dev 2.32.1 要 `sqlite3 ^3.0.0` + `sqlparser ^0.44.0`
    ⇒ 要同时把 sqlite3 2.9.4 → 3.x、sqlparser 0.43.1 → 0.44.x 抬上去，还可能连带 drift_flutter /
    sqlite3_flutter_libs；一次构建 15~25 分钟，失败代价高（`ADR-027`）。
  - 钉 analyzer 的代价只是"生成器工具链冻结在已知可用组合"：drift_dev 2.31.0 允许
    `analyzer >=8.1.0 <11.0.0`、source_gen 4.2.4 允许 `>=8.1.1 <15.0.0`、build_runner 2.15.1 允许
    `>=8.0.0 <14.0.0` —— 三者都接受 10.1.0；且 10.1.0 与 `_fe_analyzer_shared` 95.0.0 已在 pub 缓存里，
    无需下载新包。
  - 语言版本那条 W 只是"本机 Flutter/Dart SDK（语言版本 3.13）比锁定的 analyzer（最高 3.12）新"的提示：
    本包自身语言版本由 `environment.sdk: ">=3.5.0"`（=3.5）决定，代码里没用 3.13 的新语法，
    生成/分析结果不受影响；真要消掉它得让 analyzer ≥13，即 drift_dev ≥2.34.1（属于 ② 的后续升级）。
- 备选与为何不选:
  - **升 drift/drift_dev 到 2.32.1（上游根治）**：见上（级联 + 本轮无法编译验证）；已在 `ISSUE-020` 里写明升级路径与新版本约束。
  - 升到最新的 drift_dev 2.35.1（要 analyzer ≥13，还能顺带消掉 ③ 那条 W）：跳得更远
    （`cli_util <0.7`、`sqlparser ^0.45`、sdk >=3.10.0），风险更高。
  - 把 `references()` 改写成 `customConstraint('REFERENCES albums (id) ON DELETE CASCADE')`：能立刻恢复 DDL，
    但 drift 侧会**失去外键元数据**（后续 `Migrator`/schema 校验看不到引用），而且是绕开一个上游已修的 bug，属于坏味道。
  - 忽略警告：FK 悄悄丢失，`PRAGMA foreign_keys = ON` 名存实亡（`ISSUE-020` 的反例）。
  - 用 `dependency_overrides` 钉 analyzer：能省掉"把 analyzer 变成直接 dev 依赖"的不寻常写法，但 override 是
    "压过所有约束"的重锤，本场景不需要。
- 影响 / 约束:
  - 以后动 `pubspec.yaml` 的 dev 依赖、或想跑 `flutter pub upgrade` 时**必须先回看本 ADR + `ISSUE-020`**：
    analyzer ≥10.2.0 或 drift_dev 升级都要重新用复发判据验一遍
    （`findstr /c:"REFERENCES" lib\data\db\database.g.dart` 必须非空）。
  - `pubspec.lock` 会在下一次 `flutter pub get` 时变化：analyzer 10.2.0 → 10.1.0、`_fe_analyzer_shared`
    96.0.0 → 95.0.0（其它包不变）。
  - 本轮验证方式：只跑了**只读**的 `flutter pub upgrade --dry-run`（结论：在 `analyzer: 10.1.0` 约束下解析成功，
    并把 analyzer 10.2.0 → 10.1.0、`_fe_analyzer_shared` 96.0.0 → 95.0.0 降级；drift / drift_dev 保持 2.31.0 不动）。
    **未做编译/装机验证**，需手工构建。
- 首次记录: 2026-10-07

## ADR-030 推送 git 只推「当前分支」（单分支 refspec；禁止 `--all` / 多分支一次推）
- 日期: 2026-10-07 | 状态: 已采纳
- 背景: 之前的习惯是把 `main` / `dev`（必要时还有 `backup_*`）在一条/连续几条命令里一起推完
  （见 `ADR-021` 的 2026-10-07 两轮记录）；用户 2026-10-07 明确要求「**推送只推当前分支**」，
  并要求写进项目约定（已落到 `.clinerules/rules.md`）。
- 决策:
  ① push 一律显式写**单分支** refspec：`git push origin <当前分支>`（`main` / `dev`）；
  ② 禁止 `git push --all`、`git push --mirror`、`git push origin main dev`（一条命令推多个分支）；
  ③ 不主动推 `backup_*` 快照分支（只在 `ADR-021` ①的备份步骤里按需创建/推送）；
  ④ 推前 `git branch --show-current` 确认当前分支，推后 `git log --oneline -1 --decorate` + `git status -sb` 复核；
     需要硬证据时 `git ls-remote origin refs/heads/main refs/heads/dev`（一看就知道"没推的分支指针没动"）；
  ⑤ 本约定只约束"推哪些分支"，不改变「Cline 不自动 commit/push，只有用户当场明确要求才推」。
- 理由: push 是低频但影响面大的动作（改别人拉取的基线、可能触发远端 Release/Actions）。
  一次只推一个分支 ⇒ 每条 push 都能一句话说清"动了什么"；少推一个分支的代价是再敲一条命令，
  多推一个分支的代价是别人拿到你没打算发布的代码。
- 备选与为何不选: ①沿用"一条命令推多分支"（正是本次要禁止的）；
  ②只靠 `push.default=simple`（默认确实只推当前分支，但拦不住 `git push --all` / 多 refspec，约束力不足）；
  ③干脆禁止一切 push（不现实：`ADR-021` 的发版流程必须推 `main` / `dev`）。
- 影响 / 约束:
  - `ADR-021` 的发布流程按本约定拆成多次**单分支**推送：先 `git push origin main`；
    需要同步 `dev` 时再 `git checkout dev && git merge --ff-only main && git push origin dev`；
  - 只推 `main` 时 `dev` / `origin/dev` 会**故意落后**于 `main`，这是预期状态（下轮发版时补齐）；
  - 本轮记录（2026-10-07 第三轮）: 在 `main` 上提交 `b2b01f1`（`fix(deps): 钉 analyzer 10.1.0 …`）与
    `docs(rules): 推送 git 只推当前分支（ADR-030）`（= `e682c5f`），**只执行 `git push origin main`**，
    回执 `cb4c67a..e682c5f  main -> main`；推送后 `git ls-remote origin refs/heads/dev` 仍为 `cb4c67a`
    （**未动**，见 `PIT-008` 第三轮复核）；本轮之后 memory-bank 的补记提交同样只推 `main`（单分支）。
- 首次记录: 2026-10-07

## ADR-031 「播完后重播」一律**重建原生播放器**（不在原生里 `stop()+play()` 复活已结束的 input）
- 日期: 2026-10-10 | 状态: 已采纳
- 背景: `ISSUE-022` —— 视频播完后拖进度条回开头，不播放、进度条还弹回结尾。
  拆下来有三个独立缺陷：原生 `getPosition()` 在 `isEnded` 时报 `durationMs`（位置说谎）；
  播完后 `seekTo(0)+play()` 起不来（input 已结束）；Dart 侧"重播要重建"的分支被
  `seekTo()` 清掉 `isCompleted` 而跳过。修 ①② 之后还剩一个选择：**怎么让播完的视频重新播**。
- 决策:
  ① 「播完后重播」（拖进度条回前面 / 按播放 / 滑动快进快退）统一走**重建**：
     `_stopVideo()+_loadCurrent()`（gallery）、`_detachVideo()+_syncVideo()`（viewer）、
     `_disposeNativeVideo()+loadVideo()`（player screen，已有）；
  ② 重播起点用**一次性显式参数**传递（gallery/viewer 的 `_pendingStartMs`；
     player screen 的 `_replayItemId/_replayStartMs`，按 item id 消费），
     优先于 `VideoResumeService` 里持久化的续播位置；
  ③ `NativeVideoController` 用**每实例闩锁** `mediaEnded` 表达"这条原生 input 已经结束"，
     `seekTo()` / `play()` 都不清它 —— 界面据此判定必须重建，而不是靠 `value.isCompleted`
     （拖进度条会把它清掉）；
  ④ 原生侧只做**真实性**修复：`getPosition()` 的 `isEnded` 分支回 `lastPositionMs`，
     `status().position` 改用 `getPosition()`；**不加** `stop()+play()`。
- 理由:
  - 重建走的是"正常打开视频"完全同一条链路（日志里每一轮真实加载都是它），
    已在真机验证过成百次；而 `MediaPlayer.stop()` 之后不 `detachViews` 直接再 `play()`
    在这台设备/这个 libvlc-all 版本上**没有任何实测证据**，风险是 vout 不重建 ⇒ 黑屏
    （本仓库已经被黑屏/几何问题坑过：`ISSUE-008`、`ISSUE-016`、`ADR-022`）。
  - `Cline` 默认不跑构建（`ADR-027`），这类"要么好要么黑屏"的平台行为改成重建路径后，
    改动本身不需要装机验证就能判定逻辑正确性（只是多一次 ~0.2~0.5s 的加载）。
  - 显式起点（②）是必要的：重建后新控制器位置归零，靠"读旧进度条位置"或
    "读持久化续播值"都不确定（后者可能是更早的残留；拖到 0 时还不会写盘）。
- 备选与为何不选:
  - **原生 `play()` 里 `if (isEnded) { stop(); play(); time = lastPositionMs }`**：
    最省 Dart 改动、无加载延迟，但依赖未验证的 libVLC 行为（见上）；记为"以后想在真机上试"的选项。
  - **`seekTo(0)+play()`（旧 `ViewerScreen` 的写法）**：日志已证明无效
    （`play: textureId=N` 之后无 `Playing`/`onPlaying`，`getStatus` 恒 `isPlaying=false`）。
  - **保持 `isCompleted` 闩锁不清、只用它判定**：也是可行的最小改法，但它把
    "已播完"和"要重建"两种语义挤在一个字段里，进度条拖动/`applyStatus` 都会动它，
    正是 `ISSUE-022` 根因 ③ 的坑；独立闩锁更不容易被后续改动踩坏。
  - **播完后禁用进度条/播放按钮**：退化成功能缺失，用户要的就是重播。
- 影响 / 约束（后续改动必须注意）:
  - 新写"播完后重新播放"的代码**不要**用 `seekTo(0)+play()`，用 `mediaEnded` + 重建；
  - `mediaEnded` 是**每实例**闩锁：控制器 dispose 后新实例自然为 false，
    不要为了"复位"去清它（清了界面就会重新掉回空转的 seek+play 路径）；
  - 三个界面的重播都要带显式起点，别再依赖 `VideoResumeService` 的往返
    （它在 ≥95% 时会删键，看似方便，实则是隐蔽的不确定性）；
  - 真机验证要点（待手工构建）：播完 →（a）拖回开头应**立即重新播放**；
    （b）拖到中间再按播放应从中途继续；（c）进度条不应弹回结尾；
    日志应出现 `Replaying finished video from <N>ms (recreating native player)` +
    新的 `Creating native player` / `onPlaying`。
  - **「循环播放」也属于本条**（追加 2026-10-14，见 `ISSUE-046`）：`NativeVideoController.setLooping()`
    是空实现（原生 libVLC / ExoPlayer 都没有循环开关），单视频循环只能在**三个界面各自的 `onCompleted`**
    里用「重建 + 从 0 起播」实现 —— 新增播放界面时**必须**照抄这段分支，
    只改一个界面就会出现"点了循环按钮毫无反应"（日志里只有 `Video ended, staying on this item`）。
- 首次记录: 2026-10-10 ／ 追加约束: 2026-10-14（`ISSUE-046`：循环播放同属本条）

## ADR-032 单击打开的视频播完**停在最后一帧**，不自动切下一个（只有「播放」入口的播放列表页连播）
- 日期: 2026-10-10 | 状态: 已采纳
- 背景: 用户 2026-10-10 明确要求：「如果是**单击打开**的文件，播放完毕后不要自动切换下一个文件」。
  改动前两个"单击打开"的界面（私密相册 → `ViewerScreen`、可见库 → `GalleryPreviewScreen`）
  在 `onCompleted` 里都会 `_showItem(index + 1)` 自动连播，并靠
  `_ignoreAutoAdvanceUntil`（800ms / 新加载 2s）抑制"刚拖完进度条就到结尾"造成的误连播。
- 决策:
  ① `ViewerScreen._onVideoEnded` / `GalleryPreviewScreen._onNativeVideoEnded` 改为"停在最后一帧"：
     记 `_completedForId` + 把控制条显示出来，**不再** `_showItem(next)`；
  ② 随之**删掉**已经没人读的 `_ignoreAutoAdvanceUntil` 字段与 `_markUserSeek()`（两个界面各一套）
     —— 它存在的唯一目的就是抑制自动连播，留着只会变成"写而不读"的死代码
     （`dart analyze` 的 `unused_field` 会报，而且下次排查会被它误导）；
  ③ `PlayerScreen`（从「播放」/「播放全部」入口进的播放列表页）**保持连播**：
     它的连播由 `PlayerController.onItemCompleted() → next()` 驱动，与上面两个界面无关；
  ④ 「上一个 / 下一个」按钮、左右滑翻页、拖进度条重播（`ISSUE-022`）全部保留
     —— 用户要的是"别自己切"，不是"不能切"。
- 理由:
  - 单击打开 = "我要看这一个"；在相册里随手点开一段视频却一直被带走到别的文件，
    位置与上下文都丢（尤其可见库里相邻的都是同一文件夹的其它文件）。
  - 要连续观看本来就有显式入口（「播放」→ `PlayerScreen`，还带顺序/随机选择），
    把两种意图分开，比"一个行为两种期望"更好维护。
  - 删 `_ignoreAutoAdvanceUntil` 而不是留着：它是为抑制自动连播而生；
    没有自动连播之后，留下就是会误导下一个人的死代码。
- 备选与为何不选:
  - **加参数 `autoAdvance`（默认 false，长按「内部播放」传 true）**：长按菜单的「内部播放」
    也只是"看这一个"（`ADR-023`），没有任何入口需要 true ⇒ 参数会变成永远为 false 的摆设；
    真要连播应该走 `PlayerScreen`。
  - **加设置项（"播完自动下一个"开关）**：默认关闭只是把问题藏起来；而且设置里已经有
    语义混乱的「循环播放」（见下），不宜再加。以后确实要开关时，再按"默认关"补。
  - **可见库也保留连播**：可见库目前没有「播放」入口（`visible_media_grid.dart` 不推
    `PlayerScreen`）。以后若要连播，应**新增显式的「播放」按钮** → `PlayerScreen`，
    而不是恢复这里的自动切下一个。
- 影响 / 约束（后续改动必须注意）:
  - 以后在这两个界面写 `onCompleted` 相关逻辑时**不要**恢复 `_showItem(next)`；
  - 唯一保留连播的是 `PlayerScreen`（`PlayerController.onItemCompleted()`）：
    改连播行为请去 `lib/application/player/player_controller.dart`；
  - **已知限制**：「循环播放」开关（视频设置面板）仍是**空操作** ——
    `NativeVideoController.setLooping()` 一直是 `// Not directly supported ... ignore`；
    改良前它唯一可见的效果就是"别自动切下一个"，而现在的默认行为就是停住，
    所以这个开关彻底看不出效果。真要实现循环需要原生支持
    （ExoPlayer `REPEAT_MODE_ONE`，或 libVLC 结束后 `stop()+play()` —— 后者见 `ADR-031` 的顾虑），
    不要用"每轮重播都重建播放器"去凑（每轮循环会闪一次加载态）；
  - 真机验证要点（待手工构建）：单击打开一段视频 → 播完应停在最后一帧、控制条出现、
    **不跳下一个**；日志应出现 `Video ended, staying on this item (no auto-advance): <itemId>`。
- 相关文件: `lib/presentation/viewer/viewer_screen.dart`、`lib/presentation/visible/gallery_preview_screen.dart`（改动）；
  `lib/presentation/player/player_screen.dart`、`lib/application/player/player_controller.dart`（保持连播）
- 首次记录: 2026-10-10

## ADR-033 AES-256-GCM 文件加密：仿华为保密柜双层密钥架构（KEK / DEK），硬件加速分块加解密
- 日期: 2026-10-13 | 状态: 已采纳
- 背景: 私密仓库当前仅靠 `.nomedia` 目录隐藏，媒体文件以明文存放，其他程序仍可扫描到。
  需要真正的文件级加密，同时满足三个约束：①大文件（35GB 视频）加密不能 OOM；
  ②解密必须在 1~2 秒内完成（用户打开视频的容忍上限）；
  ③指纹/密码/图案多种解锁方式共用同一密钥体系。
- 决策:
  ① **双层密钥**：KEK（密钥加密密钥）= 用户密码经 **PBKDF2**（210000 迭代、SHA-256、32 字节）派生，
     存于 FlutterSecureStorage（Android Keystore 硬件保护）；DEK（数据密钥）= 256 位安全随机数，
     经 KEK 用 AES-GCM 加密后存数据库 `encrypted_dek` 列，明文仅存内存；实际文件用 DEK 加密。
  ② **硬件加速**：文件加解密走 Android native（`javax.crypto.Cipher`，自动启用 AES-NI / ARMv8 extensions）；
     纯 Dart cryptography 包只有 30-80 MB/s，native Cipher 可达 500-2000 MB/s。
  ③ **1MB 分块流式读写**：不论文件多大（35GB），内存占用恒定 ~1MB，不会 OOM。
  ④ **AES-256-GCM 认证加密**：12 字节随机 nonce + 16 字节 auth tag，每次加密生成新 nonce；
     解密时 GCM 自动校验 auth tag，篡改/损坏文件立即失败。
  ⑤ **原子临时文件**：加密/解密先写临时文件，成功后 `rename()` 原子替换；中途崩溃不损坏原始文件。
  ⑥ **KEK 生命周期**：内存仅存一份 `_kek`，`lock()` 时立即清空（同步）并异步删 FlutterSecureStorage 条目；
     `_kekGen` generation counter 防异步回调在锁屏后注入 KEK。
  ⑦ **指纹兼容**：所有手指共用同一 KEK（指纹仅做 Android BiometricPrompt 身份认证，不参与密钥派生），
     不存在"不同手指无法解密"的问题。
  ⑧ **向后兼容**：`encrypted_dek IS NULL` 的行视为明文旧文件，`looksEncrypted()` 校验文件头魔数防重复加密。
- 理由: 双层密钥是华为保密柜的成熟架构——修改密码只需重加密 DEK（几百字节），
  不用重加密所有媒体文件；每个文件独立 DEK 意味着单文件泄露不暴露其他文件密钥。
  硬件加速 + 分块流式读写是处理大文件的唯一可行方案：纯 Dart 全量内存方式 35GB 至少 OOM。
- 备选与为何不选:
  ① **纯 Dart cryptography 全量内存加解密**：35GB 文件直接 OOM，且速度 30-80 MB/s，35GB 需 7-21 分钟——不可用；
  ② **单层密钥（直接用密码加密文件）**：改密码要重加密所有文件；每个文件同密钥，批量泄露风险高；
  ③ **HUKS 硬件密钥注入**：华为真机可通过 HUKS（Hardware Unique Key Store）把 KEK 注入 TEE，
     密钥永不离片——但需要 HarmonyOS SDK，本应用是纯 Android APK 侧载，暂不引入鸿蒙依赖。
     当前 FlutterSecureStorage + Android Keystore 的保护级别已满足离线本地应用的安全需求。
- 影响 / 约束:
  - 新导入文件自动加密；设置页「Encrypt Existing Files」可批量加密已有明文文件（需解锁后操作）；
  - viewer 解密为临时文件，看完自动清理；`vault_reveal_runner` 还原时先解密再移动；
  - **新增任何"读文件路径"的代码都不能直接读 `item.privatePath`**——必须经过
    `_resolveDisplayPath()`（或等价的解密→临时文件链），否则会拿到密文；
  - schema v8→v9 迁移新增 `encrypted_dek` 列（`TEXT, NULL`），不破坏已有数据；
  - `looksEncrypted()` 只读前 32 字节做启发式检测（`PIT-031` 的教训），不可再用全量读取；
  - **文件原地替换必须用 backup→rename→delete 三步，永不可 delete-then-rename**（`PIT-034`）；
  - **三个 setup/unlock 入口（setupPattern/setupPin/enterAppAfterSetup）全部要
    派生/加载 KEK**——新增入口时按 `unlockWithPattern` 的模式对齐，不要遗漏。
- 相关文件: `lib/data/services/media_encryption_service.dart`、`encryption_key_manager.dart`、
  `native_crypto_service.dart`、`android/.../CryptoHandler.kt`、`lib/data/db/database.dart`(v8→v9)、
  `lib/presentation/settings/settings_screen.dart`(batch encrypt)、
  `lib/presentation/viewer/viewer_screen.dart`(transparent decrypt)
- 首次记录: 2026-10-13

## ADR-034: changePattern/changePin/migratePinToPattern 必须旋转所有 DEK

- 日期: 2026-10-13
- 状态: ✅ 已采纳（第三次审计 → PIT-036）
- 背景: 双层密钥架构 KEK→DEK→File。`changePattern` 原先只改 credential 不处理 DEK，
  锁屏再解锁后新 KEK 无法解密旧 DEK → 所有加密文件永久丢失。
- 决策:
  - `changePattern`、`changePin`、`migratePinToPattern` 三个入口全部调用
    `_rotateAllDeks(oldKek, newKek, caller)` 旋转所有 DEK
  - `_rotateAllDeks` 遍历 `listEncrypted()` → 旧 KEK 解密 DEK → 新 KEK 加密 DEK
    → `updateEncryptedDek` 写回 DB
  - 部分失败时记录日志（`lostCount > 0`）但不回滚凭证变更（凭证已改）
  - `recoverWithSystemAuth` 不加旋转（旧凭证已清除无法恢复），改为 UI 警告
- 影响 / 约束:
  - 数据库层新增 `listEncryptedActiveMediaRows` 查询（`encryptedDek IS NOT NULL`）
  - Repository 新增 `listEncrypted()`
  - 改密码操作从此包含 DB 全表扫描，加密文件越多越慢（但 DEK 都是 32 字节，
    解密+加密很快，几百个文件 ≈ 几秒）
- 备选方案:
  - 方案 A（已否决）: 不改密码，只改 KEK → 密码不跟着变，安全性弱
  - 方案 B（已否决）: 旧 KEK 用新 KEK 包一层存下来 → 密钥版本多了管理复杂还降安全性
- 首次记录: 2026-10-13

## ADR-035 生物识别解锁：KEK 缺失时"保持锁定 + 明确提示"，且**不**统一 FlutterSecureStorage 后端
- 日期: 2026-10-13 | 状态: 已采纳
- 背景: `f812d9d`（`PIT-049`）把"指纹验证通过但持久化 KEK 缺失"从老行为（照样置 `unlocked` = 半解锁）
  改成"保持锁定 + 裸 `return false`"。半解锁确实危险（vault 标已解锁、`getKey() == null`，
  加密导入/批量加密会写出坏数据，见 `ISSUE-024`/`ISSUE-027`），但静默失败让锁屏界面**毫无反馈**，
  用户直接判定"指纹坏了"（`ISSUE-028`）。
- 决策:
  ① 语义：拿不到 KEK 就**不允许解锁**（保持 `LockStatus.locked`），**绝不**半解锁；
  ② 反馈：新增 `VaultLockErrorCode.kekUnavailable` + l10n `biometricKekUnavailable`，
     锁屏明确提示"用图案解锁一次即可恢复指纹"；
  ③ 诊断：`_deriveAndStoreEncryptionKey()` 在 `kek == null` 时打 error 日志（此前 PBKDF2 失败完全静默）；
  ④ **不动** `EncryptionKeyManager` 的 `FlutterSecureStorage` 后端选项（保持该类默认的 `AndroidOptions()`），
     尽管 `SecurityService` 用的是 `AndroidOptions(encryptedSharedPreferences: true)`。
- 理由: ①半解锁是本项目最贵的一类 bug（用户以为已解锁，加密链路却拿不到密钥）；
  ②凡是用户可感知的失败，必须能在 UI 或日志里定论；
  ④两种后端**各自都能读到自己写的键**，统一它们等于**换存储桶** ——
  已安装版本持久化的 `privi_kek_v1` 在新后端里不存在 ⇒ 所有老用户指纹解锁当场失效（正好是本次要修的病症）。
- 备选与为何不选:
  - 方案 A（已否决）: 保持半解锁 —— 加密媒体/导入会看到 null KEK，回归 `ISSUE-024`
  - 方案 B（已否决）: KEK 缺失时改用"设备凭证"重新派生 KEK —— KEK 由用户图案/PIN + `encryption_salt`
    经 PBKDF2 派生，系统凭证只证明身份、**推不出**用户 secret，技术上做不到
  - 方案 C（已否决）: 把两个 `FlutterSecureStorage` 后端统一为 `encryptedSharedPreferences: true` —— 见理由④
  - 方案 D（暂缓）: `setBiometricEnabled(true)` 时顺手持久化一份 KEK —— 只能覆盖"解锁状态下开开关"的新用户，
    救不了"历史版本从未写过 KEK"的老用户；留作后续专项（`ISSUE-028`「下一步验证」④）
- 影响 / 约束:
  - `_mapLockError` 的 `switch` 表达式是**穷尽**的 —— 以后再加 `VaultLockErrorCode` 必须同步补 l10n，否则编译不过
  - 指纹路径的失败从此有三种可区分日志，排查按此顺序读：
    `biometric status:`（硬件/录入）→ `biometric authenticate result=`（验证）→
    `Biometric OK but no persisted KEK found`（密钥缺失）
  - 新增"持久化 KEK 的写入点"时要记住：老用户的 KEK 是在**图案/PIN 解锁**时才写入的，
    任何"跳过图案解锁"的入口都不能假设 KEK 已存在
- 相关文件: `lib/application/lock/lock_controller.dart`、`lib/presentation/lock/lock_screen.dart`、
  `lib/l10n/app_localizations.dart`、`lib/data/services/encryption_key_manager.dart`
- 首次记录: 2026-10-13

## ADR-036 加密媒体不得交给外部 app；解密层必须覆盖每个展示入口（本轮只落了"不外放"）
- 日期: 2026-10-13 | 状态: 已采纳（同日 R11 全部落地：①不外放 ②PlayerScreen 解密 ③缩略图 ④备份带
  salt+DEK；仅「抽共享 mixin」未做，作为技术债记在 `ISSUE-029` 补修①）
- 背景: 第十轮审计（`ISSUE-029`）发现加密上线后 `item.privatePath` 仍被直接喂给三类消费者：
  外部播放器（`media_grid_screen._openExternally`、`player_controller._onItemEntered`）、
  内置播放列表页（`player_screen._buildImage` 与 `NativeVideoController.create`）、
  缩略图生成器（`thumbnail_generator.makeThumbnail`）。它们拿到的都是**密文**，表现为"文件坏了"。
- 决策:
  ① **加密媒体一律不外放**（不给系统 chooser / 其它 app）：外放要么喂密文（现状，打不开），
     要么必须先在共享存储落一份**明文**（隐私倒退且清理时机不可控），加密项直接走内置链路；
  ② 解密层继续"每个展示入口各自接入"，但**新增入口必须显式接入** ——
     `viewer_screen._resolveDisplayPath` 是参考实现（`encryptedDek != null → decryptToTempFileWithDek →
     内存缓存 → dispose 清理`），后续应抽共享 mixin，禁止出现第三份实现；
  ③ 缩略图：加密项要么解密后再取帧，要么**跳过**，不能像现在这样让 `repairOutdatedVideos()` 每次启动无效重试；
  ④ 备份：加密媒体的备份必须"要么明文导出、要么带上 DEK"，两者都是产品决策；在定下来之前
     **不得**让用户以为备份可恢复（`ISSUE-029` 未修复③）。
- 理由: 密文外放/外显属于"静默失败"——用户看到的是"文件坏了"而不是"此功能不支持"；
  而明文外放会把加密的意义抹掉。两者都比"明确不支持"差。
- 备选与为何不选:
  - 方案 A（已否决）: 外放前解密到共享目录 → 明文落盘在别处、任何 app 可读，与加密目标冲突
  - 方案 B（已否决）: 把 KEK/DEK 交给外部 app 去解密 → 绝对不可接受
  - 方案 C（已采纳）: 加密项留在内置播放器/查看器，由 app 自己解密到 `systemTemp`
- 影响 / 约束:
  - 写任何读 `item.privatePath` 的新代码前先自问：这是明文消费者吗？是 → 必须走解密层；
    不是（存在性判断、删除、rename）→ 才可以直接用；
  - `PlayerScreen` / 缩略图 / 备份 是**已知未修**的三处，动手前不要以"加密功能已经没问题"为前提。
- 相关文件: `lib/presentation/grid/media_grid_screen.dart`、`lib/application/player/player_controller.dart`、
  `lib/presentation/player/player_screen.dart`、`lib/presentation/viewer/viewer_screen.dart`、
  `lib/data/services/import/thumbnail_generator.dart`
- 首次记录: 2026-10-13

## ADR-037 长任务保持屏幕常亮：用 holder 集合仲裁，不要直接置位 `setKeepScreenOn`
- 日期: 2026-10-13 | 状态: 已采纳
- 背景: 批量加密 / 导入后的加密阶段可能持续数十秒到数分钟。期间屏幕熄灭会让系统把应用切后台甚至杀掉，
  而加密最危险的窗口正是"文件已换成密文、DEK 还没写库"（`PIT-044` / `ISSUE-030`）。
  仓库已有现成通道：`MainActivity.setKeepScreenOn`（`FLAG_KEEP_SCREEN_ON`）← `PlaybackDisplayService`
  ← `VideoSystemUi.setKeepScreenOn`。但它原本是**播放器语义**：谁最后调用谁说了算
  （`VideoSystemUi.restore()` 在播放器退出时会 `setKeepScreenOn(false)`）。
- 决策: 在 `PlaybackDisplayService` 内做**请求仲裁**：
  - `setKeepScreenOn(bool)` = 播放器请求（语义不变 ⇒ 播放器/查看器代码**零改动**）
  - `holdScreenOn(holder)` / `releaseScreenOn(holder)` = 长任务 holder 集合（幂等、可重入）
  - 真正下发的值 = `播放器请求 || holder 非空`；仅当值变化时才调通道（`_applied` 去重）
  - 现有持有者：`settings.batchEncrypt`（批量加密）、`import.encryptFiles`（导入后的加密阶段）
- 理由: 长任务若直接 `setKeepScreenOn(true)`，会被随后任何播放器页面退出时的 `restore()/false` 清掉；
  反之长任务结束时若直接 `setKeepScreenOn(false)`，又会误灭正在播放的播放器。仲裁后两边互不干扰。
- 备选与为何不选:
  - 方案 A（已否决）: 在加密流程里直接调 `setKeepScreenOn(true/false)` —— 与播放器互相覆盖（见上）
  - 方案 B（已否决）: 引入 `wakelock_plus` 依赖 —— 仓库已有通道，为一个 flag 加依赖不划算
  - 方案 C（已否决）: 用 `SystemChrome` 类 API —— Flutter 没有等价的"保持屏幕常亮"接口
- 影响 / 约束:
  - 以后新增长任务（导出备份、扫描孤儿、恢复索引…）只要可能超过屏幕超时，**统一用
    `holdScreenOn` / `releaseScreenOn`**，不要直接调 `setKeepScreenOn`；
  - **必须成对调用**（出错也要 `try/finally` 释放）：holder 泄漏会让屏幕永远不灭（费电、用户可感知）。
    `_batchEncrypt` 里额外留了一层 `finally` 兜底；
  - 它只防"屏幕熄灭"，**不防**应用自身的自动锁定（`autoLockSeconds`）：若设为"立即锁定"，
    切后台仍会锁定并中止加密（数据是安全的，只是任务会停）⇒ 加密期间请勿切后台。
- 相关文件: `lib/data/services/playback_display_service.dart`、`lib/presentation/settings/settings_screen.dart`、
  `lib/data/services/import_service.dart`、`android/.../MainActivity.kt`（通道未改）
- 首次记录: 2026-10-13

## ADR-038 加密容器 v2：分块 AES-GCM（每块独立 tag），取代单流格式
- 日期: 2026-10-13 | 状态: 已采纳（新加密一律 v2；v1 只读兼容）
- 背景: 单流 GCM 在 Android/Conscrypt 上对大文件会在 `doFinal` 一次性申请 ≈2× 文件大小
  （`ISSUE-032`：71.8MB 视频 → 134MB 分配 → 进程崩溃，堆上限仅 384MB）。而 `ADR-033` 的目标恰恰是
  "支持 35GB 级视频且不 OOM"——单流格式从根上不成立。
- 决策: 新容器 v2：
  ```
  [magic 'PRV2' 4][baseNonce 8][plaintextSize 8][chunkSize 4][chunk 0..n-1]
  chunk = ciphertext(≤chunkSize) + tag(16)
  chunk nonce = baseNonce(8) || int32be(index)      // 12 字节，全局唯一
  ```
  默认 chunkSize = 1MiB。**加密一律写 v2**；解密按 magic 分流，v1（`[nonce12][ciphertext][tag16]`）保持只读兼容。
- 理由: 每块独立 tag 让加解密都在 1MiB 量级完成 ⇒ 内存与文件大小无关（真正达成 ADR-033 的目标）；
  nonce 用 `base + 计数器` 保证唯一（GCM 的硬性要求，安全性不降级）；密文仅多出 16×块数 字节
  （71MB 文件 → +1.1KB，可忽略）。
- 备选与为何不选:
  - 方案 A（已否决）: 保留单流 + 限制文件大小 ⇒ 直接违背"支持大视频"的产品前提
  - 方案 B（已否决）: 换 CTR+HMAC / ChaCha20-Poly1305 ⇒ 同样必须分块才是恒定内存，且"先解密后校验"
    引入新的安全陷阱；Conscrypt 的 GCM 已有硬件加速
  - 方案 C（已否决）: 分块但整体一个 tag（块作为 AAD）⇒ 需要两遍读写，实现更复杂而收益相同
- 影响 / 约束:
  - **新写入的密文都带 `PRV2` 头**；Dart 侧 `looksEncrypted()` 依据"不像已知明文媒体签名"判断，
    v2 头不是任何媒体签名 ⇒ 天然兼容，**Dart 侧无需改动**
  - **v1 大文件解密仍可能 OOM**（格式决定）：现在返回 `out of memory` 错误而不是崩溃；
    用户应在低内存时刻（重启 app 后立即）先解密回相册，再重新加密（自动 v2）
  - 加密结果长度校验下界改为 `头部(24) + 块数×16`（`encryptedSize` 相应略增）
  - 块大小写进头部（`chunkSize`），将来调整不需要改格式
- 相关文件: `android/app/src/main/kotlin/com/privi/app/CryptoHandler.kt`
- 首次记录: 2026-10-13

## ADR-039 批量加密 = 「N 条共享游标的队列」+ 原生专用 crypto 线程池（4~8）
- 日期: 2026-10-13 | 状态: 已采纳（待真机验证吞吐）
- 背景: 保险库有 6 000+ 明文文件时，「设置 → 加密已有文件」是**单文件串行**（每项要读文件头、
  包 DEK、写 DB、跑一次原生 AES-GCM），耗时分钟级；而原生 crypto 又挂在 `ioExecutor(3)` 上，
  天生把并发压到 3（`ISSUE-033`）。
- 决策:
  ① Dart 侧：`BatchEncryptionService.run()` 起 N 条队列（默认 `2 × numberOfProcessors`，
     clamp `6…24`，且 ≤ 待处理项数），**共用一个游标**领任务（工作窃取）；单项逻辑统一走
     `encryptOne()`（含 `PIT-051` 的"先落 DEK 再加密文件"与"确认是明文才回滚 DEK"）。
  ② 原生侧：新增专用 `cryptoExecutor`（`availableProcessors().coerceIn(4, 8)`）+ `runCrypto()`，
     三个 crypto 方法（encrypt / decrypt / decryptToBytes）改走它；`ioExecutor(3)` 保持不动。
  ③ UI：进度回调节流 100 ms 再 rebuild 对话框（`_encryptProgressUiIntervalMs = 100`）。
- 理由:
  - 每项开销的大头是**等待**（跨平台往返 + sqflite 写 + 文件头读），不是 CPU ⇒ Dart 侧允许
    oversubscribe（2 × 核数）才能把原生池喂满；旧实现只有 1 条队列时这些等待全被串起来。
  - 用共享游标而不是"预先切成 N 段"：一个 500 MB 视频落到某条队列时，该队列不会拖住后面一大串
    小文件（动态负载均衡），取消也能更快生效。
  - 原生池上限取 4~8：每次并发加解密峰值 ~2 MiB（`ISSUE-032` / `ADR-038` 的分块 GCM），
    8 × 2 MiB ≈ 16 MiB 堆增量可控；再往上只是增加 IO 抖动与 OOM 风险。
  - crypto 单独一个池，批量加密就不会把 metadata / libVLC parse 饿死（它们仍在 ioExecutor）。
- 备选与为何不选:
  - **保持串行、只优化单项**（例如批量写 DB）：天花板太低（仍是 1 项/轮），且要改 DB 层
  - **纯 Dart `Isolate` 并行**：加解密在原生侧、DB 在 sqflite 单队列，Isolate 帮不上，
    还多出跨 isolate 传 KEK 的安全面
  - **直接把 `ioExecutor` 从 3 调大**：会连带改掉 metadata / VLC parse 的并发，影响面没评估过
  - **"几十条队列 = 几十个原生线程"**：内存与 IO 抖动不可接受（`ISSUE-032` 的教训）
  - **原生侧一次调用批量加密多个文件**：要跨 Dart / native 协调 DEK 落库与失败回滚，收益不明显
- 影响 / 约束:
  - 新增批量加密入口**一律走 `BatchEncryptionService`**（别再写 `for (item in items)` 的串行循环）；
    单项行为要改就改 `encryptOne()`。
  - 队列数可调，但**必须**与原生池同量级；`cryptoExecutor` 的上限（4~8）与内存预算绑定（`ADR-038`）。
  - `runCrypto` 必须 catch `Throwable` 并回复 `result.error`：一次未捕获的 `Error`
    会让 Dart future 永久 pending，整批任务不结束。
  - 并发**不改变** `ISSUE-030` 的两道重入守卫（模块级 `_batchEncryptInFlight` + 对话框级 `started`）；
    也不要删 UI 节流，否则 6 000 项 × rebuild 会拖慢主 isolate。
  - 取消只在"项目之间"生效：在途的原生调用不会被中断（中断会留下 `.enc_tmp*`，见 `PIT-056`）。
- 相关文件: `lib/data/services/batch_encryption_service.dart`、`lib/application/providers.dart`、
  `lib/presentation/settings/settings_screen.dart`、`android/app/src/main/kotlin/com/privi/app/MainActivity.kt`
- 首次记录: 2026-10-13

## ADR-040 加密中间文件放「媒体同目录 + 固定短名」；`.enc_bak` 保持原名（不为此牺牲自愈）
- 日期: 2026-10-13 | 状态: 已采纳
- 背景: `CryptoHandler.encryptFile` 的临时文件原为 `"$filePath.enc_tmp-<uuid>"`（媒体名 + 45 字节）。
  一个 227 字节的中文/日文 jpg 名因此变成 272 字节，超过 Linux 单文件名上限 255 字节，
  `open failed: ENAMETOOLONG` ⇒ 该文件永远加密失败（`ISSUE-034`）。
- 决策:
  ① 原地加密的临时文件 = **同目录** + `.enc_tmp-<uuid>`（45 字节定长，与媒体名无关）——
     同目录是为了同一文件系统，`renameTo` 保持原子（`PIT-034`）。
  ② 陈旧临时文件的清理改成"同目录 + `TEMP_PREFIX` + mtime 早于 1 小时"，
     **不再**按"媒体名前缀"匹配（新命名与之无关），也不允许"见 `.enc_tmp*` 就删"。
  ③ **`.enc_bak` 不改名**（仍是 `媒体名 + .enc_bak`）：启动自愈靠
     `<name>.enc_bak` → `<name>` 反推主文件，改成短名就丢了这个映射。
- 理由:
  - 失败面只需"临时文件名"可控即可消除；`.enc_bak` 的映射是**救援**能力，价值高于支持极端长名。
  - 年龄阈值是"既能清残留、又不会误删并发在写的临时文件"的最小代价手段（`ISSUE-030` 的教训：
    误删 live 临时文件 = 0 字节媒体）。
- 备选与为何不选:
  - **临时文件放 `cacheDir`/`getExternalCacheDir`**：跨文件系统时 `rename` 退化成"复制+删除"甚至直接失败，
    原子替换（`PIT-034`）不再成立
  - **截断媒体名再拼后缀**（如 `take(120)`）：字节数仍不确定（UTF-8 中文 3 字节/字），治标不治本
  - **`.enc_bak` 也用短名 + 把原名写进 sidecar / DB**：要跨 Dart/native 维护新映射，
    只为支持"媒体名 ≥ 248 字节"这种本就连导入都困难的极端情况，不值
  - **把 `.enc_bak` 换成"先复制原件到缓存"**：等于把大文件复制一遍，35 GB 视频不可接受
- 影响 / 约束:
  - 以后新增任何"媒体旁边的中间文件"（临时、分片、缩略图候选……）都要按 `PIT-061`：
    名字**不得**拼在媒体名之后，且必须与媒体同目录。
  - 临时文件的清理规则与命名绑定：改前缀必须同时改 `deleteStaleTemps` 与启动自愈
    （`maintenance_service` 用 `name.contains('.enc_tmp')`，对新旧命名都兼容）。
  - 已知**安全失败**：媒体名 ≥ 248 字节时 `.enc_bak` 的 rename 会失败，主文件不受损、
    返回 `Failed to back up original file`（不静默）；要支持这类名字需要先解决"备份→原名"的映射问题。
- 相关文件: `android/app/src/main/kotlin/com/privi/app/CryptoHandler.kt`、
  `lib/data/services/maintenance_service.dart`
- 相关条目: `ISSUE-034`、`PIT-061`、`PIT-056`、`PIT-034`、`ISSUE-030`
- 首次记录: 2026-10-13


## ADR-041 密钥备份包 = 明文 `salt + KEK`，导入后"导入的 KEK 优先"（解锁不再覆盖）
- 日期: 2026-10-13 | 状态: 已采纳（待真机复核）
- 背景: KEK = `PBKDF2(密码|图案, encryption_salt)`（`ADR-033`①），salt 存安全存储。卸载重装后 salt 消失，
  `SecurityService.deriveEncryptionKey()` 会**新建随机 salt** ⇒ 派生出另一个 KEK ⇒ 旧文件全部打不开。
  用户要求：能把密钥导出到网盘防丢，重装后导入即恢复解密能力（`ISSUE-036`）。
- 决策:
  ① 密钥包 = **明文 JSON**：`{format:'privi-key-backup', version:1, createdAt, encryptionSalt, kek(base64)}`；
  ② 导入 = 写 salt（**仅当本机没有** salt 时采用，沿用 `adoptEncryptionSaltIfAbsent`）+ `setImportedKey(kek)`；
  ③ `EncryptionKeyManager` 记 `privi_kek_source_v1 = imported|derived`；**导入态下解锁只加载持久化 KEK、不再派生**
     （`LockController._deriveAndStoreEncryptionKey`）；
  ④ 改密码/图案（`changePattern` / `changePin` / `migratePinToPattern`）在"派生新 KEK + 旋转全部 DEK"成功后
     `markDerivedKey()`，回到派生态；
  ⑤ 导入前必须通过 `matchesVault()`（最多 8 条 `encryptedDek` 实测解密）与 salt 冲突检查，任何一项不过就**拒绝**。
- 理由:
  - 只导 salt 不够：用户导密钥的动机就是"怕忘密码 / 怕 salt 丢"，带上 KEK 后**任意新图案**都能解锁；
  - 不做二次密码包裹：包裹要多记一个口令，而身份校验已由图案/PIN 承担；真正的风险边界是"密钥包文件本身怎么保管"，
    所以用 UI 明确警告 + 建议离线/加密网盘；
  - 固定持久化 KEK（而不是每次派生）是"重装后仍能解密"的必要条件；把"导入态"显式化成 source 标志，
    便于用一行日志判定（`unlock: using the imported vault key`）。
- 备选与为何不选:
  - **只导出 salt**：真忘了密码就没救，达不到防丢目的；
  - **密码二次加密密钥包**：多一层口令与失败点（用户已有一个密码/图案）；
  - **改成"KEK 随机生成 + 密码包裹存储"（LUKS 式）**：架构上更正确，但会牵动 `ADR-033`/`ADR-034` 的
    KEK 生命周期与所有解锁路径，属大重构，本 ADR 只在派生模型上加"导入态"这一条分支；
  - **导入时覆盖本机已有 salt**：会让本机已加密文件全部变孤儿（`ISSUE-029`③ 的老坑），直接否决。
- 影响 / 约束:
  - 密钥包 = 全部文件的钥匙：**不得**写入日志、备份 manifest 或除用户选定目录以外的任何位置；
  - **改过图案/密码后必须重新导出**：`changePattern` / `changePin` / `migratePinToPattern` 会派生新 KEK
    并旋转所有 DEK（`ADR-034`），旧包里的 KEK 与库不再匹配 —— 导入旧包会被 `matchesVault()` 拒绝，
    等于"这份备份过期了"（导出警告文案已提示）；
  - `key_backup_service.dart` 是包格式的唯一定义处，改格式必须升 `version`；
  - 导入态下"忘记密码也能进"是**设计意图**，但用户若想回到"密码派生密钥"，用「更改图案」即可
    （自动旋转 DEK + 退出导入态）；
  - 导出要求已解锁（`buildPackage` 在无 KEK 时抛 `StateError`），UI 先提示"请先解锁"；
  - 导入态**不改变** `ISSUE-030` 的重入守卫与 `decryptDek` 的失败语义。
- 相关文件: `lib/data/services/key_backup_service.dart`、`lib/data/services/encryption_key_manager.dart`、
  `lib/application/lock/lock_controller.dart`、`lib/presentation/settings/settings_screen.dart`
- 相关条目: `ISSUE-036`、`ADR-033`、`ADR-034`、`ADR-035`、`ISSUE-029`③
- 首次记录: 2026-10-13

## ADR-042 加密文件名：已加密媒体一律用「纯随机名、不带扩展名」，并提供一次性迁移按钮
- 日期: 2026-10-13 | 状态: 已采纳（**阶段 1 + 阶段 2 均已实施**：`ISSUE-038` 历史文件迁移、`ISSUE-040` 导入即随机名）
- 背景: 现在密文文件名是 `<uuid8>_<原文件名带扩展名>`（如 `1e795213_xxxx.jpg`）。虽然保险库目录有
  `.nomedia` + 隐藏目录，但"文件名带原扩展名"仍会**被按扩展名扫描的第三方程序**认出是媒体
  （用户诉求：加密时连文件名一起加密）。另外这批名字太长还引出过 `ISSUE-034`（临时/备份名超 255 字节）。
- 决策:
  ① 已加密媒体的文件名 = **32 位随机 hex，无扩展名**（例：`9f3c…c7a1`），原名继续只存 DB
     （`media_items.original_name` 已有，还原到相册仍用原名）；
  ② 入口**复用「加密已有文件」**（用户要求，不新增菜单项）：确认弹框里两个勾选项
     「加密文件内容」/「加密文件名」；勾了改名就对 `listEncrypted()` 中"命名仍是原样"的项逐项
     `rename` + 更新 `private_path`；**幂等**（`basename` 已匹配 `^[0-9a-f]{32}$` 的项跳过）——
     实现要点与判据见 `ISSUE-038`；
  ③ 阶段 2（已实施，见 `ISSUE-040`）：导入/隐藏链路（`HidePreparer` + `VaultStorageService.hiddenDestPath`）
     在**准备时 KEK 已加载**的情况下直接生成随机短名 ⇒ 新库不再产生长名；保险库锁定导入保留可读名
     （明文状态可读更合理，之后用「加密已有文件」勾「加密文件名」补做）。迁移按钮仍保留（兼容老库）。
- 理由:
  - **不含扩展名**才能挡住"按扩展名/关键词扫描"；统一后缀（`.prv`）仍会让扫描器建立关联，效果差一截；
  - "无扩展名也能正常用"在本仓库**已经验证**：解密到临时文件的名字一直是 `privi_dec_<millis>_<hex>`
    （无扩展名），照片与视频都能正常显示/播放 ⇒ 类型判定走 DB + 内容魔数，不依赖文件名；
  - 随机名同时顺带解决长名（`ISSUE-034` 的两处上限问题在新库里彻底消失）。
- 备选与为何不选:
  - **保留扩展名只打乱主名**：挡不住按扩展名扫描，等于没做；
  - **统一后缀 `.prv`**：仍可被"按后缀聚类"的程序识别成保险库文件，且引入新命名规则；
  - **放进单一大文件容器（虚拟文件系统）**：最彻底但工程量大，本项目不做（超出当前范围）。
- 影响 / 约束（实施前必须逐项确认，实施后必须真机验证）:
  - 依赖点：`MediaItem.isVideo` / `mimeType`（DB）、缩略图取帧（按内容探测）、播放器（ExifPlayer/VLC 按内容，
    且播放路径本来就经"解密到无扩展名临时文件"）、`Image.file`（按内容）、还原到相册（用 `original_name`）、
    备份 manifest（存路径 + 原名）、启动自愈（`.enc_tmp-*` / `.enc_bak`，已与媒体名解耦）；
  - 迁移**只动"已加密"项**；保险库锁定期间导入的明文项暂不改名（阶段 2 再统一），
    避免明文项在其它链路被按类型扫描时出现"文件没后缀"的新问题；
  - 迁移顺序：`rename` 成功 → 更新 DB；DB 更新失败则**尝试改回原名**，保持"DB 路径 = 实际文件"不变；
    失败项计数并汇总提示，可重跑（幂等）；
  - 迁移**必须**在已解锁状态执行（要读 `encrypted_dek`，且改名后立刻要能解密校验）；
  - 不许在迁移里顺手做别的（加密/解密/去重），一次只做改名。
- 相关文件（实施时）: `lib/data/services/vault_storage_service.dart`、`lib/data/services/import/hide_preparer.dart`、
  `lib/presentation/settings/settings_screen.dart`、`lib/data/repositories/media_repository.dart` + 新增迁移服务
- 相关条目: `ISSUE-034`（长名上限）、`ADR-033`（加密架构）、`PIT-031`（不要按扩展名判类型）、
  `ISSUE-029`③（还原用原名）
- 首次记录: 2026-10-13


## ADR-043 反向操作与"失效记录修复"：镜像 UI 选项 + 复用队列服务 + 只动随机名
- 日期: 2026-10-13 | 状态: 已采纳（待真机复核）
- 背景: 用户要求两个反向能力：① 「解密所有文件」（两个复选项：解密文件内容 / 解密文件名）；
  ② 清除"记录了已加密但文件仍是明文"的失效记录（早期 bug 留下 4 条，会让查看器把明文当密文解）。
- 决策:
  ① 「解密所有文件」放在设置 → 存储（紧挨「加密已有文件」），弹框选项与该入口**镜像**：
     「解密文件内容」（数量 = 有 DEK 的项）/「解密文件名」（数量 = 32 位随机名的项）；默认同样保守
     （有内容可解就勾内容，否则只勾文件名）；一项不勾 → 确定禁用 + 提示。
  ② 内容解密复用"并行队列 + 共享游标 + 节流进度"的既有模式（`BatchDecryptionService`），单项顺序固定为
     **解密文件 → 校验非空 → 原子替换 → 最后清 DEK**（`PIT-064`）。
  ③ 文件名解密复用 `FilenameEncryptionService` 的"rename → 校验 → 更新 DB → 失败改回"模式；反向**只处理
     32 位随机名**（历史 `<id8>_原名` 属"可读名"，不动），目标名取 DB `original_name`，重名按
     `<id8>_` → `-2…` → 随机名退避。
  ④ 「修复加密记录」放在维护组（与「扫描孤立隐藏文件」「修复拍摄时间」并列）：先 `scan(apply:false)` 出数量 →
     确认框 → `apply:true`；只清"有 DEK 但文件是明文"，"密文无 DEK"只报告不改。
  ⑤ 加密与解密**互斥**（`_encryptionFlowBusy()`）：两者都原地改写同一批文件（`ISSUE-030` 的教训）。
- 理由:
  - 镜像 UI 让"一对操作"的心智模型一致，用户不必学两套；
  - 复用既有队列服务与"rename → 校验 → 改 DB"定式，避免出现第二套不一致实现；
  - 失效记录修复是**幂等且安全**的：只删 DB 里多余的记录，不碰文件字节；
  - 把"不可恢复孤儿"显式报告而不是静默清理，用户才能决定去备份里找。
- 备选与为何不选:
  - **解密时直接删掉所有 `encrypted_dek`**：会制造"密文无 DEK"孤儿，直接否决；
  - **「修复记录」顺带把明文重新加密**：把维护动作变成破坏性操作，超出用户预期；
  - **文件名恢复连历史 `<id8>_` 前缀一起去掉**：会改动从未加密文件名的项，重名风险也更高；
  - **解密走"导出到相册"的既有链路**：那是"移出保险库"，与"留在库里但变明文"是两回事。
- 影响 / 约束:
  - 解密后 `encrypted_dek = null` ⇒ 这些文件会重新出现在「加密已有文件」的待加密列表里（可逆操作）；
  - 「修复加密记录」跑完 `ref.invalidate(albumsProvider / vaultSizeBytesProvider)`（队列状态变了）；
  - 解密同样受 `ISSUE-032` 约束：v1 大文件解密可能 OOM ⇒ 该项失败并保留密文，不会损坏文件；
  - 新增第三种"反向"操作时照本 ADR 三条定式走：镜像 UI、复用队列服务、崩溃窗口放可修复侧。
- 相关文件: `lib/data/services/batch_decryption_service.dart`、`lib/data/services/encryption_record_repair_service.dart`、
  `lib/data/services/filename_encryption_service.dart`、`lib/presentation/settings/settings_screen.dart`、
  `lib/application/providers.dart`、`lib/l10n/app_localizations.dart`
- 相关条目: `ISSUE-039`、`PIT-064`、`ISSUE-038`、`ADR-042`、`PIT-063`、`PIT-051`
- 首次记录: 2026-10-13


## ADR-044 取消隐藏的三条边界：被拦下的项"宁可不搬"、不自动清 DEK、缩略图缓存的作废机制
- 日期: 2026-10-14 | 状态: 已采纳
- 背景: 用户报「取消隐藏不能用 / 图片到了相册却显示失败 / 每十几项一个黑缩略图」。
  同时工作区里已有另一轮（trae）的补丁：`VaultRevealRunner._decryptIfNeeded` 跳过"已明文"的项、
  `GridThumbnailService` 不再把密文喂给解码器、`ThumbnailCache` 增加 `cacheVersion`。
  这三处方向都对，但边界要在代码里定死，否则下次改动又会退回去（`ISSUE-041`、`ISSUE-042`）
- 决策:
  ① **解密被拦下的项一律不进原生批量请求**（`_batchResults(movable)`）。宁可这轮少搬几项、
     把原因写进日志，也不允许密文离开保险库 —— `PIT-052` 的损坏不可逆
  ② `_decryptIfNeeded` 检测到"文件已是明文但 DB 还记着 DEK"时 **只跳过、不删 DEK**：
     删 DEK 不可逆，而且它可能是别处密文副本（例如备份、或已被误搬进相册的密文）的唯一钥匙；
     清理交给既有入口「设置 → 修复加密记录」（`ISSUE-039`）
  ③ 缩略图缓存作废用 `ThumbnailCache.cacheVersion`（`.cache_version` 不匹配就清盘），
     而不是换 key 前缀或每次启动清空；并且 `_resolveDir` 必须**单飞**（首帧并发 N 次 `_checkVersion`
     会互相删掉刚写好的缓存文件）
- 理由: 三条都是"失败时要保守"的取舍 —— 数据损坏不可逆，缓存/日志可以重来
- 备选与为何不选:
  - 让 Kotlin 侧在搬运前判密文（在原生里再写一份 `looksEncrypted`）：**不做** —— 签名表会有两份，
    必然漂移（`PIT-050` 的教训）；判断只在 Dart 侧保留一处真相
  - 在 reveal 里自动 `updateEncryptedDek(id, null)` 清理残留：会丢掉可能还能救回密文副本的 DEK，见 ②
  - 用文件 mtime/大小给缓存做指纹：不可靠（再生字节大小可能相同），不如显式版本号
- 影响 / 约束:
  - 改 `_batchResults` 调用点时，**请求列表与 `results` 的 index 兜底映射必须用同一个列表**（现在是 `movable`）
  - 新增任何"跳过某项"的分支都要 `AppLogger.w` + 尽量填 `lastError`，否则现场还是只剩一个数字
  - `cacheVersion` 是**手动**递增的：改了 `GridThumbnailService` 的 produce 逻辑就要 +1，否则老设备继续看旧字节
  - 注意 `cacheVersion` 只解决"旧字节"，**解决不了**"produce 返回 null"造成的深色 tile（见 `ISSUE-042`）
- 相关文件: `lib/data/services/import/vault_reveal_runner.dart`、`lib/data/services/thumbnail_cache.dart`、
  `lib/application/providers.dart`、`lib/data/services/grid_thumbnail_service.dart`
- 相关条目: `ISSUE-041`、`ISSUE-042`、`PIT-052`、`ISSUE-029`④、`ISSUE-039`、`PIT-066`
- 首次记录: 2026-10-14

## ADR-045 「加解密修复」：放进文件选择胶囊 + 就地修 + 多候选 DEK + 崩溃窗口放"密文侧"
- 日期: 2026-10-14 | 状态: 已采纳
- 背景: `ISSUE-044` —— 隐藏时"文件已像密文 → 跳过加密"，却把**新生成的 DEK 存进 DB**，
  之后所有解密路径必然 auth 失败：取消隐藏被 `ADR-044`① 拦下、相册里留下的文件打不开。
  设置页已有的两个入口都不适用：「解密所有文件」按 DB 行批量跑（文件已不在保险库的行没辙）、
  「修复加密记录」的判据与 `looksEncrypted` 同源（`ISSUE-043`②：识别不了"其实是明文但格式不认识"）
- 决策:
  ① 入口做成**文件选择操作**（可见网格 + 私密网格的选择胶囊各一个「加解密修复」），
     针对"当前选中的这几个文件"，而不是再加一个批量设置项；
  ② 每个文件按**证据**分派动作：明文嗅探命中且记录里有 DEK ⇒ 只清记录（一个字节都不碰）；
     否则按「本行 DEK → 同名/同大小行的 DEK」逐个尝试解密；
  ③ 试解成功才做「原地原子替换（密文 → `.enc_bak`，明文 → 原路径）→ 清 DEK」；
     全部失败则**完全保持原样**，并把 `bytes=` / `header=` 写进日志（现场可判定）；
  ④ 跨行 DEK 候选有硬上限（≤6 个；文件 >512 MiB 时只试本行）——每次尝试都要把整个文件读一遍，
     不设上限就会变成"看起来卡死"；
  ⑤ 中间文件沿用自愈能识别的名字（`.enc_tmp-repair-<哈希>` / `<path>.enc_bak`，见 `ISSUE-030`），
     文件名走哈希而不是拼媒体名（`PIT-061` 的 255 字节上限）；
  ⑥ 运行期：全局互斥（同时只跑一个修复，`ISSUE-030`）+ holder 常亮（`ADR-037`）+ 无取消按钮
     （解密 + 替换中途被打断正是 `PIT-064` 的崩溃窗口）
- 理由: 用户此刻面对的是"一个已可见的文件打不开"，最小修复面就是"这个文件 + 它的记录"；
  把动作分派交给证据（文件头 + DB 记录）而不是猜，才能一并覆盖"真密文配错钥匙"与"明文被当成密文"两种状态
- 备选与为何不选:
  - 让「取消隐藏」在解密失败时自动清 DEK 并把文件搬出去：违反 `ISSUE-029`④ / `ADR-044`（fail-open 数据损坏）
  - 复用「修复加密记录」的批量扫描：判据同源，正是 `ISSUE-043`② 指出"修不了"的那种情况
  - 遍历库里**所有** DEK 去撞：大文件 × N 次全量解密，耗时不可控；先只扩到"同名/同大小"这一层
  - 把修复做成"导出到临时目录再比对"：多一次全量拷贝，且与可见相册不同卷时 rename 非原子（`PIT-034`）
- 影响 / 约束:
  - 该动作会**原地改写用户可见的原文件** ⇒ 失败必须回滚、`.enc_bak` 必须留到最后才删；
    任何"顺手清理"都要先确认文件确实已是明文
  - 修完要刷新周边状态：可见网格 `MediaStore.scanPath` + `_reload()`、两个网格的缩略图缓存
    `evictAsset` / `evictVault`、`albumsProvider` / `vaultSizeBytesProvider` 作废
  - 新增候选策略（例如"按内容摘要匹配"）时，必须同时遵守 ④ 的耗时上限
- 相关文件: `lib/data/services/media_crypto_repair_service.dart`、`lib/presentation/common/crypto_repair_action.dart`、
  `lib/presentation/grid/media_grid_screen.dart`、`lib/presentation/visible/visible_media_grid.dart`、
  `lib/application/providers.dart`
- 相关条目: `ISSUE-044`、`ISSUE-041`、`ISSUE-043`、`ISSUE-039`、`ISSUE-030`、`ADR-037`、`ADR-044`、`PIT-034`、`PIT-061`、`PIT-064`
- 首次记录: 2026-10-14

## ADR-046 build.bat 的「确定性路径 + 硬失败 + 退出码透传」三条约定
- 日期 2026-10-14 | 状态: 已采纳
- 背景: `ISSUE-045`：tee 包装器 `--log` 重启 + `shift` 让 `%~dp0` 变成"当前目录"，导致 [4/7] 的看门狗脚本路径指错
  （PowerShell `-File` 返回 `-196608`）；又因块内 `%ERRORLEVEL%` 是解析期取值，这个码一路冒充"flutter 的退出码"
  ⇒ 明明 `√ Built` 却判"构建失败"，APK 不复制、Release 不发布；同时辅助脚本缺失时是"警告 + 跳过"（`ISSUE-011` 同类静默降级），
  且脚本对外退出码恒为 0（包装器结尾裸 `exit /b`，内层结果被丢掉）。
- 决策:
  ① **路径去魔法**：文件开头（任何 `shift`、任何分支之前）固化 `SCRIPT_DIR` / `PROJECT_ROOT`，
     全文不再出现裸 `%~dp0`（含 `cd /d "%PROJECT_ROOT%"`、`GRADLE_USER_HOME`、包装器日志路径）；
  ② **缺脚本 = 硬失败**：5 个辅助 ps1（`build_hash` / `build_pub_get` / `build_wmi_guard` / `build_mem` / `bump_version`）
     任一缺失 ⇒ 启动自检直接 `[错误]` + `BUILD_FAILED=1` + 终止（不再"找不到就跳过"）；
     [4/7] 调用前再单独 `if not exist` 兜一层，并把 `-196608` 明确解释出来；
  ③ **退出码只用 `!ERRORLEVEL!`**：凡在 `( )` 块内读取，一律延迟展开（`PIT-007`）；
  ④ **结果要透传**：包装器 `finally` 里 `exit $LASTEXITCODE`，脚本退出码必须等于内层结果（0/1）。
- 理由: 路径与退出码是"判定构建成功/失败"的基础设施；这里宁可失败得响亮，也不能静默降级或误报
  （误报的代价 = 用户以为没编出来，实际 APK 已生成但没有复制/发布）。
- 备选与为何不选: ① 保留 `%~dp0` 但禁用 `shift`（要重写全部参数分发，改动面大且满文件 `%~1`）；
  ② 只把出问题的那一行写死绝对路径（治标，换个 cwd 或下次编辑再踩）；
  ③ 继续用"警告 + 跳过"处理缺失脚本（历史证明会被忽略，`ISSUE-011`）。
- 影响 / 约束（后续改动必须注意）:
  - 新增辅助脚本要同步进 `build.bat` 的自检清单（并放进 `scripts\tools\`）；
  - 改完 `build.bat` 先跑 `ISSUE-045` 的复发判据 ①②；
  - **不要在 `build.bat` 运行期间改写它**（cmd 按字节偏移续读，会把新文件的片段当命令执行，见 `PIT-075`）。
- 相关条目: `ISSUE-045`、`ISSUE-011`、`ISSUE-007`、`PIT-007`、`PIT-073`、`PIT-074`、`PIT-075`、`ADR-027`（构建由用户手工执行）
- 首次记录: 2026-10-14


## ADR-047 密钥包改用 SQLite 数据库（v2）：密钥 + 每文件 DEK + 文件名映射一起走
- 日期: 2026-10-21 | 状态: 已采纳（待真机复核）
- 背景: `ADR-041` 的 v1 包是 5 字段 JSON，只解决"`KEK` + salt 丢失"（`ISSUE-036`）。
  但重装/换机同时丢掉 metadata DB，于是密文文件（随机名，`ADR-042`）既没有原名可显示，
  也没有 `encrypted_dek` 可解密（`ISSUE-049`）。用户要求把"所有跟加解密相关的信息"一起带走，
  并明确"格式改成 SQLite 数据库文件以便存更多信息"。
- 决策:
  ① 包 = **单个 SQLite 数据库文件**（`privi-key-YYYYMMDD-HHMMSS.db`），格式版本 `2`；
  ② 三张表：`meta(key,value)`（format/version/createdAt/fileCount/encryptedFileCount/warning）、
     `key_material(id=1, encryption_salt, kek BLOB, kek_source, created_at)`、
     `media_keys(media_id, private_path, original_path, original_name, mime_type, is_video,
     size_bytes, width, height, duration_ms, date_added, date_taken, encrypted_dek, content_digest)`；
     `PRAGMA user_version = 2` 供外部工具识别；
  ③ 直接依赖 `package:sqlite3` 读写（`sqlite3_flutter_libs` 已提供原生库，drift 启动时已加载），
     **不复用** app 的 drift schema（包格式必须独立于内部 schema 迁移）；
  ④ 导入沿用 v1 的两道闸门（salt 冲突、KEK 实测），再把映射**有选择地**写回：
     只有本机存在同名文件的条目才建行/补 DEK，其余"跳过"并计数；
  ⑤ v1 JSON 包保留只读兼容（首字符 `{` 分支），不提供降级导出。
- 理由:
  - 一份文件解决"密钥 + 文件名 + DEK"，用户少管一个东西，也避免"导了密钥却忘了导映射"；
  - SQLite 天然支持多表、索引与演进（以后加相册归属、缩略图清单只需加列/加表，不破坏旧包）；
  - 只给存在的文件建行，才能避免"导入后满屏打不开的空条目"这种更糟的用户体验。
- 备选与为何不选:
  - **继续扩 JSON 字段**：结构演进、按行查询、大库（数千条）都别扭，且没有版本化的 schema；
  - **zip（manifest + jsonl）**：自造容器格式，要自己写校验/分块，SQLite 现成；
  - **直接导出 app 的 drift 数据库**：把相册、播放历史等与加解密无关的数据也带走，
    且包格式被内部 schema 版本绑死（一次迁移就让旧包读不了）；
  - **把 KEK 用密码二次包裹**：见 `ADR-041` 的取舍（多一个口令与失败点），本次不改变安全边界。
- 影响 / 约束（后续改动必须注意）:
  - `key_backup_service.dart` 仍是包格式的**唯一**定义处：改 schema 必须升 `formatVersion`，
    并在 `_readSqlitePackage` 里保留旧版本读取分支（`version > formatVersion` ⇒ `unsupportedVersion` 拒绝）；
  - 包内 `encrypted_dek` 是"文件+KEK 之外"的额外敏感物，但安全边界不变：**包 = 明文 KEK**，
    UI 警告与"离线/加密网盘保存"文案必须保留（导出前确认框已有）；
  - 导入是**单向**的：不改本机已有的 `original_name`（避免覆盖用户改名），**不覆盖已有 DEK**
    （文件可能在本包之后被重新加密，旧 DEK 已不匹配字节）；只补"缺失且 `looksEncrypted` 成立"的 DEK；
  - 改过图案/密码后旧包依旧过期（`ADR-034` 会旋转全部 DEK），仍需重新导出（文案已提示）；
  - 包格式 v2 与"整库备份/恢复"（`vault_backup_export`）是两件事：后者搬媒体文件，本条只搬密钥与索引。
- 相关文件: `lib/data/services/key_backup_service.dart`、`lib/data/services/vault_storage_service.dart`、
  `lib/presentation/settings/settings_screen.dart`、`lib/l10n/app_localizations.dart`、`pubspec.yaml`
- 相关条目: `ISSUE-049`、`ISSUE-036`、`ADR-041`、`ADR-042`、`ADR-034`
- 首次记录: 2026-10-21

