# =============================================================================
#  bump_version.ps1 - bump the patch of pubspec.yaml's version (called by build.bat)
#
#  WHY THIS FILE EXISTS
#  On locked-down machines an endpoint policy silently blocks a PowerShell
#  -Command one-liner whose command line contains a regex: powershell.exe exits
#  with code 786 and never touches the file, so build.bat kept bumping its own
#  counter while pubspec.yaml stayed behind - and the built APK ended up with a
#  stale version. The same logic invoked from this script file through -File is
#  not affected, which is why this helper exists.
#
#  VERSION SCHEME (see memory-bank ADR-026)
#    pubspec.yaml holds a plain three-part version - `version: 1.0.59` - with no
#    `+<build>` suffix any more, so every build bumps the last number:
#    1.0.59 -> 1.0.60. The Android versionCode is derived from that version name
#    in android/app/build.gradle.kts (major*10000 + minor*100 + patch).
#
#  USAGE
#    powershell -NoProfile -ExecutionPolicy Bypass -File scripts\bump_version.ps1
#    powershell -NoProfile -ExecutionPolicy Bypass -File scripts\bump_version.ps1 -Path pubspec.yaml
#
#  OUTPUT (stdout, single line)
#    OK=<old>-><new>   file updated, exit code 0
#    ERROR=<reason>    nothing written, exit code != 0
# =============================================================================
param(
    [string]$Path = 'pubspec.yaml'
)

$ErrorActionPreference = 'Stop'

try {
    $full = (Resolve-Path -LiteralPath $Path).Path
    $text = [IO.File]::ReadAllText($full)

    # Touch the version: line only - every other byte stays as it is.
    $found = [regex]::Match($text, '(?m)^[ \t]*version:[^\r\n]*')
    if (-not $found.Success) {
        Write-Output 'ERROR=no-version-line'
        exit 2
    }

    $line = $found.Value
    # A legacy `1.0.30+59` line still matches: the +build suffix is simply dropped
    # and the clean three-part form is written back.
    $m = [regex]::Match($line, '(\d+)\.(\d+)\.(\d+)')
    if (-not $m.Success) {
        Write-Output 'ERROR=version-not-three-part'
        exit 4
    }

    $old = '' + [int]$m.Groups[1].Value + '.' + [int]$m.Groups[2].Value + '.' + [int]$m.Groups[3].Value
    $new = '' + [int]$m.Groups[1].Value + '.' + [int]$m.Groups[2].Value + '.' + ([int]$m.Groups[3].Value + 1)
    $newLine = 'version: ' + $new

    # Never trust the replace: read the version back from the new line.
    $parsed = [regex]::Match($newLine, '^version:[ \t]*(\d+\.\d+\.\d+)\s*$')
    if (-not $parsed.Success -or $parsed.Groups[1].Value -ne $new) {
        Write-Output 'ERROR=version-not-applied'
        exit 3
    }

    if ($newLine -ne $line) {
        $out = $text.Substring(0, $found.Index) + $newLine + $text.Substring($found.Index + $found.Length)
        # UTF8Encoding($true) keeps the UTF-8 BOM that pubspec.yaml already has.
        [IO.File]::WriteAllText($full, $out, (New-Object Text.UTF8Encoding($true)))
    }

    Write-Output ('OK=' + $old + '->' + $new)
    exit 0
}
catch {
    Write-Output ('ERROR=' + $_.Exception.Message)
    exit 1
}
