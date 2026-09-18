@echo off
chcp 65001 > nul 2>&1
setlocal enabledelayedexpansion

REM ============================================
REM  Log tee: restart self via PowerShell so all
REM  output goes to both console and build_full.log
REM ============================================
if "%~1" NEQ "--log" (
    if not exist "%~dp0build" mkdir "%~dp0build" 2>nul
    powershell -NoProfile -Command ^
        "$OutputEncoding = [Console]::OutputEncoding = [Console]::InputEncoding = [Text.Encoding]::UTF8; " ^
        "$utf8NoBom = [Text.UTF8Encoding]::new($false); " ^
        "$sw = [System.IO.StreamWriter]::new('%~dp0build\build_full.log', $false, $utf8NoBom); " ^
        "try { cmd /c '%~f0 --log %*' 2>&1 | ForEach-Object { Write-Host $_; $sw.WriteLine($_) } } finally { $sw.Close() }"
    exit /b
) else (
    shift
)

title Privi Build

REM ============================================
REM  Privi 一键构建脚本
REM  用法: 双击运行     (完整构建 + 递增版本)
REM        build codegen (仅代码生成)
REM        build clean   (清理构建产物)
REM        build fast    (构建但跳过代码生成)
REM ============================================

REM ---- 全局状态变量 ----
set "BUILD_FAILED=0"
set "STEP_NAME="

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
    echo [错误] 无法切换到项目目录: %~dp0
    set BUILD_FAILED=1
    goto :end
)

REM ---- 确保根路径 build 目录存在 ----
if not exist "build" mkdir "build" 2>nul

REM ---- 路由到具体任务 ----
if /i "%~1"=="codegen" call :codegen && goto :end
if /i "%~1"=="clean"   goto :clean
if /i "%~1"=="fast"    goto :fast
goto :build

REM ============================================
REM  统一错误处理入口：捕获错误后跳转此处
REM ============================================
:on_error
echo.
echo ============================================
echo  [错误] !STEP_NAME! 执行失败！
echo ============================================
set BUILD_FAILED=1
goto :end

REM ============================================
REM  环境检查（非致命，失败只警告不退出）
REM ============================================
:checkenv
echo.
echo ============================================
echo  检查构建环境...
echo ============================================

where java >nul 2>&1
if %ERRORLEVEL% neq 0 (
    echo [警告] 未找到 Java。请安装 JDK 17+
    echo        下载地址: https://jdk.java.net/17/
    set BUILD_FAILED=1
    goto :eof
)
for /f "tokens=3" %%v in ('java -version 2^>^&1 ^| findstr /i "version"') do (
    echo        Java: %%v
)

where flutter >nul 2>&1
if %ERRORLEVEL% neq 0 (
    echo [警告] 未找到 Flutter。
    echo        下载地址: https://docs.flutter.dev/get-started/install/windows
    set BUILD_FAILED=1
    goto :eof
)
echo        [Flutter 位置] %FLUTTER_HOME%

REM Flutter --version 可能会触发 SDK 首次初始化（Building flutter tool...）
echo        [Flutter 版本] 正在获取（首次运行可能需要下载 SDK 组件，请耐心等待）...
for /f "tokens=2" %%v in ('flutter --version 2^>^&1 ^| findstr /r "^Flutter"') do (
    echo        Flutter: %%v
)
if %ERRORLEVEL% neq 0 (
    echo        [警告] flutter --version 未返回版本号，但可能不影响构建
)

if not exist "%ANDROID_HOME%" (
    echo [警告] Android SDK 未找到: %ANDROID_HOME%
    echo        下载 Android Studio: https://developer.android.com/studio
    set BUILD_FAILED=1
    goto :eof
)
echo        Android SDK: %ANDROID_HOME%

REM ---- 打印镜像/代理环境变量 ----
echo        PUB_HOSTED_URL=%PUB_HOSTED_URL%
echo        FLUTTER_STORAGE_BASE_URL=%FLUTTER_STORAGE_BASE_URL%
if defined HTTP_PROXY echo        HTTP_PROXY=%HTTP_PROXY%
if defined HTTPS_PROXY echo        HTTPS_PROXY=%HTTPS_PROXY%

REM ---- 测试 pub.dev 连通性（非致命） ----
echo.
echo        [网络诊断] 测试 pub 仓库连通性...
for %%h in (pub.dev pub.flutter-io.cn mirrors.tuna.tsinghua.edu.cn) do (
    powershell -NoProfile -Command "try { $r = Invoke-WebRequest -Uri 'https://%%h' -TimeoutSec 5 -UseBasicParsing; Write-Host '          %%h: 可达 (' $r.StatusCode ')' } catch { Write-Host '          %%h: 不可达 (' $_.Exception.Message.Trim() ')' }" 2>nul
)

REM ---- Flutter Doctor 简要状态（非致命） ----
echo.
echo        [Flutter 状态] flutter doctor 摘要...
flutter doctor 2>&1 | findstr /i /c:"No issues" /c:"issue" /c:"Android toolchain" /c:"Chrome" 2>nul
if %ERRORLEVEL% neq 0 (
    echo        [警告] flutter doctor 未返回预期内容，但可能不影响构建
)

if not exist "local.properties" (
    echo sdk.dir=%ANDROID_HOME%> "local.properties" 2>nul
    echo flutter.sdk=%FLUTTER_HOME%>> "local.properties" 2>nul
    echo        local.properties 已生成
)
goto :eof

REM ============================================
REM  递增版本号（根目录 BUILD 文件 + pubspec.yaml 联动）
REM ============================================
:increment_version
echo.
echo [递增版本号]...

if not exist "pubspec.yaml" (
    echo [警告] pubspec.yaml 不存在，跳过
    set "NEW_VER=unknown"
    goto :eof
)

REM ---- 初始化 BUILD_NUM 文件（从 pubspec.yaml 提取当前 build number） ----
if not exist ".BUILD_NUM" (
    for /f "tokens=2 delims=+" %%n in ('findstr /c:"version: " pubspec.yaml') do (
        echo %%n> ".BUILD_NUM"
    )
    if not exist ".BUILD_NUM" echo 0> ".BUILD_NUM"
)

REM ---- 读取并递增 ----
set /p B=<".BUILD_NUM"
set /a BN=%B%+1
set "NEW_BUILD_NUM=%BN%"
echo %BN%> ".BUILD_NUM"

REM ---- 更新 pubspec.yaml：仅替换 + 号后面的数字，不动版本名 ----
set "PS_CMD=Set-Content pubspec.yaml -Encoding UTF8 -NoNewline -Value ((Get-Content pubspec.yaml -Encoding UTF8 -Raw) -replace '(\+)\d+','${1}%BN%')"
powershell -NoProfile -Command "!PS_CMD!"
if %ERRORLEVEL% neq 0 (
    echo [警告] 更新 pubspec.yaml 失败
)

REM ---- 读取更新后的版本号用于显示和日志 ----
for /f "tokens=2 delims=: " %%v in ('findstr /c:"version: " pubspec.yaml') do set "NEW_VER=%%v"

echo       版本号已更新: %NEW_VER%
goto :eof

REM ============================================
REM  代码生成
REM ============================================
:codegen
call :checkenv
if "%BUILD_FAILED%"=="1" (
    echo [警告] 环境检查有警告，但尝试继续代码生成...
)

echo.
echo ============================================
echo  代码生成 - %date% %time%
echo ============================================

echo [1/3] flutter pub get (verbose)...
echo       日志输出到: build\pub_get_codegen.log
echo       [提示] 首次下载依赖可能需要 2-5 分钟，请耐心等待...
echo.
call flutter pub get --verbose > build\pub_get_codegen.log 2>&1
set PUB_EXIT=%ERRORLEVEL%
if !PUB_EXIT! neq 0 (
    echo [警告] pub get 失败！Exit code=!PUB_EXIT!
    echo       最后 20 行日志:
    powershell -NoProfile -Command "Get-Content 'build\pub_get_codegen.log' -Tail 20" 2>nul
    set BUILD_FAILED=1
    goto :eof
)
echo       pub get 完成。

echo [2/3] flutter gen-l10n...
call flutter gen-l10n 2>&1
if %ERRORLEVEL% neq 0 (
    echo [警告] l10n 生成失败！缺少 .arb 文件或未配置国际化，不影响 build_runner
    set BUILD_FAILED=1
    REM 非致命：继续运行 build_runner
) else (
    echo       gen-l10n 完成。
)

echo [3/3] build_runner (Drift)...
call dart run build_runner build 2>&1
if %ERRORLEVEL% neq 0 (
    echo [警告] build_runner 失败！
    set BUILD_FAILED=1
    goto :eof
)
echo       build_runner 完成。

echo       代码生成全部完成。
goto :eof

REM ============================================
REM  清理构建产物
REM ============================================
:clean
echo.
echo ============================================
echo  清理构建产物...
echo ============================================
call flutter clean 2>nul
if exist "privi-*.apk" del /q "privi-*.apk" 2>nul
if exist "*.aab" del /q "*.aab" 2>nul
rmdir /s /q ".dart_tool" 2>nul
rmdir /s /q "build" 2>nul
echo       清理完成。
goto :end

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
set "STEP_NAME=[1/6] 代码生成"
call :codegen
if "%BUILD_FAILED%"=="1" (
    echo [警告] 代码生成阶段出现问题，但尝试继续后续步骤...
)

:do_build
echo.
echo ============================================
echo  Privi 构建 - %date% %time%
echo ============================================

echo [2/6] 递增版本号...
set "STEP_NAME=[2/6] 递增版本号"
call :increment_version
REM 版本号失败不阻塞构建

echo.
echo [3/6] flutter clean...
set "STEP_NAME=[3/6] flutter clean"
call flutter clean 2>nul
if %ERRORLEVEL% neq 0 (
    echo [警告] flutter clean 未完全成功，继续...
)
echo       完成。

REM flutter clean 会删除 build/ 目录，重建它以支持后续日志重定向
if not exist "build" mkdir "build" 2>nul

echo.
echo [4/6] flutter pub get (verbose)...
echo       日志输出到: build\pub_get_build.log
echo       [提示] 如果 codegen 阶段已成功，这步会很快...
echo.
set "STEP_NAME=[4/6] flutter pub get"
call flutter pub get --verbose > build\pub_get_build.log 2>&1
set PUB_EXIT=%ERRORLEVEL%
if !PUB_EXIT! neq 0 (
    echo [警告] pub get 失败！Exit code=!PUB_EXIT!
    echo       最后 20 行日志:
    powershell -NoProfile -Command "Get-Content 'build\pub_get_build.log' -Tail 20" 2>nul
    set BUILD_FAILED=1
    goto :end
)
echo       pub get 完成。

echo.
echo [5/6] 编译 Release APK（请耐心等待，首次约 5-10 分钟）...
set "STEP_NAME=[5/6] flutter build apk"
call flutter build apk --release
set BUILD_EXIT=%ERRORLEVEL%

REM flutter 可能不传递 Gradle 错误码，以 APK 是否真正生成作为唯一判断依据
set "APK_SOURCE=build\app\outputs\flutter-apk\app-release.apk"
if not exist "!APK_SOURCE!" (
    echo.
    echo ============================================
    echo  [警告] 构建失败！未找到构建产物
    if !BUILD_EXIT! neq 0 echo        Flutter exit code=!BUILD_EXIT!
    echo        预期路径: !APK_SOURCE!
    echo ============================================
    set BUILD_FAILED=1
    goto :end
)

echo.
echo ============================================
echo  构建成功！
echo ============================================

echo [6/6] 复制 APK 到项目根目录...
set "STEP_NAME=[6/6] 复制 APK"
if exist "privi-*.apk" del /q "privi-*.apk" 2>nul
set "APK_DEST=privi-%NEW_VER%.apk"
copy /y "!APK_SOURCE!" "!APK_DEST!" > nul 2>&1
for %%f in ("!APK_DEST!") do echo  APK: %%~nxf  (%%~zf bytes)

echo.
echo  APK 已复制到项目根目录。
goto :end

REM ============================================
REM  统一出口：永远 pause，让用户看到结果
REM ============================================
:end
REM 写入诊断文件，确认脚本走到了 :end
echo %date% %time% BUILD_FAILED=%BUILD_FAILED% NEW_VER=%NEW_VER% > build\build_exit.log 2>nul
echo.
echo ============================================
if "%BUILD_FAILED%"=="1" (
    echo  构建过程有错误/警告，请查看上方日志
) else (
    echo  构建流程结束
)
echo ============================================
echo.
echo 窗口将在 60 秒后自动关闭，或按任意键立即关闭...
timeout /t 60 > nul
exit /b %BUILD_FAILED%