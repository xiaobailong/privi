# 踩坑记录（pitfalls）

> 记「**本机环境 / 工具链 / 命令语法**」层面的坑：踩一次就写，不管问题最终有没有修好。
> 每条必须有「正确做法」（可直接复制）与「反例」（别这么写）。模板见 `README.md` §5。

## PIT-001 本机安全策略静默拦截长 `powershell -Command`（含正则/管道）→ 退出码 786、无输出
- 触发条件: 用 `powershell -NoProfile -Command "<带正则或管道的一长串>"`
- 错误现象: 什么都不输出、退出码 **786**，被当成"命令没结果"；脚本层面表现为哈希为空、文件没改
- 正确做法: 逻辑写成 `.ps1` 文件，用 `powershell -NoProfile -ExecutionPolicy Bypass -File <脚本> -参数`
- 反例: `powershell -Command "$t -replace '(\+)\d+', ...; [IO.File]::WriteAllText(...)"`
- 自检: 命令退出码 786 或"没输出但应该有输出" ⇒ 立刻改 `-File`
- 首次记录: 2026-09-21 ／ 最近复核: 2026-09-22（`scripts\build_hash.ps1` 用 `-File` 调用正常出哈希）

## PIT-002 `.ps1` 必须 UTF-8 **BOM** + CRLF；`.bat` 必须 UTF-8 **无 BOM** + CRLF
- 触发条件: 新建/改写 PowerShell 脚本（尤其含中文注释）
- 错误现象: Windows PowerShell 5.1 缺 BOM 时按 **GBK** 读脚本 ⇒ 中文全乱码、甚至语法错误；
  `.bat` 带 BOM 则第一行 `@echo off` 变 garbage（cmd 报错/首行不生效）
- 正确做法: 写完用脚本核对：读前 3 字节判断 `EF BB BF`，并统计 CRLF 与 bare LF
  （本次实现见 git 历史里的临时校验脚本；`scripts\` 下 7 个 ps1 全部 `enc=BOM CRLF=...`，`bareLF=0`）
- 反例: 用编辑器直接"另存为 UTF-8"（多数编辑器默认无 BOM）
- 自检: `enc=BOM` + `bareLF=0` 才算合格
- 复核 2026-09-22（又踩一次，症状更隐蔽）: 临时脚本 `tmp\grep_log.ps1` 里写了中文路径
  `$root\tmp\密册_log_2026-09-22.txt`，而该 ps1 是**编辑器写出的无 BOM UTF-8**
  ⇒ PowerShell 5.1 按 GBK 解码，路径变乱码 ⇒ 脚本一声不响，`Get-Content` 返回
  **0 行**，输出文件里只有 `TOTAL_LINES=0`，看着像"日志文件是空文件"。
  正确做法：**无 BOM 的 ps1 里不要出现中文路径/中文字面量**，改用通配符定位：
  `$src = (Get-ChildItem -Path "$root\tmp" -Filter '*_log_2026-09-22.txt' | Select-Object -First 1).FullName`
  （`read_files` 传中文绝对路径不受影响，那是 Cline 侧按 UTF-8 处理）
- 新增自检: 脚本输出"空/0 行/0 命中"时，先确认脚本自身编码是否 BOM；再确认里面有没有中文字面量

## PIT-003 PowerShell 嵌套数组会被展平 ⇒ `@(@('a','b'))` 里 `$pair[0]` 取出的是**字符**
- 触发条件: 写"成对参数"表，如 `$pairs = @(@('old','new'), @('old2','new2'))` 再 `foreach ($p in $pairs) { $p[0] / $p[1] }`
- 错误现象: 内层数组被展平成字符串序列，`$p[0]` = 字符串首字符、`$p[1]` = 第二个字符 ⇒
  **变成按单字符全局替换**。本项目实际事故：`'-File build_mem.ps1'` 被当成 `old='-'` / `new='F'`，
  把 7 个 ps1 里所有 `-` 全换成 `F`（`Get-FileHash` → `GetFFileHash`），文件全废
- 正确做法: 每个替换用**两个独立的 `[string]` 参数**，一次调用只做一对替换：
  `Update-File -Path 'build.bat' -Old 'build_hash.ps1' -New 'scripts\build_hash.ps1'`
- 反例: `@(@('a','b'), @('c','d'))` 传进 `-Pairs`；或 `foreach ($p in $pairs) { $p[0] }`
- 自检: 替换完**逐行看 `git diff`**；再对所有脚本跑一次 PowerShell Parser 语法检查；
  出现"某个字符被大面积替换"立刻 `git checkout -- <路径>` 从 index 还原
- 首次记录: 2026-09-22（本仓库真实事故，已完整还原并重做）

## PIT-004 替换文本包含查找文本时，绝不能 `while`/反复 `Replace`
- 触发条件: 把 `build_hash.ps1` 替换成 `scripts\build_hash.ps1`（新文本**包含**旧文本）
- 错误现象: 循环替换 ⇒ `scripts\scripts\build_hash.ps1`（前后缀重复），或死循环
- 正确做法: **单次** `$text.Replace($old, $new)`（或 `-replace` 只跑一次），并先 `Contains` 判空
- 反例: `while ($text.Contains($old)) { $text = $text.Replace($old, $new) }`
- 自检: grep 目标文件是否出现 `scripts\scripts\`、路径段重复

## PIT-005 `echo xxx(!VAR!)yyy` 写在 `if (...)` 块里 → `)` 提前闭合批处理
- 触发条件: 在 `( )` 块内的 `echo` 里出现半角括号
- 错误现象: `: was unexpected at this time.` / 整个批处理中断
- 正确做法: 括号用 `^(` `^)` 转义（或改用全角括号）；必要时把整行拼进变量再 `echo !VAR!`
- 反例: `echo 检查未完全成功 (exit=%X%)，继续构建...`
- 自检: 批处理是否"只跑一半就退出"、有无 `unexpected at this time`

## PIT-006 `echo` 里输出重定向符要转义；`%ERRORLEVEL%>> file` 相邻写法会吞内容
- 触发条件: 想"打印一条含 `>` 的命令提示"或"把退出码写进文件"
- 错误现象: 提示里的 `>` 被 cmd 当重定向（把后面的内容写进文件）；`echo X=%ERRORLEVEL%>> f.txt` 里
  变量与 `>>` 相邻时会吃掉输出（本次实测：日志里只留下空行，内容跑到了控制台）
- 正确做法: 转义 `^>`；写退出码时把重定向**用空格隔开**或先存变量：
  `set "RC=%ERRORLEVEL%"` + `echo PUBGET_EXIT=%RC%>> file`（或 `>> file echo ...`）
- 反例: `echo git show a:b > scripts\x.ps1`（真的会写文件）；`echo RC=%ERRORLEVEL%>> f.txt`
- 自检: 文件里该出现的行是否真的出现了

## PIT-007 `%VAR%` 是解析期展开、`!VAR!` 才是延迟展开（同一行 `&` 链必踩）
- 触发条件: 在同一行用 `&` 串命令并读取上一条命令刚设置的变量 / `ERRORLEVEL`
- 错误现象: 取到**旧值或空值**（例如 `set "FL=path" & "%FL%\x.exe"` 用的是旧值）
- 正确做法: 同一行里用绝对路径；批处理内需要先设后用就开 `setlocal enabledelayedexpansion` 用 `!VAR!`；
  退出码用 `set "RC=%ERRORLEVEL%"` 再判断，或用 `if errorlevel` 结构
- 反例: `&` 链里 `%FL%` / `( ... %ERRORLEVEL% ... )` 块内读 `%ERRORLEVEL%`
- 自检: 变量/退出码判断是否"永远走同一分支"

## PIT-008 本环境终端抓不到命令输出 ⇒ 一律重定向到文件再读；且**一次只发一条命令链**
- 触发条件: 用终端跑命令并想直接看结果
- 错误现象: 输出丢失（"could not be captured through shell integration"）；
  更坑的是**新命令会掐掉仍在运行的前一条命令**（构建/长任务被静默中断）
- 正确做法: `cmd > out.txt 2>&1` 然后 `read_files` 读该文件；把多条独立命令**串进同一行**（`&` / `&&`）执行；
  长任务用独立窗口（见 `PIT-009`）
- 反例: 一条消息里发多条独立命令（并行/互相打断）；直接依赖终端回显
- 自检: 关键结果是否落在文件里、能否二次读取复核
- 复核 2026-10-07（`git push` 链路，本条最容易误判的形态）: 用 `&&` 串起
  「push main → checkout dev → merge --ff-only → push dev」后立刻读回执，
  **第一个输出文件已写完、后面几个还没被创建**（`co_main.txt` / `merge_dev.txt` 报 ENOENT），
  看着像"链条在 push 处断了"，其实只是 SSH 还在建连/传输 —— **再读一次就齐了**：
  `push_main.txt` = `ae4b5e1..6f48328  main -> main`、`push_dev.txt` = `8e1ea91..6f48328  dev -> dev`。
  易误判点：①`push_*.txt` **空文件 ≠ 失败**（命令仍在跑）；②因此重发命令会**掐断正在进行的 push**
  （同 `PIT-021` 的"等待被提前掐断"）；③判断是否真失败，等第二个文件出现后再看内容，不要看文件是否存在
- 复核 2026-10-07（第二轮：换成**不碰终端**的复核手段）: `git push origin main` 的终端回显只有
  `Active code page: 65001`（等于没输出），紧接着读 `.git\refs\remotes\origin\dev` 还是**旧值** `8fde665…`
  —— 差一点判成"push 没生效"。**不要**为此重发命令（会掐断正在跑的 push，同 `PIT-021`）。
  最稳的判据是**完全不用终端**，直接 `read_files` 读 git 自己的记录：
  - `.git\refs\remotes\origin\<branch>`：push 成功后就是新提交号（`main` 这次立刻可见）；
  - `.git\logs\refs\remotes\origin\<branch>`（reflog）：最后一行为
    `8fde665… 1004a89… <作者/时间>  update by push` ⇒ **铁证**。
  本次 `dev` 是 reflog 先出现 `update by push`、ref 文件**滞后十几秒**才刷新。
  ⇒ 复核顺序：ref/reflog 文件 → `git branch -vv` 里 `[origin/xx]` 是否还带 `ahead N` → 最后才看终端回显。
- 复核 2026-10-07（第三轮：`git ls-remote` 紧跟 push 之后的**假失败**）: `git push origin main` 成功
  （回执 `cb4c67a..e682c5f  main -> main`，落在 `tmp\push_main.txt`），但同一条命令链里紧随其后的
  `git ls-remote origin refs/heads/main refs/heads/dev` 报：
  ```
  fatal: Could not read from remote repository.
  Please make sure you have the correct access rights
  and the repository exists.
  ```
  —— **不是**权限/仓库问题：隔几秒重试同一条命令就正常返回
  （`refs/heads/main = e682c5f`（新）、`refs/heads/dev = cb4c67a`（未动，正是要证明的结论））。
  ⇒ 判据：**push 的回执行**（`<old>..<new>  <branch> -> <branch>`）才是"推成功"的证据；
  `ls-remote` 只用于核对"其它分支没被动"，一旦报 `Could not read` 就**等几秒重试**，
  别改判成"推送失败"、更别重发 push（重发可能掐断仍在跑的传输，同 `PIT-021`）。

## PIT-009 长构建要放独立窗口 / 分离进程，前台跑会被下一条命令掐断
- 触发条件: `build.bat` 这类分钟级任务
- 错误现象: 跑到一半被杀，`build_full.log` 停在中间，或产生"半成品"状态
- 正确做法: `start "Privi Build SelfTest" cmd /c "build.bat gradle"`（新窗口，独立存活），
  然后**只用 `read_files` 轮询** `build\build_full.log`；需要等待就 `ping -n N 127.0.0.1 > nul`
  （本机 `timeout` 在非交互环境不可靠）
- 反例: 前台起构建后又发命令/构建中反复发命令
- 自检: `build_full.log` 是否连续、进程（`tasklist | findstr java/dart`）是否还在

## PIT-010 `Get-Content` 默认按 GBK(936) 解码 ⇒ 中文被啃成 `?` 或乱码
- 触发条件: 读 dart/flutter 写出的 UTF-8 日志
- 错误现象: 日志里中文变 `?`，据此排查会得出错误结论
- 正确做法: 一律 `Get-Content -LiteralPath <f> -Raw -Encoding UTF8`；
  控制台输出也先 `[Console]::OutputEncoding = [Text.Encoding]::UTF8`
- 反例: `Get-Content build\x.log -Tail 20`
- 自检: 读回来的中文是否正常（拿已知中文行验证）

## PIT-011 本机 WMI / `jps` / `jcmd` / `Get-Counter` 会**挂死**（无输出、永不返回）
- 触发条件: 用它们查内存、进程、性能计数
- 错误现象: 命令永远不返回，连带把整个排查卡死（与 `ISSUE-001` 同源）
- 正确做法: 内存用 kernel32 `GlobalMemoryStatusEx`（P/Invoke，见 `scripts\build_mem.ps1`）；
  进程列表用 `Get-Process` + 可执行文件路径过滤；杀进程用 `Stop-Process`
- 反例: `Get-CimInstance Win32_OperatingSystem`、`jps -l`、`Get-Counter`
- 自检: 命令是否在 1~2 秒内返回（否则立刻停手，别等）

## PIT-012 Gradle 离线构建必须带 Flutter 镜像环境变量，否则 `--offline` 报「缺少依赖」
- 触发条件: `gradlew ... --offline`（或不带镜像变量）
- 错误现象: `No cached version of ... available for offline mode` ⇒ **看起来像依赖缺失**
- 正确做法: 先设再跑（离线缓存 key 与仓库 URL 绑定）：
  `set "FLUTTER_STORAGE_BASE_URL=https://storage.flutter-io.cn"` / `set "PUB_HOSTED_URL=https://pub.flutter-io.cn"`
- 反例: 不带镜像变量直接 `--offline`，然后去改依赖版本"修"一个不存在的缺失
- 自检: 不带 `--offline` 能解析成功、带 `--offline` 才报错 ⇒ 就是它
- 来源: `docs/HANDOFF-Flutter工具WMI挂死诊断.md`「不修 WMI 也能用」第 2 条

## PIT-013 本机可靠的 Kotlin 校验方式：只跑 `:app:compileReleaseKotlin` 并排除 Flutter 任务
- 触发条件: flutter 工具不可用（WMI 挂死期间）但仍要验证 Kotlin 改动
- 错误现象: 直接跑 `assembleRelease` 会连带触发 `:app:compileFlutterBuildRelease`（需要 flutter）→ 卡死/失败，
  得不到"Kotlin 是否编过"的结论
- 正确做法:
  `gradlew -x :app:compileFlutterBuildRelease :app:compileReleaseKotlin`（插件模块基本全 UP-TO-DATE）
  → 出现 `BUILD SUCCESSFUL` + `:app:compileReleaseKotlin` 真执行 = 最强证据
- 反例: 用 `flutter build apk` 去验证一个纯 Kotlin 改动（受 WMI/Flutter 工具链影响，结论不干净）
- 自检: 任务图里是否真的执行了 `compileReleaseKotlin`（不是 UP-TO-DATE）

## PIT-014 `dart analyze` / `dart format` 会挂死（dartdev 遥测）⇒ 用 `frontend_server` 校验 Dart
- 触发条件: 需要校验 Dart 语法/类型但 flutter 工具挂死
- 错误现象: `dart analyze` 卡在 `dartdev` 遥测，永不返回
- 正确做法: 直接跑 Flutter 真正用的编译器前端（**AOT 快照必须用 `dartaotruntime.exe`**，用 `dart.exe` 会报误导性的
  `The system cannot find the path specified.`）：
  ```
  "D:\Tools\DevTools\flutter\bin\cache\dart-sdk\bin\dartaotruntime.exe" ^
    "D:\Tools\DevTools\flutter\bin\cache\dart-sdk\bin\snapshots\frontend_server_aot.dart.snapshot" ^
    --sdk-root "D:\Tools\DevTools\flutter\bin\cache\artifacts\engine\common\flutter_patched_sdk\" ^
    --target=flutter --packages=.dart_tool\package_config.json ^
    --output-dill=build\_dartcheck.dill lib\main.dart
  ```
  输出最后一行是 `<uuid> <dill 路径> <错误数>`，**只看最后那个数字**（0 = 通过）
- 反例: 把中间那一大串 `+file:///…` 当成错误；不改文件就相信"0 error"（要用负控验证工具真的在检查）
- 自检: 负控（故意写错的文件）应报出 >0 个 error
- 来源: `docs/HANDOFF-Flutter工具WMI挂死诊断.md` 第 5 条
- 复核 2026-10-07（本轮实测：条目里"`dart format` 会挂死"**未复现**）:
  ```
  D:\Tools\DevTools\flutter\bin\cache\dart-sdk\bin\dart.exe format --output=none --set-exit-if-changed lib\presentation\common\swipe_action_cell.dart
  ```
  **0.04s 返回**（4 个文件一起亦然），可作为**最快的 Dart 语法自检**：
  语法错会直接报 `Could not format because the source could not be parsed`，
  纯格式差异只打印 `Changed <file>` 并退出码 1。**挂死的是 `dart analyze`**（分析器 + dartdev 遥测），
  `dart format` 只做解析/排版 ⇒ 校验 Dart 改动时先试它，比 `frontend_server` 那条命令便宜得多。
- 路径更正（本轮踩到）: **`<FLUTTER_HOME>\bin\dart.exe` 在本机不存在**（`where dart` 也找不到，`FLUTTER_HOME` 见
  `build.bat:58` = `D:\Tools\DevTools\flutter`），正确路径是
  `%FLUTTER_HOME%\bin\cache\dart-sdk\bin\dart.exe`（与 `build_wmi_guard.ps1:67` 一致）。
  报 `'...\bin\dart.exe' is not recognized` 时**别怀疑 Dart 坏了**，就是路径错。
- 判读技巧（本轮用到）: `format --output=show <file> > tmp\x.dart` 再 `fc /n <file> tmp\x.dart`，
  差异里**只出现在自己没改过的段落** ⇒ 说明该文件的旧风格本来就不符合新版 dart format，
  **不要**对自己的改动做全局重排（`--output=show` 会在末尾多一行 `Formatted 1 file ...`，别当成差异）。
- 复核 2026-10-07（`--set-exit-if-changed` 在**本仓库任何 Dart 文件**上都会报 `Changed`）:
  `git ls-files --eol lib/presentation/player/player_screen.dart` → **`i/lf w/crlf`**
  （工作区是 CRLF、索引是 LF），且 Dart 3.7+ 的「tall style」格式化器会重排大量旧代码。
  决定性对照：把 **HEAD 版本**导出到 `tmp\` 后跑同一条命令，同样报 `Changed`
  （`tmp\head_fmt.txt` = `Changed tmp\ps_head.dart` / `Changed tmp\vc_head.dart`）
  ⇒ 这条命令在本仓库只能当**语法**校验用（解析失败会明确报
  `Could not format because the source could not be parsed`），**不能**当作「格式已通过」的判据。
  想确认自己**新写的那几行**是否合规：`dart format --output=show <file> > tmp\x.dart`，
  然后只读自己动过的那几行去对照（本次据此改掉了 1 处续行缩进 + 2 处 doc 注释前缺空行），
  与 `ADR-026` 的做法一致：**只对齐自己的段落，绝不全局重排**。
  另：`format --output=show` 写进文件后与原文件字节数差 ~280B 属正常（tall style 的重排量），
  不要用文件大小判断"有没有被格式化"。

## PIT-015 批量改动改坏了怎么救：`git checkout -- <路径>` 从 index 还原（不用重写）
- 触发条件: 脚本/工具批量替换把文件内容改坏（或改错方向）
- 错误现象: 想手动回滚，越改越乱
- 正确做法: `git checkout -- build.bat scripts`（从 **index** 还原工作区内容）；
  用 `git ls-files -s scripts` 拿索引里的 blob 哈希、`git rev-parse HEAD:<file>` 对照，确认还原到原内容；
  `git mv` 登记的 rename 不会被这次 checkout 撤销（改名保留、内容还原）
- 反例: 逐个文件手工撤销；或 `git checkout HEAD -- .`（会连别处未提交的工作一起丢掉）
- 自检: 还原后 `git diff --numstat <路径>` 应为空

## PIT-016 `flutter pub get` 会污染 `pubspec.lock`（镜像域名被改回去）
- 触发条件: 跑 `pub get` / `pub upgrade` 后 `git status`
- 错误现象: `pubspec.lock` 出现成百行 diff（`pub.flutter-io.cn` ↔ `pub.dev`），淹没真实改动
- 正确做法: 确认无依赖变更时 `git checkout -- pubspec.lock` 还原；提交前检查该文件是否被噪声污染
- 反例: 把镜像域名变更一起提交
- 自检: `git diff --numstat pubspec.lock` 只在真正升降级依赖时才非空
- 来源: `docs/HANDOFF-媒体类型重构.md` §2.3

## PIT-017 诊断产物要放 `docs\`（或 memory-bank），**不要放 `build\`**
- 触发条件: 写排查脚本/日志/交接文档
- 错误现象: `flutter clean` / `build.bat clean` 会删掉 `build\`，文档和脚本一起消失
- 正确做法: 需要留存的放 `docs\`（已被 `.gitignore` 忽略、不会被 clean 删）或 `memory-bank\`（进 git）；
  纯临时的放 `build\`
- 反例: 把交接文档写在 `build\` 下
- 自检: 跑完 `build.bat clean` 后文档还在不在
- 来源: `docs/HANDOFF-媒体类型重构.md` 开头说明

## PIT-018 同一个输出文件反复写入时，工具可能只回 `[outdated]` / 读到旧内容
- 触发条件: 反复把命令输出重定向到**同一个**文件名，然后再读
- 错误现象: 读到的还是上一轮内容（或工具提示文件未更新）
- 正确做法: 每轮换一个文件名（如 `test_hash_gradle2.txt`），或先 `del` 再写；
  **判断"构建是否还在跑"要看小文件**（`build\build_exit.log` 的 mtime/内容）而不是长日志尾部
- 反例: 一直用 `out.txt`；靠读 `build\build_full.log` 判断进度
- 自检: 内容是否与刚跑的步骤匹配（不匹配就换名重跑）
- 实测（2026-09-22）: 构建 16:46:12 已结束并写进 `build\build_exit.log`，
  但同一路径 `build\build_full.log` 连续读 4 次仍只显示到第 31 行（旧内容）；
  只有再等一段时间/换名读才看到尾部 → **不要据此判断"构建卡住了"**（对比 `ISSUE-002` 的 0 字节才是真卡死）
- 实测追加（2026-09-22 19:0x，本轮三次踩到同一件事）:
  ① **`scripts\build_wmi_guard.ps1` 的输出文件停在 0 字节，不代表它没跑** ——
     只要我发下一条终端命令，前一条（含守卫）就被回收，输出永远写不出来；
     正确做法是把守卫/长任务放**独立窗口**（`start "" /min cmd /c "..." > tmp\x.txt 2>&1`），
     之后只用 `read_files tmp\x.txt` 看结果（不再动终端）；
  ② `build\build_full.log` 在 `dir` 里显示 **0 字节**、1 秒后的 `copy` 却有内容 ⇒ 同一条命令链里
     "先 dir 再 copy"会看到两个不同结果，别用 dir 的大小下结论；
  ③ 判断构建是否还在跑，用 `tasklist /fi "imagename eq java.exe"`（Gradle JVM 内存会持续上涨）
     或看 `build\app\outputs\mapping\release\*` 是否已被写出，比读日志可靠
- 实测追加（2026-09-22 17:54）: `read_files` 读 `push5.txt` 返回**空内容**，同时 `dir /tw` 显示它其实已有
  **333 字节**（里面正是 `Connection reset by ... port 22` + `ls-remote` 结果）⇒
  判断"命令没输出/文件没写"之前，先用 `dir /tw <文件>` 看 size/mtime

## PIT-019 本仓库的「检索手段」实测：`search_codebase` 常超时、cmd `findstr` 搜中文不可靠
- 触发条件: 想在仓库里按关键词找东西（包括检索 `memory-bank/`）
- 错误现象: ①Cline 的 `search_codebase` 在本工作区多次 30s 超时（连 `ISSUE-011` 这种纯 ASCII 词也超时）；
  ②cmd 里 `findstr /s /n /c:"卡死" memory-bank\*.md`（65001 代码页）**零命中**，
  而同一批文件里确实有「卡死」两个字（`read_files` 能看到）
- 正确做法: **优先 `read_files` 直接整篇读**（`memory-bank/` 4 个文件合计 ~50KB，最可靠、代价可接受）；
  需要批量过滤时用 `powershell ... -File <脚本>` 里的 `Select-String -Encoding UTF8`（`-Command` 会被 786 拦，见 `PIT-001`）
- 反例: 用 `findstr`/`search_codebase` 零命中就下结论「知识库里没有」「仓库里没有」——
  这是**假阴性**，中文关键词尤其危险
- 自检: 用一个"已知一定存在"的词做正控（例如在你刚写下的行里搜），确认检索手段本身有效
- 首次记录: 2026-09-22

## PIT-020 `flutter analyze` / `dart analyze` 在本机「看起来卡住」+ 长输出读不到最新内容
- 触发条件: 想用静态分析校验 Dart 改动，并把输出重定向到文件后再读
- 错误现象: ①输出文件里一直停在 `Analyzing privi...`，**连续 25 分钟读不到任何结果**
  （`dart.exe` 内存 165MB → 338MB 持续增长，其实一直在干活）；
  ②`analyze_out.txt` 反复读都只有 167 字节，实际跑完是 **2068 字节**
  —— 是**读取滞后**（`PIT-018`），不是文件没写
- 正确做法: ①**先按"它其实在跑"处理，别急着杀进程**：本次实测全仓 `flutter analyze` **149.2s** 就出结果；
  ②要**快速**结论用 `frontend_server`（`PIT-014`）：末行 `<uuid> <dill> <错误数>` + 退出码
  （有错 = **254**，0 error = **0**），约 1~2 分钟，还能一次抓出 undefined 引用
  —— 本次就是它先抓到 `player_screen.dart:836` 漏改的 `_loadWatchdog`；
  ③读结果前**换名复制**：`copy /y analyze_out.txt analyze_c3.txt`；
  ④想立刻判断有没有错：`findstr /c:"Error:" <输出文件>`，不必等它跑完
- 反例（别这么写）: 看到 `Analyzing privi...` 就断定"分析器挂了"并杀掉；
  直接 `read_files` 同一个输出路径并相信内容是最新的
- 自检: 结果文件的 size/mtime 是否在变；`tasklist /fi "imagename eq dart.exe"` 看进程是否还在
- 首次记录: 2026-09-22（实测：全仓 analyze = 149.2s；输出滞后约 25 分钟才读到）

## PIT-021 长等待会被提前掐断 ⇒ 轮询必须"先写状态文件、再等"
- 触发条件: 想等构建/任务跑一会儿再检查（`ping -n 400`、`timeout /t`、`Start-Sleep`）
- 错误现象: 命令在 ~30~60 秒就被回收，**等待时间远小于预期**（实测 `ping -n 400` 只活约 40 秒），
  `&` 串在它后面的命令**根本没执行**、状态文件甚至没被创建；再叠加 `PIT-018` 的读取滞后，
  很容易得出"命令没跑 / 没输出"的错误结论
- 正确做法: ①按 **1 分钟粒度**设计轮询：**先把状态写进文件，再 `ping -n 400`**（被掐断也不影响已写内容），
  下一轮直接读该文件；②状态文件写到 `build\`（gitignored，不用清理）；
  ③真正需要长时间等待的任务放**独立窗口**（`start "x" cmd /c ...`，见 `PIT-009`），它不受终端回收影响；
  ④判断"是否在跑"用 `dir /tw <文件>` + `tasklist`，不要只看 `read_files` 的内容
- 反例: 发一条 `ping -n 600` 指望等 10 分钟；把 `&` 后面的命令当作一定会执行；
  用 `read_files` 读到空就断定命令失败
- 自检: 状态文件 mtime 是否在推进；目标任务进程（`java.exe`/`dart.exe`）是否还在
- 首次记录: 2026-09-22（本次全程用它轮询 `build.bat` 进度）
- 复发 2026-10-07（同一根因，新症状）: 用 `timeout /t 25` 当"等一会儿"的轮询，
  **把上一条正在前台跑的 `dart analyze` 一起掐死**了 —— `tmp\analyze3.txt` 停在 2 行
  （`Analyzing player_screen.dart, ...` + `Failed to init NativeSymbolResolver ...`），
  容易被误判成"分析器又挂了"（`PIT-020`）。
  正确做法（本轮验证有效）: 长任务放**独立窗口**
  ```
  start "" /min cmd /c "cd /d D:\WorkSpace\test\privi && D:\Tools\DevTools\flutter\bin\cache\dart-sdk\bin\dart.exe analyze <files> > tmp\analyze5.txt 2>&1"
  ```
  之后**只用 `read_files` 读输出文件**（不再发任何等待类命令），独立窗口不会被终端回收；
  实测 3 个文件的 analyze 几十秒内就把 `1 issue found.` 写完（`tmp\analyze4.txt`）。

## PIT-024 `findstr` 的文件名里带通配符但**整个路径被引号包住** ⇒ 0 命中（假阴性）
- 触发条件: 想在一批文件里找关键词，而文件名里有中文/空格，于是写成
  `findstr /n /c:"Vout" "C:\Users\xxx\Downloads\*_log_2026-10-01.txt"`
- 错误现象: 退出码 1、**一行输出都没有**（同一批文件里明明有 `Vout`），
  很容易误判成"日志里没有这个现象" —— 而本次排查的结论恰恰要靠"有没有 `video layout:`"来定
- 根因: `findstr` 的**搜索参数**支持通配符，但**引号包住整个带通配符的路径**时它按普通
  文件名处理（找不到该"文件"）⇒ 静默 0 命中；中文文件名又让人不敢去掉引号
- 正确做法: **先用通配符 copy 到一个 ASCII 名字，再对 ASCII 文件搜**：
  ```bat
  copy /y "C:\Users\xxx\Downloads\*_log_2026-10-01.txt" tmp\log.txt
  findstr /n /c:"video layout" tmp\log.txt
  ```
  （`copy` 支持引号内的通配符；`tmp\` 见 `ADR-019`）
- 反例（别这么写）: `findstr /c:"Vout" "C:\...\*_log.txt"`；或直接用中文文件名去 `findstr`
- 自检: 先用一个**已知一定存在**的词（如 `INFO`）做正控：正控也 0 命中 ⇒ 是检索手段坏了，不是日志里没有
- 首次记录: 2026-10-01（本次：`grep_layout.txt`/`grep_events.txt` 空文件，改用 copy 后立刻正常）

## PIT-025 终端回显里的中文可能"看起来是乱码/错字"，**文件其实是好的**
- 触发条件: 命令输出里带中文（尤其 `type`/`findstr` 回显 + `chcp 65001`），或者被 Cline 的
  终端抓取截断/半行显示
- 错误现象: 看到 `几何和挂视图的���序`、整行被截成两段、行尾多出空格等 —— 看着像文件被写坏了，
  于是想再去"修"一遍（完全没必要，而且真去改反而可能改坏）
- 正确做法: **用 `read_files` 复核文件真实内容**（它按 UTF-8 读，不受终端代码页/抓取影响）；
  确认无误就忽略终端里的显示噪声
- 反例（别这么写）: 依据终端回显断定"文件里的中文坏了"并重新编辑；把终端截断当成"行内容变短"
- 自检: `read_files` 读同一行 → 与 `git diff` 的显示一致即为正常
- 首次记录: 2026-10-01（本次改 `VlcPlayerHandler.kt` 时踩到，`read_files` 复核后确认文件正常）

## PIT-026 全新环境（无 `.dart_tool` / `build`）的首次构建：`pub get` 会在 SDK `git fetch --tags` 上"静止" 2 分多钟，别当成卡死
- 触发条件: 干净工作区（`flutter clean` 之后、或换机器）跑 `build.bat`
- 错误现象: `build_full.log` 的 pub 心跳行连出
  `[pub] 已运行 xx s | 日志 NNNN 字节 | 静止 NNs` + `注意: 日志已 NNs 无增长（可能正在下载依赖;
  若长期为零, 多半是 dart.exe 被安全软件拦截）`；`pub_get_*.log` 停在同一行不动；
  同时 `tasklist` 里能看到**多个** `git.exe`（其中一个几百 MB）
- 实测（2026-10-01 首次构建）: 静止在 **141s** 后自行恢复（`日志 4915 字节 | 静止 0s`），
  整次 `pub get` 182s；触发点是 flutter 工具在 SDK 仓库里跑
  `git fetch --tags`（`pub_get_codegen.log:27` `executing: [...] git fetch --tags`），
  与项目依赖、网络连通性都无关（`curl -sI https://github.com` 当时 200/1.4s）
- 正确做法:
  ①**看到"静止"先别杀**，等到看门狗给出结论；判活看
  `tasklist /fi "imagename eq git.exe"` 与 SDK 的 `git fetch` 是否还在；
  ②`ISSUE-002` 的看门狗是"日志零增长 300s ⇒ 杀"，**真正慢的 `git fetch` 有被误杀的风险**
  —— 本机实测最坏已到 141s，网络差时可能超 300s；真要复现失败就用 `build.bat` 再跑一次
  （fetch 的对象已经落地，第二次会快很多）
- 反例（别这么写）: 看到 `静止 101s` 就 `taskkill` 掉 dart/git，然后写"pub get 卡死"
  （会误导成 `ISSUE-002` 复发）
- 附：本机首次构建耗时基线（2026-10-01，Ryzen 7 8745H）：codegen `build_runner` AOT 217s +
  `assembleRelease` 712.1s，整条 `build.bat norelease` 约 **21 分钟**；`WMI 自检 7572ms rc=0`、
  `MEM OK FreeCommitMB=18397`，**没有**复发 `ISSUE-001` / `ISSUE-004`
- 自检: `git.exe` 还在 + 心跳行在推进 ⇒ 正常；只有 `dart.exe` 静默且**无 git.exe** 才按卡死处理
- 首次记录: 2026-10-01

## PIT-023 上一轮 `build.bat` 的窗口没关 ⇒ 新构建**完全没跑**（tee 抢不到 `build\build_full.log`）
- 触发条件: 构建失败后立刻再次 `build.bat`（尤其用 `start /min cmd /c "build.bat ..."` 启动的窗口，
  它在失败后会停 60 秒"窗口将在 60 秒后自动关闭，或按任意键立即关闭"，期间**一直占着日志句柄**）
- 错误现象: 新窗口里只有一堆 PowerShell 异常，**构建一行都没执行**：
  ```
  Exception calling ".ctor" with "3" argument(s): "The process cannot access the file
  '...\build\build_full.log' because it is being used by another process."
  ... you cannot call a method on a null-valued expression ...
  ```
  同时 `build\build_exit.log` 不更新、`build_full.log` mtime 还是上一轮的时间 ⇒
  很容易误判成"构建又失败了"（其实**根本没启动**）
- 正确做法:
  ```bat
  REM 1) 先确认真空：能删掉日志说明没有残留窗口持有它
  del /q build\build_full.log 2>nul
  if exist build\build_full.log (echo LOCKED: 还有旧窗口没关) else (echo OK: 可以开始)
  REM 2) 还锁着就杀窗口（窗口名 = start 的第一个参数），或用 WINDOWTITLE 过滤
  taskkill /f /fi "WINDOWTITLE eq privi_main_build"
  ```
- 反例（别这么写）: 构建失败后马上原地重跑，然后看 `build_exit.log` 的旧内容下结论
- 自检: 新构建启动 10 秒内 `dir /tw build\build_full.log` 的 **mtime 必须是今天刚变的**；
  `build_main_console*.txt` 里不能出现 `StreamWriter` / `being used by another process`
- 首次记录: 2026-09-22（本轮 2 次重跑就是这样白跑的）

## PIT-022 临时产物散落在仓库根 ⇒ `git status` 噪声 + 要人工辨认哪些能删
- 触发条件: 把命令输出、临时脚本、轮询/状态文件直接写在仓库根（如 `> out.txt`、`> st3.txt`）
- 错误现象: 仓库根迅速堆满一次性文件 —— 本次会话前后累积 40+ 个
  （`_apply_script_paths.ps1`、`_enc_*.ps1`、`_cpu.ps1`、`_tail.ps1`、`ps1refs*.txt`、`git_*.txt`、
  `diff_*.txt`、`st3.txt`…`st27.txt`、`cpu*.txt`、`push*.txt`、`tmp_recon.txt`），
  `git status` 里混着 `??` 噪声，收尾必须逐个 `del`，还有误删业务文件的风险。
  上一轮交接文档的收尾清单里就专门列了一条「删掉仓库根目录的一次性产物」
- 正确做法: 一切中间文件写进仓库根 `tmp\`（约定见 `.clinerules/tmp-files.md` / `ADR-019`）：

  ```bat
  mkdir tmp 2>nul
  git status --porcelain -M > tmp\status.txt 2>&1
  powershell -NoProfile -ExecutionPolicy Bypass -File tmp\probe.ps1 > tmp\probe_out.txt 2>&1
  ```

  收尾清理：`rmdir /s /q tmp`（或直接跑 `clean.bat` / `build.bat clean`，二者都会整目录清掉 `tmp\`）
- 反例: 把 `> out.txt`、`> push5.txt` 写在仓库根；把临时 ps1 写在根目录"用完删"（忘了删就留下；
  重名还会覆盖上一次的排查证据）
- 自检: `git status --porcelain` 里除真实改动外**不应有 `??` 项**；`dir /b tmp` 只应有本次要用的文件
- 首次记录: 2026-09-22（本次任务落地 `tmp\` 规范）

## PIT-027 `pubspec.yaml` 的 `version:` 不带 `+N` 时，Flutter 会**删掉** `local.properties` 的 `flutter.versionCode`，插件回退为 1 ⇒ 覆盖安装报 `INSTALL_FAILED_VERSION_DOWNGRADE`
- 触发条件: 把 `pubspec.yaml` 写成三段式（`version: 1.0.59`，没有 `+59`），然后 `flutter build apk`
- 错误现象: 构建成功、日志一行警告都没有，但产出的 APK `versionCode='1'`；
  手机上装着旧版（如 versionCode 59）时 `adb install -r` 直接失败
  `INSTALL_FAILED_VERSION_DOWNGRADE`，系统安装器/应用商店同样拒绝升级
- 源码依据:
  `flutter_tools\lib\src\android\gradle_utils.dart:1184-1215` —
  `changeIfNecessary('flutter.versionCode', buildNumber)`，`buildNumber` 为 null 时走
  `settings.values.remove(key)`（**删键**，不是留旧值）；
  `flutter_tools\gradle\src\main\kotlin\FlutterPlugin.kt:131-134` —
  `rootProjectLocalProperties.getProperty("flutter.versionCode", "1")`（缺键 → `"1"`）
- 正确做法: 别用 `flutter.versionCode`，在 `android/app/build.gradle.kts` 里按版本名自己算
  （实现见 `ADR-026`，`versionCodeFromName()` 定义在 `plugins {}` 之后、`android {}` 之前）:
  ```kotlin
  versionName = flutter.versionName
  versionCode = versionCodeFromName(flutter.versionName) // major*10000 + minor*100 + patch
  ```
- 反例（别这么写）: 只改 `pubspec.yaml` 就去打包发布；把 `versionCode = flutter.versionCode` 留着
  （本机 `android\local.properties` 里会看到 `flutter.versionCode=59` 是**上一次**构建留下的残留，
  下一次 `flutter build apk` 就会把它删掉 —— 拿它当"现在还是 59"会误判）
- 自检: `D:\Tools\DevTools\Android\Sdk\build-tools\36.0.0\aapt2.exe dump badging build\app\outputs\flutter-apk\app-release.apk | findstr versionCode`
  → 期望 `versionCode='10059' versionName='1.0.59'`，出现 `versionCode='1'` 即命中本坑
- 首次记录: 2026-10-07

## PIT-028 替换式编辑 md 时，`old_text` 捎带了下一节标题、`new_text` 却没带回 ⇒ 标题被静默吃掉
- 触发条件: 用「锚定下一节开头」的方式在文档中间插入内容，例如
  `old_text = "\n## PIT-009 <标题>"`、`new_text = "<新段落>"`（没把标题写回去）
- 错误现象: 目标标题行被删掉、正文还在 ⇒ 文档结构坏掉（本节内容挂到了上一节名下）；
  编辑工具的 diff 回显里其实有 `-90: ## PIT-009 …` 这一行，很容易被当成"行号位移"而忽略
- 正确做法: **`new_text` 必须原样带回 `old_text` 的全部既有行**（`new_text = 新内容 + old_text`），
  或干脆用 `insert_line`（纯插入，绝不改既有行）
- 反例: `old_text = "## PIT-009 …"` / `new_text = "<新段落>"`（标题就没了）；
  以整节标题作锚点又只写回正文
- 自检: 每次编辑后 **`read_files` 回读改动区域**（含上下各 3 行），确认相邻标题、
  `---` 分隔线、代码块围栏都还在；本次就是这样发现并修回 `PIT-009` 标题的
- 复核 2026-10-10（同一族的第二种翻车）: 想在 `X();` 这一行**之前**插入新方法时，用
  `old_text = "  Future<void> _seekTo(Duration position) async {\n    if (video == null) return;\n"`
  这种"**以结尾换行收尾**"的锚点，而 `new_text` 末行写成了 `... return;`（**没带换行**）
  ⇒ 结果是两行被**粘成一行**（`if (video == null) return;    // 播完之后拖进度条…`），
  编译器/格式化器能过、但代码结构被破坏。
  正确做法：锚点的**每一行都必须原样出现在 `new_text` 里**（含行尾），
  插入类改动优先用 `insert_line`；改完立刻回读该区域确认没有两行粘一起
- 复核 2026-10-13（第三次踩，形态最隐蔽）: 给 `SecurityService` 插入两个新方法时，
  `old_text` 只取了 `Future<Uint8List?> deriveEncryptionKey(String secret) async {` 一行（含行尾），
  而 `new_text` 末行写成 `... async {`（**没带回换行**）⇒ 结果变成
  `Future<Uint8List?> deriveEncryptionKey(String secret) async {    try {`（两行粘连）。
  **代码仍能编译**（`{    try {` 是合法语法）、`dart format` 也不报错 ⇒ 只能靠回读/diff 发现。
  教训：锚点尽量取**两行**（如 `xxx async {` + 下一行 `    try {`），或改用 `insert_line`；
  编辑后必须回读该区域（本次靠 editor 的 diff 回显当场发现并修回）
- 首次记录: 2026-10-07 ／ 最近复核: 2026-10-13（第三次同类翻车，已即时修回）

## PIT-029 Cline 的 shell 里 `flutter` 不在 PATH；`start "" /min cmd /c "…嵌套引号…"` 会立刻报「命令语法不正确」
- 触发条件: ①想在 Cline 终端直接跑 `flutter ...`（本机 `flutter.bat` 只在 `build.bat` 内部才被加进 PATH）；
  ②想用 `start "" /min cmd /c "<一段本身带引号的命令>"` 起后台进程（例如"先 set 镜像变量再跑 flutter"）
- 错误现象: ①`'flutter' is not recognized as an internal or external command, operable program or batch file.`
  （命令"秒完"，容易被误当成"跑过了、没输出"）；
  ②`start` 那条只在输出文件里留下一行乱码 `�����﷨����ȷ��`（= 命令语法不正确），后台什么都没起来
- 正确做法: ①flutter / dart 一律用**全路径**：`"D:\Tools\DevTools\flutter\bin\flutter.bat" ...`、
  `%FLUTTER_HOME%\bin\cache\dart-sdk\bin\dart.exe`（后者见 `PIT-014`）；
  ②需要"设置环境变量 + 长任务 + 输出重定向"时，把命令写进 `tmp\xxx.bat`（纯 ASCII 即可），再
  `start "" /min cmd /c tmp\xxx.bat`，重定向到 `tmp\` 下的文件，之后用 `read_files` 轮询文件内容
- 反例（别这么写）: `flutter pub upgrade --dry-run`；
  `start "" /min cmd /c "set X=Y && ""D:\Tools\...\flutter.bat"" pub upgrade --dry-run > tmp\o.txt 2>&1"`
- 自检: 起完 10~30 秒后用 `read_files tmp\o.txt` 看文件是否在长；首行出现
  `is not recognized` 或 "命令语法不正确" 的乱码即说明写坏了（`find /c /v "" tmp\o.txt` 也能看行数变化）
- 首次记录: 2026-10-07

## PIT-030 想看源码的"中间某几行"：`read_files` 子区间会回 `[outdated]`；嵌套 `powershell -Command "...$l[...]"` 里的 `$l` 会被外层 shell 先展开
- 触发条件: ① 同一个文件先被 `read_files` **整篇读过**（长文件会被中间截断），再请求它的
  局部行范围；② 在**一条** `run_commands` 命令里嵌套第二个 `powershell -NoProfile -Command "..."`
  （或在一个 `powershell -Command` 字符串里重复使用 `$l` 之外的变量）
- 错误现象:
  ① `read_files` 对 `start_line/end_line` 返回 `[outdated - see the latest file content]`，
  **连续试 3 次、换范围也拿不到内容**（不是文件问题，换文件就正常）；
  ② 报 `Missing type name after '['` / `=Get-Content` 前面丢变量名 —— `$l`、`$_.Count`
  这类变量在**外层** PowerShell 解析时就被展开成空，内层脚本拿到的是 `.Count-8`、`[184..345]`
- 正确做法（本次实测可用）:
  ```powershell
  # 读第 184~345 行（1-based 204~345 → 0-based 203..344）；注意外层用单引号，$l 才不会被展开
  powershell -NoProfile -Command '$l=Get-Content -Encoding UTF8 ''lib\presentation\player\video_player_controls.dart''; $l[184..345] | ForEach-Object { $_ }'
  ```
  要点：**外层单引号**、内层路径用 `''` 转义、**一条命令只放一个 `powershell -Command`**
  （要读多段就用 `run_commands` 的多条数组项，或 `; '=== 段2 ==='; $l[299..450]` 这样在**同一个**
  `-Command` 里接，本次这两种写法都成功过）；
  `Get-Content` 一律带 `-Encoding UTF8`（否则中文注释按 GBK 解成乱码，见 `PIT-002`）
- 反例（别这么写）:
  ```powershell
  # ① 嵌套调用：外层把 $l 展开成空 ⇒ Missing type name after '['（实测复现 3 次）
  powershell -NoProfile -Command "...; '=== 330-436 ==='; powershell -NoProfile -Command "$p=...; $l[329..435]"
  # ② 先整篇 read_files、再要子区间 ⇒ [outdated - see the latest file content]
  ```
- 自检: 输出的行号/行首内容与 `git grep -n` 给的行号对得上；报 `Missing type name` 就是踩了 ②
- 首次记录: 2026-10-10

## PIT-031 `File.readAsBytesSync()` 读整个文件只为了判断头部 → OOM（35GB 文件直接崩）
- 触发条件: 用 `readAsBytesSync()` / `readAsBytes()` 读文件，只为了检查前几个字节的魔数
- 错误现象: 35GB 视频文件 `readAsBytesSync()` → 进程物理内存爆到几十 GB → OOM/系统杀进程；
  退一步讲即使没崩，读 35GB 进内存也要几十秒，而实际只需要前 12~32 字节
- 正确做法: 用 `RandomAccessFile`（`file.openSync(mode: FileMode.read)`）只读需要的字节：
  ```dart
  final raf = file.openSync(mode: FileMode.read);
  final bytes = Uint8List(32);
  final read = raf.readIntoSync(bytes);
  raf.closeSync();
  ```
  32 字节足以覆盖 JPEG/PNG/MP4/WebM/MKV 的所有常见魔数 + AES-GCM nonce（12 字节）
- 反例（别这么写）: `final bytes = file.readAsBytesSync();` — 即使后面只取 `bytes.sublist(0, 12)`，
  `readAsBytesSync()` 已经把整个文件装进内存了
- 自检: 对一个大文件（1GB+）跑 `looksEncrypted()` 如果耗时超过 1 毫秒 ⇒ 用了全量读取
- 首次记录: 2026-10-13（`media_encryption_service.dart` 的 `looksEncrypted()`，已修复）

## PIT-032 `Future<String>` 返回值类型强制密文路径返回 → 调用方无感知地拿到密文传给播放器
- 触发条件: Viewers/播放器需要从数据库拿到文件路径来播放；函数签名为 `Future<String>`，
  而加密文件需要在"播放前透明解密成临时文件"——但解密可能失败（KEK 缺失/认证失败）
- 错误现象: 原 `_resolveDisplayPath` 返回类型是 `Future<String>`，KEK 缺失或解密失败时
  "兜底"返回 `item.privatePath`（加密密文路径）→ 播放器/外部播放器用密文解码 → 画面全噪点或直接崩溃。
  `catch` 块也只是 log 完继续 return 密文路径，与失败分支行为一致——都是埋雷
- 正确做法: 返回类型改为 `Future<String?>`，失败一律 `return null`；
  **所有**调用方必须处理 null 分支（显示错误提示 / SnackBar / 不启动播放器），
  绝不能让密文字节流进解码器
- 反例: `if (kek == null) return item.privatePath;` — 这等于"检测到问题后绕过去了"；
  `try { ... } catch (e) { log(e); } return item.privatePath;` — 同上
- 自检: `grep -n "return.*privatePath"` 查看器/播放器文件 → 这些 return 是否发生在解密失败分支？
  如果是，每个都要改成 null + 错误态
- 首次记录: 2026-10-13（`viewer_screen.dart` 的 `_resolveDisplayPath`，已修复；
  同一次排查还修复了 `_syncVideoBody` 和 `_openExternal` 两个调用方）

## PIT-033 改 PopupMenuButton 菜单项时只改了一个界面忘记同步另一个
- 触发条件: viewer 和 visible/gallery_preview 各有一个长得几乎一模一样的三个点菜单
  （`PopupMenuButton<String>`），菜单项列表非常接近（都有「内部播放(libVLC)」「内部播放(ExoPlayer)」
  「打开方式」「信息」等），但它们是**两份独立代码**，分别在不同文件里：
  - `lib/presentation/viewer/viewer_screen.dart` → `PopupMenuButton<String>(`（第 900 行附近）
  - `lib/presentation/visible/gallery_preview_screen.dart` → `PopupMenuButton<String>(`（第 685 行附近）
- 错误现象: 在 viewer 的菜单里加了新功能→只改了 `viewer_screen.dart`，忘了 `gallery_preview_screen.dart`
  里也有一个外观相同、入口不同的同名菜单→用户从可见库预览页打开三个点看不到新功能→
  以为是"没生效"或"bug"，来回排查几轮才发现是**改错了文件/漏了同步**
- 正确做法: 任何涉及三个点菜单的改动，改完一个文件后立刻 grep 全仓搜 `PopupMenuButton`，
  确认所有实例都同步了：
  ```bash
  git grep -n "PopupMenuButton" lib/
  ```
  输出应该是两个文件，确认每个文件的菜单项列表中新增的通用功能项一致
  （注意菜单项不完全相同——gallery_preview 没有「播放全部」等入口，但**新增的通用功能**
  如加密状态标记/还原入口等，两份菜单都要同步考虑）。
- 反例: 在 viewer 的 `PopupMenuButton(onSelected: (value) { ...` 里加了
  `'reveal'` / `'toggleEncryption'` case，构建完拿真机验证只在 viewer 里能找到，
  从可见库预览打开同一个文件却没有——就是因为 `gallery_preview_screen.dart` 的菜单
  根本没被改过。
- 自检: 改完菜单后 `git diff --stat` 应该显示两个文件都被修改；如果只有一个 `.dart` 文件
  被改而改动涉及三个点菜单项，停一下——大概率漏了另一个。
- 首次记录: 2026-10-13（基于用户反馈的"三个点菜单改错地方"模式）

## PIT-034 文件原地替换用 delete-then-rename → 中间崩溃窗口导致数据永久丢失
- 触发条件: 加密/解密需要原地替换文件（覆盖原文件），实现为 `delete(original)` → `rename(temp, original)`。
  如果进程在这两步之间崩溃（系统杀掉/电池耗尽/OOM），原始文件已删除而临时文件未 rename，
  文件永久丢失。
- 错误现象: 
  - `CryptoHandler.kt encryptFile()`: 加密 35GB 视频时 OOM 崩溃 → 原视频已删，加密临时文件残留但未
    链入 → 用户丢失唯一副本
  - `VaultRevealRunner._decryptIfNeeded()`: 还原大批量文件时中途被系统杀进程 → 部分文件已删未 rename
    → 文件消失
- 正确做法: backup → rename → delete（三步，永远不先删原始文件）：
  ```kotlin
  // Kotlin (CryptoHandler.kt)
  val bak = File(original + ".bak")
  if (!original.renameTo(bak)) error  // Step 1: backup (atomic on same fs)
  try {
      if (!temp.renameTo(original)) {  // Step 2: promote temp
          bak.renameTo(original)        // Restore on failure
          error
      }
  } finally {
      bak.delete()                      // Step 3: cleanup
  }
  ```
  ```dart
  // Dart (VaultRevealRunner)
  final bakPath = '$privatePath.bak';
  await _files.rename(privatePath, bakPath);
  try {
    await _files.rename(tempPath, privatePath);
  } catch (_) {
    await _files.rename(bakPath, privatePath); // restore
    await _files.delete(tempPath);
    rethrow;
  }
  try { await _files.delete(bakPath); } catch (_) {}
  ```
  每个崩溃窗口:
  - 1之后崩溃: bak = 原始文件, original 不存在 ⇒ 恢复 = rename(bak→original) ✅
  - 2之后崩溃: original = 新文件, bak 残留 ⇒ finally delete bak ✅
  - 2-恢复崩溃: bak 回到 original ✅, temp 仍在 ⇒ delete temp ✅
- 反例: `inputFile.delete(); tmpFile.renameTo(inputFile);` ← delete 和 rename 之间任何崩溃=数据消失
- 自检: `git grep -n "\.delete().*\n.*\.renameTo\|\.delete(.*\n.*\.rename("` 跨 Kotlin/Dart 搜
  delete 紧跟 rename 的模式 → 任何匹配项都是潜在的 PIT-034
- 首次记录: 2026-10-13（CryptoHandler.kt + VaultRevealRunner._decryptIfNeeded，已修复）

## PIT-035 lookupEncrypted JPEG 魔数过于严格 → 带 EXIF 的 JPEG 被误判为已加密
- 触发条件: `_looksLikePlainMedia` 的 JPEG 检测用 8 字节 JFIF 魔数 `FF D8 FF E0 00 10 4A 46`。
  JPEG 文件的 SOI 标记只保证前 3 字节 `FF D8 FF`，第 4 字节表示 APP 标记类型：
  - E0 = JFIF（最常用）
  - E1 = EXIF（相机直出 JPEG 几乎都是这个）
  - E2 = ICC profile
  - DB = 量化表（无元数据 JPEG）
  → EXIF JPEG 不匹配 commonJpeg → `_looksLikePlainMedia` 返回 false → `looksEncrypted` 返回 true
  → `encryptFile` 跳过加密 → 文件始终保持明文且无任何提示
- 错误现象: 用相机拍的 JPEG（自带 EXIF）导入密册后永远不会被加密；批量加密时这些文件被静默跳过
- 正确做法: JPEG 只匹配 `FF D8 FF`（3 字节 SOI），不要求 JFIF 特定标记
- 反例: `[0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10, 0x4A, 0x46]` ← 第 4 字节限死 E0，丢失 EXIF/ICC 等
- 自检: 任何魔数检测的前缀匹配不要含变体字节；宁可用更短的确定前缀
- 首次记录: 2026-10-13（第三次审计发现，已修复）

## PIT-036 changePattern/changePin/recoverWithSystemAuth 不重加密 DEK → 改密码后文件永久丢失
- 触发条件: 用户更改密码/图案后，新 KEK 无法解密用旧 KEK 加密的 DEK → 所有已加密文件永久不可读。
  `recoverWithSystemAuth` 更严重：旧凭证直接清除，恢复后旧 DEK 彻底成孤儿。
- 错误现象:
  - 用户导入了 100 个加密文件 → 正常查看 → 去设置改图案 → 锁屏再解锁 → 100 个文件全部打不开
  - 用户忘记图案 → 系统验证恢复 → 设新图案 → 所有加密文件永久丢失
- 正确做法: `changePattern` 等入口必须在改凭证后遍历所有 `encryptedDek`，用旧 KEK 解密、
  新 KEK 重加密、写回 DB。`_rotateAllDeks` 集中处理。`recoverWithSystemAuth` 的对话框已加
  警告文字。
- 自检: 任何修改根凭证（pattern/pin）的代码路径都要检查是否做了 DEK 旋转
- 首次记录: 2026-10-13（第三次审计发现，已修复 changePattern/migratePinToPattern/changePin，
  recoverWithSystemAuth 加了 UI 警告）

## PIT-037 _resolveDisplayPath 返回 null 后 UI 永远 loading → 用户卡死
- 触发条件: 加密文件解密失败（KEK 缺失/auth tag 不匹配/文件损坏），`_resolveDisplayPath` 返回 null，
  但 `_decryptedTempPaths` 未设置任何值 → `_mediaPage` 的 `hasEncryptedDek && cachedPath==null`
  永远为 true → `CircularProgressIndicator` 永远转圈
- 修复: 新增 `_decryptFailedIds` 集合记录已尝试且失败的项目。`_mediaPage` 检测到 failed 状态时
  显示 `broken_image` 图标而非 spinner。
- 首次记录: 2026-10-13（第三次审计发现，已修复）

## PIT-038 changePattern/changePin/migratePinToPattern 在 oldKek==null 时静默跳过 DEK 轮转
- 触发条件: `changePattern` 获取 `oldKek = keyManager.getKey()`，若此时 KEK 已被清空
  （auto-lock 在图案绘制对话框期间触发 / 其他异常路径），`if (oldKek != null)` 分支跳过，
  DEK 轮转不执行 → 新凭证 + 旧 DEK → 所有加密文件永久丢失。
- 修复:
  - 三个修改凭证入口统一在 `oldKek == null` 时查询 `listEncrypted()` 数量
  - 有加密文件 → 抛 `StateError` 阻止操作，提示用户先锁屏再解锁以重载 KEK
  - 无加密文件 → 安全放行
- 首次记录: 2026-10-13（第四次审计发现，已修复）

## PIT-039 _rotateAllDeks 非幂等 + 先改凭证后轮转 → 崩溃窗口全损
- 触发条件:
  - 原 `_rotateAllDeks` 只用 `oldKek` 解密 DEK → 若上次轮转中断（部分 DEK 已是 newKek），
    重跑时无法解密已轮转 DEK → 永久成为孤儿
  - 原顺序 `setPattern → deriveNewKek → rotate`：若 `setPattern` 成功后、`rotate` 前崩溃，
    重启后用新 pattern 解锁 → 新 KEK 覆盖旧 KEK → 所有旧 DEK 失效 → 全损
- 修复:
  - `_rotateAllDeks` 幂等化：先试 `newKek`（已轮转），再试 `oldKek`（未轮转），
    两种都失败才标记 lost
  - 操作顺序改为 `deriveNewKek → rotate → setPattern → setKey`：
    轮转在改凭证之前 → 崩溃后旧凭证仍有效 → 可重跑轮转
- 首次记录: 2026-10-13（第四次审计发现，已修复）

## PIT-040 viewer 并发解密同一文件 → 临时文件泄漏
- 触发条件: `initState` 的 `addPostFrameCallback` 回调中同时调用
  `_resolveDisplayPath(current)` 和 `_syncVideo()` → `_syncVideoBody` 也调用
  `_resolveDisplayPath` → 同一 item 启动两次解密 → 第一个 temp 文件的路径被第二个覆盖
  → 文件泄漏在 `systemTemp` 中
- 修复: 新增 `_decryptFutures` 互斥表，`_resolveDisplayPath` 检测到已有 in-flight future
  时直接返回同一 future
- 首次记录: 2026-10-13（第四次审计发现，已修复）

## PIT-041 _showEncryptProgress 死参数 kek
- 触发条件: `_batchEncrypt` 传入 `kek` 参数但在 `_showEncryptProgress` 中从未使用，
  循环内改为每次读 `keyManager.getKey()` —— 参数冗余
- 修复: 移除死参数，保持循环内实时读取的模式
- 首次记录: 2026-10-13（第四次审计发现，已修复）

## PIT-042 lock() 删除持久化 KEK → 生物识别解锁永久不可用
- 触发条件: `lock()` 调用 `keyManager.clear()` → 删除 FlutterSecureStorage 中的 KEK →
  下一次 `unlockWithBiometric` → `retrievePersistedKek()` 返回 null →
  KEK 加载失败，加密媒体不可访问。每次 auto-lock 或手动 lock 后必须重新用图案/PIN 解锁。
- 修复:
  - `EncryptionKeyManager` 新增 `clearMemory()`：仅清空内存 KEK，保留持久化副本
  - `lock()` 改用 `clearMemory()` 替代 `clear()`
  - `clear()` 保留用于凭据重置场景（如 `recoverWithSystemAuth`）
- 首次记录: 2026-10-13（第五次审计发现，已修复）

## PIT-043 purgeMany 文件删除失败后仍删除 DB 行 → 孤儿文件
- 触发条件: `purgeMany` 先遍历删除所有行对应的文件，再无条件调用
  `hardDeleteMediaMany(ids)` 删除所有行。若某个文件的删除失败，DB 行仍被删除
  → 文件残留在 vault 中无人引用，永久占用存储。
- 修复: 逐个 try/catch 删除文件，仅收集成功删除的 id 执行 DB 清理。
  失败的文件保留 DB 行，下次 purge 或 maintenance 可重试。
- 首次记录: 2026-10-13（第五次审计发现，已修复）

## PIT-044 _encryptRecordedFiles / _batchEncrypt — crash 窗口期 DEK 永久丢失
- 触发条件: `encryptFile` 成功 → 返回 `encryptedDekBase64` → 在 `updateEncryptedDek`
  写入 DB 前 app 崩溃 → DEK 在内存中随进程消失 → 文件已加密但无法解密。
- 风险: 两个 await 之间仅微秒级，实际概率极低，但一旦发生则 100% 数据丢失。
- 修复: `_encryptRecordedFiles` 改为先生成 DEK → 用 KEK 加密 → **先存 DB** →
  再加密文件。如果文件加密失败，回滚 DB 中已存的 DEK。
  - `MediaEncryptionService` 新增 `encryptFileWithDek()` 支持预生成 DEK。
  - 文件已加密但 DEK 丢失的不可逆场景永久消除。
- 首次记录: 2026-10-13（第五次审计发现）／ 修复: 2026-10-13（R7）

## PIT-045 enterAppAfterSetup — PBKDF2 竞态导致 vault unlocked 但 KEK 为空
- 触发条件: `setupPattern(unlockNow: false)` 启动异步 PBKDF2 → 用户快速跳过
  生物识别对话框 → `enterAppAfterSetup` → `retrievePersistedKek()` 时 PBKDF2
  尚未完成写入 → KEK 为 null → vault unlocked 但加密文件无法访问。
- 风险: 实践概率极低（PBKDF2 约 1-2 秒，生物识别对话框至少几秒），但理论上存在。
- 修复: `enterAppAfterSetup` 新增 `_retrievePersistedKekWithRetry()`，最多重试
  10 次 × 300ms = 3 秒。PBKDF2 必然在此期间完成，KEK 100% 可用。
- 首次记录: 2026-10-13（第五次审计发现）／ 修复: 2026-10-13（R7）

## PIT-046 unlockWithPattern/unlock 在 PBKDF2 完成前将状态置为 unlocked
- 触发条件: `unlockWithPattern` → 先 `state = unlocked` → 再 `_deriveAndStoreEncryptionKey`
  （fire-and-forget）→ PBKDF2 运行期间内 `keyManager.getKey() == null` →
  用户浏览加密文件时看到 spinner / broken_image → 1-2 秒后恢复正常。
- 修复: `_deriveAndStoreEncryptionKey` 改为 async（`Future<void>`），在
  `unlockWithPattern`/`unlock`/`setupPattern(unlockNow:true)`/
  `setupPin(unlockNow:true)` 中 `await` 它**后再**设置 `state = unlocked`。
  PBKDF2 完成后 vault 才标记为已解锁，UI 过渡期间 KEK 已就绪。
  - `_kekGen` 竞态保护不变：如 lock() 在派生期间发生，stale KEK 不会写入。
- 首次记录: 2026-10-13（第五次审计发现）／ 修复: 2026-10-13（R7）

## PIT-047 `audit-tracker.md` 的 `PIT-0xx` 编号与 `pitfalls.md` 存在整体偏移（+5），照它检索会搜空
- 触发条件: 按 `memory-bank/audit-tracker.md` 备注栏里的 `PIT-0xx` 去 `pitfalls.md` 找条目
- 错误现象: 搜不到，或搜到**另一个**问题（同一编号指向不同条目）。实测偏移：
  - audit-tracker `data/services/encryption_key_manager.dart … clearMemory()新增(PIT-047)`、
    `application/lock/lock_controller.dart … biometric修复(PIT-047)`
    ↔ `pitfalls.md` 里这条实际是 **PIT-042**（`pitfalls.md:663`）
  - audit-tracker `presentation/settings/settings_screen.dart … 死参数移除(PIT-042)`
    ↔ `pitfalls.md` 里实际是 **PIT-041**（`pitfalls.md:657`）
  - audit-tracker 引用的 `PIT-048`（`_bytesMatch` 拒绝 3 字节 JPEG 头）在 `pitfalls.md` 里**原本整条缺失**（本次补齐）
- 正确做法: **以 `pitfalls.md` 的编号为准**；`audit-tracker.md` 只当"文件 → 审计轮次"的状态表用。
  代码注释/commit message 里的 `PIT-04x` 引用（例如 `lock_controller.dart` 里的 `PIT-049`）
  按**条目名**去 `pitfalls.md` 检索，不要假设编号连续一致
- 反例（别这么写）: 用 `findstr PIT-047 memory-bank\pitfalls.md` 没命中就断定"条目不存在、这是个新问题"
- 自检: `Select-String -Path memory-bank\pitfalls.md -Pattern '^## PIT-'` 看最大编号与连续性
- 首次记录: 2026-10-13

## PIT-048 `_bytesMatch` 的 `b.length < 4` 守卫 ⇒ 3 字节 JPEG 魔数永不匹配 ⇒ 所有 JPEG 被判成"已加密"
- 触发条件: 魔数表里含 3 字节签名（`commonJpeg = [0xFF, 0xD8, 0xFF]`），而守卫写成"签名长度必须 ≥ 4"
- 错误现象: `looksEncrypted()` 对**所有** JPEG 返回 true ⇒ `encryptFileWithDek` 抛 `StateError` ⇒
  加密流水线永久跳过每一个 JPEG（相机拍的 JPEG 导入后一直不加密；`PIT-035` 是它的前身）
- 正确做法: 只挡空签名，长度比较交给上一级的 `a.length < b.length`
  ```dart
  static bool _bytesMatch(List<int> a, List<int> b) {
    if (a.length < b.length || b.isEmpty) return false;
    for (var i = 0; i < b.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
  ```
- 反例（别这么写）: `if (a.length < b.length || b.length < 4) return false;`
- 自检: `git grep -n "b.length < 4" -- lib/` 应无命中；`looksEncrypted()` 对普通 JPEG 必须返回 false
- 首次记录: 2026-10-13（`6d18a74 fix(PIT-048)`；本条为本次回填）

## PIT-049 指纹"验证通过但拿不到持久化 KEK"时返回裸 `false` ⇒ 指纹按钮看起来完全坏了
- 触发条件: `unlockWithBiometric()` 里 `bio.authenticate()` 返回 true，但
  `EncryptionKeyManager.retrievePersistedKek()` 返回 null —— 常见于"该设备从未用图案/PIN 成功派生过 KEK"
  （KEK 只在 `setupPattern`/`setupPin`/`unlockWithPattern`/`unlock(pin)` 里写入），
  或 `SecurityService.deriveEncryptionKey()` 内部 catch 返回 null
- 错误现象: 指纹弹窗验证成功 → 界面**什么都不发生**：不解锁、无错误、无进度。
  用户体感 = "指纹解锁坏了"。`f812d9d` 之前是"照样置 `unlocked`"（半解锁：能进 app，但加密文件打不开），
  改成"保持锁定 + `return false`"后，症状从"半解锁"升级成"完全没反应"
- 正确做法: 保持锁定（**不要**半解锁），但必须把原因说出来：
  `VaultLockErrorCode.kekUnavailable` → `_mapLockError` → l10n `biometricKekUnavailable`
  （"请先用图案解锁一次，之后指纹即可正常使用"）；同时 `_deriveAndStoreEncryptionKey` 在 `kek == null` 时补 error 日志
- 反例（别这么写）:
  - `if (ok) { state = unlocked; ... }` —— 半解锁：vault 已解锁但 `getKey() == null`（回归 `ISSUE-024`）
  - `return false;` 什么都不设 —— 静默失败，用户只能猜
  - 顺手把 `EncryptionKeyManager` 的 storage 改成 `AndroidOptions(encryptedSharedPreferences: true)`
    "统一后端" —— 等于换存储桶，**已安装版本**持久化的 KEK 全部读不到（见 `ADR-035`）
- 自检: 设备日志出现 `Biometric OK but no persisted KEK found` ⇒ 命中的就是本条；
  修复后同场景应在锁屏界面看到"请先用图案解锁一次"的提示文案
- 首次记录: 2026-10-13（`f812d9d` 引入静默失败；本轮补可见提示 + 诊断日志）

## PIT-050 ISO-BMFF（MP4/MOV/HEIC）魔数判断不能用固定的"size + `ftyp`"8 字节签名
- 触发条件: 写明文媒体探测时，把 `ftyp` box 当成固定头部
  `[00 00 00 20 66 74 79 70]` 去比对
- 错误现象: 判断**永不成立** ⇒ `looksEncrypted()` 对每个 MP4 返回 true ⇒ `encryptFileWithDek` 抛
  `StateError('File already appears encrypted')` ⇒ 批量加密把每个视频都记成失败、导入也永不加密视频。
  和 `PIT-048`（3 字节 JPEG 头）是同一类错误：**签名长度/位置写错 ⇒ 静默漏判**
- 正确做法: `ftyp` 的 **box size 每个文件都不同**（0x18 / 0x1C / 0x20 / 0x24…），只能匹配 offset 4 的 4 字节标签；
  另外顺手把 GIF / RIFF 容器补上（签名都 ≥4 字节，防止把随机密文误判成明文而**二次加密**）：
  ```dart
  // 读 32 字节头（不要全量读，见 PIT-031）
  final ftypTag  = Uint8List.fromList([0x66,0x74,0x79,0x70]);        // 'ftyp'
  final commonGif = Uint8List.fromList([0x47,0x49,0x46,0x38]);       // 'GIF8'
  final commonRiff = Uint8List.fromList([0x52,0x49,0x46,0x46]);      // 'RIFF'
  final commonAvi  = Uint8List.fromList([0x41,0x56,0x49,0x20]);      // 'AVI '
  final commonWebp = Uint8List.fromList([0x57,0x45,0x42,0x50]);      // 'WEBP'

  if (_bytesMatch(header, commonGif)) return true;
  if (bytes.length >= 8 && _bytesMatch(bytes.sublist(4, 8), ftypTag)) return true;
  if (_bytesMatch(header, commonRiff) && bytes.length >= 12) {
    final fourcc = bytes.sublist(8, 12);
    if (_bytesMatch(fourcc, commonAvi)) return true;
    if (_bytesMatch(fourcc, commonWebp)) return true;
  }
  ```
- 反例（别这么写）: `_bytesMatch(bytes.sublist(4, 12), [00,00,00,20,'f','t','y','p'])`；
  也别加 2 字节签名（如 BMP 的 `BM`）—— 误判成"明文"会导致**二次加密**（真正会丢数据）
- 自检: `git grep -n "sublist(4, 12)" -- lib/` 无命中；真实 MP4 的 `looksEncrypted()` 必须为 false
  （取一个 `ffmpeg`/相机产出、开头是 `00 00 00 18 66 74 79 70 …` 的 mp4 验证）
- 首次记录: 2026-10-13（第十轮审计，见 `ISSUE-029`①）

## PIT-051 批量加密必须"先存 DEK 再加密文件"，且失败回滚要看**文件是否真的被加密**
- 触发条件: 用 `MediaEncryptionService.encryptFile()`（一把梭：native 原地加密 → 再 `encryptDek` 返回）后
  才 `updateEncryptedDek`
- 错误现象: 两次 await 之间崩溃/被杀 = **文件已密文、DEK 从未落库 = 永久无法解密**（`PIT-044` 的导入路径已修，
  但"加密已有文件"批量入口漏了）；反向错误同样致命：catch 里无条件 `updateEncryptedDek(id, null)`，
  而 native 可能**已经把文件换掉了**、只是结果回传失败（Activity 重建/通道断）⇒ 清掉 DEK = 永久孤儿
- 正确做法:
  ```dart
  final dek = encryptionService.generateDek();
  final nonce = Uint8List.fromList(encryptionService.generateNonce());
  final encryptedDek = await encryptionService.encryptDek(dek: dek, kek: kek);
  await repo.updateEncryptedDek(item.id, encryptedDek);      // ① 先落库
  try {
    await encryptionService.encryptFileWithDek(              // ② 再加密文件
      filePath: item.privatePath, dek: dek, nonce: nonce,
    );
  } catch (e) {
    if (!encryptionService.looksEncrypted(File(item.privatePath))) {
      await repo.updateEncryptedDek(item.id, null);          // ③ 只有确认仍是明文才回滚
    }
    rethrow;
  }
  ```
- 反例（别这么写）: `final r = await encryptFile(...); await updateEncryptedDek(id, r.encryptedDekBase64);`；
  或 catch 里无条件 `updateEncryptedDek(id, null)`
- 自检: `git grep -n "updateEncryptedDek" -B 8 -- lib/presentation/settings/settings_screen.dart`
  ⇒ 存 DEK 的行必须出现在 `encryptFileWithDek` **之前**
- 首次记录: 2026-10-13（第十轮审计，见 `ISSUE-029`②③）

## PIT-052 "解不开就静默 return" = 把密文搬出保险库并删掉它的 DEK（fail-open 数据损坏）
- 触发条件: 还原/导出（`reveal`）路径里，KEK 未加载（锁屏后）、DEK 解密失败、或加密服务只为 null 时
  **静默 `return`**，让后续的 unhide 继续跑
- 错误现象: 密文被当成媒体移出保险库 → 相册里是个打不开的文件；紧接着 DB 行（连同 `encrypted_dek`）被删除
  ⇒ **不可逆**的数据损坏。用户看到的是"还原后文件坏了/打不开"
- 正确做法: 解密前置校验失败必须**抛异常/返回失败**，让调用方跳过该项：
  ```dart
  Future<void> _decryptIfNeeded(MediaItem item) async {
    final encryptedDek = item.encryptedDek;
    if (encryptedDek == null || encryptedDek.isEmpty) return;
    final kek = _encryptionKeyManager!.getKey();
    if (kek == null) {
      throw StateError('vault key not loaded (lock and unlock, then retry)');
    }
    final dek = await _encryptionService!.decryptDek(encryptedDekBase64: encryptedDek, kek: kek);
    if (dek == null) throw StateError('DEK decryption failed');
    ...
  }
  ```
  调用方：单项 `try { ... } catch { return false; }`；批量维护 `blockedIds` 集合并 `continue` 跳过。
- 反例（别这么写）: `if (kek == null) return;` / `if (dek == null) return;`（看着"稳妥"，实际是 fail-open）
- 自检: `git grep -n "if (kek == null) return" -- lib/data/services/import/vault_reveal_runner.dart` 应无命中
- 首次记录: 2026-10-13（第十轮审计，见 `ISSUE-029`④）

## PIT-053 原生 AES-GCM 分块实现的三个隐蔽坑（skip 不可靠 / 空文件 minLength / finally 删备份）
- 触发条件: 用 `javax.crypto.Cipher` + 流式 `update()/doFinal()` 做文件加解密
- 错误现象:
  ① `InputStream.skip(n)` 只承诺"最多跳过 n 字节"，**可以少跳** ⇒ 若只跳过 0~11 字节，nonce 会被当密文喂进 GCM
     ⇒ 认证失败（"文件损坏"假象）；② `minLength = nonce + tag + 1` 让 **0 字节明文的密文（正好 28 字节）拒绝解密**；
  ③ `finally { bakFile.delete() }` 在"恢复 rename 也失败"的分支里会删掉**唯一的备份** ⇒ 真正的数据丢失
- 正确做法:
  ```kotlin
  // ① 循环跳过，直到真的跳够
  var skipped = 0L
  while (skipped < nonceLen) {
      val step = input.skip(nonceLen - skipped)
      if (step <= 0) break
      skipped += step
  }

  // ② 下限就是 nonce + tag（12 + 16 = 28），不要 +1
  val minLength = GCM_NONCE_LENGTH + GCM_TAG_LENGTH / 8

  // ③ 只在"新文件已就位"之后删备份；恢复失败必须保留备份并报错
  if (!tmp.renameTo(original)) {
      if (!bak.renameTo(original)) return mapOf("ok" to false, "error" to "...; kept as ${bak.name}")
      return mapOf("ok" to false, "error" to "Failed to rename temp file (restored backup)")
  }
  bak.delete()
  ```
  另外建议做 crash 自愈：`encryptFile` 开头若主文件缺失而 `.enc_bak` 存在 → 回填；残留 `.enc_tmp` 直接删。
- 反例（别这么写）: `input.skip(nonceLen)`；`minLength = nonce + tag + 1L`；
  `try { ... } finally { bakFile.delete() }`
- 自检: `git grep -n "GCM_TAG_LENGTH / 8 + 1L" -- android/` 应无命中；
  `git grep -n "input.skip(" -- android/app/src/main/kotlin/com/privi/app/CryptoHandler.kt` 只应出现在循环跳过里
- 首次记录: 2026-10-13（第十轮审计，见 `ISSUE-029`⑥）

## PIT-054 备份不含"密钥材料"就不叫备份：必须带 `encryptionSalt` + 每行 `encryptedDek`
- 触发条件: 应用有文件级加密（DEK 用 KEK 包、KEK 由 `PBKDF2(密码, salt)` 派生），但导出/备份只打包媒体文件
- 错误现象: 备份里全是**密文**、且没有 DEK/盐 ⇒ 重装或换机后恢复出来的文件**永远打不开**，而用户以为
  "我有备份"。`ISSUE-029`③ 正是如此（`vault_backup_*` 里 `grep -i encrypt` 零命中）
- 正确做法:
  - manifest 顶层存 `encryptionSalt`（**它不是秘密**，明文落盘没问题），每个媒体条目存 `encryptedDek`
    （已用 KEK 包好的密文）；
  - 还原时写回每行 `encrypted_dek`；salt **只能"缺失时采用"**：
    ```dart
    Future<bool> adoptEncryptionSaltIfAbsent(String salt) async {
      final existing = await readEncryptionSalt();
      if (existing != null && existing.isNotEmpty) return false; // 绝不覆盖
      await _storage.write(key: _kEncryptionSalt, value: salt);
      return true;
    }
    ```
    覆盖 salt = 换 KEK = 本机**已有**的加密文件全部失效；
  - 新字段一律做成**可选**且不 bump `manifestVersion`（旧备份缺字段 → null；旧版本 app 也能读新备份）
- 反例（别这么写）: 只把密文文件 copy 进备份包；还原时无条件 `write(encryption_salt, manifest.salt)`；
  为加字段而 bump manifestVersion（旧客户端会直接拒收备份）
- 自检: 导出后 `privi_manifest.json` 顶层应有 `encryptionSalt`，**已加密项**的条目应有 `encryptedDek`；
  还原到干净安装后用**导出时的图案**解锁 → 加密图片能正常显示
- 首次记录: 2026-10-13（R11，见 `ISSUE-029`③）

## PIT-055 `StatefulBuilder` 的 builder 里启动"一次性任务"必须加守卫，否则每次 rebuild 都会再起一个并发任务
- 触发条件: 在 `showDialog` 的 `StatefulBuilder(builder: (ctx, setDialogState) {...})` 里写
  `WidgetsBinding.instance.addPostFrameCallback((_) => run());`，而 `run()` 内部又会调
  `setDialogState(() {})` 刷新进度
- 错误现象: `setDialogState` → rebuild → builder 再执行 → **再注册一个 `run()`** ⇒ 并发任务数逐项递增
  （1→2→3→…），每个任务都从头处理同一批数据。本项目里表现为同一文件被几十个循环同时加密，
  产生 **0 字节 / 消失的媒体**（`ISSUE-030`，真机 15 个文件被打坏）
- 正确做法: 用闭包外的 `var started = false;`（或 State 字段）守卫，只启动一次：
  ```dart
  if (!started) {
    started = true;
    WidgetsBinding.instance.addPostFrameCallback((_) => run());
  }
  ```
  并且**跨调用**也要防重入（用户重复点按钮 / 重复打开对话框）：用一个模块级或 State 级
  `bool inFlight` + `try { ... } finally { inFlight = false; }`
- 反例（别这么写）: `builder` 里裸调 `addPostFrameCallback(() => run())`；
  或者用 `initState` 之外的方式在 build 里触发一次性副作用（`build`/`builder` 都必须是无副作用的）
- 自检: 日志里同一任务出现**多次并发开始**（时间戳间隔 <1s 的重复首条记录）就是命中了；
  修完应只看到一条开始记录
- 首次记录: 2026-10-13（真机 `密册_log_2026-10-13.txt` 定位，见 `ISSUE-030`）

## PIT-056 原地加密：临时文件名必须唯一 + 结果必须做长度校验（否则并发/异常会留下 0 字节文件）
- 触发条件: 在原生侧用"写临时文件 → rename 覆盖原文件"实现原地加密，且临时名写死
  （如 `"$filePath.enc_tmp"`），入口还带 `if (tmpFile.exists()) tmpFile.delete()`
- 错误现象: 两个并发调用会**互相删掉对方正在写的临时文件**：一个把（已被删除的 inode 的）数据写完，
  另一个 rename 出一个 **0 字节文件**覆盖原始媒体 ⇒ 数据永久丢失。日志里表现为
  `Encrypted: … (472687 → 0 bytes)` 紧接着 `File not found`
- 正确做法:
  ```kotlin
  // ① 同一路径串行
  fun encryptFile(path: String, dek: ByteArray, nonce: ByteArray): Map<String, Any?> =
      synchronized(lockFor(path)) { encryptLocked(path, dek, nonce) }

  // ② 临时名唯一，避免任何"清理旧临时文件"的动作误伤其它 writer
  val tmpFile = File("$path.enc_tmp-${UUID.randomUUID()}")

  // ③ rename 成功后校验长度：密文 = 明文 + nonce(12) + tag(16)
  val minimum = originalLength + GCM_NONCE_LENGTH + GCM_TAG_LENGTH / 8
  if (encryptedLength < minimum) {
      inputFile.delete()
      bakFile.renameTo(inputFile)   // 从备份恢复原文，绝不留下坏文件
      return mapOf("ok" to false, "error" to "Encryption produced a truncated file; original restored")
  }
  ```
  另外：`finally { bak.delete() }` 这类"无条件清理"要改成"只有在确认新文件就位后才删备份"
  （`PIT-053`③），并保留 `.enc_bak` 供启动时自愈恢复
- 反例（别这么写）: 固定临时名 + 入口 `tmp.delete()`；只依赖 Dart 侧串行（native 可能被多处调用）；
  加密后不校验长度直接删备份
- 自检: `git grep -n "enc_tmp" -- android/` 应看到 `UUID.randomUUID()` 且**看不到** `"$filePath.enc_tmp`
  （临时名不得拼在媒体名之后，见 `PIT-061`）；日志里不应再出现 `→ 0 bytes`
- 补充 2026-10-13（同一条链路上的第二处坑）: **唯一 ≠ 长度安全** —— 把 `.enc_tmp-<uuid>` 拼在媒体名后面，
  会让 227 字节的中文/日文名变成 272 字节 > 255 ⇒ `ENAMETOOLONG`，批量加密永远剩一个失败项
  （`ISSUE-034` / `PIT-061`）。另外清理逻辑不能再按"原文件名的前缀"匹配（新命名与原名无关），
  改为"同目录 + 前缀 + mtime 年龄阈值"，否则会误删并发在写的临时文件（`ISSUE-030` 复发）
- 首次记录: 2026-10-13（真机日志定位，见 `ISSUE-030`）

## PIT-057 `FlutterSecureStorage` 的两种 Android 后端不能"各用一个"：要么成对写读，要么统一
- 触发条件: 项目里同时存在 `const FlutterSecureStorage()`（默认后端）与
  `FlutterSecureStorage(aOptions: AndroidOptions(encryptedSharedPreferences: true))`（ESP 后端），
  且同一个 key 只往其中一个写
- 错误现象: 真机上出现"写进去但读不出来"：`setKey` 不抛异常（日志无 `Failed to persist KEK`），
  但 `retrievePersistedKek()` 每次都返回 null ⇒ 指纹解锁永远报 `no persisted KEK found`
  （`ISSUE-031`，用户图案解锁成功后依旧如此）
- 正确做法: 把 KEK 这类"必须能读回来"的密钥**在两个后端都写、读时取第一个非空**：
  ```dart
  static const _defaultStorage = FlutterSecureStorage();
  static const _espStorage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );
  // setKey: 两个都写（至少一个成功即可，全失败打 error）
  // retrievePersistedKek: 依次读，取第一个非空；全空时打 warn
  ```
  —— 幂等、能自愈任一方向的失败，也不会 orphan 老版本写入的值
- 反例（别这么写）: 只用一个实例；或"发现不一致就把两处都改成 ESP"（等于换存储桶，
  老用户已写入的值当场读不到，见 `ADR-035`④）
- 自检: 设备日志里 `EncryptionKeyManager` 不应出现 `no persisted KEK found in any of 2 backend(s)`
  （修复后若仍出现，说明两个后端都写不进去，需要换策略）；`KEK persisted to 1/2 backends` 是允许的
- 首次记录: 2026-10-13（真机日志定位，见 `ISSUE-031`）

## PIT-058 Android 上"单流 AES-GCM"处理大文件必然 OOM：AEAD 必须分块，且 `OutOfMemoryError` 要单独 catch
- 触发条件: 对一个文件做"整文件一个 tag"的 AES-GCM 加解密（`cipher.update()` 循环 + 末尾一次
  `doFinal()` 也算），且文件达到几十 MB 以上
- 错误现象: 实测 71.8MB 视频：
  `java.lang.OutOfMemoryError: Failed to allocate a 140444664 byte allocation`（≈2× 文件大小），
  栈顶 `com.android.org.conscrypt.OpenSSLAeadCipher.reset / doFinalInternal`
  ⇒ **进程崩溃**（`catch (e: Exception)` 抓不到 Error，日志只留在 `密册_crash_*.txt`）
- 正确做法:
  1) **分块 AEAD**：按固定块（1MiB）切分，每块用独立 nonce（`baseNonce(8) || int32be(index)`）与独立 tag，
     加解密都按块 `doFinal(input, off, len)` ⇒ 峰值内存 = 2×块大小，与文件大小无关；
     容器头部记录 `plaintextSize`，解密时据此循环
  2) 所有 native 加解密入口都要单独捕获 OOM：
     ```kotlin
     } catch (e: OutOfMemoryError) {          // Error ≠ Exception，必须单独写
         Log.e(TAG, "...", e)
         return mapOf("ok" to false, "error" to "Out of memory: file too large")
     } catch (e: Exception) { ... }
     ```
  3) 识别 magic 兼容旧格式；旧的大文件解密失败时返回明确错误（不要崩、不要写成半成品）
- 反例（别这么写）: `while (...) { cipher.update(...) } ; cipher.doFinal()`；
  `catch (e: Exception)` 里指望兜住 OOM；用"文件大小上限"当作内存保护
- 自检: 加密/解密一个 >200MB 的视频，`dumpsys meminfo <pkg>` 的峰值应稳定在几十 MB 量级；
  日志出现 `Encrypted(v2)` / `Decrypted(v2)`；`密册_crash_*.txt` 不再出现 `OpenSSLAeadCipher`
- 首次记录: 2026-10-13（见 `ISSUE-032`）

## PIT-059 本机手动跑 Gradle 校验的两个前置条件：`GRADLE_USER_HOME=.gradle_home` + `.\gradlew.bat`
- 触发条件: 想绕开 `build.bat`，直接在 `android/` 下跑单项任务（如 `:app:compileReleaseKotlin`）验证 Kotlin 改动
- 错误现象 / 代价:
  ① **不设 `GRADLE_USER_HOME`** 时 gradlew 用默认 `%USERPROFILE%\.gradle`，其 wrapper dists 里**没有**项目要求的
     `gradle-9.3.1` ⇒ 立刻去腾讯镜像**下载数百 MB**
     （日志 `Downloading https://mirrors.cloud.tencent.com/gradle/gradle-9.3.1-all.zip`）
  ② 在 `.bat` / cmd 里写 `gradlew.bat ...`（不带 `.\`）报 `'gradlew.bat' 不是内部或外部命令` ——
     本机 cmd **不把当前目录加入可执行搜索路径**（`NoDefaultCurrentDirectoryInExePath`），必须写 `.\gradlew.bat`
- 正确做法:
  ```powershell
  $env:GRADLE_USER_HOME = 'D:\WorkSpace\test\privi\.gradle_home'   # 项目缓存里已有 gradle-9.3.1
  Set-Location 'D:\WorkSpace\test\privi\android'
  & .\gradlew.bat -x :app:compileFlutterBuildRelease :app:compileReleaseKotlin --console=plain *> ..\tmp\kotlin_check.log
  ```
  长任务用 `Start-Process powershell -File tmp\xxx.ps1` 放独立窗口（`PIT-009`）；
  **ps1 里不要用嵌套双引号**（命令行传参会炸）：写成 `('RESULT=FAIL rc=' + $rc) | Out-File ...`
- 反例: `cmd /c "cd /d D:\...\android && gradlew.bat ..."`；用默认 `GRADLE_USER_HOME`（白等下载）
- 自检: 日志出现 `> Task :app:compileReleaseKotlin`（**不带 UP-TO-DATE**）才算真编译；
  出现 `Downloading ...gradle-9.3.1-all.zip` 说明 `GRADLE_USER_HOME` 没设对
- 首次记录: 2026-10-13

## PIT-060 Dart 侧加并发 ≠ 原生并发：MethodChannel 的 handler 跑在共享线程池上，池子多小并发就多小
- 触发条件: 给一个批量任务（本仓库是 6 000+ 文件的「加密已有文件」）在 Dart 侧加"多队列"，
  但没动原生 handler 的执行线程池
- 错误现象: 队列数从 1 加到 24，耗时几乎不变。本仓库实测原因：三处 crypto 调用都走
  `MainActivity.runIo()` → `Executors.newFixedThreadPool(3)`（原本给 metadata / libVLC parse 用），
  真正并行的只有 3 个，其余全部在排队（`ISSUE-033`）
- 正确做法: 批量任务要"真并发"时，给原生侧一个**专用且显式**的池，量与 Dart 队列同量级：
  ```kotlin
  private val cryptoExecutor = Executors.newFixedThreadPool(
      Runtime.getRuntime().availableProcessors().coerceIn(4, 8),
  )

  private fun <T> runCrypto(result: MethodChannel.Result, block: () -> T) {
      cryptoExecutor.execute {
          try {
              mainHandler.post { result.success(block()) }
          } catch (e: Throwable) {   // 必须 Throwable：不回复 = Dart 侧 future 永久 pending
              Log.w("PriviMain", "crypto call failed: ${e.message}", e)
              mainHandler.post { result.error("io_error", e.message, null) }
          }
      }
  }
  ```
  上限别给大：本仓库每个并发加解密峰值内存 ~2 MiB（`ISSUE-032`），4~8 是内存与吞吐的折中
- 反例（别这么写）: 只改 Dart（`for` → `Future.wait` / 多队列）就宣布"已并行"；
  或把 `ioExecutor` 的 3 直接改成 32（会连带改掉 metadata、libVLC parse 的并发，影响面没评估过）
- 自检: 用**并发证据**而不是队列数验证 —— 日志时间戳密度（同一毫秒级窗口内 ≥4 条
  `Encrypted with pre-saved DEK`）或 `dumpsys meminfo` 看峰值；
  静态自检: `git grep -n "runIo(result) { crypto" -- android/` 必须无命中（crypto 一律走 `runCrypto`）
- 首次记录: 2026-10-13（`ISSUE-033`）

## PIT-061 给媒体文件加后缀命名"临时/中间文件"前，先算 255 字节的预算（`ENAMETOOLONG`）
- 触发条件: 在媒体文件旁边新建中间文件，且名字 = **媒体原名 + 后缀**（例如
  `"$filePath.enc_tmp-${UUID.randomUUID()}"`，后缀 45 字节），媒体名又是中文/日文长名
- 错误现象: `FileOutputStream` 打不开临时文件：`open failed: ENAMETOOLONG (File name too long)`；
  表现是"批量加密永远剩下那一个失败项"，与并发、磁盘、密钥都无关（`ISSUE-034`）
- 正常做法: 让中间文件**与媒体名解耦**，同时保持"同目录"（同文件系统 ⇒
  `renameTo` 原子，`PIT-034`）：
  ```kotlin
  private const val TEMP_PREFIX = ".enc_tmp-"

  private fun tempFileFor(inputFile: File): File =
      File(inputFile.parentFile, "$TEMP_PREFIX${UUID.randomUUID()}")   // 固定 45 字节
  ```
  清理也要跟着改：新命名匹配不到"原名前缀"，必须按
  "**同目录 + 前缀 + mtime 年龄阈值（如 1h）**"，否则会误删并发加密**正在写**的临时文件
  （`ISSUE-030` 的 0 字节事故就是这么来的）
- 反例（别这么写）: `File("$filePath.enc_tmp-$uuid")` / `File(original.name + ".tmp")`；
  把临时文件放 `cacheDir`（跨文件系统 rename 不原子）；
  清理时"删掉同目录所有 `.enc_tmp*`"
- 自检: 复现用的媒体名要**故意长**（中文/日文 80+ 字 + 原后缀 = 200+ 字节）——
  短名不会暴露这个坑；命令参考:
  ```powershell
  # 从日志原文精确算字节数（255 = Linux/ext4/f2fs 单文件名上限）
  $line=(Select-String -LiteralPath <log> -Pattern 'ENAMETOOLONG').Line
  [Text.Encoding]::UTF8.GetBytes($line).Length   # 目视媒体名 + 后缀的字节数
  ```
  静态自检: `git grep -n '"$filePath.enc_tmp' -- android/` 必须无命中
- 首次记录: 2026-10-13（`ISSUE-034`，用户真机日志）
- 补充 2026-10-13（同一条链路上的第二处）: 备份名 `<媒体名>.enc_bak` 吃**同一个 255 字节预算**
  —— 第二次真机日志里出现了 6 次 `Failed to back up original file`。
  若备份名**必须**带原名（启动自愈靠它反推主文件），就要为"名字过长"准备退化路径：
  不建备份槽，直接 `tmp.renameTo(原文件)` 原子覆盖，并且该路径下**永不删主文件**
  （没有备份可恢复 ⇒ 删了就是丢数据），见 `ISSUE-034` 修法④


## PIT-062 本仓库的老 Dart 文件没跟上当前 SDK 的 `dart format`：写入式格式化会带进大量无关重排
- 触发条件: 对**早于当前 formatter 风格**的文件跑 `dart format <file>`（写模式）
- 错误现象: 只改了 30~50 行，diff 却几百行 —— 参数续行、`AppLogger.w(...)` 的换行与缩进会被整体重排
  （实测 `player_screen.dart`：逻辑改动 35 行 / diff 135 行；`settings_screen.dart`：diff 303 行）
- 正确做法:
  - 自测优先用**只读**检查 `dart format --output=none --set-exit-if-changed <file>`；
    但注意对仓库里的**老文件**它必然报 `Changed`（文件本来就不符合当前格式）⇒ `exit=1` **不代表**"我的改动有问题"；
  - 判断真实改动量用 `git --no-pager diff -w --stat`（忽略空白），行数应≈实际改动量，
    与 `git diff --stat` 的差额就是格式化噪音；
  - 只关心"能不能解析/类型对不对"时，用 `frontend_server` 编译检查（`PIT-014`）；
  - 真要写入格式化：先确认该文件本来就是 format 干净的，或**明确接受**这次重排并在交付说明里写清楚
- 反例: 直接 `dart format <一批老文件>`，把 300 行 diff 一起交出去 —— 用户 review 时找不到真实改动
- 自检: `git --no-pager diff -w --numstat -- <file>`，若"新增行数"≈你实际写的行数 ⇒ 噪音只是缩进
- 首次记录: 2026-10-13（本轮：Dart 侧 3 个老文件被顺带重排）


## PIT-063 重命名"已被 DB 引用的媒体文件"必须三步：rename → 校验 → 更新 DB（失败要改回原名）
- 触发条件: 对 `media_items.private_path` 指向的文件做 `rename`（文件名加密迁移 `ADR-042`、批量整理…）
- 错误现象（两个方向都不行）:
  ① **先更新 DB 再 rename**：rename 失败 ⇒ DB 指向不存在的文件（媒体在网格里"消失"，启动维护当孤儿清掉）；
  ② **rename 成功但 DB 没更新**（抛异常/进程被杀）⇒ 磁盘上多一个没人认得的文件，DB 仍指向旧名字（同样表现为丢文件）
- 正确做法（本仓库实现见 `FilenameEncryptionService.renameOne`）:
  ```dart
  await file.rename(target.path);                     // 同目录 ⇒ 同一文件系统 ⇒ 原子
  if (!target.existsSync() || target.lengthSync() != originalLength) {
    await _restore(target, item.privatePath);         // 校验不通过 ⇒ 改回
    return FilenameRenameOutcome.failed;
  }
  try {
    await _repository.updatePrivatePath(item.id, target.path);
  } catch (_) {
    await _restore(target, item.privatePath);         // 写库失败 ⇒ 改回，保持两者一致
    return FilenameRenameOutcome.failed;
  }
  ```
  另外：目标**必须同目录**（跨卷 rename 不原子甚至直接失败）；随机名要**检查存在性**并重试；
  迁移要**幂等**（"已经是新命名"就跳过），失败项可重跑
- 反例（别这么写）: 先 `updatePrivatePath` 再 `rename`；rename 后不校验、不 try/catch；
  跨目录/跨卷改名；用"原名 + 序号"这类可能撞名的规则且不检查存在性
- 自检: 改名中途杀进程（或让 DB 更新故意抛异常）后重启：网格里不应出现"打不开/消失"的项；
  日志应出现 `restoring the old name`（`could not restore` 才是真问题）
- 首次记录: 2026-10-13（`ISSUE-038`）

