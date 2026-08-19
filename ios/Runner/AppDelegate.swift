import Flutter
import UIKit

/// iOS 端 MethodChannel 处理
///
/// 注意：iOS 平台限制
/// - 屏幕捕获：仅能通过 ReplayKit 捕获本 App 界面，或通过 Broadcast Extension 录制系统屏幕
/// - 触控模拟：iOS 不允许第三方 App 模拟系统级触控事件
/// - 唤醒：只能通过推送通知唤醒，无法程序化唤醒
class AppDelegate: FlutterAppDelegate {

    private var screenCaptureManager: ScreenCaptureManager?
    private var frameEventSink: FlutterEventSink?
    private var statusEventSink: FlutterEventSink?

    override func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {

        screenCaptureManager = ScreenCaptureManager()

        guard let controller = window?.rootViewController as? FlutterViewController else {
            return super.application(application, didFinishLaunchingWithOptions: launchOptions)
        }

        let messenger = controller.binaryMessenger

        // ─── 屏幕捕获通道 ───
        let screenChannel = FlutterMethodChannel(
            name: "com.remotecontrol/screen_capture",
            binaryMessenger: messenger
        )
        screenChannel.setMethodCallHandler { [weak self] call, result in
            guard let self = self else { return }
            switch call.method {
            case "startCapture":
                let args = call.arguments as? [String: Any] ?? [:]
                let fps = args["fps"] as? Int ?? 15
                let quality = args["quality"] as? Int ?? 50
                let maxWidth = args["maxWidth"] as? Int ?? 720
                self.startCapture(fps: fps, quality: quality, maxWidth: maxWidth, result: result)

            case "stopCapture":
                self.screenCaptureManager?.stopCapture()
                result(nil)

            case "isCapturing":
                result(self.screenCaptureManager?.isCapturing ?? false)

            default:
                result(FlutterMethodNotImplemented)
            }
        }

        // ─── 触控模拟通道（iOS 受限，大部分操作不可用） ───
        let controlChannel = FlutterMethodChannel(
            name: "com.remotecontrol/touch_control",
            binaryMessenger: messenger
        )
        controlChannel.setMethodCallHandler { call, result in
            switch call.method {
            case "isAccessibilityEnabled":
                // iOS 没有等价的 AccessibilityService，返回 false
                result(false)

            case "openAccessibilitySettings":
                // 打开辅助功能设置页
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
                result(nil)

            case "touchDown", "touchMove", "touchUp", "scroll", "keyAction":
                // iOS 不支持模拟系统级触控
                // 记录日志但不报错
                print("[iOS] Touch simulation not supported on this platform")
                result(nil)

            default:
                result(FlutterMethodNotImplemented)
            }
        }

        // ─── 唤醒/锁屏通道 ───
        let wakeChannel = FlutterMethodChannel(
            name: "com.remotecontrol/wake_lock",
            binaryMessenger: messenger
        )
        wakeChannel.setMethodCallHandler { call, result in
            switch call.method {
            case "wakeUp":
                // iOS 无法程序化唤醒设备
                print("[iOS] Programmatic wake-up not supported")
                result(nil)

            case "lockScreen":
                // iOS 无法程序化锁屏
                print("[iOS] Programmatic lock not supported")
                result(nil)

            case "keepScreenOn":
                let args = call.arguments as? [String: Any] ?? [:]
                let on = args["on"] as? Bool ?? false
                UIApplication.shared.isIdleTimerDisabled = on
                result(nil)

            case "startForegroundService":
                // iOS 没有前台服务概念
                result(nil)

            default:
                result(FlutterMethodNotImplemented)
            }
        }

        // ─── 设备信息通道 ───
        let deviceChannel = FlutterMethodChannel(
            name: "com.remotecontrol/device_info",
            binaryMessenger: messenger
        )
        deviceChannel.setMethodCallHandler { call, result in
            switch call.method {
            case "getDeviceId":
                let id = UIDevice.current.identifierForVendor?.uuidString ?? "unknown"
                result(id)

            case "getDeviceName":
                result(UIDevice.current.name)

            case "getScreenSize":
                let screen = UIScreen.main
                let scale = screen.scale
                let width = Int(screen.bounds.width * scale)
                let height = Int(screen.bounds.height * scale)
                result(["width": width, "height": height])

            default:
                result(FlutterMethodNotImplemented)
            }
        }

        // ─── 帧数据事件通道 ───
        let frameEventChannel = FlutterEventChannel(
            name: "com.remotecontrol/screen_frames",
            binaryMessenger: messenger
        )
        frameEventChannel.setStreamHandler(FrameStreamHandler(
            manager: screenCaptureManager!,
            onListen: { [weak self] sink in
                self?.frameEventSink = sink
                self?.screenCaptureManager?.frameCallback = { data in
                    DispatchQueue.main.async {
                        self?.frameEventSink?(FlutterStandardTypedData(bytes: data))
                    }
                }
            },
            onCancel: { [weak self] in
                self?.frameEventSink = nil
                self?.screenCaptureManager?.frameCallback = nil
            }
        ))

        // ─── 服务状态事件通道 ───
        let statusEventChannel = FlutterEventChannel(
            name: "com.remotecontrol/service_status",
            binaryMessenger: messenger
        )
        statusEventChannel.setStreamHandler(StatusStreamHandler(
            onListen: { [weak self] sink in
                self?.statusEventSink = sink
            },
            onCancel: { [weak self] in
                self?.statusEventSink = nil
            }
        ))

        GeneratedPluginRegistrant.register(with: self)
        return super.application(application, didFinishLaunchingWithOptions: launchOptions)
    }

    private func startCapture(fps: Int, quality: Int, maxWidth: Int, result: @escaping FlutterResult) {
        guard let vc = window?.rootViewController else {
            result(false)
            return
        }

        if #available(iOS 12.0, *) {
            screenCaptureManager?.startCapture(
                from: vc,
                fps: fps,
                quality: quality,
                maxWidth: maxWidth
            ) { success in
                result(success)
            }
        } else {
            result(false)
        }
    }
}

// ─── Stream Handler 实现 ───

class FrameStreamHandler: NSObject, FlutterStreamHandler {
    let manager: ScreenCaptureManager
    let onListenCallback: (FlutterEventSink) -> Void
    let onCancelCallback: () -> Void

    init(manager: ScreenCaptureManager,
         onListen: @escaping (FlutterEventSink) -> Void,
         onCancel: @escaping () -> Void) {
        self.manager = manager
        self.onListenCallback = onListen
        self.onCancelCallback = onCancel
    }

    func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        onListenCallback(events)
        return nil
    }

    func onCancel(withArguments arguments: Any?) -> FlutterError? {
        onCancelCallback()
        return nil
    }
}

class StatusStreamHandler: NSObject, FlutterStreamHandler {
    let onListenCallback: (FlutterEventSink) -> Void
    let onCancelCallback: () -> Void

    init(onListen: @escaping (FlutterEventSink) -> Void,
         onCancel: @escaping () -> Void) {
        self.onListenCallback = onListen
        self.onCancelCallback = onCancel
    }

    func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        onListenCallback(events)
        return nil
    }

    func onCancel(withArguments arguments: Any?) -> FlutterError? {
        onCancelCallback()
        return nil
    }
}
