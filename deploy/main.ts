/**
 * 远程控制中继服务器 - Deno Deploy 版本
 *
 * 基于 Deno 原生 API 重写，无需 npm install，直接部署。
 * WebSocket 使用 Deno.serve 的原生 upgrade 支持。
 */

// ═══════════════════════════════════════════
//  设备管理器
// ═══════════════════════════════════════════

interface DeviceEntry {
  id: string;
  ws: WebSocket;
  platform: string;
  osVersion: string;
  deviceName: string;
  lastHeartbeat: number;
  registeredAt: number;
}

class DeviceManager {
  devices = new Map<string, DeviceEntry>();

  registerDevice(deviceId: string, ws: WebSocket, meta: Record<string, string> = {}) {
    const existing = this.devices.get(deviceId);
    if (existing && existing.ws !== ws && existing.ws.readyState === WebSocket.OPEN) {
      try { existing.ws.close(4001, "replaced by new connection"); } catch (_) {}
    }
    this.devices.set(deviceId, {
      id: deviceId,
      ws,
      platform: meta.platform || "unknown",
      osVersion: meta.osVersion || "",
      deviceName: meta.deviceName || `Device-${deviceId.slice(-4)}`,
      lastHeartbeat: Date.now(),
      registeredAt: Date.now(),
    });
  }

  removeDevice(deviceId: string) { this.devices.delete(deviceId); }

  getDeviceSocket(deviceId: string): WebSocket | null {
    return this.devices.get(deviceId)?.ws ?? null;
  }

  getDeviceInfo(deviceId: string) {
    const e = this.devices.get(deviceId);
    if (!e) return null;
    return { deviceId: e.id, deviceName: e.deviceName, platform: e.platform, osVersion: e.osVersion, status: "online", lastSeen: new Date(e.lastHeartbeat).toISOString() };
  }

  updateHeartbeat(deviceId: string) {
    const e = this.devices.get(deviceId);
    if (e) e.lastHeartbeat = Date.now();
  }

  getStaleDevices(threshold: number): string[] {
    const stale: string[] = [];
    for (const [id, e] of this.devices) {
      if (e.lastHeartbeat < threshold) stale.push(id);
    }
    return stale;
  }

  getOnlineCount() { return this.devices.size; }
  getAllDeviceIds() { return Array.from(this.devices.keys()); }

  getDeviceList(excludeId: string | null = null) {
    const list: any[] = [];
    for (const [id, e] of this.devices) {
      if (id === excludeId) continue;
      list.push({ deviceId: e.id, deviceName: e.deviceName, platform: e.platform, osVersion: e.osVersion, status: "online", lastSeen: new Date(e.lastHeartbeat).toISOString() });
    }
    return list;
  }
}

// ═══════════════════════════════════════════
//  会话管理器
// ═══════════════════════════════════════════

interface SessionEntry {
  id: string;
  controllerId: string;
  controlledId: string;
  createdAt: number;
  state: string;
}

class SessionManager {
  sessions = new Map<string, SessionEntry>();
  deviceToSession = new Map<string, string>();

  createSession(controllerId: string, controlledId: string): string {
    const sessionId = crypto.randomUUID();
    this.sessions.set(sessionId, { id: sessionId, controllerId, controlledId, createdAt: Date.now(), state: "active" });
    this.deviceToSession.set(controllerId, sessionId);
    this.deviceToSession.set(controlledId, sessionId);
    console.log(`[Session] Created ${sessionId}: ${controllerId} ↔ ${controlledId}`);
    return sessionId;
  }

  hasActiveSession(deviceId: string): boolean {
    const sid = this.deviceToSession.get(deviceId);
    if (!sid) return false;
    return this.sessions.get(sid)?.state === "active";
  }

  removeSessionByDevice(deviceId: string): string | null {
    const sid = this.deviceToSession.get(deviceId);
    if (!sid) return null;
    const s = this.sessions.get(sid);
    if (!s) return null;
    const partnerId = s.controllerId === deviceId ? s.controlledId : s.controllerId;
    this.sessions.delete(sid);
    this.deviceToSession.delete(s.controllerId);
    this.deviceToSession.delete(s.controlledId);
    console.log(`[Session] Removed ${sid} (device ${deviceId} disconnected)`);
    return partnerId;
  }

  getActiveCount() { return this.sessions.size; }
}

// ═══════════════════════════════════════════
//  服务器主逻辑
// ═══════════════════════════════════════════

const deviceManager = new DeviceManager();
const sessionManager = new SessionManager();
const handledDisconnects = new Set<string>();
const HEARTBEAT_INTERVAL = 15000;
const DEVICE_TIMEOUT = 30000;

function safeSend(ws: WebSocket | null, data: any) {
  try {
    if (ws && ws.readyState === WebSocket.OPEN) {
      ws.send(typeof data === "string" ? data : JSON.stringify(data));
      return true;
    }
  } catch (e) {
    console.error("[SafeSend]", (e as Error).message);
  }
  return false;
}

// 心跳定时器
setInterval(() => {
  const now = Date.now();
  for (const deviceId of deviceManager.getStaleDevices(now - DEVICE_TIMEOUT)) {
    console.log(`[Heartbeat] Device ${deviceId} timed out`);
    const ws = deviceManager.getDeviceSocket(deviceId);
    if (ws && ws.readyState === WebSocket.OPEN) {
      try { ws.close(4000, "heartbeat timeout"); } catch (_) {}
    }
    handleDisconnect(deviceId);
  }
}, HEARTBEAT_INTERVAL);

function handleMessage(ws: WebSocket, data: any, currentDeviceId: string | null, setDeviceId: (id: string) => void) {
  switch (data.type) {
    case "register": {
      const id = data.deviceId;
      if (!id) { safeSend(ws, { type: "error", message: "deviceId required" }); return; }
      deviceManager.registerDevice(id, ws, { platform: data.platform || "unknown", osVersion: data.osVersion || "" });
      setDeviceId(id);
      console.log(`[Register] Device ${id}`);
      safeSend(ws, { type: "registered", deviceId: id, serverTime: Date.now() });
      broadcastStatus(id, "online");
      safeSend(ws, { type: "device_list", devices: deviceManager.getDeviceList(id) });
      break;
    }
    case "ping": {
      if (currentDeviceId) deviceManager.updateHeartbeat(currentDeviceId);
      safeSend(ws, { type: "pong", timestamp: data.timestamp || Date.now(), serverTime: Date.now() });
      break;
    }
    case "request_connect": {
      const tw = deviceManager.getDeviceSocket(data.targetId);
      if (!tw || tw.readyState !== WebSocket.OPEN) { safeSend(ws, { type: "error", message: `Device ${data.targetId} is not online` }); return; }
      if (sessionManager.hasActiveSession(data.targetId)) { safeSend(ws, { type: "connect_rejected", reason: "设备正在被其他设备控制" }); return; }
      const info = currentDeviceId ? deviceManager.getDeviceInfo(currentDeviceId) : null;
      safeSend(tw, { type: "request_connect", fromId: currentDeviceId, fromName: info?.deviceName || "Unknown" });
      break;
    }
    case "connect_accepted": {
      const tw = deviceManager.getDeviceSocket(data.targetId);
      if (!tw || !currentDeviceId) return;
      const sid = sessionManager.createSession(currentDeviceId, data.targetId);
      safeSend(tw, { type: "connect_accepted", fromId: currentDeviceId, sessionId: sid });
      break;
    }
    case "connect_rejected": {
      const tw = deviceManager.getDeviceSocket(data.targetId);
      if (tw) safeSend(tw, { type: "connect_rejected", fromId: currentDeviceId, reason: data.reason || "用户拒绝" });
      break;
    }
    case "start_stream": case "stop_stream": case "screen_frame": case "control_cmd": case "wake_up": case "disconnect": {
      const tw = deviceManager.getDeviceSocket(data.targetId);
      if (tw) safeSend(tw, { ...data, fromId: currentDeviceId });
      if (data.type === "disconnect" && currentDeviceId) sessionManager.removeSessionByDevice(currentDeviceId);
      break;
    }
    case "refresh_list": {
      safeSend(ws, { type: "device_list", devices: deviceManager.getDeviceList(currentDeviceId) });
      break;
    }
    default:
      safeSend(ws, { type: "error", message: `Unknown message type: ${data.type}` });
  }
}

function handleDisconnect(deviceId: string) {
  if (handledDisconnects.has(deviceId)) return;
  handledDisconnects.add(deviceId);
  setTimeout(() => handledDisconnects.delete(deviceId), 30000);
  deviceManager.removeDevice(deviceId);
  broadcastStatus(deviceId, "offline");
  const partnerId = sessionManager.removeSessionByDevice(deviceId);
  if (partnerId) {
    safeSend(deviceManager.getDeviceSocket(partnerId), { type: "disconnect", fromId: deviceId, reason: "设备已离线" });
  }
}

function broadcastStatus(deviceId: string, status: string) {
  const msg = JSON.stringify({ type: status === "online" ? "device_online" : "device_offline", deviceId, device: deviceManager.getDeviceInfo(deviceId) });
  for (const id of deviceManager.getAllDeviceIds()) {
    if (id === deviceId) continue;
    safeSend(deviceManager.getDeviceSocket(id), msg);
  }
}

// ═══════════════════════════════════════════
//  Deno.serve — HTTP + WebSocket
// ═══════════════════════════════════════════

const port = Number(Deno.env.get("PORT")) || 8080;

Deno.serve({ port }, (req: Request) => {
  const url = new URL(req.url);

  // WebSocket upgrade
  if (url.pathname === "/ws" && req.headers.get("upgrade") === "websocket") {
    const { socket, response } = Deno.upgradeWebSocket(req);
    let deviceId: string | null = null;

    socket.onopen = () => {
      console.log("[Connect] New WebSocket connection");
      safeSend(socket, { type: "welcome", message: "Connected to Remote Control Relay Server", serverTime: Date.now() });
    };

    socket.onmessage = (event) => {
      try {
        const data = JSON.parse(event.data);
        handleMessage(socket, data, deviceId, (id) => { deviceId = id; });
      } catch (e) {
        safeSend(socket, { type: "error", message: "Invalid JSON message" });
      }
    };

    socket.onclose = () => {
      if (deviceId) {
        console.log(`[Disconnect] Device ${deviceId}`);
        handleDisconnect(deviceId);
      }
    };

    socket.onerror = (e) => {
      console.error(`[Error] WebSocket error for ${deviceId || "unknown"}:`, e);
    };

    return response;
  }

  // HTTP endpoints
  if (url.pathname === "/health") {
    return new Response(JSON.stringify({ status: "ok", devices: deviceManager.getOnlineCount(), sessions: sessionManager.getActiveCount(), uptime: performance.now() / 1000 }), {
      headers: { "Content-Type": "application/json" },
    });
  }

  if (url.pathname === "/api/devices") {
    return new Response(JSON.stringify({ devices: deviceManager.getDeviceList() }), {
      headers: { "Content-Type": "application/json" },
    });
  }

  return new Response("Remote Control Relay Server is running", { status: 200 });
});

console.log(`Relay server started on port ${port}`);
