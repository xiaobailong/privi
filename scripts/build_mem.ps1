# =============================================================================
#  build_mem.ps1 - report memory headroom + reclaim leftover JVMs of this repo
#                  (called by build.bat before `flutter build apk --release`)
#
#  WHY THIS FILE EXISTS
#  The release build runs R8 in full mode (android/app/build.gradle.kts sets
#  isMinifyEnabled = true). The Gradle daemon, the Kotlin compile daemon and the
#  C2 JIT compiling R8 internals allocate a lot of *native* memory (compiler
#  arenas, Metaspace, CodeCache) on top of the Java heap. When the system commit
#  charge (physical RAM + page file) runs out, the JVM cannot malloc even 1.5 MB
#  for Chunk::new and Gradle dies with:
#      "The message received from the daemon indicates that the daemon has disappeared."
#      "JVM crash log found: ... android/hs_err_pid58400.log"
#  That crash log shows the real cause:
#      "Out of Memory Error (arena.cpp:168)"
#      "Native memory allocation (malloc) failed to allocate 1577504 bytes for Chunk::new"
#      "TotalPageFile size 54340M (AvailPageFile size 23M)"
#  Leftover daemons make it worse: the Kotlin compile daemon stays alive for
#  hours holding hundreds of MB (see android/.kotlin/sessions/*.salive). So
#  before compiling we
#      1) kill the JVMs of this toolchain that are still lingering,
#      2) print physical and commit memory headroom, so the next crash can be
#         attributed correctly (machine out of memory vs. too aggressive -Xmx).
#
#  IMPORTANT - this is a locked down Windows box, these calls hang forever here:
#      Get-CimInstance / Get-WmiObject (WMI)  -> hangs, no output at all
#      jps / jcmd (Java attach API)           -> hangs
#      Get-Counter (PDH performance counters) -> works once, then hangs
#  Therefore: memory numbers come from kernel32!GlobalMemoryStatusEx (P/Invoke,
#  ~1 s, matches the TotalPageFile/AvailPageFile figures in hs_err logs) and the
#  JVM list comes from Get-Process + executable path. Never WMI, never attach.
#
#  WHY MATCHING ON THE EXECUTABLE PATH IS SAFE
#  Only java.exe / javaw.exe started from %JAVA_HOME%\bin (the JDK build.bat puts
#  on PATH) are candidates. VS Code's redhat.java JRE, Android Studio's JBR and
#  any system JVM live elsewhere, so they are never touched. Processes younger
#  than -MinAgeSeconds are skipped as well, so a build started in another window
#  is not killed by accident. With an empty -JavaHome nothing is killed at all.
#
#  USAGE
#    powershell -NoProfile -ExecutionPolicy Bypass -File scripts\build_mem.ps1 -JavaHome "D:\...\jdk-21"
#    powershell -NoProfile -ExecutionPolicy Bypass -File scripts\build_mem.ps1 -JavaHome "D:\...\jdk-21" -StopDaemons
#
#  OUTPUT (stdout; the last line is machine readable, callers parse it)
#    MEM OK FreePhysMB=... FreeCommitMB=... CommitLimitMB=... Daemons=... Killed=...
#    MEM LOW_COMMIT ...  warning line when free commit charge is nearly gone
#    MEM WARN=<reason>   + exit code 1 on a hard error (callers treat it as non fatal)
#  The full report is appended to build\mem_report.log (<project>\build by default).
# =============================================================================
param(
    [string]$JavaHome = '',
    [string]$ProjectRoot = '',
    [switch]$StopDaemons,
    [int]$MinAgeSeconds = 120,
    [int]$MinFreeCommitMB = 1500,
    [string]$LogFile = ''
)

# MEMORYSTATUSEX via kernel32: ullTotalPageFile / ullAvailPageFile are exactly
# the "commit limit / available commit" pair printed as TotalPageFile /
# AvailPageFile in the JVM crash logs.
function Initialize-MemoryApi {
    if ('PriviMemoryStatus' -as [type]) { return }
    Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class PriviMemoryStatus {
    [StructLayout(LayoutKind.Sequential)]
    public struct MEMORYSTATUSEX {
        public uint dwLength;
        public uint dwMemoryLoad;
        public ulong ullTotalPhys;
        public ulong ullAvailPhys;
        public ulong ullTotalPageFile;
        public ulong ullAvailPageFile;
        public ulong ullTotalVirtual;
        public ulong ullAvailVirtual;
        public ulong ullAvailExtendedVirtual;
    }
    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern bool GlobalMemoryStatusEx(ref MEMORYSTATUSEX lpBuffer);
    public static MEMORYSTATUSEX Get() {
        MEMORYSTATUSEX st = new MEMORYSTATUSEX();
        st.dwLength = (uint)Marshal.SizeOf(typeof(MEMORYSTATUSEX));
        if (!GlobalMemoryStatusEx(ref st)) {
            throw new System.ComponentModel.Win32Exception(Marshal.GetLastWin32Error());
        }
        return st;
    }
}
'@ -ErrorAction Stop
}

function Get-MemorySnapshot {
    $s = [PriviMemoryStatus]::Get()
    return [pscustomobject]@{
        TotalPhysMB   = [math]::Round($s.ullTotalPhys / 1MB)
        FreePhysMB    = [math]::Round($s.ullAvailPhys / 1MB)
        CommitLimitMB = [math]::Round($s.ullTotalPageFile / 1MB)
        FreeCommitMB  = [math]::Round($s.ullAvailPageFile / 1MB)
    }
}

function Format-MemorySnapshot([string]$Prefix, $Snap) {
    return ('{0} physical free {1} MB / total {2} MB ; commit free {3} MB / limit {4} MB' -f `
        $Prefix, $Snap.FreePhysMB, $Snap.TotalPhysMB, $Snap.FreeCommitMB, $Snap.CommitLimitMB)
}

# Candidates = JVMs launched from this JDK. No JAVA_HOME -> empty list, i.e. the
# script degrades to a pure memory report instead of guessing.
function Get-ToolchainJvms([string]$JavaHome) {
    $list = @()
    if ([string]::IsNullOrWhiteSpace($JavaHome)) { return $list }
    $prefix = ($JavaHome.TrimEnd('\', '/') + '\').ToLowerInvariant()

    foreach ($p in @(Get-Process -Name 'java', 'javaw' -ErrorAction SilentlyContinue)) {
        $exe = $null
        try { $exe = $p.Path } catch { }
        if ([string]::IsNullOrWhiteSpace($exe)) { continue }
        if (-not $exe.ToLowerInvariant().StartsWith($prefix)) { continue }

        $start = $null
        try { $start = $p.StartTime } catch { }
        $ageSec = -1
        if ($null -ne $start) { $ageSec = [int]((Get-Date) - $start).TotalSeconds }

        $list += [pscustomobject]@{
            Id        = $p.Id
            Exe       = $exe
            WSMB      = [math]::Round($p.WorkingSet64 / 1MB)
            CpuSec    = [math]::Round($p.CPU)
            StartTime = $start
            AgeSec    = $ageSec
        }
    }
    return $list
}

$ErrorActionPreference = 'Stop'
$script:Transcript = New-Object System.Collections.ArrayList

function Emit([string]$Line) {
    [void]$script:Transcript.Add($Line)
    Write-Output $Line
}

# ---------------------------------------------------------------------------
#  main
# ---------------------------------------------------------------------------
$exitCode = 0
try {
    Initialize-MemoryApi

    if ([string]::IsNullOrWhiteSpace($JavaHome)) { $JavaHome = $env:JAVA_HOME }
    if ([string]::IsNullOrWhiteSpace($LogFile)) {
        $root = $ProjectRoot
        if ([string]::IsNullOrWhiteSpace($root) -and $PSScriptRoot) { $root = Split-Path -Parent $PSScriptRoot }   # scripts\ -> project root
        if ([string]::IsNullOrWhiteSpace($root)) { $root = (Get-Location).Path }
        $LogFile = Join-Path $root 'build\mem_report.log'
    }

    $homeText = $JavaHome
    if ([string]::IsNullOrWhiteSpace($homeText)) { $homeText = '<not set - nothing will be killed>' }
    Emit ('[memory] java home      : ' + $homeText)

    $before = Get-MemorySnapshot
    Emit (Format-MemorySnapshot '[memory] before reclaim:' $before)

    # @() keeps a single hit an array too - PowerShell unwraps one-element
    # collections on return, which used to print "Daemons=" with no number.
    $jvms = @(Get-ToolchainJvms -JavaHome $JavaHome)
    $killed = 0
    $kept = 0

    if ($jvms.Count -eq 0) {
        Emit '[memory] no java process of this JDK is running (nothing to reclaim)'
    }

    foreach ($j in $jvms) {
        $ageText = 'unknown'
        if ($j.AgeSec -ge 0) { $ageText = [string]$j.AgeSec + 's' }
        $line = ('[memory] jvm pid={0} ws={1} MB cpu={2}s age={3}' -f $j.Id, $j.WSMB, $j.CpuSec, $ageText)

        if (-not $StopDaemons) {
            Emit ($line + ' (report only)')
            continue
        }
        if ($j.AgeSec -lt 0) {
            $kept++
            Emit ($line + ' (age unknown - kept)')
            continue
        }
        if ($j.AgeSec -lt $MinAgeSeconds) {
            $kept++
            Emit ($line + ' (younger than {0}s - kept)' -f $MinAgeSeconds)
            continue
        }
        try {
            Stop-Process -Id $j.Id -Force -ErrorAction Stop
            $killed++
            Emit ($line + ' -> killed')
        }
        catch {
            Emit ($line + ' -> cannot kill: ' + $_.Exception.Message)
        }
    }

    if ($killed -gt 0) {
        # Give Windows a moment to release the commit charge of the killed JVMs.
        Start-Sleep -Seconds 2
    }

    $after = Get-MemorySnapshot
    Emit (Format-MemorySnapshot '[memory] after reclaim :' $after)

    Emit ('MEM OK FreePhysMB={0} FreeCommitMB={1} CommitLimitMB={2} Daemons={3} Killed={4}' -f `
        $after.FreePhysMB, $after.FreeCommitMB, $after.CommitLimitMB, $jvms.Count, $killed)

    if ($kept -gt 0) {
        Emit ('[memory] note: {0} jvm(s) younger than {1}s were kept alive' -f $kept, $MinAgeSeconds)
    }

    if ($after.FreeCommitMB -lt $MinFreeCommitMB) {
        Emit ('MEM LOW_COMMIT FreeCommitMB={0} ThresholdMB={1}' -f $after.FreeCommitMB, $MinFreeCommitMB)
        Emit ('[memory] WARN free commit charge is only {0} MB (threshold {1} MB): R8 minification may exhaust the machine. Close other heavy apps or grow the page file before retrying.' -f $after.FreeCommitMB, $MinFreeCommitMB)
    }
}

catch {
    Emit ('MEM WARN=' + $_.Exception.Message)
    $exitCode = 1
}
finally {
    # Keep a copy of every run next to the build logs: after a JVM crash the
    # hs_err log tells what died, this file tells how much memory was left.
    try {
        $dir = Split-Path -Parent $LogFile
        if ($dir -and -not (Test-Path -LiteralPath $dir)) {
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
        }
        Add-Content -LiteralPath $LogFile -Value ('--- {0} ---' -f (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')) -Encoding UTF8
        Add-Content -LiteralPath $LogFile -Value $script:Transcript -Encoding UTF8
    }
    catch {
        Write-Output ('[memory] WARN cannot write log ' + $LogFile + ': ' + $_.Exception.Message)
    }
}

exit $exitCode
