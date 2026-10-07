- 处于 Act/YOLO 模式时不要请求批准，直接执行；仅在操作不可逆（删除数据、强推、改生产配置）时才停下确认。
- 需要技术选型时自行采用推荐方案并在结尾说明理由，不要用提问工具等待确认；失败时按预设备选方案自动重试，最多 3 轮。
- **构建一律由用户手工执行，Cline 默认不跑构建**（硬性约定）：本仓库构建耗时太长
  （全量/首次 15~25 分钟，本机还常遇 WMI 静默挂死），所以 Cline **不要**主动运行**任何**构建类命令 ——
  `build.bat`（全流程）、`build.bat gradle`、`build.bat fast`、`build.bat norelease`、`flutter build apk`、
  `flutter clean` 等都算在内。**只有用户当场明确要求**（例如"跑一下构建"/"build 一下"）才可以执行；
  需要验证构建结果时，改为提醒用户手工点击构建，并在拿到日志后再分析。
  入口与日志备查：build.bat（全流程）/ build.bat gradle（仅 Gradle）/ build.bat fast；
  `build\build_full.log`、`build\build_exit.log`。另：发现已有构建在跑时不要重复启动（见 `PIT-023`）。
- **改完的自测 = 静态验证（不是构建）**：默认只跑
  `dart format --output=none --set-exit-if-changed <改动文件>`（语法）
  与 `dart analyze <改动文件>`（类型/静态，实测可用；`dart.exe` 全路径见 `PIT-014`），
  并把输出贴出来，不要只给结论；.bat/.ps1 等改动则按 `PIT-002` 校验编码与行尾。
  只有用户明确要求构建时，才去跑构建并贴日志尾部。
- 结束前必须给出 git diff 摘要；不要自动 `git commit` / `git push`（只有用户当场明确要求时才推）。
- **推送 git 只推「当前分支」**（硬性约定，2026-10-07 起）：push 一律显式写**单分支** refspec ——
  在 `main` 上就 `git push origin main`、在 `dev` 上就 `git push origin dev`；
  **禁止** `git push --all` / `--mirror` / `git push origin main dev`（一条命令推多个分支），
  也**不要**顺手推 `backup_*` 快照分支（它们只在 `ADR-021` ①的备份步骤里按需创建/推送）。
  推前用 `git branch --show-current` 确认当前分支；推后用 `git log --oneline -1 --decorate` 与
  `git status -sb` 复核，需要硬证据时用 `git ls-remote origin refs/heads/main refs/heads/dev`
  （远端 ref 刷新有滞后，见 `PIT-008`）。理由与影响见 `ADR-030`。
- 知识库（强制）：**开工前**先查 `memory-bank/`（协议 + 索引见 `memory-bank/README.md`），命中即复用条目结论、不重复排查；**结束前**必须按模板回填 `memory-bank/issues-solved.md`（已排查问题）/ `pitfalls.md`（踩坑）/ `decisions.md`（技术决策）并更新索引。完整硬性要求见 `.clinerules/memory-bank.md`。
- 临时文件（强制）：任务过程中产生的**一切中间文件**（命令输出、临时脚本、状态/轮询文件、探针日志…）统一写在仓库根 `tmp\` 下，禁止散落在仓库根或其它目录；收尾前清理干净。完整规则见 `.clinerules/tmp-files.md`。