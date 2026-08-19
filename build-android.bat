@echo off
chcp 65001 >nul 2>&1
title 远程控制 - 构建 Android APK
color 0A

echo.
echo  ╔══════════════════════════════════════╗
echo  ║     远程控制 - Android APK 构建器     ║
echo  ╚══════════════════════════════════════╝
echo.

:: ─── 检查 Flutter ───
where flutter >nul 2>&1
if %ERRORLEVEL% neq 0 (
    echo  [错误] 未检测到 Flutter SDK
    echo.
    echo  请先安装 Flutter:
    echo    下载地址: https://docs.flutter.dev/get-started/install
    echo    或使用: git clone https://github.com/flutter/flutter.git -b stable
    echo.
    echo  安装完成后，确保 flutter 命令在 PATH 中。
    echo.
    pause
    exit /b 1
)

for /f "tokens=1-2" %%a in ('flutter --version ^| findstr "Flutter"') do set FLUTTER_VER=%%c
echo  [OK] Flutter %FLUTTER_VER%

:: ─── 检查 Java/Android SDK ───
where java >nul 2>&1
if %ERRORLEVEL% neq 0 (
    echo  [警告] 未检测到 Java，请确保已安装 Android Studio
    echo         或已配置 JAVA_HOME 环境变量
)

:: ─── 进入项目根目录 ───
cd /d "%~dp0"
echo.
echo  [1/3] 获取 Flutter 依赖...
call flutter pub get
if %ERRORLEVEL% neq 0 (
    echo  [错误] 依赖获取失败
    pause
    exit /b 1
)
echo  [OK] 依赖就绪

echo.
echo  [2/3] 构建 Release APK...
echo  （首次构建可能需要 3-5 分钟，请耐心等待）
echo.
call flutter build apk --release
if %ERRORLEVEL% neq 0 (
    echo.
    echo  [错误] 构建失败，请检查:
    echo    1. 是否已安装 Android SDK
    echo    2. 是否已接受 Android licenses: flutter doctor --android-licenses
    echo    3. 是否已安装 JDK 11+
    echo.
    pause
    exit /b 1
)

echo.
echo  [3/3] 复制 APK 到项目目录...
set APK_SRC=build\app\outputs\flutter-apk\app-release.apk
set APK_DST=release\remote-control.apk

if not exist "release\" mkdir release
copy /Y "%APK_SRC%" "%APK_DST%" >nul

echo.
echo  ╔══════════════════════════════════════╗
echo  ║         构建成功!                     ║
echo  ╠══════════════════════════════════════╣
echo  ║                                      ║
echo  ║  APK 位置: release\remote-control.apk  ║
echo  ║                                      ║
echo  ║  将 APK 传到手机上安装即可使用          ║
echo  ║  首次打开需在设置中配置服务器地址        ║
echo  ║                                      ║
echo  ╚══════════════════════════════════════╝
echo.

pause
