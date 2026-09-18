@echo off
chcp 65001 > nul
title Privi Build

REM ============================================
REM  Privi 一键构建脚本
REM  用法: 双击运行     (完整构建 + 递增版本)
REM        build codegen (仅代码生成)
REM        build clean   (清理构建产物)
REM        build fast    (构建但跳过代码生成)
REM ============================================

REM ---- 环境配置（按实际路径修改） ----
set "JAVA_HOME=D:\Tools\DevTools\Java\JDK\jdk-21.0.10-oracle"
set "FLUTTER_HOME=D:\Tools\DevTools\flutter"
set "ANDROID_HOME=D:\Tools\DevTools\Android\Sdk"
set "ANDROID_SDK_ROOT=D:\Tools\DevTools\Android\Sdk"
set "PATH=%JAVA_HOME%\bin;%FLUTTER_HOME%\bin;%ANDROID_HOME%\platform-tools;%PATH%"

REM ---- 切换到项目根目录 ----
cd /d "%~dp0"
if %ERRORLEVEL% neq 0 (
    echo [错误] 无法切换到项目目录
    pause
    exit /b 1
)

REM ---- 确保根路径 build 目录存在 ----
if not exist "build" mkdir "build"

if /i "%~1"=="codegen" goto :codegen
if /i "%~1"=="clean"   goto :clean
if /i "%~1"=="fast"    goto :fast
goto :build

REM ============================================
REM  环境检查
REM ============================================
:checkenv
echo.
echo ============================================
echo  检查构建环境...
echo ============================================

where java >nul 2>&1
if %ERRORLEVEL% neq 0 (
    echo [错误] 未找到 Java。请安装 JDK 17+
    echo        下载地址: https://jdk.java.net/17/
    pause
    exit /b 1
)
for /f "tokens=3" %%v in ('java -version 2^>^&1 ^| findstr /i "version"') do (
    echo        Java: %%v
)

where flutter >nul 2>&1
if %ERRORLEVEL% neq 0 (
    echo [错误] 未找到 Flutter。
    echo        下载地址: https://docs.flutter.dev/get-started/install/windows
    pause
    exit /b 1
)
for /f "tokens=2" %%v in ('flutter --version 2^>^&1 ^| findstr /r "^Flutter"') do (
    echo        Flutter: %%v
)

if not exist "%ANDROID_HOME%" (
    echo [错误] Android SDK 未找到: %ANDROID_HOME%
    echo        下载 Android Studio: https://developer.android.com/studio
    pause
    exit /b 1
)
echo        Android SDK: %ANDROID_HOME%

if not exist "local.properties" (
    echo sdk.dir=%ANDROID_HOME%> "local.properties"
    echo flutter.sdk=%FLUTTER_HOME%>> "local.properties"
    echo        local.properties 已生成
)
goto :eof

REM ============================================
REM  递增版本号（PowerShell 解析 pubspec.yaml）
REM ============================================
:increment_version
echo.
echo [递增版本号]...

for /f "delims=" %%v in ('powershell -NoProfile -Command ^
    "$y = Get-Content pubspec.yaml -Raw; ^
    if ($y -match 'version:\s*(\S+)') { ^
        $v = $Matches[1]; ^
        if ($v -match '^(.+)\+(\d+)$') { ^
            $name = $Matches[1]; $code = [int]$Matches[2] + 1; ^
            $new = \"$name+$code\"; ^
            $y = $y -replace 'version:\s*\S+', \"version: $new\"; ^
            $y ^| Set-Content pubspec.yaml -NoNewline; ^
            Write-Output $new ^
        } else { Write-Output \"PARSE_ERROR\" } ^
    } else { Write-Output \"NOT_FOUND\" }"') do set "NEW_VER=%%v"

if "%NEW_VER%"=="PARSE_ERROR" (
    echo [错误] 无法解析版本号格式，期待 ^<name^>+^<code^>
    pause
    exit /b 1
)
if "%NEW_VER%"=="NOT_FOUND" (
    echo [错误] pubspec.yaml 中未找到 version 字段
    pause
    exit /b 1
)
echo       版本号已更新: %NEW_VER%
goto :eof

REM ============================================
REM  代码生成
REM ============================================
:codegen
call :checkenv
if %ERRORLEVEL% neq 0 exit /b 1

echo.
echo ============================================
echo  代码生成 - %date% %time%
echo ============================================

echo [1/3] flutter pub get...
call flutter pub get
if %ERRORLEVEL% neq 0 (
    echo [错误] pub get 失败！
    pause
    exit /b 1
)

echo [2/3] flutter gen-l10n...
call flutter gen-l10n
if %ERRORLEVEL% neq 0 (
    echo [错误] l10n 生成失败！
    pause
    exit /b 1
)

echo [3/3] build_runner (Drift)...
call flutter pub run build_runner build --delete-conflicting-outputs
if %ERRORLEVEL% neq 0 (
    echo [错误] build_runner 失败！
    pause
    exit /b 1
)

echo       代码生成完成。
if /i "%~1"=="codegen" (
    pause
    exit /b 0
)
goto :eof

REM ============================================
REM  清理构建产物
REM ============================================
:clean
echo.
echo ============================================
echo  清理构建产物...
echo ============================================
call flutter clean
if exist "privi-*.apk" del /q "privi-*.apk" 2>nul
if exist "*.aab" del /q "*.aab" 2>nul
rmdir /s /q ".dart_tool" 2>nul
rmdir /s /q "build" 2>nul
echo       清理完成。
pause
exit /b 0

REM ============================================
REM  快速构建（跳过代码生成）
REM ============================================
:fast
goto :do_build

REM ============================================
REM  完整构建流程
REM ============================================
:build
echo.
echo ============================================
echo  Privi 构建 - %date% %time%
echo ============================================

echo [1/6] 代码生成...
call :codegen
if %ERRORLEVEL% neq 0 exit /b 1

:do_build
call :checkenv
if %ERRORLEVEL% neq 0 exit /b 1

echo.
echo ============================================
echo  Privi 构建 - %date% %time%
echo ============================================

echo [2/6] 递增版本号...
call :increment_version
if %ERRORLEVEL% neq 0 exit /b 1

echo.
echo [3/6] flutter clean...
call flutter clean
echo       完成。

echo.
echo [4/6] flutter pub get...
call flutter pub get
if %ERRORLEVEL% neq 0 (
    echo [错误] pub get 失败！
    pause
    exit /b 1
)

echo.
echo [5/6] 编译 Release APK（请耐心等待，首次约 5-10 分钟）...
call flutter build apk --release
set BUILD_EXIT=%ERRORLEVEL%

echo.
if %BUILD_EXIT% neq 0 (
    echo ============================================
    echo  构建失败！Exit code=%BUILD_EXIT%
    echo ============================================
    pause
    exit /b 1
)

echo ============================================
echo  构建成功！
echo ============================================

echo [6/6] 复制 APK 到项目根目录...
if exist "privi-*.apk" del /q "privi-*.apk" 2>nul
set "APK_SOURCE=build\app\outputs\flutter-apk\app-release.apk"
set "APK_DEST=privi-%NEW_VER%.apk"
if exist "%APK_SOURCE%" (
    copy /y "%APK_SOURCE%" "%APK_DEST%" > nul
    for %%f in ("%APK_DEST%") do echo  APK: %%~nxf  (%%~zf bytes)
) else (
    echo [错误] 未找到构建产物: %APK_SOURCE%
    pause
    exit /b 1
)

echo.
echo  APK 已复制到项目根目录。
echo.
pause
exit /b 0