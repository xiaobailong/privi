# 临时文件归属（硬性要求）：一律写进仓库根 `tmp\`

> 目的：Cline 工作过程中产生的中间文件**集中在一个可识别的目录**，`git status` 保持干净、
> 清理动作可以脚本化，也不会误删业务文件。
> 目标路径：`D:\WorkSpace\test\privi\tmp\`（仓库相对路径 `tmp\`）。

## 1. 规则

- Cline 在任务过程中产生的**任何中间文件**都必须写在 `tmp\` 下；
  **禁止**写在仓库根、`lib\`、`android\`、`scripts\`、`docs\`、`memory-bank\` 等任何其它位置。
- 包括但不限于：命令输出重定向（`> tmp\out.txt 2>&1`）、临时 `.ps1` / `.bat` 辅助脚本、
  状态 / 轮询 / 进度文件、探针与诊断日志、导出的对比数据、临时 JSON/CSV/截图。
- 目录不存在就先建：`mkdir tmp`（一次即可）。
- 命令里写**相对路径**即可（shell 的工作目录就是仓库根）：`> tmp\out.txt`；
  需要绝对路径时：`D:\WorkSpace\test\privi\tmp\out.txt`。
- 命名直接用用途（如 `build_status.txt`、`probe_encode.ps1`），**不要**在 `tmp\` 里再建多层子目录。

## 2. 例外（这些不是"临时文件"，不要往 `tmp\` 塞）

| 产出 | 归属 | 原因 |
| --- | --- | --- |
| 构建/脚本自身的规范日志（`build_full.log`、`build_exit.log`、`mem_report.log`、`pub_*.log`、`toolchain_probe.log`…） | `build\` | 由脚本自己写，`build.bat`/`clean.bat` 负责清理 |
| 知识库条目 | `memory-bank\` | 入库、跨会话复用（见 `.clinerules/memory-bank.md`） |
| 过程 / 交接文档 | `docs\HANDOFF-*.md` | gitignored 且不会被 `flutter clean` 删 |
| 长期复用的构建脚本 | `scripts\` | 入库；新增脚本要同步 `build.bat` 路径（见 `ISSUE-011`） |
| 临时脚本验证后决定长期保留 | 迁到 `scripts\` 并同步 `build.bat` | 同上 |

**不要**把自制临时文件塞进 `build\`：`flutter clean` 会删掉，而且会被误当成构建产物（见 `PIT-017`）。

## 3. 清理（必须做）

- **任务结束前**：删掉本次不再需要的临时文件，`tmp\` 应为空（或不存在）。
- **一键清理**：`clean.bat` 与 `build.bat clean` 都会整目录删除 `tmp\`。
- 收尾回复里说明「`tmp\` 是否已清空」。

## 4. 为什么这样定

- 以前临时产物散落在仓库根，`git status` 噪声大、要人工辨认哪些能删 ——
  上一轮任务的交接清单里就有一条「删掉仓库根目录的一次性产物」（见 `PIT-022`）。
- 统一目录后：`git status` 只需看真实改动；清理是一条命令；也不会误删业务文件。
- `tmp\` 整目录被 `.gitignore` 忽略（`/tmp/`），**不会入库**，可放心当垃圾桶用。
