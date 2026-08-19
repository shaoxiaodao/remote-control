/**
 * 远程控制中继服务器 (Relay Server)
 *
 * 职责：
 * 1. WebSocket 连接管理（设备注册、心跳）
 * 2. 信令路由（连接请求/接受/拒绝）
 * 3. 数据转发（屏幕帧、控制命令）
 * 4. 在线设备列表维护
 *
 * 架构：
 *   [控制端手机] ←→ WebSocket ←→ [中继服务器] ←→ WebSocket ←→ [被控端手机]
 *
 * 部署：
 *   npm install
 *   npm start          # 生产模式
 *   npm run dev        # 开发模式（自动重启）
 */

const http = require('http');
const os = require('os');
const { WebSocketServer } = require('ws');
const { DeviceManager } = require('./deviceManager');
const { SessionManager } = require('./sessionManager');

// ─── 配置 ───
const PORT = process.env.PORT || 8080;
const HOST = process.env.HOST || '0.0.0.0';
const HEARTBEAT_INTERVAL = 30000; // 30 秒心跳检查
const DEVICE_TIMEOUT = 60000;     // 60 秒无心跳视为离线

// ─── 创建 HTTP 服务器 ───
const server = http.createServer((req, res) => {
    // 健康检查端点
    if (req.url === '/health') {
        res.writeHead(200, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify({
            status: 'ok',
            devices: deviceManager.getOnlineCount(),
            sessions: sessionManager.getActiveCount(),
            uptime: process.uptime(),
        }));
        return;
    }

    // API: 获取在线设备列表
    if (req.url === '/api/devices') {
        res.writeHead(200, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify({
            devices: deviceManager.getDeviceList(),
        }));
        return;
    }

    res.writeHead(404);
    res.end('Not Found');
});

// ─── WebSocket 服务器 ───
const wss = new WebSocketServer({
    server,
    path: '/ws',
    maxPayload: 2 * 1024 * 1024, // 单条消息最大 2MB
});

// ─── 管理器实例 ───
const deviceManager = new DeviceManager();
const sessionManager = new SessionManager();

// 追踪已处理的断连，防止双重触发
const handledDisconnects = new Set();

// ─── 安全发送（防止 ws.send 在关闭的 socket 上抛异常导致服务器崩溃） ───
function safeSend(ws, data) {
    try {
        if (ws && ws.readyState === 1 /* WebSocket.OPEN */) {
            const payload = typeof data === 'string' ? data : JSON.stringify(data);
            ws.send(payload);
            return true;
        }
    } catch (e) {
        console.error('[SafeSend] Send failed:', e.message);
    }
    return false;
}

// ─── 心跳检查定时器 ───
const heartbeatTimer = setInterval(() => {
    const now = Date.now();
    const staleDevices = deviceManager.getStaleDevices(now - DEVICE_TIMEOUT);

    for (const deviceId of staleDevices) {
        console.log(`[Heartbeat] Device ${deviceId} timed out, removing`);
        const ws = deviceManager.getDeviceSocket(deviceId);
        if (ws && ws.readyState === 1 /* OPEN */) {
            ws.close(4000, 'heartbeat timeout');
        }
        handleDeviceDisconnect(deviceId);
    }
}, HEARTBEAT_INTERVAL);

// ─── WebSocket 连接处理 ───
wss.on('connection', (ws, req) => {
    const clientIp = req.headers['x-forwarded-for'] || req.socket.remoteAddress;
    let deviceId = null;

    console.log(`[Connect] New connection from ${clientIp}`);

    ws.on('message', (rawData) => {
        try {
            const data = JSON.parse(rawData.toString());
            handleMessage(ws, data, deviceId, (newId) => { deviceId = newId; });
        } catch (e) {
            console.error('[Error] Invalid JSON:', e.message);
            safeSend(ws, {
                type: 'error',
                message: 'Invalid JSON message',
            });
        }
    });

    ws.on('close', (code, reason) => {
        if (deviceId) {
            console.log(`[Disconnect] Device ${deviceId} disconnected (code: ${code})`);
            handleDeviceDisconnect(deviceId);
        }
    });

    ws.on('error', (err) => {
        console.error(`[Error] WebSocket error for ${deviceId || 'unknown'}:`, err.message);
    });

    // 发送欢迎消息
    safeSend(ws, {
        type: 'welcome',
        message: 'Connected to Remote Control Relay Server',
        serverTime: Date.now(),
    });
});

// ─── 消息处理 ───
function handleMessage(ws, data, currentDeviceId, setDeviceId) {
    const { type } = data;

    switch (type) {
        // ═══ 设备注册 ═══
        case 'register': {
            const id = data.deviceId;
            if (!id) {
                safeSend(ws, { type: 'error', message: 'deviceId required' });
                return;
            }

            // 注册设备
            deviceManager.registerDevice(id, ws, {
                platform: data.platform || 'unknown',
                osVersion: data.osVersion || '',
            });
            setDeviceId(id);

            console.log(`[Register] Device ${id} registered`);

            // 回复注册成功
            safeSend(ws, {
                type: 'registered',
                deviceId: id,
                serverTime: Date.now(),
            });

            // 广播设备上线
            broadcastDeviceStatus(id, 'online');

            // 发送当前在线设备列表
            safeSend(ws, {
                type: 'device_list',
                devices: deviceManager.getDeviceList(id), // 排除自己
            });
            break;
        }

        // ═══ 心跳 ═══
        case 'ping': {
            deviceManager.updateHeartbeat(currentDeviceId);
            safeSend(ws, {
                type: 'pong',
                timestamp: data.timestamp || Date.now(),
                serverTime: Date.now(),
            });
            break;
        }

        // ═══ 请求连接 ═══
        case 'request_connect': {
            const targetId = data.targetId;
            const targetWs = deviceManager.getDeviceSocket(targetId);

            if (!targetWs || targetWs.readyState !== 1 /* OPEN */) {
                safeSend(ws, {
                    type: 'error',
                    message: `Device ${targetId} is not online`,
                });
                return;
            }

            // 检查是否已有活跃会话
            if (sessionManager.hasActiveSession(targetId)) {
                safeSend(ws, {
                    type: 'connect_rejected',
                    reason: '设备正在被其他设备控制',
                });
                return;
            }

            // 转发连接请求到目标设备
            const deviceInfo = deviceManager.getDeviceInfo(currentDeviceId);
            safeSend(targetWs, {
                type: 'request_connect',
                fromId: currentDeviceId,
                fromName: deviceInfo?.deviceName || 'Unknown',
            });

            console.log(`[Connect] ${currentDeviceId} → request_connect → ${targetId}`);
            break;
        }

        // ═══ 接受连接 ═══
        case 'connect_accepted': {
            const targetId = data.targetId;
            const targetWs = deviceManager.getDeviceSocket(targetId);

            if (!targetWs) return;

            // 创建会话
            const sessionId = sessionManager.createSession(currentDeviceId, targetId);

            // 通知控制端连接已建立
            safeSend(targetWs, {
                type: 'connect_accepted',
                fromId: currentDeviceId,
                sessionId: sessionId,
            });

            console.log(`[Session] ${sessionId}: ${targetId} ↔ ${currentDeviceId} established`);
            break;
        }

        // ═══ 拒绝连接 ═══
        case 'connect_rejected': {
            const targetId = data.targetId;
            const targetWs = deviceManager.getDeviceSocket(targetId);

            if (targetWs) {
                safeSend(targetWs, {
                    type: 'connect_rejected',
                    fromId: currentDeviceId,
                    reason: data.reason || '用户拒绝',
                });
            }
            break;
        }

        // ═══ 开始投屏 ═══
        case 'start_stream': {
            const targetId = data.targetId;
            const targetWs = deviceManager.getDeviceSocket(targetId);

            if (targetWs) {
                safeSend(targetWs, {
                    type: 'start_stream',
                    fromId: currentDeviceId,
                });
            }
            break;
        }

        // ═══ 停止投屏 ═══
        case 'stop_stream': {
            const targetId = data.targetId;
            const targetWs = deviceManager.getDeviceSocket(targetId);

            if (targetWs) {
                safeSend(targetWs, {
                    type: 'stop_stream',
                    fromId: currentDeviceId,
                });
            }
            break;
        }

        // ═══ 屏幕帧转发 ═══
        case 'screen_frame': {
            const targetId = data.targetId;
            const targetWs = deviceManager.getDeviceSocket(targetId);

            if (targetWs) {
                safeSend(targetWs, {
                    type: 'screen_frame',
                    fromId: currentDeviceId,
                    frame: data.frame,
                    seq: data.seq,
                    timestamp: data.timestamp,
                });
            }
            break;
        }

        // ═══ 控制命令转发 ═══
        case 'control_cmd': {
            const targetId = data.targetId;
            const targetWs = deviceManager.getDeviceSocket(targetId);

            if (targetWs) {
                safeSend(targetWs, {
                    type: 'control_cmd',
                    fromId: currentDeviceId,
                    command: data.command,
                });
            }
            break;
        }

        // ═══ 唤醒命令 ═══
        case 'wake_up': {
            const targetId = data.targetId;
            const targetWs = deviceManager.getDeviceSocket(targetId);

            if (targetWs) {
                safeSend(targetWs, {
                    type: 'wake_up',
                    fromId: currentDeviceId,
                });
            }
            break;
        }

        // ═══ 断开连接 ═══
        case 'disconnect': {
            const targetId = data.targetId;
            const targetWs = deviceManager.getDeviceSocket(targetId);

            if (targetWs) {
                safeSend(targetWs, {
                    type: 'disconnect',
                    fromId: currentDeviceId,
                });
            }

            sessionManager.removeSessionByDevice(currentDeviceId);
            break;
        }

        // ═══ 刷新设备列表 ═══
        case 'refresh_list': {
            safeSend(ws, {
                type: 'device_list',
                devices: deviceManager.getDeviceList(currentDeviceId),
            });
            break;
        }

        default: {
            console.log(`[Unknown] Message type: ${type}`);
            safeSend(ws, {
                type: 'error',
                message: `Unknown message type: ${type}`,
            });
        }
    }
}

// ─── 设备断开处理（防重复执行） ───
function handleDeviceDisconnect(deviceId) {
    // 防止双重断连（heartbeat timeout + ws close 事件同时触发）
    if (handledDisconnects.has(deviceId)) return;
    handledDisconnects.add(deviceId);
    // 30秒后清理标记
    setTimeout(() => handledDisconnects.delete(deviceId), 30000);

    // 先获取设备信息（移除后就拿不到了）
    const deviceInfo = deviceManager.getDeviceInfo(deviceId);

    deviceManager.removeDevice(deviceId);
    broadcastDeviceStatus(deviceId, 'offline', deviceInfo);

    // 清理相关会话
    const partnerId = sessionManager.removeSessionByDevice(deviceId);
    if (partnerId) {
        const partnerWs = deviceManager.getDeviceSocket(partnerId);
        safeSend(partnerWs, {
            type: 'disconnect',
            fromId: deviceId,
            reason: '设备已离线',
        });
    }
}

// ─── 广播设备状态 ───
function broadcastDeviceStatus(deviceId, status, deviceInfo = null) {
    const devices = deviceManager.getAllDeviceIds();
    const info = deviceInfo || deviceManager.getDeviceInfo(deviceId);

    const message = JSON.stringify({
        type: status === 'online' ? 'device_online' : 'device_offline',
        deviceId: deviceId,
        device: info,
    });

    for (const id of devices) {
        if (id === deviceId) continue;
        const ws = deviceManager.getDeviceSocket(id);
        safeSend(ws, message);
    }
}

// ─── 获取本机 IP 地址 ───
function getLocalIPs() {
    const interfaces = os.networkInterfaces();
    const ips = [];
    for (const name of Object.keys(interfaces)) {
        for (const iface of interfaces[name] || []) {
            if (iface.family === 'IPv4' && !iface.internal) {
                ips.push({ name, address: iface.address });
            }
        }
    }
    return ips;
}

// ─── 启动服务器 ───
server.listen(PORT, HOST, () => {
    const localIPs = getLocalIPs();

    console.log('');
    console.log('╔══════════════════════════════════════════════════╗');
    console.log('║        远程控制中继服务器 v1.0.0                    ║');
    console.log('╠══════════════════════════════════════════════════╣');
    console.log(`║  监听地址:  ws://${HOST}:${PORT}                    ║`);
    console.log(`║  健康检查:  http://${HOST}:${PORT}/health             ║`);
    console.log('║                                                  ║');
    console.log('║  本机 IP 地址（在手机 App 设置中填入）：             ║');
    if (localIPs.length > 0) {
        for (const ip of localIPs) {
            const line = `║    ${ip.address}:${PORT}  (${ip.name})`;
            console.log(line.padEnd(51) + '║');
        }
    } else {
        console.log('║    未检测到网络接口                                 ║');
    }
    console.log('║                                                  ║');
    console.log('║  提示: 手机和服务器需在同一局域网内                   ║');
    console.log('║  公网部署时请使用公网 IP 或域名                      ║');
    console.log('╚══════════════════════════════════════════════════╝');
    console.log('');
});

// ─── 优雅关闭 ───
process.on('SIGINT', () => {
    console.log('\n[Server] Shutting down gracefully...');
    clearInterval(heartbeatTimer);
    wss.close(() => {
        server.close(() => {
            console.log('[Server] Goodbye!');
            process.exit(0);
        });
    });
});

process.on('SIGTERM', () => {
    console.log('\n[Server] SIGTERM received, shutting down gracefully...');
    clearInterval(heartbeatTimer);
    wss.close(() => {
        server.close(() => {
            console.log('[Server] Goodbye!');
            process.exit(0);
        });
    });
});
