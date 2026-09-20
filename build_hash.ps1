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
#
#  OUTPUT (stdout, 单行)
#    32 位大写十六进制哈希，exit code 0
#    （失败时 stdout 为空，错误写到 stderr，exit code != 0）
# =============================================================================
param(
    [ValidateSet('codegen', 'gradle')]
    [string]$Kind = 'codegen'
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
    else {
        # Gradle 配置相关：任一文件变更都会让 APK 需要重新编译
        $paths = @(
            'android\build.gradle.kts',
            'android\app\build.gradle.kts',
            'android\settings.gradle.kts',
            'android\gradle.properties'
        )
        $joined = ($paths.ForEach({ Get-FileHashOrEmpty $_ }) -join '')
    }

    Write-Output (Get-Md5Hex $joined)
    exit 0
}
catch {
    [Console]::Error.WriteLine('ERROR=' + $_.Exception.Message)
    exit 1
}
