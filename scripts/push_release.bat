@echo off
chcp 65001 > nul 2>&1
setlocal enabledelayedexpansion

title Privi Release Push

set "GH_EXE="

cd /d "%~dp0.."
if %ERRORLEVEL% neq 0 (
    set "ERR_MSG=无法切换到项目目录: %~dp0.."
    goto :die
)

REM ---- 读取版本号 ----
set "NEW_VER="
if not exist "pubspec.yaml" (
    set "ERR_MSG=未找到 pubspec.yaml，无法确定版本号"
    goto :die
)
for /f "tokens=2 delims=: " %%v in ('findstr /c:"version: " pubspec.yaml') do set "NEW_VER=%%v"
if not defined NEW_VER (
    set "ERR_MSG=无法从 pubspec.yaml 解析 version 行"
    goto :die
)
echo 当前版本: !NEW_VER!

REM ---- 检查 APK ----
set "APK_DEST=privi-!NEW_VER!.apk"
if not exist "!APK_DEST!" goto :no_apk
for %%f in ("!APK_DEST!") do set "APK_SIZE=%%~zf"
echo APK: !APK_DEST! ^(!APK_SIZE! bytes^)
goto :resolve_gh

:no_apk
echo [错误] 未找到 !APK_DEST!
echo        根目录现有 APK:
dir /b "privi-*.apk" 2>nul
echo.
set "ERR_MSG=请先完成构建 (build.bat) 再推送"
goto :die

REM ---- 定位 gh CLI ----
:resolve_gh
if defined GH_EXE if exist "!GH_EXE!" goto :gh_found
set "GH_EXE="
for /f "delims=" %%g in ('where gh 2^>nul') do if not defined GH_EXE set "GH_EXE=%%g"
if not defined GH_EXE if exist "%ProgramFiles%\GitHub CLI\gh.exe" set "GH_EXE=%ProgramFiles%\GitHub CLI\gh.exe"
if not defined GH_EXE if exist "%ProgramFiles(x86)%\GitHub CLI\gh.exe" set "GH_EXE=%ProgramFiles(x86)%\GitHub CLI\gh.exe"
if not defined GH_EXE if exist "%LOCALAPPDATA%\Programs\GitHub CLI\gh.exe" set "GH_EXE=%LOCALAPPDATA%\Programs\GitHub CLI\gh.exe"
if not defined GH_EXE if exist "%USERPROFILE%\scoop\shims\gh.exe" set "GH_EXE=%USERPROFILE%\scoop\shims\gh.exe"
if defined GH_EXE goto :gh_found
set "ERR_MSG=未找到 gh CLI。安装: winget install --id GitHub.cli"
goto :die

:gh_found
echo gh: !GH_EXE!

REM ---- 检查 gh 登录状态（写入临时文件，避免管道/重定向干扰 exit code） ----
set "GH_AUTH_FILE=%TEMP%\privi_gh_auth.txt"
"%GH_EXE%" auth status > "%GH_AUTH_FILE%" 2>&1
set "GH_AUTH_RC=!ERRORLEVEL!"
set "GH_LOGGED_IN=0"
set "GH_HAS_REPO_SCOPE=0"

if !GH_AUTH_RC! equ 0 set "GH_LOGGED_IN=1"
REM 即使 exit code 非 0，也可能只是 stderr 有输出；检查文件内容确认登录状态
for /f "tokens=*" %%l in ('findstr /i "Logged.in" "%GH_AUTH_FILE%" 2^>nul') do set "GH_LOGGED_IN=1"

if "!GH_LOGGED_IN!"=="0" (
    del "%GH_AUTH_FILE%" 2>nul
    set "ERR_MSG=gh 未登录。请执行: gh auth login"
    goto :die
)
echo        gh 已登录

REM ---- 检查 token scope ----
for /f "tokens=*" %%l in ('findstr /i "Token.scopes" "%GH_AUTH_FILE%" 2^>nul') do set "TOKEN_LINE=%%l"
if defined TOKEN_LINE (
    echo "!TOKEN_LINE!" | findstr /i "repo" >nul 2>&1
    if !ERRORLEVEL! equ 0 set "GH_HAS_REPO_SCOPE=1"
)
del "%GH_AUTH_FILE%" 2>nul
set "GH_AUTH_FILE="

if "!GH_HAS_REPO_SCOPE!"=="0" (
    set "ERR_MSG=gh token 缺少 repo scope。授权: gh auth refresh -h github.com -s repo"
    goto :die
)
echo        token 包含 repo scope

REM ---- 解析仓库 owner/repo ----
set "RELEASE_SLUG="
for /f "delims=" %%u in ('git config --get remote.origin.url 2^>nul') do set "REMOTE_URL=%%u"
if not defined REMOTE_URL (
    set "ERR_MSG=无 remote.origin，无法确定目标仓库"
    goto :die
)
set "REMOTE_TAIL=!REMOTE_URL:*github.com:=!"
if "!REMOTE_TAIL!"=="!REMOTE_URL!" set "REMOTE_TAIL=!REMOTE_URL:*github.com/=!"
set "REMOTE_TAIL=!REMOTE_TAIL:.git=!"
for /f "tokens=1,2 delims=/" %%a in ("!REMOTE_TAIL!") do if not "%%b"=="" set "RELEASE_SLUG=%%a/%%b"
if not defined RELEASE_SLUG (
    set "ERR_MSG=无法解析 remote.origin 为 GitHub owner/repo"
    goto :die
)
echo 仓库: !RELEASE_SLUG!
set "REL_REPO_ARG=--repo !RELEASE_SLUG!"

REM ---- 当前 HEAD 信息 ----
set "GIT_SHA="
set "GIT_SHA_SHORT="
set "GIT_DESC="
set "GIT_BRANCH="
for /f "delims=" %%c in ('git rev-parse HEAD 2^>nul') do set "GIT_SHA=%%c"
for /f "delims=" %%c in ('git rev-parse --short HEAD 2^>nul') do set "GIT_SHA_SHORT=%%c"
for /f "delims=" %%c in ('git log -1 --oneline 2^>nul') do set "GIT_DESC=%%c"
for /f "delims=" %%c in ('git rev-parse --abbrev-ref HEAD 2^>nul') do set "GIT_BRANCH=%%c"
if not defined GIT_SHA (
    set "ERR_MSG=无 git 提交记录"
    goto :die
)
echo 分支: !GIT_BRANCH!
echo 提交: !GIT_DESC!

if /i not "!GIT_BRANCH!"=="main" (
    set "ERR_MSG=Release 仅允许从 main 分支发布，当前: !GIT_BRANCH!"
    goto :die
)

REM ---- 检查是否已推送过（Release 存在 且 APK 资产已存在） ----
set "RELEASE_TAG=v!NEW_VER!"
set "ALREADY_PUBLISHED=0"
"%GH_EXE%" release view "!RELEASE_TAG!" !REL_REPO_ARG! >nul 2>&1
if !ERRORLEVEL! equ 0 (
    for /f "delims=" %%a in ('"%GH_EXE%" release view "!RELEASE_TAG!" --json assets !REL_REPO_ARG! 2^>nul ^| findstr /c:"\"name\":\"!APK_DEST!\""') do set "ASSET_MATCH=%%a"
    if defined ASSET_MATCH set "ALREADY_PUBLISHED=1"
)
if "!ALREADY_PUBLISHED!"=="1" (
    echo.
    echo ============================================
    echo  [跳过] Release !RELEASE_TAG! 已推送成功
    echo        APK !APK_DEST! 已存在于该 Release
    echo        页面: https://github.com/!RELEASE_SLUG!/releases/tag/!RELEASE_TAG!
    echo ============================================
    goto :end_ok
)

REM ---- SHA-256 ----
echo.
echo 计算 SHA-256...
set "APK_SHA="
if exist "%~dp0tools\build_hash.ps1" (
    for /f "usebackq delims=" %%h in (`powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\build_hash.ps1" -Kind file -Path "!APK_DEST!" 2^>nul`) do set "APK_SHA=%%h"
)
if not defined APK_SHA (
    for /f "usebackq delims=" %%h in (`powershell -NoProfile -Command "(Get-FileHash -Algorithm SHA256 '!APK_DEST!').Hash.ToLower()"`) do set "APK_SHA=%%h"
)
if not defined APK_SHA (
    set "ERR_MSG=计算 SHA-256 失败"
    goto :die
)
> "!APK_DEST!.sha256" echo !APK_SHA!
echo SHA-256: !APK_SHA!

REM ---- Release 说明文件 ----
set "RELEASE_TITLE=密册 v!NEW_VER!"
set "NOTES_FILE=build\release_notes_!NEW_VER!.md"

if exist "%~dp0..\release_notes.md" (
    copy /y "%~dp0..\release_notes.md" "!NOTES_FILE!" >nul 2>&1
) else (
    > "!NOTES_FILE!" echo # 密册 v!NEW_VER!
)

set "GIT_DESC=!GIT_DESC:<=!"
set "GIT_DESC=!GIT_DESC:>=!"
set "GIT_DESC=!GIT_DESC:&=!"
set "GIT_DESC=!GIT_DESC:|=!"

set "SIGN_NOTE=release key"
if not exist "android\key.properties" set "SIGN_NOTE=debug key"

echo.>> "!NOTES_FILE!"
echo --->> "!NOTES_FILE!"
echo.>> "!NOTES_FILE!"
echo - version: !NEW_VER!>> "!NOTES_FILE!"
echo - build time: %DATE% %TIME%>> "!NOTES_FILE!"
echo - commit: !GIT_DESC!>> "!NOTES_FILE!"
echo - branch: !GIT_BRANCH!>> "!NOTES_FILE!"
set "PRODUCT_LINE=!APK_DEST! (!APK_SIZE! bytes)"
echo - artifact: !PRODUCT_LINE!>> "!NOTES_FILE!"
echo - SHA-256: !APK_SHA!>> "!NOTES_FILE!"
echo - signature: !SIGN_NOTE!>> "!NOTES_FILE!"
echo.>> "!NOTES_FILE!"
echo install: download !APK_DEST! and sideload, requires Android 8.0+>> "!NOTES_FILE!"
echo verify: the !APK_DEST!.sha256 file in this release provides the APK SHA-256>> "!NOTES_FILE!"
set "PS_LINE=verify command (PowerShell): Get-FileHash -Algorithm SHA256 .\!APK_DEST!"
echo !PS_LINE!>> "!NOTES_FILE!"

REM ---- 推送 Release ----
echo.
echo ============================================
echo  推送 Release
echo ============================================

set "REL_EXISTS=0"
"%GH_EXE%" release view "!RELEASE_TAG!" !REL_REPO_ARG! >nul 2>&1
if !ERRORLEVEL! equ 0 set "REL_EXISTS=1"

if "!REL_EXISTS!"=="1" goto :update_release

REM ---- 新建 Release ----
echo creating Release !RELEASE_TAG! (tag: !GIT_SHA_SHORT!)...
echo checking if commit !GIT_SHA_SHORT! is on origin...
set "COMMIT_ON_REMOTE=0"
git ls-remote origin "!GIT_SHA!" >nul 2>&1
if !ERRORLEVEL! equ 0 set "COMMIT_ON_REMOTE=1"
if "!COMMIT_ON_REMOTE!"=="0" (
    set "ERR_MSG=commit !GIT_SHA_SHORT! not on origin. Push first: git push origin !GIT_BRANCH!"
    goto :die
)
echo confirmed, creating Release...
"%GH_EXE%" release create "!RELEASE_TAG!" "!APK_DEST!" "!APK_DEST!.sha256" --title "!RELEASE_TITLE!" --notes-file "!NOTES_FILE!" --latest --target !GIT_SHA! !REL_REPO_ARG!
set "REL_EXIT=!ERRORLEVEL!"
goto :check_rel_exit

:update_release
echo 已存在 !RELEASE_TAG!, updating APK and notes...
"%GH_EXE%" release upload "!RELEASE_TAG!" "!APK_DEST!" "!APK_DEST!.sha256" --clobber !REL_REPO_ARG!
set "REL_EXIT=!ERRORLEVEL!"
if "!REL_EXIT!"=="0" (
    "%GH_EXE%" release edit "!RELEASE_TAG!" --title "!RELEASE_TITLE!" --notes-file "!NOTES_FILE!" --latest !REL_REPO_ARG!
    set "REL_EXIT=!ERRORLEVEL!"
)
goto :check_rel_exit

:check_rel_exit

if "!REL_EXIT!"=="0" (
    echo.
    echo ============================================
    echo  Release published: !RELEASE_TAG!
    echo        page: https://github.com/!RELEASE_SLUG!/releases/tag/!RELEASE_TAG!
    echo        latest: https://github.com/!RELEASE_SLUG!/releases/latest
    echo ============================================
) else (
    echo.
    echo ============================================
    echo  [FAILED] Release push failed (exit=!REL_EXIT!)
    echo ============================================
    exit /b !REL_EXIT!
)

:end_ok
echo.
echo window will close in 30 seconds, or press any key...
timeout /t 30 > nul
exit /b 0

:die
echo.
echo ============================================
echo  [ERROR] !ERR_MSG!
echo ============================================
echo.
echo window will close in 30 seconds, or press any key...
timeout /t 30 > nul
exit /b 1