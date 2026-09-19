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
REM  用法: 双击运行            (完整构建 + 递增版本)
REM        build codegen       (仅代码生成)
REM        build clean         (清理构建产物)
REM        build fast          (构建但跳过代码生成)
REM        build gradle        (仅 Gradle 编译，调试用)
REM ============================================

REM ---- 全局状态变量 ----
set "BUILD_FAILED=0"
set "BUMP_FAILED=0"
set "STEP_NAME="
set "RESUME_STEP=0"

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
REM ============================================
set "STATE_FILE=build\.build_state"

REM 计算代码生成相关文件的哈希
:calc_hash_codegen
set "HASH_CODE_GEN="
powershell -NoProfile -Command ^
    "$files = @(Get-ChildItem 'lib' -Recurse -File -Include '*.dart','*.yaml' -ErrorAction SilentlyContinue ^| Sort FullName); " ^
    "$hash = ($files.ForEach({ (Get-FileHash $_.FullName -Algorithm MD5).Hash }) + " ^
             "(Get-FileHash 'pubspec.yaml' -Algorithm MD5 -ErrorAction SilentlyContinue).Hash + " ^
             "(Get-FileHash 'pubspec.lock' -Algorithm MD5 -ErrorAction SilentlyContinue).Hash + " ^
             "(Get-FileHash 'build.yaml' -Algorithm MD5 -ErrorAction SilentlyContinue).Hash) -join ''; " ^
    "$bytes = [Text.Encoding]::UTF8.GetBytes($hash); " ^
    "$md5 = [Security.Cryptography.MD5]::Create().ComputeHash($bytes); " ^
    "Write-Output ([BitConverter]::ToString($md5) -replace '-','')" > build\_hash_codegen.tmp 2>nul
if exist "build\_hash_codegen.tmp" (
    set /p HASH_CODE_GEN=<build\_hash_codegen.tmp
    del build\_hash_codegen.tmp 2>nul
)
goto :eof

REM 计算 Gradle 配置文件的哈希
:calc_hash_gradle
set "HASH_GRADLE="
powershell -NoProfile -Command ^
    "$files = @('android\build.gradle.kts','android\app\build.gradle.kts','android\settings.gradle.kts','android\gradle.properties'); " ^
    "$hash = ($files.ForEach({ (Get-FileHash $_ -Algorithm MD5 -ErrorAction SilentlyContinue).Hash })) -join ''; " ^
    "$bytes = [Text.Encoding]::UTF8.GetBytes($hash); " ^
    "$md5 = [Security.Cryptography.MD5]::Create().ComputeHash($bytes); " ^
    "Write-Output ([BitConverter]::ToString($md5) -replace '-','')" > build\_hash_gradle.tmp 2>nul
if exist "build\_hash_gradle.tmp" (
    set /p HASH_GRADLE=<build\_hash_gradle.tmp
    del build\_hash_gradle.tmp 2>nul
)
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
set "RESUME_STEP=%SAVED_STEP%"
echo [断点续传] 上次完成到第 !RESUME_STEP! 步，继续执行
goto :eof

REM 保存当前步骤到状态文件
:save_state
set "SAVE_NUM=%~1"
(
    echo SAVED_STEP=!SAVE_NUM!
    echo HASH_CODE_GEN=!HASH_CODE_GEN!
    echo HASH_GRADLE=!HASH_GRADLE!
) > "%STATE_FILE%"
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
set /a BN=B+1 2>nul
if not defined BN set /a BN=1
set "NEW_BUILD_NUM=%BN%"

REM ---- 更新 pubspec.yaml：只替换 + 号后面的数字，不动版本名 ----
REM  必须用 -File 调脚本，不能用 powershell -Command 一行式！
REM  本机安全策略会拦截命令行里含正则 (\+)\d+ 的 -Command 调用：powershell 以退出码
REM  786 静默退出，pubspec.yaml 不会被修改（历史版本号漂移就是这么来的）。
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

echo.
echo ============================================
echo  [调试模式] 仅 Gradle 编译 - %date% %time%
echo ============================================

set "STEP_NAME=[调试] flutter build apk"

REM 检查并安装缺失的 SDK 平台
call :ensure_sdk

REM 配置 Gradle 代理
call :config_gradle_proxy

call flutter build apk --release
set BUILD_EXIT=%ERRORLEVEL%

set "APK_SOURCE=build\app\outputs\flutter-apk\app-release.apk"
if not exist "!APK_SOURCE!" (
    echo ============================================
    echo  [警告] 构建失败！Flutter exit code=!BUILD_EXIT!
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
    echo [1/6] 代码生成...
    set "STEP_NAME=[1/6] 代码生成"
    call :codegen
    if "%BUILD_FAILED%"=="1" (
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

REM 步骤2: 递增版本号（每次构建都需要）
echo [2/6] 递增版本号...
set "STEP_NAME=[2/6] 递增版本号"
call :increment_version
if "!BUMP_FAILED!"=="1" (
    set "BUILD_FAILED=1"
    goto :end
)
if "%BUILD_FAILED%"=="0" call :save_state 2

REM 步骤3: flutter clean
if !RESUME_STEP! lss 3 (
    echo.
    echo [3/6] flutter clean...
    set "STEP_NAME=[3/6] flutter clean"
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
    echo [4/6] flutter pub get ^(verbose^)...
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
    call :save_state 4
) else (
    echo [断点续传] 跳过步骤4^(pub get^)，已完成
)

REM 步骤5: flutter build apk
if !RESUME_STEP! lss 5 (
    echo.
    echo [5/6] 编译 Release APK（请耐心等待，首次约 5-10 分钟）...
    set "STEP_NAME=[5/6] flutter build apk"

    call :ensure_sdk
    call :config_gradle_proxy

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
    call :save_state 5
) else (
    echo [断点续传] 跳过步骤5^(编译APK^)，已完成
    set "APK_SOURCE=build\app\outputs\flutter-apk\app-release.apk"
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
call :save_state 6
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