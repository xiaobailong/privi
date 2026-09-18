@echo off
chcp 65001 > nul 2>&1
setlocal enabledelayedexpansion

title Privi 依赖升级

REM ---- 环境配置（与 build.bat 保持一致） ----
set "JAVA_HOME=D:\Tools\DevTools\Java\JDK\jdk-21.0.10-oracle"
set "FLUTTER_HOME=D:\Tools\DevTools\flutter"
set "ANDROID_HOME=D:\Tools\DevTools\Android\Sdk"
set "ANDROID_SDK_ROOT=D:\Tools\DevTools\Android\Sdk"
set "PUB_HOSTED_URL=https://pub.flutter-io.cn"
set "FLUTTER_STORAGE_BASE_URL=https://storage.flutter-io.cn"
set "PATH=%JAVA_HOME%\bin;%FLUTTER_HOME%\bin;%ANDROID_HOME%\platform-tools;%PATH%"

cd /d "%~dp0"

echo ============================================
echo  Privi 依赖升级 - %date% %time%
echo ============================================

echo.
echo [1/3] 当前依赖信息...
echo.
echo pubspec.lock 最后修改时间:
for %%f in (pubspec.lock) do echo   %%~tf

echo.
echo [2/3] flutter pub upgrade...
echo       首次运行可能需要 2-5 分钟，请耐心等待...
echo.
call flutter pub upgrade
set UPGRADE_EXIT=%ERRORLEVEL%

if !UPGRADE_EXIT! neq 0 (
    echo.
    echo ============================================
    echo  [失败] flutter pub upgrade 退出码=!UPGRADE_EXIT!
    echo ============================================
    goto :end
)

echo.
echo [3/3] 升级后的依赖...
echo.
echo 关键包版本:
for %%p in (flutter_riverpod drift drift_dev build_runner analyzer) do (
    for /f "tokens=1-3" %%a in ('findstr /c:"%%p:" pubspec.lock') do (
        if "%%a"=="%%p:" echo   %%a %%b
    )
)

echo.
echo ============================================
echo  依赖升级完成！
echo ============================================

:end
echo.
echo 窗口将在 30 秒后自动关闭，或按任意键立即关闭...
timeout /t 30 /nobreak > nul 2>&1
endlocal