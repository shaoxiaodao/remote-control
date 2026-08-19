#!/bin/bash
# 远程控制 - 构建 Android APK (Linux/macOS)

echo ""
echo "  ╔══════════════════════════════════════╗"
echo "  ║     远程控制 - Android APK 构建器     ║"
echo "  ╚══════════════════════════════════════╝"
echo ""

# 检查 Flutter
if ! command -v flutter &> /dev/null; then
    echo "  [错误] 未检测到 Flutter SDK"
    echo ""
    echo "  安装方法: https://docs.flutter.dev/get-started/install"
    exit 1
fi

echo "  [OK] $(flutter --version | head -1)"
echo ""

# 进入项目根目录
cd "$(dirname "$0")"

echo "  [1/3] 获取 Flutter 依赖..."
flutter pub get
if [ $? -ne 0 ]; then
    echo "  [错误] 依赖获取失败"
    exit 1
fi

echo ""
echo "  [2/3] 构建 Release APK..."
echo "  （首次构建可能需要 3-5 分钟）"
echo ""
flutter build apk --release
if [ $? -ne 0 ]; then
    echo ""
    echo "  [错误] 构建失败，请检查:"
    echo "    1. 是否已安装 Android SDK"
    echo "    2. flutter doctor --android-licenses"
    echo "    3. JDK 11+ 是否已安装"
    exit 1
fi

echo ""
echo "  [3/3] 复制 APK..."
mkdir -p release
cp build/app/outputs/flutter-apk/app-release.apk release/remote-control.apk

echo ""
echo "  ╔══════════════════════════════════════╗"
echo "  ║         构建成功!                     ║"
echo "  ╠══════════════════════════════════════╣"
echo "  ║  APK: release/remote-control.apk      ║"
echo "  ║  传到手机安装即可使用                   ║"
echo "  ╚══════════════════════════════════════╝"
echo ""
