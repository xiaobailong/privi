# 密册 (privi) 项目规则

## 概述
密册 — personal on-device Android media vault，基于 Flutter 构建的个人本地媒体保险库应用。

## 技术栈
- **语言**: Dart
- **框架**: Flutter
- **Android 构建**: Gradle + Android SDK
- **架构**: Clean Architecture（lib/core, lib/data, lib/domain, lib/presentation）

## 目录结构
```
privi/
├── lib/
│   ├── main.dart                  # 应用入口
│   ├── app.dart                   # App 组件
│   ├── application/               # 应用层
│   ├── core/                      # 核心模块
│   ├── data/                      # 数据层
│   ├── domain/                    # 领域层
│   ├── presentation/              # 展示层
│   └── l10n/                      # 国际化
├── android/                       # Android 工程文件
├── scripts/                       # 构建脚本
├── .clinerules/                   # Cline 强制规则
├── memory-bank/                   # 知识库
└── tmp/                           # 临时文件（gitignored）
```

## 关键约定

### 构建命令
- **完整构建**: 通过 `build.bat` 执行（全流程）
  - `build.bat` — 完整构建
  - `build.bat gradle` — 仅 Gradle 构建
  - `build.bat fast` — 快速构建
  - `build.bat norelease` — 构建但不发布
  - `build.bat clean` — 清理构建产物
- **日志**: `build\build_full.log`、`build\build_exit.log`

### 自测（禁止跑 build.bat）
- **禁止为了自测跑 `build.bat`**（会真的 push + 发 Release）
- 校验改动优先静态分析：
  - `dart format --output=none --set-exit-if-changed <改动文件>`
  - `dart analyze <改动文件>`
- 只有用户明确要求构建时，才去跑构建

### 代码规范
- 遵循 Flutter/Dart 标准代码风格
- 使用 Clean Architecture 分层
- 中文注释、日志、文案保持中文

### 交流约定（强制）
- 所有思考、分析、回答必须使用中文
- 代码注释可使用中文或英文

### 终端管理（强制）
- **不要假设终端类型！** 实际可能是 PowerShell 也可能是 cmd，每次执行命令前**必须先探测**。
  - 探测命令：`$PSVersionTable`
    - 输出含版本信息 → **PowerShell**
    - 报 `is not recognized` → **cmd**
  - **PowerShell 语法**：分隔用 `;`、重定向 `2>$null`、注释 `#`、变量 `$env:VAR`、末尾 `; exit`
  - **cmd 语法**：分隔用 `&`/`&&`、重定向 `2>nul`、注释 `rem`、变量 `%VAR%`、末尾 `& exit`
  - 禁止用 `cmd /c` 包裹命令
- **终端内容标识（必须）**：每个新终端首条命令必须是标识头：
  ```
  PowerShell: echo "=== task-N-用途 ==="
  cmd:        echo === task-N-用途 ===
  ```
- **终端自关闭（强制）**：每条命令末尾加自关闭语句
- **禁止主动杀进程**：`taskkill /f /im cmd.exe` 会误伤用户自己的 cmd

### Git 操作约定（强制）
- **禁用分页器**：所有 `git` 命令必须加 `--no-pager` 参数
- **推送只推当前分支**：禁止 `git push --all` / `--mirror`；禁止一条命令推多个分支

### 临时文件管理（强制）
- 所有中间产物全写 `tmp\`
- `tmp\` 被 `.gitignore` 忽略（`/tmp/`）
- **收尾必须清空**

### 知识库管理
- 知识库位于 `memory-bank/`，索引文件 `memory-bank/README.md`
- 开工读索引 → 只读命中条目；收工照 `memory-bank/WRITING.md` 回填
- 禁止 `read all` 知识库、禁止扫全仓库

### 命令等待
- 在终端执行命令后必须等待命令执行完成，不要命令一发出就立刻查看输出并断定执行失败

## 常用操作
- **语法检查**: `dart format --output=none --set-exit-if-changed <文件>`
- **静态分析**: `dart analyze <文件>`
- **完整构建发布**: `build.bat`
- **清理构建缓存**: `build.bat clean`

## 项目记忆
- Git 仓库位于 `D:\WorkSpace\test\privi`，所有代码变更通过 git 管理
- Flutter 项目，Android 目标平台