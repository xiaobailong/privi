# =============================================================================
#  build_wmi_guard.ps1 - WMI 硬超时守卫（由 build.bat 的 :checkenv 调用）
#
#  WHY THIS FILE EXISTS
#  Windows 上 Dart 是通过 COM/WMI 查平台信息的：
#      Platform.operatingSystemVersion  ->  Win32_OperatingSystem
#  dart sdk 里这条调用没有超时。当 winmgmt 服务"看起来在跑"（services.msc 里
#  状态 RUNNING）但实际不回 Win32_OperatingSystem 请求时：
#      * dart.exe 静默阻塞，CPU 0%，不输出任何东西
#      * flutter.bat 一启动就读这个属性 -> 每条 flutter 命令都永远不返回
#      * 表现就是"构建卡在 [1/3] flutter pub get，日志 0 字节，永远不动"
#   实测症状：build\pub_get_codegen.log 0 字节、dart.exe 长时间存在但 CPU 不涨。
#
#  这个守卫用 dart 自己跑一行 Platform.operatingSystemVersion，硬超时 TimeoutSec 秒。
#  超时 → 退出码 5，build.bat 立刻报"WMI 无响应"，不用再等 5 分钟看门狗。
#
#  USAGE
#    powershell -NoProfile -ExecutionPolicy Bypass -File build_wmi_guard.ps1
#    powershell -NoProfile -ExecutionPolicy Bypass -File build_wmi_guard.ps1 -TimeoutSec 5
#
#  OUTPUT (stdout, 单行, 已 Sanitize 成纯 ASCII, 可安全被 cmd 的 for /f 抓取)
#    OK: WMI 正常 (operatingSystemVersion 在 N 秒内返回)
#    HANG: WMI 无响应 ...
#    ERROR: ...
#    SKIP: 无法定位 dart.exe ...
#
#  EXIT CODE
#    0 = 正常        5 = WMI 挂死        4 = 找不到 dart.exe
# =============================================================================
param(
    # 定位 Flutter 根目录（不传则用 FLUTTER_HOME，再退回 PATH 里的 flutter）
    [string]$FlutterRoot = '',

    # Platform.operatingSystemVersion 最长容忍秒数
    [int]$TimeoutSec = 15
)

$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [Text.Encoding]::UTF8

# cmd 端会用 echo/if 处理这一行，必须剔除 cmd 特殊字符
function Sanitize([string]$t) {
    if ([string]::IsNullOrEmpty($t)) { return '' }
    $t = $t -replace '[&|<>()^!%"]', ' '
    $t = $t -replace '[^\x20-\x7E]', ' '
    $t = $t -replace '\s+', ' '
    return $t.Trim()
}

function Guard-Exit([int]$code, [string]$msg) {
    Write-Output (Sanitize $msg)
    exit $code
}

try {
    if ($TimeoutSec -lt 1) { $TimeoutSec = 1 }

    if ([string]::IsNullOrWhiteSpace($FlutterRoot)) { $FlutterRoot = $env:FLUTTER_HOME }
    if ([string]::IsNullOrWhiteSpace($FlutterRoot) -or -not (Test-Path -LiteralPath $FlutterRoot)) {
        $cmd = Get-Command flutter -ErrorAction SilentlyContinue
        if ($cmd) { $FlutterRoot = [IO.Path]::GetDirectoryName([IO.Path]::GetDirectoryName($cmd.Source)) }
    }
    if ([string]::IsNullOrWhiteSpace($FlutterRoot)) {
        Guard-Exit 4 'SKIP: 无法定位 Flutter 根目录, 请传 -FlutterRoot 或设置 FLUTTER_HOME'
    }

    $dartExe = Join-Path $FlutterRoot 'bin\cache\dart-sdk\bin\dart.exe'
    if (-not (Test-Path -LiteralPath $dartExe)) {
        Guard-Exit 4 ('SKIP: 未找到 dart.exe ' + $dartExe)
    }

    # 临时脚本放 build\ 下，避免污染项目根目录
    $dir = Join-Path (Get-Location).Path 'build'
    if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    $script = Join-Path $dir '.wmi_guard.dart'
    Set-Content -LiteralPath $script -Encoding ASCII -Value @'
import 'dart:io';
void main() {
  print('OSVER=' + Platform.operatingSystemVersion);
}
'@

    $out = Join-Path $env:TEMP 'wmi_guard.out'
    $err = Join-Path $env:TEMP 'wmi_guard.err'
    Remove-Item -LiteralPath $out, $err -Force -ErrorAction SilentlyContinue

    $sw = [Diagnostics.Stopwatch]::StartNew()
    # 用 dart.exe 直接跑脚本：绕过 flutter.bat / cmd 包装层，
    # 这样"到底是 WMI 卡住还是 flutter 包装层卡住"不会被混在一起。
    $p = Start-Process -FilePath $dartExe -ArgumentList @($script) -PassThru -NoNewWindow `
        -WorkingDirectory $FlutterRoot -RedirectStandardOutput $out -RedirectStandardError $err

    $ok = $p.WaitForExit($TimeoutSec * 1000)
    $sw.Stop()
    $ms = $sw.ElapsedMilliseconds

    if (-not $ok) {
        # Stop-Process 直接走内核终止，不依赖 taskkill.exe。
        # 顺带清掉可能的残留 dart：dart 被 WMI 卡住时 WaitForExit 未必能拿到真实退出。
        try { Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue } catch { }
        Get-Process dart,dartaotruntime -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath $script -Force -ErrorAction SilentlyContinue
        Guard-Exit 5 ('HANG: WMI 无响应, Platform.operatingSystemVersion 超过 ' + $TimeoutSec +
            ' 秒不返回. 所有 flutter 命令都会静默挂死. 请重启机器 (或 winmgmt /resetrepository) 后重试')
    }

    $o = ''
    # 必须 -Encoding UTF8：dart 按 UTF-8 输出（本机是中文系统，OS 名里有"专业版"），
    # Get-Content 默认按 GBK(936) 解码，非法字节会被替换成 '?'，OS 名就被啃坏了。
    try { $o = [string](Get-Content -LiteralPath $out -Raw -Encoding UTF8 -ErrorAction SilentlyContinue) } catch { }
    $e = ''
    try { $e = [string](Get-Content -LiteralPath $err -Raw -Encoding UTF8 -ErrorAction SilentlyContinue) } catch { }
    Remove-Item -LiteralPath $script -Force -ErrorAction SilentlyContinue

    if ($o -notmatch 'OSVER=') {
        $why = if ($e) { $e } else { '无输出' }
        Guard-Exit 4 ('ERROR: dart 跑不动 Platform.operatingSystemVersion, ' + $why)
    }

    Guard-Exit 0 ('OK: WMI 正常 (' + $ms + 'ms) ' + (($o -split "`r?`n")[0]))
}
catch {
    Guard-Exit 4 ('ERROR: WMI 守卫异常 ' + $_.Exception.Message)
}
