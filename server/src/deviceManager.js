/**
 * 设备管理器
 *
 * 维护所有已注册设备的状态：
 * - WebSocket 连接引用
 * - 设备元数据（平台、名称等）
 * - 最后心跳时间
 */
class DeviceManager {
    constructor() {
        /** @type {Map<string, DeviceEntry>} */
        this.devices = new Map();
    }

    /**
     * 注册设备
     * @param {string} deviceId
     * @param {import('ws').WebSocket} ws
     * @param {object} meta
     */
    registerDevice(deviceId, ws, meta = {}) {
        // 如果该设备已有旧连接，关闭旧连接
        const existing = this.devices.get(deviceId);
        if (existing && existing.ws !== ws && existing.ws.readyState === existing.ws.OPEN) {
            existing.ws.close(4001, 'replaced by new connection');
        }

        this.devices.set(deviceId, {
            id: deviceId,
            ws: ws,
            platform: meta.platform || 'unknown',
            osVersion: meta.osVersion || '',
            deviceName: meta.deviceName || `Device-${deviceId.slice(-4)}`,
            lastHeartbeat: Date.now(),
            registeredAt: Date.now(),
        });
    }

    /**
     * 移除设备
     */
    removeDevice(deviceId) {
        this.devices.delete(deviceId);
    }

    /**
     * 获取设备的 WebSocket 连接
     */
    getDeviceSocket(deviceId) {
        const entry = this.devices.get(deviceId);
        return entry?.ws || null;
    }

    /**
     * 获取设备信息（公开字段，不含 ws 引用）
     */
    getDeviceInfo(deviceId) {
        const entry = this.devices.get(deviceId);
        if (!entry) return null;

        return {
            deviceId: entry.id,
            deviceName: entry.deviceName,
            platform: entry.platform,
            osVersion: entry.osVersion,
            status: 'online',
            lastSeen: new Date(entry.lastHeartbeat).toISOString(),
        };
    }

    /**
     * 更新心跳时间
     */
    updateHeartbeat(deviceId) {
        const entry = this.devices.get(deviceId);
        if (entry) {
            entry.lastHeartbeat = Date.now();
        }
    }

    /**
     * 获取超时的设备列表
     */
    getStaleDevices(threshold) {
        const stale = [];
        for (const [id, entry] of this.devices) {
            if (entry.lastHeartbeat < threshold) {
                stale.push(id);
            }
        }
        return stale;
    }

    /**
     * 获取在线设备数量
     */
    getOnlineCount() {
        return this.devices.size;
    }

    /**
     * 获取所有设备 ID
     */
    getAllDeviceIds() {
        return Array.from(this.devices.keys());
    }

    /**
     * 获取设备列表（JSON 格式，可选排除指定设备）
     */
    getDeviceList(excludeId = null) {
        const list = [];
        for (const [id, entry] of this.devices) {
            if (id === excludeId) continue;
            list.push({
                deviceId: entry.id,
                deviceName: entry.deviceName,
                platform: entry.platform,
                osVersion: entry.osVersion,
                status: 'online',
                lastSeen: new Date(entry.lastHeartbeat).toISOString(),
            });
        }
        return list;
    }
}

/**
 * @typedef {Object} DeviceEntry
 * @property {string} id
 * @property {import('ws').WebSocket} ws
 * @property {string} platform
 * @property {string} osVersion
 * @property {string} deviceName
 * @property {number} lastHeartbeat
 * @property {number} registeredAt
 */

module.exports = { DeviceManager };
