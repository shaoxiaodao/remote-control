@echo off
chcp 65001 >nul 2>&1
title 远程控制 - 启动中继服务器
color 0B

echo.
echo  ╔══════════════════════════════════════╗
echo  ║     远程控制 - 中继服务器启动器        ║
echo  ╚══════════════════════════════════════╝
echo.

:: ─── 检查 Node.js ───
where node >nul 2>&1
if %ERRORLEVEL% neq 0 (
    echo  [错误] 未检测到 Node.js
    echo.
    echo  请先安装 Node.js:
    echo    下载地址: https://nodejs.org/
    echo    推荐 LTS 版本 (18+)
    echo.
    echo  安装完成后重新运行此脚本。
    echo.
    pause
    exit /b 1
)

for /f "tokens=*" %%i in ('node --version') do set NODE_VER=%%i
echo  [OK] Node.js %NODE_VER%
for /f "tokens=*" %%i in ('npm --version') do set NPM_VER=%%i
echo  [OK] npm v%NPM_VER%
echo.

:: ─── 进入 server 目录 ───
cd /d "%~dp0server"

:: ─── 检查 node_modules ───
if not exist "node_modules\" (
    echo  [安装] 正在安装服务器依赖...
    echo.
    call npm install --production
    if %ERRORLEVEL% neq 0 (
        echo.
        echo  [错误] 依赖安装失败，请检查网络连接
        pause
        exit /b 1
    )
    echo.
    echo  [OK] 依赖安装完成
    echo.
) else (
    echo  [OK] 依赖已就绪
    echo.
)

:: ─── 显示本机 IP ───
echo  ── 本机网络信息 ──
for /f "tokens=2 delims=:" %%a in ('ipconfig ^| findstr /c:"IPv4"') do (
    echo    IP: %%a
)
echo.
echo  ── 启动服务器 ──
echo  启动后，将显示的 IP 地址填入手机 App 设置中
echo.
echo  ══════════════════════════════════════
echo.

:: ─── 启动服务器 ───
call npm start

pause
