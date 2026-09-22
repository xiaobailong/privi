# =============================================================================
#  build_pub_get.ps1 - 带"卡死看门狗"的 flutter pub get 执行器（由 build.bat 调用）
#
#  WHY THIS FILE EXISTS
#  build.bat 原来直接执行
#      call flutter pub get --verbose > build\pub_get_codegen.log 2>&1
#  一旦 dart.exe 卡在启动阶段（日志 0 字节、CPU 不再增长、进程永不返回），
#  构建就会无限期挂起且看不到任何提示，只能靠人肉猜。
#
#  2026-09-21/09-22 的实测根因（已定位并复现）：
#    Windows 上 Dart 用 COM/WMI 查平台信息（Platform.operatingSystemVersion
#    -> Win32_OperatingSystem），该调用没有超时。当 winmgmt 服务"显示 RUNNING
#    但不回 Win32_OperatingSystem"时，flutter.bat 每次启动都在这里静默阻塞。
#    所以真正的前置拦截放在 build_wmi_guard.ps1（由 :checkenv 调用），
#    本脚本的看门狗是第二道保险：不管什么原因，日志静止就砍。
#
#  本脚本把命令放进子进程, 持续监视日志文件:
#    * 每 -HeartbeatSec 秒打印一行心跳（已运行时长 / 日志字节数 / 静止时长）
#    * 日志连续 -IdleTimeoutSec 秒零增长 → 判定卡死，杀掉整棵进程树并 exit 124
#  这样最坏情况下 build.bat 几分钟内就能给出结论和排查建议，而不是永远不动。
#
#  USAGE
#    powershell -NoProfile -ExecutionPolicy Bypass -File build_pub_get.ps1
#    powershell -NoProfile -ExecutionPolicy Bypass -File build_pub_get.ps1 -IdleTimeoutSec 600
#    powershell -NoProfile -ExecutionPolicy Bypass -File build_pub_get.ps1 `
#        -Log "build\pub_get_build.log" -IdleTimeoutSec 300
#    powershell -NoProfile -ExecutionPolicy Bypass -File build_pub_get.ps1 `
#        -Command "cmd /c ping -n 60 127.0.0.1" -IdleTimeoutSec 6 -HeartbeatSec 2   # 自测用
#
#  OUTPUT (stdout)
#    [pub] ...    心跳/结论行（会被 build.bat 的 tee 同时写进 build_full.log）
#    退出码        子进程退出码; 124 = 判定卡死并已杀掉进程树; 125 = 执行器自身异常
# =============================================================================
param(
    # 要执行的命令（默认就是 build.bat 需要的 flutter pub get）
    [string]$Command = 'flutter pub get --verbose',

    # 日志文件（stdout + stderr 都进这里）
    [string]$Log = 'build\pub_get_codegen.log',

    # 日志零增长多久判定为卡死（秒）
    [int]$IdleTimeoutSec = 300,

    # 心跳间隔（秒）
    [int]$HeartbeatSec = 20
)

$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [Text.Encoding]::UTF8

function Write-Line([string]$Text) { Write-Output $Text }

try {
    if ($HeartbeatSec -lt 1) { $HeartbeatSec = 1 }

    $logFull = [IO.Path]::GetFullPath((Join-Path (Get-Location).Path $Log))
    $logDir = [IO.Path]::GetDirectoryName($logFull)
    if (-not (Test-Path -LiteralPath $logDir)) { New-Item -ItemType Directory -Path $logDir -Force | Out-Null }

    Write-Line ("[pub] 执行: " + $Command)
    Write-Line ("[pub] 日志: " + $logFull)
    Write-Line ("[pub] 看门狗: 日志连续 " + $IdleTimeoutSec + " 秒无增长即判定卡死, 心跳 " + $HeartbeatSec + " 秒")

    # stderr 用独立文件，正常应为 0 字节；便于区分"输出被吞"和"根本没输出"
    $errFull = $logFull + '.stderr'
    Remove-Item -LiteralPath $errFull -Force -ErrorAction SilentlyContinue

    $sw = [Diagnostics.Stopwatch]::StartNew()
    # 通过 cmd.exe 启动，才能直接跑 flutter.bat（.bat 不能被 CreateProcess 直接执行）
    #
    # 退出码必须让 cmd 自己回显到日志里：本机 Start-Process -PassThru 返回的对象
    # 读 $proc.ExitCode 会得到空值，而后面的 exit $null 会被 PowerShell 当成 0，
    # 于是"pub get 失败"被静默当成功（实测：-Command "cmd /c exit 7" → 报告退出码 0）。
    # 注意 /v:on + !ERRORLEVEL!：整条命令行是一次解析的，用 %ERRORLEVEL% 会取到执行前的旧值。
    $rcMarker = '[pub-exit]'
    $cmdLine = "$Command 2>&1 & echo $rcMarker !ERRORLEVEL!"
    $proc = Start-Process -FilePath $env:ComSpec -ArgumentList @('/v:on', '/c', $cmdLine) -PassThru -NoNewWindow `
        -RedirectStandardOutput $logFull -RedirectStandardError $errFull

    $lastLen = -1
    $lastGrowth = [TimeSpan]::Zero
    $killed = $false

    while (-not $proc.HasExited) {
        Start-Sleep -Seconds $HeartbeatSec
        if ($proc.HasExited) { break }

        $len = 0
        try { $len = (Get-Item -LiteralPath $logFull -ErrorAction SilentlyContinue).Length } catch { $len = -1 }
        if ($null -eq $len) { $len = 0 }
        if ($len -ne $lastLen) { $lastLen = $len; $lastGrowth = $sw.Elapsed }
        $idle = [int]($sw.Elapsed - $lastGrowth).TotalSeconds

        Write-Line ("[pub] 已运行 " + [int]$sw.Elapsed.TotalSeconds + "s | 日志 " + $len + " 字节 | 静止 " + $idle + "s")

        if ($idle -ge 60 -and $idle -lt $IdleTimeoutSec) {
            Write-Line ("[pub] 注意: 日志已 " + $idle + "s 无增长（可能正在下载依赖; 若长期为零, 多半是 dart.exe 被安全软件拦截）")
        }

        if ($idle -ge $IdleTimeoutSec) {
            Write-Line ("[pub] 判定卡死: 日志连续 " + $idle + " 秒无增长（阈值 " + $IdleTimeoutSec + "s）, 开始杀掉进程树...")
            # /T 连子孙一起杀：cmd -> flutter.bat -> dart.exe
            & taskkill.exe /PID $proc.Id /T /F 2>&1 | ForEach-Object { Write-Line ("[pub] " + $_) }
            $killed = $true
            break
        }
    }

    if (-not $killed) { $proc.WaitForExit() }
    $sw.Stop()

    $finalLen = 0
    try { $finalLen = (Get-Item -LiteralPath $logFull -ErrorAction SilentlyContinue).Length } catch { $finalLen = 0 }
    if ($null -eq $finalLen) { $finalLen = 0 }

    if ($killed) {
        Write-Line ("[pub] 卡死结论: 已运行 " + [int]$sw.Elapsed.TotalSeconds + "s, 日志仅 " + $finalLen + " 字节")
        if ($finalLen -gt 0) {
            Write-Line "[pub] ---- 日志最后 15 行 ----"
            Get-Content -LiteralPath $logFull -Tail 15 -Encoding UTF8 -ErrorAction SilentlyContinue | ForEach-Object { Write-Line ("[pub] " + $_) }
        } else {
            Write-Line "[pub] 日志为空: 说明 flutter/dart 在写出任何东西之前就被拦住了（不是网络/依赖问题）"
            Write-Line "[pub] 提示: 先跑 build_wmi_guard.ps1 确认 WMI 是否正常（Dart 查 OS 版本走 WMI 且无超时）"
        }
        exit 124
    }

    # 退出码取 cmd 回显的那一行；取不到才退回 $proc.ExitCode；两者都没有就判失败，
    # 绝不能默认成功 —— 否则 pub get 失败会被静默放过，后面的 Gradle 报一堆莫名其妙的错。
    $code = -1
    $raw = ''
    try { $raw = [string](Get-Content -LiteralPath $logFull -Raw -Encoding UTF8 -ErrorAction SilentlyContinue) } catch { }
    if ($raw -and ($raw -match ([regex]::Escape($rcMarker) + '\s*(\d+)'))) { $code = [int]$Matches[1] }
    if ($code -lt 0) {
        try { $code = [int]$proc.ExitCode } catch { $code = -1 }
    }
    if ($code -lt 0) {
        Write-Line "[pub] 警告: 既没抓到 cmd 回显的退出码, 也读不到进程退出码, 按失败处理"
        exit 125
    }

    Write-Line ("[pub] 结束: 退出码 " + $code + ", 耗时 " + [int]$sw.Elapsed.TotalSeconds + "s, 日志 " + $finalLen + " 字节")
    exit $code
}
catch {
    Write-Line ("[pub] 执行器异常: " + $_.Exception.Message)
    exit 125
}
