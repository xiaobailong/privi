@echo off
chcp 65001 > nul 2>&1
setlocal enabledelayedexpansion
cd /d "%~dp0.."

REM ---- 0. 自动检测 Android SDK ----
if defined ANDROID_HOME (
    set "PATH=%ANDROID_HOME%\platform-tools;%PATH%"
) else if exist "%LOCALAPPDATA%\Android\Sdk\platform-tools\adb.exe" (
    set "PATH=%LOCALAPPDATA%\Android\Sdk\platform-tools;%PATH%"
) else if exist "D:\Tools\DevTools\Android\Sdk\platform-tools\adb.exe" (
    set "PATH=D:\Tools\DevTools\Android\Sdk\platform-tools;%PATH%"
)

echo ========================================
echo   密册 - ADB 安装脚本
echo ========================================
echo.

REM ---- 1. 检查 adb ----
where adb >nul 2>&1
if %ERRORLEVEL% neq 0 goto :no_adb_found

for /f "tokens=*" %%a in ('adb --version 2^>nul ^| findstr /i "version"') do (
    echo [adb] %%a
)
echo.

REM ---- 2. 检查设备连接 ----
for /f "skip=1 tokens=1,2" %%a in ('adb devices 2^>nul') do (
    if not "%%a"=="" (
        set "SERIAL=%%a"
        set "STATE=%%b"
        goto :check_device_state
    )
)
goto :no_device_found

:check_device_state
echo [设备] !SERIAL! ^(!STATE!^)
if /i "!STATE!" neq "device" goto :device_not_ready
echo.

REM ---- 3. 查找 APK ----
set "APK_PATH="

REM 优先用项目根目录下的 privi-*.apk（build.bat 步骤6产物）
for /f "delims=" %%f in ('dir /b /o-d "privi-*.apk" 2^>nul') do (
    set "APK_PATH=%%f"
    goto :found_apk
)

REM 其次用 flutter build 原始输出
if exist "build\app\outputs\flutter-apk\app-release.apk" (
    set "APK_PATH=build\app\outputs\flutter-apk\app-release.apk"
    goto :found_apk
)

echo [错误] 未找到 APK 文件
echo        请在项目根目录运行 build.bat 先构建 APK
echo        或确保 privi-*.apk 存在于当前目录
exit /b 1

:found_apk

for %%f in ("!APK_PATH!") do (
    set "APK_SIZE=%%~zf"
    set "APK_NAME=%%~nxf"
)

set /a APK_SIZE_MB=!APK_SIZE! / 1048576
echo [APK]  !APK_NAME!  (%APK_SIZE_MB% MB)
echo.

REM ---- 4. 安装 ----
echo [安装] 正在安装到设备...
echo.
adb install -r -d "!APK_PATH!"
set "INSTALL_EXIT=%ERRORLEVEL%"

echo.
if !INSTALL_EXIT! equ 0 goto :install_success
goto :install_failed

REM ============================================================
REM  安装结果标签（放在 if 块外面，避免 cmd 解析器乱码）
REM ============================================================

:install_success
echo [成功] 安装完成！
echo.
echo        提示：如果桌面没有图标，请到系统设置的「应用」列表中查找「密册」
exit /b 0

:install_failed
echo [失败] 安装失败 ^(adb 退出码: !INSTALL_EXIT!^)
echo.
echo        常见原因：
echo        - INSTALL_FAILED_UPDATE_INCOMPATIBLE: 签名与已安装版本不一致
echo          ^(debug 签名 vs release 签名^)，请先卸载再安装
echo        - INSTALL_FAILED_INSUFFICIENT_STORAGE: 手机存储空间不足
echo        - 设备未授权安装来自此来源的应用
echo.
echo        如需卸载旧版后重新安装：
echo        adb uninstall com.privi.app ^&^& adb install -r "!APK_PATH!"
exit /b !INSTALL_EXIT!

REM ============================================================
REM  错误处理标签（放在 if 块外面，避免 cmd 解析器乱码）
REM ============================================================

:no_adb_found
echo [错误] 未找到 adb，请确保 Android SDK platform-tools 在 PATH 中
echo.
echo        SDK 目录:
echo            %%LOCALAPPDATA%%\Android\Sdk\platform-tools
echo        或已安装 Android Studio 时可在终端运行:
echo        set PATH=%%LOCALAPPDATA%%\Android\Sdk\platform-tools;%%PATH%%
exit /b 1

:no_device_found
echo [错误] 未检测到已连接的 Android 设备
echo.
echo        请确认：
echo        1. 手机已通过 USB 连接电脑
echo        2. 手机已开启「USB 调试」^("开发者选项"中^)
echo        3. 已授权此电脑的调试请求
echo.
echo        当前 adb 设备列表：
adb devices
exit /b 1

:device_not_ready
echo [错误] 设备状态异常 ^(!STATE!^)
echo.
if /i "!STATE!" equ "unauthorized" goto :state_unauthorized
if /i "!STATE!" equ "offline" goto :state_offline
goto :state_unknown

:state_unauthorized
echo        请在手机上点击「允许 USB 调试」授权弹窗
goto :device_not_ready_end

:state_offline
echo        设备已离线，请尝试：
echo        1. 重新插拔 USB 线
echo        2. 关闭再开启「USB 调试」
echo        3. 运行 adb kill-server 再重试
goto :device_not_ready_end

:state_unknown
echo        未能识别的设备状态，请手动检查
goto :device_not_ready_end

:device_not_ready_end
echo.
echo        当前 adb 设备列表：
adb devices
exit /b 1