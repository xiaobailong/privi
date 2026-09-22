# =============================================================================
#  build_probe_toolchain.ps1 - 工具链可用性探测（由 build.bat 的 :checkenv / :doctor 调用）
#
#  WHY THIS FILE EXISTS
#  build.bat 过去只 `where flutter` 就认为工具链没问题（--version / doctor 都被
#  "怕卡死" 主动跳过了）。可是本机真实发生过：flutter.bat 一路正常走到最后一步,
#  dart.exe 加载 flutter tool 快照时被端点安全软件拦住 → 进程活着、CPU 不涨、
#  一行输出都没有, 于是构建在 "flutter pub get" 处无限期挂起。
#  本脚本给每一步都加硬超时，把"哪种卡死"区分出来并给出修复建议：
#    1) dart --version             能跑 → Dart VM 本体没问题
#    2) Platform.operatingSystemVersion 能读 → WMI 正常（Windows 上这条走 WMI）
#    3) dart <临时脚本>             能跑 → VM 能编译/执行代码
#    4) flutter --version          能跑 → flutter tool 快照能正常加载
#  任何一步超时都能在 2 分钟内出结论, 而不是让构建永远挂着。
#
#  USAGE
#    powershell -NoProfile -ExecutionPolicy Bypass -File build_probe_toolchain.ps1
#    powershell -NoProfile -ExecutionPolicy Bypass -File build_probe_toolchain.ps1 -FlutterTimeoutSec 300
#
#  OUTPUT (stdout, 单行, 供 cmd 用 for /f 读取；刻意避开 & | < > ( ) ! % 等 cmd 特殊字符)
#    OK: flutter=Flutter 3.32.0 channel stable dart=Dart SDK version 3.9.2
#    HANG: WMI 无响应 ...  (Platform.operatingSystemVersion 不返回, 见下)
#    HANG: flutter --version 超过 120 秒零输出, dart 能跑脚本但加载 flutter tool 快照时被拦死
#    ERROR: dart --version 超过 30 秒未返回. Dart SDK 或 VM 层异常
#    SKIP: 未找到 flutter.bat 路径 xxx
#  退出码: 0 正常 / 2 Dart SDK 层异常 / 3 flutter tool 卡死 / 4 flutter 可执行文件缺失
#          5 WMI 挂死（Platform.operatingSystemVersion 不返回）/ 1 其他异常
#  详细过程写入 build\toolchain_probe.log
#
#  ⚠ WMI 那一项为什么单独列出来
#    Windows 上 Dart 把 Platform.operatingSystemVersion 实现成 COM/WMI 查询
#    （wbemuuid.lib，**没有超时**），而 flutter.bat 每次启动都会读这个属性。
#    本机 2026-09-21 与 2026-09-22 两次出现「winmgmt 服务 RUNNING、但就是不回这个查询」，
#    表现是 build.bat 卡在 flutter pub get：控制台无输出、日志 0 字节、进程杀不掉。
#    这条探针能在 WmiTimeoutSec（默认 15 秒）内把它和"网络慢 / 依赖下载慢"区分开。
# =============================================================================
param(
    [string]$FlutterRoot = '',
    [string]$Log = 'build\toolchain_probe.log',
    [int]$WmiTimeoutSec = 15,
    [int]$DartTimeoutSec = 30,
    [int]$FlutterTimeoutSec = 120
)

$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [Text.Encoding]::UTF8

$detail = New-Object System.Collections.Generic.List[string]
function Log([string]$t) { $detail.Add($t) }

# cmd 端要用 echo 打印这行（可能位于 if (...) 块里），
# 所以必须剔除 cmd 特殊字符，避免消息本身把批处理语法搞坏。
function Sanitize([string]$t) {
    if ([string]::IsNullOrEmpty($t)) { return '' }
    $t = $t -replace '[&|<>()^!%"]', ' '
    # flutter --version 里有 '•' 这样的非 ASCII 字符，本机控制台是 GBK(936)，
    # 子进程按 UTF-8 写出去会被显示成乱码（鈥?），调用方 for /f 抓取后也就没法用了。
    # 直接压成纯 ASCII，跟控制台代码页彻底解耦。
    $t = $t -replace '[^\x20-\x7E]', ' '
    $t = $t -replace '\s+', ' '
    return $t.Trim()
}

function Save-Log {
    try {
        $dir = [IO.Path]::GetDirectoryName([IO.Path]::GetFullPath((Join-Path (Get-Location).Path $Log)))
        if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
        Set-Content -LiteralPath $Log -Value $detail -Encoding UTF8
    } catch { }
}

function FirstLine([string]$t) {
    if ([string]::IsNullOrWhiteSpace($t)) { return '' }
    return ($t -split "`r?`n" | Where-Object { $_.Trim() -ne '' } | Select-Object -First 1).Trim()
}

# 运行一个命令并硬超时。返回哈希表
#
# 注意 1: 参数不能叫 $args —— $args 是 PowerShell 的自动变量，声明它会被自动变量遮蔽，
#         Start-Process -ArgumentList $args 实际拿到空数组，报
#         "Cannot validate argument on parameter 'ArgumentList' ... contains a null value"
#         （本脚本历史上从未跑通过，就是这个原因）。
# 注意 2: 不用 $p.ExitCode 做判定 —— 本机 Start-Process -PassThru 经常读不到退出码
#         （得到空值或 -1）。改用 -Expect 正则匹配输出内容，退出码只写进日志供参考。
function Invoke-Probe([string]$name, [string]$exe, [string[]]$cmdArgs, [int]$timeoutSec, [string]$wd, [string]$Expect = '') {
    $o = Join-Path $env:TEMP ("probe_" + $name + ".out")
    $e = Join-Path $env:TEMP ("probe_" + $name + ".err")
    $r = @{ Name = $name; State = 'FAIL'; Exit = -1; Ms = 0; Out = ''; Err = '' }
    $sw = [Diagnostics.Stopwatch]::StartNew()
    try {
        $p = Start-Process -FilePath $exe -ArgumentList $cmdArgs -PassThru -NoNewWindow -WorkingDirectory $wd `
            -RedirectStandardOutput $o -RedirectStandardError $e
    } catch {
        $r.State = 'FAIL'; $r.Err = 'LAUNCH-FAIL ' + $_.Exception.Message; return $r
    }
    if ($p.WaitForExit($timeoutSec * 1000)) {
        $sw.Stop()
        try { $r.Exit = $p.ExitCode } catch { $r.Exit = -1 }
        # -Encoding UTF8 不能省：dart/flutter 按 UTF-8 输出，Get-Content 默认按 GBK(936) 解码，
        # 中文系统上 OS 名/版本号里的非 ASCII 会被啃成 '?'。
        try { $r.Out = (Get-Content -LiteralPath $o -Raw -Encoding UTF8 -ErrorAction SilentlyContinue) } catch { }
        try { $r.Err = (Get-Content -LiteralPath $e -Raw -Encoding UTF8 -ErrorAction SilentlyContinue) } catch { }
        if ($null -eq $r.Out) { $r.Out = '' }
        if ($null -eq $r.Err) { $r.Err = '' }
        # dart --version 写的是 stderr，flutter --version 写的是 stdout，所以两个都看
        $blob = $r.Out + "`n" + $r.Err
        if ([string]::IsNullOrEmpty($Expect)) {
            if ($r.Exit -eq 0) { $r.State = 'OK' } else { $r.State = 'FAIL' }
        } elseif ($blob -match $Expect) {
            $r.State = 'OK'
        } else {
            $r.State = 'FAIL'
        }
    } else {
        $r.State = 'TIMEOUT'
        $r.Exit = -1
        # 用 Stop-Process 而不是 taskkill：不额外起进程，直接走内核终止，更快更可控。
        # 再补一刀扫掉可能残留的 dart —— dart 卡在 WMI 时未必报告真实退出。
        try { Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue } catch { }
        Get-Process dart,dartaotruntime -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    }
    $r.Ms = $sw.ElapsedMilliseconds
    try { $r.Out = (Get-Content -LiteralPath $o -Raw -Encoding UTF8 -ErrorAction SilentlyContinue) } catch { }
    try { $r.Err = (Get-Content -LiteralPath $e -Raw -Encoding UTF8 -ErrorAction SilentlyContinue) } catch { }
    if ($null -eq $r.Out) { $r.Out = '' }
    if ($null -eq $r.Err) { $r.Err = '' }
    return $r
}

function Describe($r) {
    Log ("  [" + $r.Name + "] state=" + $r.State + " exit=" + $r.Exit + " ms=" + $r.Ms +
        " out=" + $r.Out.Length + "B err=" + $r.Err.Length + "B")
    if ($r.Out) { Log ("    stdout: " + (FirstLine $r.Out)) }
    if ($r.Err) { Log ("    stderr: " + (FirstLine $r.Err)) }
}

try {
    Log ("=== toolchain probe " + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss') + " ===")
    Log ("PID=" + $PID + " user=" + $env:USERNAME + " cwd=" + (Get-Location).Path)

    if ([string]::IsNullOrWhiteSpace($FlutterRoot)) { $FlutterRoot = $env:FLUTTER_HOME }
    if ([string]::IsNullOrWhiteSpace($FlutterRoot) -or -not (Test-Path -LiteralPath $FlutterRoot)) {
        $cmd = Get-Command flutter -ErrorAction SilentlyContinue
        if ($cmd) { $FlutterRoot = [IO.Path]::GetDirectoryName([IO.Path]::GetDirectoryName($cmd.Source)) }
    }

    # Join-Path 不接受空串 —— 根目录解析不出来时必须在这里收口，
    # 否则会抛 "Cannot bind argument to parameter 'Path' because it is an empty string"，
    # 被下面的 catch 吞成一句没头没脑的 "SKIP: 探测脚本异常"。
    if ([string]::IsNullOrWhiteSpace($FlutterRoot)) {
        Log 'FATAL: 无法定位 Flutter 根目录（FLUTTER_HOME 未设置且 flutter 不在 PATH）'
        Save-Log
        Write-Output 'SKIP: 无法定位 Flutter 根目录, 请传 -FlutterRoot 或设置 FLUTTER_HOME'
        exit 4
    }

    $flutterBat = Join-Path $FlutterRoot 'bin\flutter.bat'
    $dartExe = Join-Path $FlutterRoot 'bin\cache\dart-sdk\bin\dart.exe'
    Log ("FLUTTER_ROOT=" + $FlutterRoot)
    Log ("flutter.bat=" + $flutterBat + " exists=" + (Test-Path -LiteralPath $flutterBat))
    Log ("dart.exe=" + $dartExe + " exists=" + (Test-Path -LiteralPath $dartExe))

    if (-not (Test-Path -LiteralPath $flutterBat)) {
        Log 'FATAL: flutter.bat 不存在'
        Save-Log
        Write-Output ("SKIP: 未找到 flutter.bat 路径 " + (Sanitize $flutterBat))
        exit 4
    }

    # ---- 环境快照：关键文件 / 锁文件 / 残留进程 ----
    foreach ($f in @(
            (Join-Path $FlutterRoot 'bin\cache\flutter_tools.snapshot'),
            (Join-Path $FlutterRoot 'bin\cache\flutter_tools.stamp'),
            (Join-Path $FlutterRoot 'bin\cache\flutter.bat.lock'),
            (Join-Path $FlutterRoot 'bin\cache\lockfile'),
            $dartExe)) {
        if (Test-Path -LiteralPath $f) {
            $i = Get-Item -LiteralPath $f
            Log ("FILE " + $i.Length + "B  " + $i.LastWriteTime.ToString('yyyy-MM-dd HH:mm:ss') + "  " + $i.FullName)
            try {
                $fs = [IO.File]::Open($f, 'Open', 'ReadWrite', 'None'); $fs.Close()
                Log '      exclusive-open=free'
            } catch { Log ("      exclusive-open=BUSY  " + $_.Exception.Message) }
        } else {
            Log ("MISSING " + $f)
        }
    }
    $stale = @(Get-Process -Name dart,dartaotruntime -ErrorAction SilentlyContinue)
    if ($stale.Count -gt 0) {
        Log ("WARN 探测前已有 " + $stale.Count + " 个 dart 进程: " +
            (($stale | ForEach-Object { $_.Id.ToString() + '@' + $_.StartTime.ToString('HH:mm:ss') }) -join ', '))
    } else {
        Log 'OK 探测前没有残留 dart 进程'
    }

    # ---- 1) Dart VM 本体 ----
    $r1 = Invoke-Probe 'dartversion' $dartExe @('--version') $DartTimeoutSec $FlutterRoot -Expect 'Dart SDK version'
    Describe $r1
    # dart --version 是写到 stderr 的，stdout 拿不到东西，两个都试
    $dartVer = if ($r1.Out) { FirstLine $r1.Out } else { FirstLine $r1.Err }

    if ($r1.State -ne 'OK') {
        Log 'FATAL: dart --version 都不能正常返回'
        Save-Log
        $m = if ($r1.State -eq 'TIMEOUT') { "dart --version 超过 $DartTimeoutSec 秒未返回" } else { "dart --version 失败, 退出码 " + $r1.Exit }
        Write-Output ("ERROR: " + (Sanitize $m) + ". Dart SDK 或 VM 层异常, 见 build\toolchain_probe.log")
        exit 2
    }

    # ---- 2) Windows 上 Dart 读 OS 版本走的是 WMI（无超时）----
    # 这是最有价值的一条：winmgmt 服务 RUNNING 但不回 Win32_OperatingSystem 时，
    # flutter.bat 每次启动都卡在这里，表现为"构建卡在 pub get、零输出、日志 0 字节"。
    # 单独测它，能把结论在 WmiTimeoutSec 秒内定死，不用等 FlutterTimeoutSec 那么久。
    $osver = Join-Path (Get-Location).Path 'build\.probe_osver.dart'
    Set-Content -LiteralPath $osver -Encoding ASCII -Value @'
import 'dart:io';
void main() {
  print('OSVER=' + Platform.operatingSystemVersion);
  print('OSVER_OK');
}
'@
    $rW = Invoke-Probe 'osversion' $dartExe @($osver) $WmiTimeoutSec $FlutterRoot -Expect 'OSVER_OK'
    Describe $rW
    Remove-Item -LiteralPath $osver -Force -ErrorAction SilentlyContinue

    if ($rW.State -eq 'TIMEOUT') {
        Log ('FATAL: Platform.operatingSystemVersion 超过 ' + $WmiTimeoutSec + ' 秒未返回 → WMI 挂死')
        Save-Log
        Write-Output ("HANG: WMI 无响应, Platform.operatingSystemVersion 超过 " + $WmiTimeoutSec + " 秒不返回. 所有 flutter 命令都会静默挂死. 需重启机器或重建 WMI 仓库, 见 build\toolchain_probe.log")
        exit 5
    }
    if ($rW.State -ne 'OK' -or $rW.Out -notmatch 'OSVER_OK') {
        Log 'FATAL: OS 版本探针没拿到结果'
        Save-Log
        Write-Output ("ERROR: OS 版本探针异常, dart 连自己的 OS 版本都读不到. 见 build\toolchain_probe.log")
        exit 5
    }

    # ---- 3) VM 能否编译/执行代码（临时脚本） ----
    $hello = Join-Path (Get-Location).Path 'build\.probe_hello.dart'
    Set-Content -LiteralPath $hello -Value "void main() { print('PROBE_OK'); }" -Encoding UTF8
    $r2 = Invoke-Probe 'dartscript' $dartExe @($hello) $DartTimeoutSec $FlutterRoot -Expect 'PROBE_OK'
    Describe $r2
    Remove-Item -LiteralPath $hello -Force -ErrorAction SilentlyContinue

    if ($r2.State -ne 'OK' -or $r2.Out -notmatch 'PROBE_OK') {
        Log 'FATAL: dart 能输出版本号但无法执行脚本'
        Save-Log
        Write-Output ("ERROR: dart 能输出版本号但无法执行脚本. VM 执行路径异常, 见 build\toolchain_probe.log")
        exit 2
    }

    # ---- 4) flutter tool（加载 flutter_tools.snapshot） ----
    $flutterCmd = '"' + $flutterBat + '" --version'
    $r3 = Invoke-Probe 'flutterversion' $env:ComSpec @('/c', $flutterCmd) $FlutterTimeoutSec $FlutterRoot -Expect 'Flutter \d'
    Describe $r3

    if ($r3.State -eq 'TIMEOUT' -and [string]::IsNullOrWhiteSpace($r3.Out) -and [string]::IsNullOrWhiteSpace($r3.Err)) {
        Log 'FATAL: flutter --version 超时且零输出 → 卡死在 flutter tool 快照加载阶段'
        Save-Log
        Write-Output ("HANG: flutter --version 超过 " + $FlutterTimeoutSec + " 秒零输出. dart 能跑脚本, 但加载 flutter tool 快照时被拦死, 见 build\toolchain_probe.log")
        exit 3
    }
    if ($r3.State -ne 'OK') {
        Save-Log
        $m = if ($r3.State -eq 'TIMEOUT') { "flutter --version 超时" } else { "flutter --version 失败, 退出码 " + $r3.Exit }
        Write-Output ("HANG: " + (Sanitize $m) + ". 见 build\toolchain_probe.log")
        exit 3
    }

    Save-Log
    Write-Output ("OK: flutter=" + (Sanitize (FirstLine $r3.Out)) + " dart=" + (Sanitize $dartVer))
    exit 0
}
catch {
    Log ("EXCEPTION: " + $_.Exception.Message)
    Save-Log
    Write-Output ("SKIP: 探测脚本异常 " + (Sanitize $_.Exception.Message))
    exit 1
}
