/**
 * 会话管理器
 *
 * 管理控制端与被控端之间的活跃会话：
 * - 创建会话（控制端 → 被控端）
 * - 查询会话状态
 * - 删除会话（断开连接时）
 */

const { v4: uuidv4 } = require('uuid');

class SessionManager {
    constructor() {
        /** @type {Map<string, SessionEntry>} */
        this.sessions = new Map();

        /** 快速索引：设备ID → 会话ID */
        /** @type {Map<string, string>} */
        this.deviceToSession = new Map();
    }

    /**
     * 创建新会话
     * @param {string} controllerId  控制端设备ID
     * @param {string} controlledId  被控端设备ID
     * @returns {string} sessionId
     */
    createSession(controllerId, controlledId) {
        const sessionId = uuidv4();

        this.sessions.set(sessionId, {
            id: sessionId,
            controllerId: controllerId,
            controlledId: controlledId,
            createdAt: Date.now(),
            state: 'active',
        });

        this.deviceToSession.set(controllerId, sessionId);
        this.deviceToSession.set(controlledId, sessionId);

        console.log(`[Session] Created ${sessionId}: controller=${controllerId}, controlled=${controlledId}`);
        return sessionId;
    }

    /**
     * 获取会话
     */
    getSession(sessionId) {
        return this.sessions.get(sessionId) || null;
    }

    /**
     * 检查设备是否有活跃会话
     */
    hasActiveSession(deviceId) {
        const sessionId = this.deviceToSession.get(deviceId);
        if (!sessionId) return false;

        const session = this.sessions.get(sessionId);
        return session?.state === 'active';
    }

    /**
     * 通过设备ID移除会话
     * @returns {string|null} 对方设备ID
     */
    removeSessionByDevice(deviceId) {
        const sessionId = this.deviceToSession.get(deviceId);
        if (!sessionId) return null;

        const session = this.sessions.get(sessionId);
        if (!session) return null;

        // 获取对方设备ID
        const partnerId = session.controllerId === deviceId
            ? session.controlledId
            : session.controllerId;

        // 清理
        this.sessions.delete(sessionId);
        this.deviceToSession.delete(session.controllerId);
        this.deviceToSession.delete(session.controlledId);

        console.log(`[Session] Removed ${sessionId} (device ${deviceId} disconnected)`);
        return partnerId;
    }

    /**
     * 获取活跃会话数量
     */
    getActiveCount() {
        return this.sessions.size;
    }

    /**
     * 获取所有会话信息
     */
    getAllSessions() {
        return Array.from(this.sessions.values()).map(s => ({
            sessionId: s.id,
            controllerId: s.controllerId,
            controlledId: s.controlledId,
            createdAt: new Date(s.createdAt).toISOString(),
            duration: Date.now() - s.createdAt,
            state: s.state,
        }));
    }
}

/**
 * @typedef {Object} SessionEntry
 * @property {string} id
 * @property {string} controllerId
 * @property {string} controlledId
 * @property {number} createdAt
 * @property {string} state
 */

module.exports = { SessionManager };
