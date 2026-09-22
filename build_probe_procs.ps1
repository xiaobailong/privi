# =============================================================================
#  build_probe_procs.ps1 - 进程/锁文件快照（排查 flutter pub get 卡死用）
#  用法: powershell -NoProfile -ExecutionPolicy Bypass -File build_probe_procs.ps1
#  输出: build\procs_probe.txt
# =============================================================================
param(
    [string]$Out = 'build\procs_probe.txt'
)

$ErrorActionPreference = 'Continue'
$lines = New-Object System.Collections.Generic.List[string]
function Add([string]$t) { $script:lines.Add($t) }

Add ("TIME " + (Get-Date).ToString('yyyy-MM-dd HH:mm:ss'))
Add ''

# ---- 1) 相关进程（名称/pid/父pid/启动时间/窗口标题/cmdline） ----
$names = @('dart', 'dartaotruntime', 'cmd', 'powershell', 'pwsh', 'java', 'javaw', 'gradle', 'flutter')
Add '[PROCESSES]'
foreach ($p in (Get-CimInstance Win32_Process -ErrorAction SilentlyContinue | Sort-Object Name)) {
    if ($names -notcontains ($p.Name -replace '\.exe$', '')) { continue }
    $start = ''
    try { $start = ([Management.ManagementDateTimeConverter]::ToDateTime($p.CreationDate)).ToString('HH:mm:ss') } catch { }
    Add ("pid=" + $p.ProcessId + " ppid=" + $p.ParentProcessId + " " + $p.Name + " start=" + $start + " cmd=" + $p.CommandLine)
}

# ---- 2) flutter SDK 锁文件与缓存文件的独占占用情况 ----
Add ''
Add '[FLUTTER-SDK-FILES]'
$root = 'D:\Tools\DevTools\flutter'
foreach ($f in @(
        (Join-Path $root 'bin\cache\flutter.bat.lock'),
        (Join-Path $root 'bin\cache\lockfile'),
        (Join-Path $root 'bin\cache\flutter_tools.snapshot'),
        (Join-Path $root 'bin\cache\flutter_tools.stamp'),
        (Join-Path $root 'bin\cache\dart-sdk\bin\dart.exe'))) {
    if (Test-Path -LiteralPath $f) {
        $i = Get-Item -LiteralPath $f
        $state = 'free'
        try {
            $fs = [IO.File]::Open($f, 'Open', 'ReadWrite', 'None')
            $fs.Close()
        } catch { $state = 'BUSY ' + $_.Exception.Message }
        Add ($i.Length.ToString() + "B " + $i.LastWriteTime.ToString('yyyy-MM-dd HH:mm:ss') + " exclusive=" + $state + " " + $f)
    } else {
        Add ("MISSING " + $f)
    }
}

# ---- 3) 项目内 pub 相关文件时间戳 ----
Add ''
Add '[PROJECT-FILES]'
foreach ($f in @('.dart_tool\package_config.json', 'pubspec.yaml', '.dart_tool\package_graph.json', '.BUILD_NUM')) {
    $p = Join-Path (Get-Location).Path $f
    if (Test-Path -LiteralPath $p) {
        $i = Get-Item -LiteralPath $p
        Add ($i.Length.ToString() + "B " + $i.LastWriteTime.ToString('yyyy-MM-dd HH:mm:ss') + " " + $f)
    } else {
        Add ("MISSING " + $f)
    }
}

$full = Join-Path (Get-Location).Path $Out
$dir = [IO.Path]::GetDirectoryName($full)
if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
Set-Content -LiteralPath $full -Value $lines -Encoding UTF8
Write-Output ("probe written: " + $full)
