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
        "$sw = [System.IO.StreamWriter]::new('%~dp0build\build_full.log', $false, $utf8NoBom); $sw.AutoFlush = $true; " ^
        "try { cmd /c '%~f0 --log %*' 2>&1 | ForEach-Object { Write-Host $_; $sw.WriteLine($_) } } finally { $sw.Close() }"
    exit /b
) else (
    shift
)

title Privi Build

REM ============================================
REM  Privi 一键构建脚本
REM  用法: 双击运行            (完整构建 + 递增版本 + 自动发布 Release)
REM        build codegen       (仅代码生成)
REM        build clean         (清理构建产物)
REM        build fast          (构建但跳过代码生成)
REM        build gradle        (仅 Gradle 编译，调试用，不发布 Release)
REM        build release       (不重新构建，直接把根目录已有 APK 发布到 Release)
REM        build fast norelease / build norelease
REM                            (构建但不自动发布 Release；等价于 set SKIP_RELEASE=1)
REM  环境变量: GH_EXE           (可选，指定 gh 可执行文件；默认自动探测)
REM ============================================

REM ---- 全局状态变量 ----
set "BUILD_FAILED=0"
set "BUMP_FAILED=0"
set "STEP_NAME="
set "RESUME_STEP=0"
REM 断点续传状态文件：必须在这里定义。放在下沉的 :calc_hash_codegen 之前
REM 会被上面的 goto 跳过（第 81 行的任务分发），导致 :save_state 重定向到空
REM 路径，日志里就会出现 "The system cannot find the path specified."，
REM 状态文件也一直写不出来。
set "STATE_FILE=build\.build_state"

REM ---- Release 发布（gh CLI）状态 ----
REM SKIP_RELEASE 允许外部预置（build.bat norelease，或 set SKIP_RELEASE=1 后运行）
REM GH_EXE 同样允许外部预置（本机 gh 不在 PATH 时，或构建脚本自测用假 gh 时）；
REM 预置路径不存在时 :resolve_gh 会清空它，发布环节只是跳过、不会让构建失败。
if not defined SKIP_RELEASE set "SKIP_RELEASE=0"
set "RELEASE_TAG="
set "RELEASE_SLUG="
set "APK_SHA="

REM ---- 环境配置（按实际路径修改） ----
set "JAVA_HOME=D:\Tools\DevTools\Java\JDK\jdk-21.0.10-oracle"
set "FLUTTER_HOME=D:\Tools\DevTools\flutter"
set "ANDROID_HOME=D:\Tools\DevTools\Android\Sdk"
set "ANDROID_SDK_ROOT=D:\Tools\DevTools\Android\Sdk"
set "PUB_HOSTED_URL=https://pub.flutter-io.cn"
set "FLUTTER_STORAGE_BASE_URL=https://storage.flutter-io.cn"
set "GRADLE_USER_HOME=%~dp0.gradle_home"

REM ---- 代理检测（Clash 默认端口 7890） ----
set "PROXY_HOST="
set "PROXY_PORT="
set "PROXY_AVAILABLE=0"
REM 通过 netstat 检查本地代理端口是否在监听
netstat -ano 2>nul | findstr /r "127\.0\.0\.1:7890.*LISTENING" >nul 2>&1
if %ERRORLEVEL% equ 0 (
    set "PROXY_HOST=127.0.0.1"
    set "PROXY_PORT=7890"
    set "PROXY_AVAILABLE=1"
)
if "%PROXY_AVAILABLE%"=="1" (
    set "HTTP_PROXY=http://%PROXY_HOST%:%PROXY_PORT%"
    set "HTTPS_PROXY=http://%PROXY_HOST%:%PROXY_PORT%"
)

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
if /i "%~1"=="gradle"  goto :gradle_only
REM norelease 可以写在任意位置: build.bat norelease / build.bat fast norelease / build.bat release norelease
if not "%~1"=="" for %%a in (%*) do if /i "%%a"=="norelease" set "SKIP_RELEASE=1"
if /i "%~1"=="release" goto :release_only
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
REM  断点续传：记录/读取构建进度，跳过已完成步骤
REM  文件: build\.build_state
REM  格式: STEP=N  +  HASH_xxx=<md5>
REM  注意: STATE_FILE 已在脚本开头的全局变量区定义
REM ============================================

REM 计算代码生成相关文件的哈希
REM 注意: 本机安全策略会静默拦截含正则/管道的 powershell -Command 长命令行
REM       （表现为退出码 786、无输出），因此哈希逻辑放在 build_hash.ps1 里用 -File 调用。
:calc_hash_codegen
set "HASH_CODE_GEN="
if not exist "%~dp0build_hash.ps1" (
    echo [警告] 未找到 build_hash.ps1，无法计算代码哈希
    goto :eof
)
for /f "usebackq delims=" %%v in (`powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0build_hash.ps1" -Kind codegen 2^>nul`) do set "HASH_CODE_GEN=%%v"
goto :eof

REM 计算 Gradle 配置文件的哈希
:calc_hash_gradle
set "HASH_GRADLE="
if not exist "%~dp0build_hash.ps1" (
    echo [警告] 未找到 build_hash.ps1，无法计算 Gradle 哈希
    goto :eof
)
for /f "usebackq delims=" %%v in (`powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0build_hash.ps1" -Kind gradle 2^>nul`) do set "HASH_GRADLE=%%v"
goto :eof

REM 读取状态文件，对比哈希，确定从哪一步开始
:load_state
set "RESUME_STEP=0"
if not exist "%STATE_FILE%" goto :eof

REM 读取保存的步骤和哈希
for /f "tokens=2 delims==" %%v in ('findstr /c:"SAVED_STEP=" "%STATE_FILE%" 2^>nul') do set "SAVED_STEP=%%v"
for /f "tokens=2 delims==" %%v in ('findstr /c:"HASH_CODE_GEN=" "%STATE_FILE%" 2^>nul') do set "SAVED_HASH_CG=%%v"
for /f "tokens=2 delims==" %%v in ('findstr /c:"HASH_GRADLE=" "%STATE_FILE%" 2^>nul') do set "SAVED_HASH_GR=%%v"

if not defined SAVED_STEP goto :eof

REM 计算当前哈希
call :calc_hash_codegen
call :calc_hash_gradle

REM 哈希没算出来（build_hash.ps1 缺失 / 被安全策略拦截）→ 绝不能拿空值去比较，
REM 否则会误判成"代码未变更"，直接跳过编译复用上一版 APK。
if not defined HASH_CODE_GEN (
    echo [断点续传] 无法计算代码哈希，取消续传，从头构建
    del "%STATE_FILE%" 2>nul
    set "RESUME_STEP=0"
    goto :eof
)
if not defined HASH_GRADLE (
    echo [断点续传] 无法计算 Gradle 哈希，取消续传，从头构建
    del "%STATE_FILE%" 2>nul
    set "RESUME_STEP=0"
    goto :eof
)

REM 代码变更 → 从步骤0重新开始
if not "%SAVED_HASH_CG%"=="%HASH_CODE_GEN%" (
    echo [断点续传] 检测到代码变更，从头开始构建
    del "%STATE_FILE%" 2>nul
    set "RESUME_STEP=0"
    goto :eof
)

REM Gradle 配置变更 → 从步骤3(clean)重新开始
if not "%SAVED_HASH_GR%"=="%HASH_GRADLE%" (
    if %SAVED_STEP% geq 3 (
        echo [断点续传] 检测到 Gradle 配置变更，从第3步重新开始
        set "RESUME_STEP=2"
        goto :eof
    )
)

REM 无变更 → 从上次结束的地方继续
REM 但续传上限只到第2步：步骤3/4/5（flutter clean → pub get → 编译APK）必须每次都跑，
REM 否则 SAVED_STEP=6 时所有 if 判断都不成立 → 一步都不执行 → 根目录 APK 还是旧版本
REM （或直接没有 APK），这正是切回旧提交后 APK 打包失败的根因之一。
set "RESUME_STEP=%SAVED_STEP%"
if !RESUME_STEP! gtr 2 set "RESUME_STEP=2"
echo [断点续传] 上次完成到第 %SAVED_STEP% 步，本次从第 !RESUME_STEP! 步继续
goto :eof

REM 保存当前步骤到状态文件
:save_state
set "SAVE_NUM=%~1"
REM flutter clean 会删除 build\ 目录；不在这里补建目录，重定向就会失败
REM （日志里的 "The system cannot find the path specified." 就是它），
REM 断点续传状态也就永远写不出来。
if not exist "build" mkdir "build" 2>nul
(
    echo SAVED_STEP=!SAVE_NUM!
    echo HASH_CODE_GEN=!HASH_CODE_GEN!
    echo HASH_GRADLE=!HASH_GRADLE!
) > "%STATE_FILE%"
goto :eof

REM ============================================
REM  构建前置自检：WMI 硬超时守卫
REM
REM  为什么需要：Windows 上 Dart 用 COM/WMI 查平台信息
REM  （Platform.operatingSystemVersion -> Win32_OperatingSystem），这条调用没有超时。
REM  winmgmt 服务"显示 RUNNING 但不回请求"时，flutter.bat 每次启动都静默阻塞：
REM  日志 0 字节、CPU 0%、永远不返回 —— 也就是"构建卡住不动"。
REM  这个自检 1 秒内就能把结论定死，不用等人肉发现。
REM
REM  结果：WMI_FAILED=1 表示确认 WMI 挂死 —— 调用方必须终止构建，不能只警告
REM        （顶层流程用 goto :end；被 call 的例程用 goto :eof，由调用方收口，避免 :end 跑两遍）
REM  每次构建只跑一次（WMI_GUARDED 去重）
REM ============================================
:preflight
if "%WMI_GUARDED%"=="1" goto :eof
set "WMI_GUARDED=1"
set "WMI_FAILED=0"

echo        [WMI 自检] Dart 读 OS 版本（WMI 无响应会让所有 flutter 命令静默挂死）...
if not exist "%~dp0build_wmi_guard.ps1" (
    echo        [跳过] 未找到 build_wmi_guard.ps1
    goto :eof
)

set "WMI_OUT=%TEMP%\privi_wmi_guard.txt"
del /q "%WMI_OUT%" 2>nul
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0build_wmi_guard.ps1" -FlutterRoot "%FLUTTER_HOME%" > "%WMI_OUT%" 2>&1
set "WMI_RC=%ERRORLEVEL%"
set "WMI_MSG="
for /f "usebackq delims=" %%l in ("%WMI_OUT%") do set "WMI_MSG=%%l"

REM 退出码 5 = 确认 WMI 无响应（build_wmi_guard.ps1 的定义）
REM 注意: 这里刻意不在 echo 里写半角括号。`echo xxx(!VAR!)yyy` 位于 ( ) 块内时，
REM 那个 ')' 会被 cmd 当成块的结束符，剩下的内容被解析成非法语句并直接中断整个批处理
REM （现象: ": was unexpected at this time."）。改用拼接好的变量输出。
set "WMI_TAG=[警告] 自检未通过"
if "!WMI_RC!"=="0" set "WMI_TAG=[WMI 自检]"
if not "!WMI_RC!"=="5" (
    echo        !WMI_TAG! rc=!WMI_RC! !WMI_MSG!
    goto :eof
)

set "WMI_FAILED=1"
echo.
echo ============================================
echo  [错误] WMI 无响应
echo ============================================
echo        !WMI_MSG!
echo.
echo        说明: Dart 在 Windows 上通过 WMI 读取 OS 版本且没有超时。
echo              winmgmt 不响应时, 每条 flutter 命令都会静默挂死（日志 0 字节、CPU 0%%），
echo              表现出来就是"构建卡住不动"。
echo        处理: 1) 重启机器（最有效）
echo              2) 或管理员执行: winmgmt /resetrepository
echo              3) 单独复现: powershell -NoProfile -ExecutionPolicy Bypass -File build_wmi_guard.ps1
echo ============================================
goto :eof

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

REM Flutter --version 触发 SDK 首次初始化可能会卡死，跳过。
REM 版本号在后续 pub get / build 阶段自然会显示。
echo        [Flutter 版本] （跳过 --version 避免触发工具链下载阻塞）

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
if "%PROXY_AVAILABLE%"=="1" (
    echo        [代理] Clash 代理已启用: %PROXY_HOST%:%PROXY_PORT%
    echo        HTTP_PROXY=%HTTP_PROXY%
) else (
    echo        [代理] 未检测到代理，将直连下载
)

REM ---- 测试 pub.dev 连通性（非致命） ----
echo.
echo        [网络诊断] 测试 pub 仓库连通性...
for %%h in (pub.dev pub.flutter-io.cn mirrors.tuna.tsinghua.edu.cn) do (
    powershell -NoProfile -Command "try { $r = Invoke-WebRequest -Uri 'https://%%h' -TimeoutSec 5 -UseBasicParsing; Write-Host '          %%h: 可达 (' $r.StatusCode ')' } catch { Write-Host '          %%h: 不可达 (' $_.Exception.Message.Trim() ')' }" 2>nul
)

REM Flutter doctor / --version 都会触发工具链下载，跳过避免卡死。
echo        [Flutter 状态] （跳过 flutter doctor 避免触发工具链下载阻塞）

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
set /a BN=B+1 2>nul
if not defined BN set /a BN=1
set "NEW_BUILD_NUM=%BN%"

REM ---- 更新 pubspec.yaml：只替换 + 号后面的数字，不动版本名 ----
REM  必须用 -File 调脚本，不能用 powershell -Command 一行式！
REM  本机安全策略会拦截命令行里含正则 (\+)\d+ 的 -Command 调用：powershell 以退出码
REM  786 静默退出，pubspec.yaml 不会被修改（历史版本号漂移就是这么来的）。
if not exist "%~dp0bump_version.ps1" (
    echo [错误] 缺少版本号更新脚本: %~dp0bump_version.ps1
    echo        该脚本被误删过，可从 git 历史恢复:
    echo          git checkout b71b426 -- bump_version.ps1
    set "BUMP_FAILED=1"
    goto :eof
)
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0bump_version.ps1" -BuildNumber %BN% -Path "pubspec.yaml"
set "BUMP_EXIT=%ERRORLEVEL%"

REM ---- 回读校验：pubspec.yaml 的 build number 必须真的等于 %BN% ----
set "VER_CODE="
for /f "tokens=2 delims=+" %%n in ('findstr /c:"version: " pubspec.yaml') do set "VER_CODE=%%n"
if not "!VER_CODE!"=="%BN%" (
    echo [错误] pubspec.yaml 版本号未更新：期望 +%BN%，实际 +!VER_CODE!（PowerShell 退出码 !BUMP_EXIT!）
    echo        排查：build\build_full.log；或手动修改 pubspec.yaml 的 version: 行
    set "BUMP_FAILED=1"
    goto :eof
)

REM ---- 确认成功后才回写 .BUILD_NUM，避免两个版本号再次漂移 ----
echo %BN%> ".BUILD_NUM"

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

REM WMI 挂死是致命的：pub get 会永远不返回，所以这里必须先拦
REM 注意用 goto :eof 不是 goto :end —— :codegen 是被 call 进来的，
REM 在里面 goto :end 会让 :end 块执行两遍（build_exit.log 写两次 + 白等两个 60 秒）。
REM 这里只置 BUILD_FAILED，让调用方（:build）跳过 :save_state 1，
REM 真正的终止交给 :do_build 里的 preflight 检查。
call :preflight
if "!WMI_FAILED!"=="1" (
    set BUILD_FAILED=1
    goto :eof
)

echo.
echo ============================================
echo  代码生成 - %date% %time%
echo ============================================

echo [1/3] flutter pub get (verbose)...
echo       日志输出到: build\pub_get_codegen.log
echo       [提示] 首次下载依赖可能需要 2-5 分钟，请耐心等待...
echo       [看门狗] 日志连续 300 秒无增长即判定卡死并终止，不再无限期挂起
echo.
REM 走 build_pub_get.ps1 而不是直接 call flutter：直接调用时一旦 dart 卡在启动阶段，
REM 日志 0 字节、进程永不返回，构建就无声挂死。看门狗保证最坏 300 秒给结论。
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0build_pub_get.ps1" -Command "flutter pub get --verbose" -Log "build\pub_get_codegen.log" -IdleTimeoutSec 300
set PUB_EXIT=%ERRORLEVEL%
if !PUB_EXIT! equ 124 (
    echo [错误] pub get 判定卡死（日志 300 秒无增长），已终止进程树
    echo        最可能原因: WMI 无响应 → 重启机器；诊断: build_wmi_guard.ps1
    set BUILD_FAILED=1
    goto :eof
)
if !PUB_EXIT! neq 0 (
    echo [警告] pub get 失败！Exit code=!PUB_EXIT!
    echo       最后 20 行日志:
    powershell -NoProfile -Command "Get-Content 'build\pub_get_codegen.log' -Tail 20 -Encoding UTF8" 2>nul
    set BUILD_FAILED=1
    goto :eof
)
echo       pub get 完成。

echo [2/3] i18n 资源检查...
dir /b "lib\l10n\*.arb" >nul 2>&1
if errorlevel 1 (
    echo       [跳过] lib\l10n 下无 .arb 文件，文案为手写 Dart，无需 gen-l10n。
) else (
    call flutter gen-l10n 2>&1
    if errorlevel 1 (
        echo [警告] l10n 生成失败！不影响 build_runner
        set BUILD_FAILED=1
        REM 非致命：继续运行 build_runner
    ) else (
        echo       gen-l10n 完成。
    )
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
call :preflight
if "!WMI_FAILED!"=="1" (
    echo        [跳过] WMI 无响应，跳过 flutter clean（否则会挂死），只删本地文件
) else (
    call flutter clean 2>nul
)
if exist "privi-*.apk" del /q "privi-*.apk" 2>nul
if exist "privi-*.apk.sha256" del /q "privi-*.apk.sha256" 2>nul
if exist "*.aab" del /q "*.aab" 2>nul
rmdir /s /q ".dart_tool" 2>nul
rmdir /s /q "build" 2>nul
echo       清理完成。
del "%STATE_FILE%" 2>nul
goto :end

REM ============================================
REM  检查并安装缺失的 Android SDK 平台（利用代理加速）
REM ============================================
:ensure_sdk
set "SDKMANAGER=%ANDROID_HOME%\cmdline-tools\latest\bin\sdkmanager.bat"
if not exist "%SDKMANAGER%" (
    echo [SDK] sdkmanager 未找到，跳过平台检查
    goto :eof
)

REM 从 android/app/build.gradle.kts 和根 build.gradle.kts 中提取 compileSdk
set "SDK_PLATFORMS="
for /f "tokens=2 delims== " %%v in ('findstr /r "compileSdk\s*=" android\app\build.gradle.kts 2^>nul') do (
    set "TARGET_SDK=%%v"
    set "TARGET_SDK=!TARGET_SDK: =!"
    if defined TARGET_SDK (
        if not exist "%ANDROID_HOME%\platforms\android-!TARGET_SDK!" (
            set "SDK_PLATFORMS=!SDK_PLATFORMS! platforms;android-!TARGET_SDK!"
        ) else (
            echo [SDK] android-!TARGET_SDK! 已安装
        )
    )
)

if "%SDK_PLATFORMS%"=="" goto :eof

echo [SDK] 需要安装以下平台:%SDK_PLATFORMS%
for %%p in (%SDK_PLATFORMS%) do (
    echo       正在安装 %%p ...
    if "%PROXY_AVAILABLE%"=="1" (
        call "%SDKMANAGER%" --proxy=http --proxy_host=%PROXY_HOST% --proxy_port=%PROXY_PORT% "%%p"
    ) else (
        call "%SDKMANAGER%" "%%p"
    )
    if %ERRORLEVEL% neq 0 (
        echo [警告] SDK 平台安装失败: %%p
    ) else (
        echo       %%p 安装完成
    )
)
goto :eof

REM ============================================
REM  配置 Gradle 使用代理（动态写入 gradle.properties）
REM ============================================
:config_gradle_proxy
set "GRADLE_PROPS=android\gradle.properties"

REM 移除旧的代理配置（如果有）
if exist "%GRADLE_PROPS%" (
    powershell -NoProfile -Command ^
        "$lines = Get-Content '%GRADLE_PROPS%' -Encoding UTF8 | Where-Object { $_ -notmatch '^systemProp\.(http|https)\.proxy' }; " ^
        "[IO.File]::WriteAllLines((Resolve-Path '%GRADLE_PROPS%').Path, $lines, (New-Object Text.UTF8Encoding($false)))" 2>nul
)

if "%PROXY_AVAILABLE%"=="1" (
    echo.
    echo [代理] 配置 Gradle 代理: %PROXY_HOST%:%PROXY_PORT%
    echo systemProp.http.proxyHost=%PROXY_HOST%>> "%GRADLE_PROPS%"
    echo systemProp.http.proxyPort=%PROXY_PORT%>> "%GRADLE_PROPS%"
    echo systemProp.https.proxyHost=%PROXY_HOST%>> "%GRADLE_PROPS%"
    echo systemProp.https.proxyPort=%PROXY_PORT%>> "%GRADLE_PROPS%"
)
goto :eof

REM ============================================
REM  构建前内存检查：回收残留 JVM + 打印可用内存
REM ============================================
:reclaim_memory
if not exist "%~dp0build_mem.ps1" (
    echo [内存] 未找到 build_mem.ps1，跳过内存检查
    goto :eof
)
echo.
echo [内存] 回收残留 JVM 并检查可用内存...
REM 为什么需要这步：R8 全模式压缩（app/build.gradle.kts 里 isMinifyEnabled=true）时
REM JVM 申请的是"物理内存 + 页面文件"的提交内存，崩溃日志 android/hs_err_pid58400.log
REM 里那句 "TotalPageFile size 54340M (AvailPageFile size 23M)" 就是提交内存被榨干，
REM JVM 连 Chunk::new 的 1.5MB 都申请不到，Gradle 守护进程直接消失。
REM build_mem.ps1 用 kernel32!GlobalMemoryStatusEx 取内存（本机 WMI/jps/Get-Counter
REM 都会挂死，详见脚本头注释），-StopDaemons 只结束本机 JDK(%JAVA_HOME%) 启动、
REM 且启动超过 120 秒的 java 进程，不会动 VS Code / Android Studio 的 JVM。
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0build_mem.ps1" -JavaHome "%JAVA_HOME%" -StopDaemons
set "MEM_EXIT=%ERRORLEVEL%"
if not "%MEM_EXIT%"=="0" (
    echo [内存] 检查未完全成功 ^(exit=%MEM_EXIT%^)，继续构建...
)
goto :eof

REM ============================================
REM  定位 gh CLI（GitHub Release 发布用）
REM  优先使用外部预置的 GH_EXE（本机 gh 不在 PATH、或自测用假 gh 时），
REM  否则依次查 PATH / Program Files / 用户级安装目录。
REM  找不到时 GH_EXE 留空，由调用方决定是跳过还是报错（构建流程里是跳过）。
REM ============================================
:resolve_gh
if defined GH_EXE (
    if exist "!GH_EXE!" goto :eof
)
set "GH_EXE="
for /f "delims=" %%g in ('where gh 2^>nul') do if not defined GH_EXE set "GH_EXE=%%g"
if not defined GH_EXE if exist "%ProgramFiles%\GitHub CLI\gh.exe" set "GH_EXE=%ProgramFiles%\GitHub CLI\gh.exe"
if not defined GH_EXE if exist "%ProgramFiles(x86)%\GitHub CLI\gh.exe" set "GH_EXE=%ProgramFiles(x86)%\GitHub CLI\gh.exe"
if not defined GH_EXE if exist "%LOCALAPPDATA%\Programs\GitHub CLI\gh.exe" set "GH_EXE=%LOCALAPPDATA%\Programs\GitHub CLI\gh.exe"
if not defined GH_EXE if exist "%USERPROFILE%\scoop\shims\gh.exe" set "GH_EXE=%USERPROFILE%\scoop\shims\gh.exe"
goto :eof

REM ============================================
REM  从 origin 远端地址解析 owner/repo（仅用于打印 Release 链接）
REM  支持 git@github.com:owner/repo.git 与 https://github.com/owner/repo.git
REM ============================================
:resolve_repo_slug
set "RELEASE_SLUG="
set "REMOTE_URL="
for /f "delims=" %%u in ('git config --get remote.origin.url 2^>nul') do set "REMOTE_URL=%%u"
if not defined REMOTE_URL goto :eof
set "REMOTE_TAIL=!REMOTE_URL:*github.com:=!"
if "!REMOTE_TAIL!"=="!REMOTE_URL!" set "REMOTE_TAIL=!REMOTE_URL:*github.com/=!"
set "REMOTE_TAIL=!REMOTE_TAIL:.git=!"
for /f "tokens=1,2 delims=/" %%a in ("!REMOTE_TAIL!") do if not "%%b"=="" set "RELEASE_SLUG=%%a/%%b"
goto :eof

REM ============================================
REM  读取当前提交信息（Release 说明与 tag 目标用）
REM  注意: 不要用带 %%s 之类的 --format 串——写进 .bat 容易被 cmd 当变量展开；
REM        git log -1 --oneline 正好给出「短 sha + 标题」。
REM ============================================
:resolve_git_sha
set "GIT_SHA="
set "GIT_SHA_SHORT="
set "GIT_DESC="
set "GIT_BRANCH="
for /f "delims=" %%c in ('git rev-parse HEAD 2^>nul') do set "GIT_SHA=%%c"
for /f "delims=" %%c in ('git rev-parse --short HEAD 2^>nul') do set "GIT_SHA_SHORT=%%c"
for /f "delims=" %%c in ('git log -1 --oneline 2^>nul') do set "GIT_DESC=%%c"
for /f "delims=" %%c in ('git rev-parse --abbrev-ref HEAD 2^>nul') do set "GIT_BRANCH=%%c"
goto :eof

REM ============================================
REM  仅发布 Release（补发/重发：不重新构建，把根目录已有 APK 推到 GitHub Release）
REM  用法: build.bat release
REM ============================================
:release_only
echo.
echo ============================================
echo  发布 Release - %date% %time%
echo ============================================

set "NEW_VER="
if not exist "pubspec.yaml" (
    echo [错误] 未找到 pubspec.yaml，无法确定版本号
    set BUILD_FAILED=1
    goto :end
)
for /f "tokens=2 delims=: " %%v in ('findstr /c:"version: " pubspec.yaml') do set "NEW_VER=%%v"
if not defined NEW_VER (
    echo [错误] 无法从 pubspec.yaml 解析 version 行
    set BUILD_FAILED=1
    goto :end
)
set "APK_DEST=privi-!NEW_VER!.apk"
if not exist "!APK_DEST!" (
    echo [错误] 未找到 !APK_DEST! ^(pubspec 当前版本: !NEW_VER!^)
    echo        先构建一次再补发: build.bat 或 build.bat fast
    echo        根目录现有 APK:
    dir /b "privi-*.apk" 2>nul
    set BUILD_FAILED=1
    goto :end
)
call :publish_release
goto :end

REM ============================================
REM  发布 GitHub Release（gh CLI）
REM  APK 已在项目根目录时调用。缺少 gh / 未登录 / 显式跳过时只打印原因并返回，
REM  不改变 BUILD_FAILED——发布失败不该把「已经编好的 APK」变成构建失败。
REM ============================================
:publish_release
echo.
echo ============================================
echo  发布 GitHub Release
echo ============================================
set "STEP_NAME=发布 GitHub Release"

if "!SKIP_RELEASE!"=="1" (
    echo       [跳过] 已通过 norelease 或 SKIP_RELEASE=1 关闭自动发布
    goto :eof
)
if not exist "!APK_DEST!" (
    echo       [跳过] 未找到待发布文件: !APK_DEST!
    goto :eof
)

call :resolve_gh
if not defined GH_EXE (
    echo       [跳过] 未找到 gh CLI，无法自动发布。安装方式:
    echo              winget install --id GitHub.cli
    echo        装好后执行 build.bat release 即可补发，无需重新编译。
    goto :eof
)
echo       gh: !GH_EXE!

call "%GH_EXE%" auth status >nul 2>&1
if !ERRORLEVEL! neq 0 (
    echo       [跳过] gh 未登录，无法自动发布。先登录一次:
    echo              gh auth login
    goto :eof
)

call :resolve_repo_slug
call :resolve_git_sha

REM 仅允许 main 分支发布 Release，其他分支（如 dev）构建完跳过发布
if /i not "!GIT_BRANCH!"=="main" (
    echo       [跳过] 当前分支 !GIT_BRANCH! 不是 main，Release 仅允许从 main 分支发布
    goto :eof
)

set "RELEASE_TAG=v!NEW_VER!"
set "RELEASE_TITLE=密册 v!NEW_VER!"
REM 显式指定仓库：gh 默认靠本地 git 远端自动识别，实测偶发「No default remote repository」
REM 解析不出 slug 时留空，退回 gh 自动识别，行为与之前一致
set "REL_REPO_ARG="
if defined RELEASE_SLUG set "REL_REPO_ARG=--repo !RELEASE_SLUG!"

REM ---- SHA-256 校验和资产（与上游 Release 的 privi-<版本>.apk.sha256 同名）----
REM 哈希逻辑放在 build_hash.ps1 里用 -File 调用，原因见该脚本头注释。
set "APK_SHA="
for /f "usebackq delims=" %%h in (`powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0build_hash.ps1" -Kind file -Path "!APK_DEST!" 2^>nul`) do set "APK_SHA=%%h"
if not defined APK_SHA (
    echo       [跳过] 计算 SHA-256 失败；为保证产物可校验，本次不发布
    goto :eof
)
> "!APK_DEST!.sha256" echo !APK_SHA!
echo       校验和: !APK_SHA!

REM ---- Release 说明：可选的项目根 release_notes.md + 自动追加的元信息 ----
set "NOTES_FILE=build\release_notes_!NEW_VER!.md"
if exist "%~dp0release_notes.md" (
    copy /y "%~dp0release_notes.md" "!NOTES_FILE!" >nul 2>&1
    echo       说明文件: release_notes.md + 自动元信息
) else (
    > "!NOTES_FILE!" echo # 密册 v!NEW_VER!
)

REM 提交标题里的 < > & | 在 bat 的 echo 块里是特殊字符，先替换掉（完整提交信息在 GitHub 上可查）
set "GIT_DESC=!GIT_DESC:<=!"
set "GIT_DESC=!GIT_DESC:>=!"
set "GIT_DESC=!GIT_DESC:&=!"
set "GIT_DESC=!GIT_DESC:|=!"

set "SIGN_NOTE=release 密钥"
if not exist "android\key.properties" set "SIGN_NOTE=debug 密钥——本机没有 android/key.properties，与官方 Release 签名不同，覆盖安装会报签名冲突"
for %%f in ("!APK_DEST!") do set "APK_SIZE=%%~zf"
(
    echo.
    echo ---
    echo.
    echo - 版本: !NEW_VER!
    echo - 构建时间: %DATE% %TIME%
    echo - 提交: !GIT_DESC!
    echo - 分支: !GIT_BRANCH!
    echo - 产物: !APK_DEST! ^(!APK_SIZE! 字节^)
    echo - SHA-256: !APK_SHA!
    echo - 签名: !SIGN_NOTE!
    echo.
    echo 安装: 下载 !APK_DEST! 侧载安装，系统要求 Android 8.0+。
    echo 校验: 同一 Release 里的 !APK_DEST!.sha256 给出该 APK 的 SHA-256。
    echo 校验命令 ^(PowerShell^): Get-FileHash -Algorithm SHA256 .\!APK_DEST!
) >> "!NOTES_FILE!"

REM ---- 同版本已发过则更新资产与说明，否则新建 Release ----
set "REL_EXISTS=0"
call "%GH_EXE%" release view "!RELEASE_TAG!" !REL_REPO_ARG! >nul 2>&1
if !ERRORLEVEL! equ 0 set "REL_EXISTS=1"

if "!REL_EXISTS!"=="1" (
    echo       已存在 !RELEASE_TAG!，更新 APK 与说明...
    call "%GH_EXE%" release upload "!RELEASE_TAG!" "!APK_DEST!" "!APK_DEST!.sha256" --clobber !REL_REPO_ARG!
    set "REL_EXIT=!ERRORLEVEL!"
    if "!REL_EXIT!"=="0" call "%GH_EXE%" release edit "!RELEASE_TAG!" --title "!RELEASE_TITLE!" --notes-file "!NOTES_FILE!" --latest !REL_REPO_ARG!
) else (
    echo       创建 Release !RELEASE_TAG! ^(tag 指向 !GIT_SHA_SHORT!^)...
    call "%GH_EXE%" release create "!RELEASE_TAG!" "!APK_DEST!" "!APK_DEST!.sha256" --title "!RELEASE_TITLE!" --notes-file "!NOTES_FILE!" --latest --target !GIT_SHA! !REL_REPO_ARG!
    set "REL_EXIT=!ERRORLEVEL!"
)

if "!REL_EXIT!"=="0" (
    echo.
    echo ============================================
    echo  Release 已发布: !RELEASE_TAG!
    if defined RELEASE_SLUG echo        页面: https://github.com/!RELEASE_SLUG!/releases/tag/!RELEASE_TAG!
    if defined RELEASE_SLUG echo        最新: https://github.com/!RELEASE_SLUG!/releases/latest
    echo ============================================
) else (
    echo.
    echo [警告] Release 发布失败 ^(exit=!REL_EXIT!^)，APK 仍在本地: !APK_DEST!
    echo        - 提交还没 git push 时新建 tag 会失败: 先 git push，再 build.bat release
    echo        - 权限不足时确认 gh auth status 的 token 有 repo scope
    echo        - 同版本重发走 upload --clobber，不会因 tag 已存在而失败
)
goto :eof

REM ============================================
REM  快速构建（跳过代码生成）
REM ============================================
:fast
goto :do_build

REM ============================================
REM  仅 Gradle 编译（调试用，跳过所有前置步骤）
REM ============================================
:gradle_only
call :checkenv
if "%BUILD_FAILED%"=="1" goto :end

REM WMI 挂死时 flutter build apk 会静默挂死，先拦
call :preflight
if "!WMI_FAILED!"=="1" goto :end

echo.
echo ============================================
echo  [调试模式] 仅 Gradle 编译 - %date% %time%
echo ============================================

set "STEP_NAME=[调试] flutter build apk"

REM 检查并安装缺失的 SDK 平台
call :ensure_sdk

REM 配置 Gradle 代理
call :config_gradle_proxy

REM 内存检查：回收残留 JVM，避免 R8 压缩阶段提交内存不足
call :reclaim_memory

REM 先删掉上次构建留下的 APK：否则本次编译失败时，"产物已存在" 会被误判成构建成功
set "APK_SOURCE=build\app\outputs\flutter-apk\app-release.apk"
if exist "!APK_SOURCE!" del /q "!APK_SOURCE!" 2>nul

call flutter build apk --release
set BUILD_EXIT=%ERRORLEVEL%

if !BUILD_EXIT! neq 0 (
    echo ============================================
    echo  [警告] 构建失败！Flutter exit code=!BUILD_EXIT!
    echo ============================================
    set BUILD_FAILED=1
) else if not exist "!APK_SOURCE!" (
    echo ============================================
    echo  [警告] 构建失败！未找到构建产物
    echo        预期路径: !APK_SOURCE!
    echo ============================================
    set BUILD_FAILED=1
) else (
    echo ============================================
    echo  构建成功！
    echo ============================================
    for %%f in ("!APK_SOURCE!") do echo  APK: %%~nxf  ^(%%~zf bytes^)
)
goto :end

REM ============================================
REM  完整构建流程（支持断点续传）
REM ============================================
:build
call :load_state

echo.
echo ============================================
echo  Privi 构建 - %date% %time%
echo ============================================

if !RESUME_STEP! leq 0 (
    echo [1/7] 代码生成...
    set "STEP_NAME=[1/7] 代码生成"
    call :codegen
    REM 必须用 !BUILD_FAILED! 而不是 %BUILD_FAILED%：整块是在 call :codegen 之前
    REM 一次性解析的，%...% 会取到调用前的旧值（永远是 0），于是把失败当成功、
    REM 错误地 :save_state 1（下次构建就会跳过代码生成）。
    if "!BUILD_FAILED!"=="1" (
        echo [警告] 代码生成阶段出现问题，但尝试继续后续步骤...
    ) else (
        call :save_state 1
    )
) else (
    echo [断点续传] 跳过步骤1^(代码生成^)，已完成
)

:do_build
echo.
echo ============================================
echo  Privi 构建 - %date% %time%
echo ============================================

REM WMI 自检：断点续传/fast 模式会跳过步骤1，这里是最后一道拦截点
call :preflight
if "!WMI_FAILED!"=="1" goto :end

REM 内存检查放在最前面：既回收上次崩溃留下的守护进程，也让日志留下构建起点的
REM 可用内存快照（崩溃后可以和 hs_err_pid*.log 对照排查）
call :reclaim_memory

REM 步骤2: 递增版本号（每次构建都需要）
echo [2/7] 递增版本号...
set "STEP_NAME=[2/7] 递增版本号"
call :increment_version
if "!BUMP_FAILED!"=="1" (
    set "BUILD_FAILED=1"
    goto :end
)
if "%BUILD_FAILED%"=="0" call :save_state 2

REM 步骤3: flutter clean
if !RESUME_STEP! lss 3 (
    echo.
    echo [3/7] flutter clean...
    set "STEP_NAME=[3/7] flutter clean"
    call flutter clean 2>nul
    if %ERRORLEVEL% neq 0 (
        echo [警告] flutter clean 未完全成功，继续...
    )
    echo       完成。
    call :save_state 3
) else (
    echo [断点续传] 跳过步骤3^(clean^)，已完成
)

REM flutter clean 会删除 build/ 目录，重建它以支持后续日志重定向
if not exist "build" mkdir "build" 2>nul

REM 步骤4: flutter pub get
if !RESUME_STEP! lss 4 (
    echo.
    echo [4/7] flutter pub get ^(verbose^)...
    echo       日志输出到: build\pub_get_build.log
    echo       [提示] 如果 codegen 阶段已成功，这步会很快...
    echo       [看门狗] 日志连续 300 秒无增长即判定卡死并终止，不再无限期挂起
    echo.
    set "STEP_NAME=[4/7] flutter pub get"
    powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0build_pub_get.ps1" -Command "flutter pub get --verbose" -Log "build\pub_get_build.log" -IdleTimeoutSec 300
    set PUB_EXIT=%ERRORLEVEL%
    if !PUB_EXIT! equ 124 (
        echo [错误] pub get 判定卡死（日志 300 秒无增长），已终止进程树
        echo        最可能原因: WMI 无响应 → 重启机器；诊断: build_wmi_guard.ps1
        set BUILD_FAILED=1
        goto :end
    )
    if !PUB_EXIT! neq 0 (
        echo [警告] pub get 失败！Exit code=!PUB_EXIT!
        echo       最后 20 行日志:
        powershell -NoProfile -Command "Get-Content 'build\pub_get_build.log' -Tail 20 -Encoding UTF8" 2>nul
        set BUILD_FAILED=1
        goto :end
    )
    echo       pub get 完成。
    call :save_state 4
) else (
    echo [断点续传] 跳过步骤4^(pub get^)，已完成
)

REM 步骤5: flutter build apk
if !RESUME_STEP! lss 5 (
    echo.
    echo [5/7] 编译 Release APK（请耐心等待，首次约 5-10 分钟）...
    set "STEP_NAME=[5/7] flutter build apk"

    call :ensure_sdk
    call :config_gradle_proxy

    REM R8 压缩是整条流水线里内存峰值最高的一步，编译前再回收一次残留 JVM
    call :reclaim_memory

    call flutter build apk --release
    set BUILD_EXIT=%ERRORLEVEL%

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
    if !BUILD_EXIT! neq 0 (
        echo.
        echo ============================================
        echo  [警告] 构建失败！Flutter exit code=!BUILD_EXIT!
        echo        即使目录里还留着旧 APK，也按失败处理
        echo ============================================
        set BUILD_FAILED=1
        goto :end
    )
    call :save_state 5
) else (
    echo [断点续传] 跳过步骤5^(编译APK^)，已完成
    set "APK_SOURCE=build\app\outputs\flutter-apk\app-release.apk"
)

echo.
echo ============================================
echo  构建成功！
echo ============================================

echo [6/7] 复制 APK 到项目根目录...
set "STEP_NAME=[6/7] 复制 APK"
if exist "privi-*.apk" del /q "privi-*.apk" 2>nul
if exist "privi-*.apk.sha256" del /q "privi-*.apk.sha256" 2>nul
set "APK_DEST=privi-%NEW_VER%.apk"
copy /y "!APK_SOURCE!" "!APK_DEST!" > nul 2>&1
for %%f in ("!APK_DEST!") do echo  APK: %%~nxf  (%%~zf bytes)

echo.
echo  APK 已复制到项目根目录。
call :save_state 6

REM 步骤7: 发布 GitHub Release（gh CLI）
REM 缺少 gh / gh 未登录 / 指定 norelease 时，:publish_release 内部只打印原因并跳过，
REM 不会把已经编好的 APK 判成构建失败。
echo.
echo [7/7] 发布 GitHub Release...
call :publish_release
goto :end

REM ============================================
REM  统一出口：永远 pause，让用户看到结果
REM ============================================
:end
REM 写入诊断文件，确认脚本走到了 :end
REM WMI_FAILED 一并落盘：后续排查"卡住不动"时，这个字段能直接区分
REM "WMI 挂死被拦下" 和 "真的编译失败"。
echo %date% %time% BUILD_FAILED=%BUILD_FAILED% WMI_FAILED=%WMI_FAILED% NEW_VER=%NEW_VER% > build\build_exit.log 2>nul
echo.
echo ============================================
if "%BUILD_FAILED%"=="1" (
    echo  构建过程有错误/警告，请查看上方日志
) else (
    echo  构建流程结束
)
echo ============================================
REM WMI 挂死是最常见的"卡住不动"根因，单独再提示一次，避免用户翻日志
if "!WMI_FAILED!"=="1" (
    echo.
    echo  [根因] WMI 无响应 → 所有 flutter 命令都会静默挂死
    echo  [处理] 重启机器；或管理员执行 winmgmt /resetrepository
    echo  [复现] powershell -NoProfile -ExecutionPolicy Bypass -File build_wmi_guard.ps1
)
echo.
echo 窗口将在 60 秒后自动关闭，或按任意键立即关闭...
timeout /t 60 > nul
exit /b %BUILD_FAILED%