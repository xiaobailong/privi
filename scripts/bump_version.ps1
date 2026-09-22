# =============================================================================
#  bump_version.ps1 - bump the build number of pubspec.yaml (called by build.bat)
#
#  WHY THIS FILE EXISTS
#  On locked-down machines an endpoint policy silently blocks a PowerShell
#  -Command one-liner whose command line contains the regex (\+)\d+:
#  powershell.exe exits with code 786 and never touches the file, so build.bat
#  kept bumping .BUILD_NUM while pubspec.yaml stayed behind - and the built APK
#  ended up with a stale versionCode. The same regex invoked from this script
#  file through -File is not affected, which is why this helper exists.
#
#  USAGE
#    powershell -NoProfile -ExecutionPolicy Bypass -File scripts\bump_version.ps1 -BuildNumber 34
#    powershell -NoProfile -ExecutionPolicy Bypass -File scripts\bump_version.ps1 -BuildNumber 34 -VersionName 1.0.29
#
#  OUTPUT (stdout, single line)
#    OK=<version>      file updated, exit code 0
#    ERROR=<reason>    nothing written, exit code != 0
# =============================================================================
param(
    [int]$BuildNumber = 0,
    [string]$VersionName = '',
    [string]$Path = 'pubspec.yaml'
)

$ErrorActionPreference = 'Stop'

try {
    if ($BuildNumber -le 0) {
        Write-Output 'ERROR=invalid-build-number'
        exit 4
    }

    $full = (Resolve-Path -LiteralPath $Path).Path
    $text = [IO.File]::ReadAllText($full)

    # Touch the version: line only - every other byte stays as it is.
    $found = [regex]::Match($text, '(?m)^[ \t]*version:[^\r\n]*')
    if (-not $found.Success) {
        Write-Output 'ERROR=no-version-line'
        exit 2
    }

    $line = $found.Value
    if ([string]::IsNullOrWhiteSpace($VersionName)) {
        if ($line -match '\+\d+') {
            $newLine = [regex]::Replace($line, '\+\d+', '+' + $BuildNumber)
        } else {
            $newLine = $line.TrimEnd() + '+' + $BuildNumber
        }
    } else {
        $newLine = 'version: ' + $VersionName + '+' + $BuildNumber
    }

    # Never trust the replace: read the build number back from the new line.
    $parsed = [regex]::Match($newLine, '\+(\d+)\s*$')
    if (-not $parsed.Success -or [int]$parsed.Groups[1].Value -ne $BuildNumber) {
        Write-Output 'ERROR=build-number-not-applied'
        exit 3
    }

    if ($newLine -ne $line) {
        $out = $text.Substring(0, $found.Index) + $newLine + $text.Substring($found.Index + $found.Length)
        # UTF8Encoding($true) keeps the UTF-8 BOM that pubspec.yaml already has.
        [IO.File]::WriteAllText($full, $out, (New-Object Text.UTF8Encoding($true)))
    }

    Write-Output ('OK=' + $newLine.Substring($newLine.IndexOf(':') + 1).Trim())
    exit 0
}
catch {
    Write-Output ('ERROR=' + $_.Exception.Message)
    exit 1
}
