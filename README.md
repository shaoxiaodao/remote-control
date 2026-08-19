# 手机远程控制 App

手机远程投屏与控制应用，功能类似 ToDesk 的手机端。支持 Android（完整远程控制）和 iOS（控制端完整，被控端受限于 Apple 沙盒限制）。

## 架构概览

```
┌──────────────┐         WebSocket          ┌──────────────┐
│  控制端手机   │ ◄─────────────────────────► │   中继服务器   │
│ (Android/iOS)│    屏幕帧 + 控制命令         │  (Node.js)   │
└──────────────┘                             └──────┬───────┘
                                                    │ WebSocket
                                                    │ 屏幕帧 + 控制命令
                                             ┌──────▼───────┐
                                             │  被控端手机    │
                                             │  (Android)   │
                                             └──────────────┘
```

**通信协议：** WebSocket（JSON 信令 + Base64 编码的 JPEG 帧数据）

## 功能清单

| 功能 | Android 被控端 | iOS 被控端 | 控制端（双平台） |
|------|:---:|:---:|:---:|
| 屏幕投屏 | ✅ MediaProjection | ⚠️ ReplayKit（仅App内） | ✅ 显示远程画面 |
| 触控模拟 | ✅ AccessibilityService | ❌ 平台不支持 | ✅ 发送触控命令 |
| 按键模拟 | ✅ 返回/Home/最近 | ❌ 平台不支持 | ✅ 虚拟按键 |
| 屏幕唤醒 | ✅ WakeLock + KeyguardManager | ❌ 平台不支持 | ✅ 发送唤醒命令 |
| 锁屏 | ✅ AccessibilityService | ❌ 平台不支持 | ✅ 发送锁屏命令 |
| 前台保活 | ✅ Foreground Service | ⚠️ 后台有限 | N/A |
| 设备在线列表 | ✅ | ✅ | ✅ |
| 延迟/FPS 显示 | N/A | N/A | ✅ |

## 快速开始

### 1. 部署中继服务器

```bash
cd server
npm install
npm start
```

服务器默认监听 `0.0.0.0:8080`。

**环境变量：**
- `PORT` — 监听端口（默认 8080）
- `HOST` — 监听地址（默认 0.0.0.0）

**健康检查：**
```bash
curl http://YOUR_SERVER_IP:8080/health
```

### 2. 配置 App

编辑 `lib/config/app_config.dart`，修改服务器地址：

```dart
static const String relayServerHost = 'YOUR_SERVER_IP'; // 替换为你的服务器公网IP
static const int relayServerPort = 8080;
static const bool useSSL = false; // 生产环境设为 true
```

### 3. 编译 Android App

```bash
# 确保已安装 Flutter SDK 3.0+
flutter pub get
flutter build apk --release
```

APK 输出路径：`build/app/outputs/flutter-apk/app-release.apk`

### 4. 编译 iOS App

```bash
cd ios
pod install
cd ..
flutter build ios --release
```

需要通过 Xcode 签名后上传到 TestFlight 或使用真机调试。

## 使用流程

### 被控端（Android）

1. 安装并打开 App
2. 等待自动连接服务器
3. 点击「允许被控制」
4. 将设备 ID 分享给控制端
5. 在系统设置中开启 **无障碍服务**（触控模拟必需）
6. 等待控制端连接请求 → 选择「接受」

### 控制端（Android / iOS）

1. 安装并打开 App
2. 等待自动连接服务器
3. 点击「远程控制」→ 输入被控端的设备 ID
4. 等待被控端接受连接
5. 远程屏幕将自动显示，可直接触控操作

## Android 权限说明

| 权限 | 用途 |
|------|------|
| `INTERNET` | WebSocket 网络通信 |
| `FOREGROUND_SERVICE` | 前台保活服务 |
| `FOREGROUND_SERVICE_MEDIA_PROJECTION` | 屏幕录制前台服务 |
| `WAKE_LOCK` | 唤醒和保持屏幕常亮 |
| `DISABLE_KEYGUARD` | 解锁屏幕（仅限滑动锁） |
| `POST_NOTIFICATIONS` | 前台服务通知 |
| `RECEIVE_BOOT_COMPLETED` | 开机自启动（可选） |

**无障碍服务：** App 内包含 `RemoteControlAccessibilityService`，用于模拟触控操作（tap、swipe、scroll、按键）。被控端必须在「设置 → 无障碍」中手动开启此服务。

## iOS 平台限制说明

由于 Apple 的沙盒机制，iOS 作为被控端存在以下限制：

- **无法远程控制锁屏设备** — iOS 不允许第三方 App 在锁屏状态下运行
- **无法模拟系统触控** — iOS 不开放模拟触摸事件的 API
- **屏幕捕获受限** — ReplayKit 只能录制本 App 界面；Broadcast Extension 可录制系统屏幕但需用户手动从控制中心启动
- **无法程序化唤醒** — 只能通过推送通知（FCM/APNs）唤醒

因此，iOS 主要作为 **控制端** 使用。如需 iOS 被控功能，建议后续考虑企业 MDM 方案。

## 项目结构

```
remote_control/
├── lib/                          # Flutter 应用代码
│   ├── main.dart                 # 入口
│   ├── config/
│   │   └── app_config.dart       # 全局配置（服务器地址等）
│   ├── models/
│   │   ├── device_info.dart      # 设备信息模型
│   │   ├── control_command.dart  # 控制命令模型
│   │   └── session.dart          # 会话模型
│   ├── providers/
│   │   └── app_state_provider.dart # 全局状态管理
│   ├── services/
│   │   ├── websocket_service.dart  # WebSocket 通信
│   │   └── platform_channel_service.dart # 平台通道
│   ├── pages/
│   │   ├── home_page.dart        # 主页
│   │   ├── controller_page.dart  # 控制端页面
│   │   ├── controlled_page.dart  # 被控端页面
│   │   └── device_list_page.dart # 设备列表
│   └── widgets/
│       ├── screen_view.dart      # 远程屏幕渲染组件
│       └── touch_overlay.dart    # 触控捕获组件
├── android/                      # Android 原生代码
│   └── app/src/main/
│       ├── kotlin/.../
│       │   ├── MainActivity.kt           # 通道注册
│       │   ├── ScreenCaptureService.kt    # MediaProjection 屏幕捕获
│       │   ├── RemoteControlAccessibilityService.kt # 触控模拟
│       │   ├── WakeLockManager.kt         # 唤醒/锁屏管理
│       │   └── RemoteControlForegroundService.kt # 前台保活
│       └── AndroidManifest.xml
├── ios/                          # iOS 原生代码
│   └── Runner/
│       ├── AppDelegate.swift     # 通道注册
│       └── ScreenCaptureManager.swift # ReplayKit 屏幕捕获
├── server/                       # Node.js 中继服务器
│   ├── package.json
│   └── src/
│       ├── index.js              # 服务器入口
│       ├── deviceManager.js      # 设备管理
│       └── sessionManager.js     # 会话管理
└── pubspec.yaml
```

## 后续优化方向

- **WebRTC P2P 模式** — 替代 WebSocket 中继，降低延迟和服务器负载
- **视频编码优化** — 使用 H.264/H.265 硬件编码替代 JPEG，大幅降低带宽
- **音频传输** — 添加远程音频流转发
- **文件传输** — 支持远程文件共享
- **多设备管理** — 一个控制端同时管理多个被控设备
- **FCM/APNs 推送** — 远程推送唤醒离线设备
- **端到端加密** — 对帧数据和控制命令进行加密
- **录制回放** — 录制远程控制过程供回放

## 技术栈

- **Flutter 3.x** — 跨平台 UI 框架
- **Provider** — 状态管理
- **web_socket_channel** — WebSocket 客户端
- **Node.js + ws** — WebSocket 中继服务器
- **Android MediaProjection** — 屏幕捕获
- **Android AccessibilityService** — 触控模拟
- **iOS ReplayKit** — 屏幕录制（受限）
