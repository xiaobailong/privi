# =============================================================================
#  build_hash.ps1 - 计算"代码哈希 / Gradle 配置哈希"，供 build.bat 断点续传使用
#
#  WHY THIS FILE EXISTS
#  build.bat 原来用 powershell -Command 一行式算哈希，本机端点安全策略会静默拦截
#  这类命令行（powershell.exe 以退出码 786 退出，什么都不输出），于是
#  HASH_CODE_GEN 永远是空的，断点续传的"代码是否变更"判断全部失效。
#  和使用 bump_version.ps1 的原因一样：同样的正则/管道放进脚本文件、用 -File
#  调用就不受影响。
#
#  USAGE
#    powershell -NoProfile -ExecutionPolicy Bypass -File build_hash.ps1 -Kind codegen
#    powershell -NoProfile -ExecutionPolicy Bypass -File build_hash.ps1 -Kind gradle
#    powershell -NoProfile -ExecutionPolicy Bypass -File build_hash.ps1 -Kind file -Path privi-1.0.29+44.apk
#
#  OUTPUT (stdout, 单行)
#    codegen / gradle : 32 位大写十六进制 MD5，exit code 0
#    file             : 64 位小写十六进制 SHA-256（与上游 Release 的
#                       privi-<版本>.apk.sha256 内容格式一致，sha256sum 风格），exit code 0
#    （失败时 stdout 为空，错误写到 stderr，exit code != 0）
# =============================================================================
param(
    [ValidateSet('codegen', 'gradle', 'file')]
    [string]$Kind = 'codegen',

    # -Kind file 时必填：要计算 SHA-256 的文件路径
    [string]$Path = ''
)

$ErrorActionPreference = 'Stop'

function Get-Md5Hex([string]$Text) {
    if ([string]::IsNullOrEmpty($Text)) { return '' }
    $bytes = [Text.Encoding]::UTF8.GetBytes($Text)
    $md5 = [Security.Cryptography.MD5]::Create().ComputeHash($bytes)
    # 与旧实现保持一致：大写、去掉连字符
    return ([BitConverter]::ToString($md5) -replace '-', '')
}

function Get-FileHashOrEmpty([string]$Path) {
    $item = Get-Item -LiteralPath $Path -ErrorAction SilentlyContinue
    if ($null -eq $item) { return '' }
    return (Get-FileHash -LiteralPath $item.FullName -Algorithm MD5).Hash
}

try {
    $joined = ''

    if ($Kind -eq 'codegen') {
        # 代码生成相关：lib 下所有 dart/yaml + 依赖清单
        $files = @(Get-ChildItem 'lib' -Recurse -File -Include '*.dart', '*.yaml' -ErrorAction SilentlyContinue |
                   Sort-Object FullName)
        $joined = ($files.ForEach({ (Get-FileHash $_.FullName -Algorithm MD5).Hash }) -join '') +
                  (Get-FileHashOrEmpty 'pubspec.yaml') +
                  (Get-FileHashOrEmpty 'pubspec.lock') +
                  (Get-FileHashOrEmpty 'build.yaml')
    }
    elseif ($Kind -eq 'gradle') {
        # Gradle 配置相关：任一文件变更都会让 APK 需要重新编译
        $paths = @(
            'android\build.gradle.kts',
            'android\app\build.gradle.kts',
            'android\settings.gradle.kts',
            'android\gradle.properties'
        )
        $joined = ($paths.ForEach({ Get-FileHashOrEmpty $_ }) -join '')
    }
    else {
        # 单个文件的 SHA-256，供 build.bat 发布 Release 时生成校验和资产
        if ([string]::IsNullOrWhiteSpace($Path)) {
            throw '-Kind file 必须提供 -Path'
        }
        $item = Get-Item -LiteralPath $Path -ErrorAction Stop
        Write-Output ((Get-FileHash -LiteralPath $item.FullName -Algorithm SHA256).Hash.ToLowerInvariant())
        exit 0
    }

    Write-Output (Get-Md5Hex $joined)
    exit 0
}
catch {
    [Console]::Error.WriteLine('ERROR=' + $_.Exception.Message)
    exit 1
}
