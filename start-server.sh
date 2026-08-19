#!/bin/bash
# 远程控制 - 启动中继服务器 (Linux/macOS)

echo ""
echo "  ╔══════════════════════════════════════╗"
echo "  ║     远程控制 - 中继服务器启动器        ║"
echo "  ╚══════════════════════════════════════╝"
echo ""

# 检查 Node.js
if ! command -v node &> /dev/null; then
    echo "  [错误] 未检测到 Node.js"
    echo ""
    echo "  安装方法:"
    echo "    Ubuntu/Debian: sudo apt install nodejs npm"
    echo "    macOS:         brew install node"
    echo "    或访问:        https://nodejs.org/"
    echo ""
    exit 1
fi

echo "  [OK] Node.js $(node --version)"
echo "  [OK] npm v$(npm --version)"
echo ""

# 进入 server 目录
cd "$(dirname "$0")/server"

# 安装依赖
if [ ! -d "node_modules" ]; then
    echo "  [安装] 正在安装服务器依赖..."
    npm install --production
    if [ $? -ne 0 ]; then
        echo "  [错误] 依赖安装失败"
        exit 1
    fi
    echo "  [OK] 依赖安装完成"
    echo ""
fi

# 启动服务器
echo "  ── 启动服务器 ──"
echo ""
npm start
