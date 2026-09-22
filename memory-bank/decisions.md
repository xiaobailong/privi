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
