@echo off
chcp 65001 > nul
title Privi Clean

REM ============================================
REM  Privi 清理构建产物脚本
REM  用途: 清理 Flutter 构建输出、缓存和产物
REM ============================================

REM ---- 环境配置（按实际路径修改） ----
set "JAVA_HOME=D:\Tools\DevTools\Java\JDK\jdk-21.0.10-oracle"
set "FLUTTER_HOME=D:\Tools\DevTools\flutter"
set "ANDROID_HOME=D:\Tools\DevTools\Android\Sdk"
set "ANDROID_SDK_ROOT=D:\Tools\DevTools\Android\Sdk"
set "PUB_HOSTED_URL=https://pub.flutter-io.cn"
set "FLUTTER_STORAGE_BASE_URL=https://storage.flutter-io.cn"
set "GRADLE_USER_HOME=%~dp0.gradle_home"
set "PATH=%JAVA_HOME%\bin;%FLUTTER_HOME%\bin;%ANDROID_HOME%\platform-tools;%PATH%"

REM ---- 切换到项目根目录 ----
cd /d "%~dp0"
if %ERRORLEVEL% neq 0 (
    echo [错误] 无法切换到项目目录
    pause
    exit /b 1
)

echo.
echo ============================================
echo  Privi 清理构建产物
echo ============================================
echo.

echo [1/5] Flutter clean...
call flutter clean 2>nul
if %ERRORLEVEL% neq 0 (
    echo [警告] flutter clean 未完全成功，继续手动清理...
)
echo       完成。

echo [2/5] 清理 .dart_tool 目录...
if exist ".dart_tool" (
    rmdir /s /q ".dart_tool" 2>nul
    echo       已删除 .dart_tool 目录。
) else (
    echo       .dart_tool 目录不存在，跳过。
)

echo [3/5] 清理 build 目录...
if exist "build" (
    rmdir /s /q "build" 2>nul
    echo       已删除 build 目录。
) else (
    echo       build 目录不存在，跳过。
)

echo [4/5] 清理 .gradle 缓存...
if exist ".gradle" (
    rmdir /s /q ".gradle" 2>nul
    echo       已删除 .gradle 目录。
) else (
    echo       .gradle 目录不存在，跳过。
)

echo [5/5] 清理输出产物...
if exist "privi-*.apk" (
    del /q "privi-*.apk" 2>nul
    echo       已删除 privi-*.apk 文件。
) else (
    echo       无 privi-*.apk 文件，跳过。
)
if exist "*.aab" (
    del /q "*.aab" 2>nul
    echo       已删除 aab 文件。
) else (
    echo       无 aab 文件，跳过。
)

echo.
echo ============================================
echo  清理完成！
echo ============================================
echo.
pause
exit /b 0