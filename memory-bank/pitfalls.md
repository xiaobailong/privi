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
