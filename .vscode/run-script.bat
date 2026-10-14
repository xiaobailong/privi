@echo off
setlocal enabledelayedexpansion

set "FILE=%~1"
set "EXT=%~x1"

if /i "%EXT%"==".sh" (
    for /f "delims=" %%i in ('wsl wslpath "%FILE%"') do set "WSL_FILE=%%i"
    for /f "delims=" %%i in ('wsl wslpath "%~dp1."') do set "WSL_DIR=%%i"
    wsl bash -c "cd \"!WSL_DIR!\" && bash \"!WSL_FILE!\""
    exit /b %ERRORLEVEL%
)

if /i "%EXT%"==".bat" (
    chcp 65001 >nul 2>&1
    call "%FILE%"
    exit /b %ERRORLEVEL%
)

if /i "%EXT%"==".cmd" (
    chcp 65001 >nul 2>&1
    call "%FILE%"
    exit /b %ERRORLEVEL%
)

if /i "%EXT%"==".ps1" (
    chcp 65001 >nul
    set "TMP_PS1=%TEMP%\runps_%RANDOM%.ps1"
    set "PS1_SRC=%FILE%"
    set "PS1_DST=!TMP_PS1!"
    powershell.exe -NoProfile -Command "[IO.File]::WriteAllText($env:PS1_DST, [IO.File]::ReadAllText($env:PS1_SRC, [Text.Encoding]::UTF8), (New-Object System.Text.UTF8Encoding($true)))"
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File "!TMP_PS1!"
    set "PS_EXIT=!ERRORLEVEL!"
    del "!TMP_PS1!" 2>nul
    exit /b !PS_EXIT!
)

if /i "%EXT%"==".vbs" (
    cscript //nologo "%FILE%"
    exit /b %ERRORLEVEL%
)

exit /b 0