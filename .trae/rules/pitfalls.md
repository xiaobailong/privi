# 密册 (privi) 工作区避坑规则

> 执行命令或操作过程中遇到的坑，自动记录在此。每条包含：现象、原因、解决方案。

## 已记录坑点

### 1. RunCommand 无法复用已有终端 + 终端清理不可靠
- **现象**：
  1. 执行命令时指定 `target_terminal` 为上一次返回的终端 ID，系统仍然会新开一个终端。
  2. 每个 `RunCommand` 都会打开一个新终端，包括清理终端自身的命令，导致终端越清越多。
- **原因**：
  1. `target_terminal` 参数指定已有 ID 时未生效，每次调用都分配新终端——这是工具层面的限制，无法通过规则规避。
  2. 任何基于 `RunCommand` 的终端清理方案（杀进程、自杀式关闭）都不可靠，因为清理命令本身也会开新终端。
- **解决方案/规避**：
  - **接受现实**：无法在工具层面强制复用或清理终端。
  - **唯一可靠方案 —— 命令末尾自关闭**：
    - 所有短命令（git、echo 等）末尾加自关闭语句，命令执行完终端自动关闭。
    - **PowerShell**：`command args; exit`
    - **cmd**：`command args & exit`
    - **关键**：如果命令中包含 `.bat` 或 `.cmd` 文件，在 cmd 里必须用 `call` 调用（如 `call build.bat`），否则控制权转移后 `& exit` 不会执行；PowerShell 里直接调用即可。
  - **终端命名（必须）**：每个新终端首条命令必须是标识头：
    - PowerShell: `echo "=== task-N-用途 ==="`
    - cmd: `echo === task-N-用途 ===`
  - **禁止使用 `taskkill /f /im cmd.exe`**，会误伤用户自己的 cmd。
  - `StopCommand` 只能停止正在运行的命令，不会关闭终端会话。

### 2. 不要假设终端类型，先探测再决定语法（重要）
- **现象**：凭经验用 cmd 语法写 `&&`、`2>nul`、`%VAR%`，或用 PowerShell 语法写 `;`、`2>$null`、`$env:VAR`，结果在另一种终端里报错。
- **原因**：RunCommand 实际启动的终端不固定，有时是 PowerShell，有时是 cmd，不能写死。
- **解决方案/规避**：
  - 每次执行命令前**先探测终端类型**。
  - 探测命令：`$PSVersionTable`
    - 输出含 `Name`/`PSVersion` 等版本信息 → **PowerShell**
    - 报 `'$PSVersionTable' is not recognized` → **cmd**
  - 探测后用对应语法：
    - **PowerShell**：分隔 `;`、重定向 `2>$null`、注释 `#`、变量 `$env:VAR`、末尾 `; exit`
    - **cmd**：分隔 `&`/`&&`、重定向 `2>nul`、注释 `rem`、变量 `%VAR%`、末尾 `& exit`
  - 禁止用 `cmd /c` 包裹命令。

### 3. git 命令输出被分页器截断，需手动翻页
- **现象**：执行 `git diff`、`git log` 等命令时，输出进入 less 分页器，内容被截断，需要手动翻页或按 q 退出，无法一次性完整显示。
- **原因**：仓库的 git 配置（`core.pager`）启用了分页器，即使运行环境设置了 `PAGER=cat`，git 自身的 pager 配置优先级更高，会覆盖环境变量。
- **解决方案/规避**：
  - 所有 `git` 命令一律加 `--no-pager` 参数：`git --no-pager diff "路径"`、`git --no-pager log -n 10`、`git --no-pager status`
  - 不要省略，环境变量 `PAGER=cat` 对 git 无效。

### 4. `.bat` 文件编码必须是 UTF-8 无 BOM + CRLF；`chcp 65001` 位置有讲究
- **现象**：
  1. `.bat` 文件带 BOM 时第一行 `@echo off` 变 garbage（cmd 报错/首行不生效）
  2. `chcp 65001` 放在任何中文行**之前**→ 后续所有中文行被 cmd 错误解析
  3. 完全不用 `chcp 65001` 时，UTF-8 中文 echo 在 GBK 默认代码页的 cmd 窗口中显示为乱码
- **原因**：
  1. cmd.exe 对 BOM 敏感
  2. `chcp 65001` 切换代码页后，cmd 重新解析后续行中的多字节 UTF-8 中文时发生字节错位
  3. cmd 默认代码页是 GBK（936），直接输出 UTF-8 中文 = 乱码
- **解决方案/规避**：
  1. `.bat` 文件：UTF-8 无 BOM、CRLF 行尾
  2. `chcp 65001 >nul 2>nul` 必须出现在**所有中文行之后**
  3. **切勿**把 `chcp 65001` 放在脚本开头（第 2 行），会导致整个脚本的中文全部错位

### 5. 批处理 `if/for ( )` 块内 `%ERRORLEVEL%` 取到旧值
- **现象**：`( )` 块内用 `%ERRORLEVEL%` 判断上一条命令的退出码，永远走到旧值对应的分支
- **原因**：`%VAR%` 是解析期展开（进块前就替换好了），`!VAR!` 才是运行时展开
- **解决方案/规避**：
  - 用 `setlocal enabledelayedexpansion` + `!ERRORLEVEL!` / `!VAR!`
  - 退出码判断优先用 `if errorlevel N` 结构

### 6. `rd /s/q` 语法在 Windows cmd 中不合法
- **现象**：`rd /s/q build` 报 `The syntax of the command is incorrect`
- **原因**：Windows cmd 要求 `rd` 的开关用空格分隔：`rd /s /q`
- **解决方案/规避**：一律写 `rd /s /q <目录>`

### 7. pip 输出重定向到 nul 导致误判卡死
- **现象**：`pip install -r requirement.txt > nul 2>&1` 运行时终端无任何输出，用户以为卡住了
- **原因**：所有输出（包括进度条和下载状态）被重定向吞掉
- **解决方案/规避**：
  - 不要让 pip 输出全部进 `nul`，保留正常输出
  - 如果必须静默，用 `> tmp\pip_log.txt 2>&1` 至少留日志文件可查

### 8. `for %%i in ("%~dp0..") do set "PROJECT_ROOT=%%~fi"` 不包含末尾 `\`
- **现象**：`if not exist "%PROJECT_ROOT%VERSION"` 实际查找路径缺少 `\` 分隔符，始终判定文件不存在
- **原因**：`%%~fi` 展开为完整路径时不追加 `\`
- **解决方案/规避**：
  - 一律写成 `set "PROJECT_ROOT=%%~fi\"`（末尾加 `\`）
  - 或用 `if not exist "%PROJECT_ROOT%\VERSION"` 引用

### 9. PowerShell 多行 commit message 解析不可靠
- **现象**：
  1. 在 PowerShell 里用 `git commit -m "第一行`n第二行"` 提交时，消息要么被压成一行，要么报错
  2. 消息里含中文、括号、引号时更容易出问题
- **原因**：
  1. PowerShell 用反引号 `` ` `` 做转义符但在工具调用的字符串参数传递过程中容易被吞掉
  2. 当 commit message 中包含特殊字符时，PowerShell 的参数解析与 git 的参数解析不一致
- **解决方案/规避**：
  - **首选方案：写临时文件 + `git commit -F`**（最稳）：
    ```powershell
    New-Item -ItemType Directory -Force tmp | Out-Null
    @'
    feat: 提交标题（第一行）

    详细说明第二行
    '@ | Out-File -FilePath tmp/commit_msg.txt -Encoding utf8
    git --no-pager commit -F tmp/commit_msg.txt
    ```
  - **禁止**：在 `-m` 参数里用 `\n` 或 `` `n`` 写多行消息

### 10. Flutter 构建输出被终端捕获不可靠
- **现象**：通过终端工具执行 `flutter build apk` 等长时间命令，输出可能被截断或终端无响应
- **原因**：Flutter 构建输出量大且可能产生子进程输出，终端工具的 stdout 捕获有限制
- **解决方案/规避**：
  - 长时间构建命令输出重定向到文件：`flutter build apk > tmp\build_out.txt 2>&1`
  - 通过 `Read` 工具读取输出文件检查结果
  - 静态分析优先用 `dart analyze`（不触发完整构建）

### 11. Gradle 构建输出无法被终端捕获（卡住无输出）
- **现象**：通过终端工具执行 Gradle 命令，终端无任何输出
- **原因**：Gradle Daemon 生成输出到子进程，终端工具的 stdout 捕获无法穿透多层进程
- **解决方案/规避**：
  - **必须通过批处理文件 + `Start-Process` 异步启动**，将输出重定向到文件
  - 遇到构建无响应时，先用 `gradle --stop` 停止僵尸 Daemon
  - 不要使用 `--no-daemon` 参数

### 12. `.ps1` = UTF-8 带 BOM + CRLF；`.bat` / `.md` = UTF-8 无 BOM + CRLF
- **现象**：无 BOM 的 `.ps1` 被 PowerShell 5.1 按 GBK 读 ⇒ 中文乱码甚至语法错；`.bat` 带 BOM ⇒ 首行 `@echo off` 变 garbage
- **解决方案/规避**：
  - `.ps1` 要 `enc=BOM` + `bareLF=0`
  - `.bat` / `.md` 要 `enc=noBOM` + `bareLF=0`
  - 无 BOM 的 ps1 里不要出现中文字面量 / 中文路径