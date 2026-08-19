import UIKit
import ReplayKit
import Foundation

/// iOS 屏幕捕获管理器
///
/// 支持两种模式：
/// 1. In-App 模式：使用 RPScreenRecorder 录制本 App 界面
/// 2. Broadcast 模式：使用 Broadcast Upload Extension 录制系统屏幕（需要用户在控制中心手动启动）
///
/// 注意限制：
/// - In-App 模式只能录制当前 App 的界面
/// - Broadcast 模式可以录制系统界面，但需要用户手动从控制中心启动
/// - 两种方式都不能在锁屏状态下运行
class ScreenCaptureManager: NSObject {

    var isCapturing: Bool = false
    var frameCallback: ((Data) -> Void)?

    private var fps: Int = 15
    private var quality: Int = 50
    private var maxWidth: Int = 720
    private var captureInterval: TimeInterval = 1.0 / 15.0
    private var lastCaptureTime: TimeInterval = 0

    // CIContext 很昂贵，只创建一次
    private lazy var ciContext = CIContext()
    // 串行队列保证帧处理的线程安全
    private let frameQueue = DispatchQueue(label: "com.remotecontrol.frameQueue")

    /// 启动屏幕捕获
    func startCapture(
        from viewController: UIViewController,
        fps: Int,
        quality: Int,
        maxWidth: Int,
        completion: @escaping (Bool) -> Void
    ) {
        self.fps = fps
        self.quality = quality
        self.maxWidth = maxWidth
        self.captureInterval = 1.0 / TimeInterval(fps)

        if #available(iOS 12.0, *) {
            let recorder = RPScreenRecorder.shared()

            if !recorder.isAvailable {
                print("[ScreenCapture] ReplayKit not available")
                completion(false)
                return
            }

            recorder.isMicrophoneEnabled = false
            recorder.isCameraEnabled = false

            recorder.startCapture({ [weak self] sampleBuffer, sampleBufferType, error in
                guard let self = self, error == nil else { return }

                if sampleBufferType == .video {
                    self.processFrame(sampleBuffer: sampleBuffer)
                }
            }, completionHandler: { [weak self] error in
                if let error = error {
                    print("[ScreenCapture] Start error: \(error.localizedDescription)")
                    completion(false)
                } else {
                    self?.isCapturing = true
                    completion(true)
                }
            })
        } else {
            completion(false)
        }
    }

    /// 停止屏幕捕获
    func stopCapture() {
        if #available(iOS 12.0, *) {
            RPScreenRecorder.shared().stopCapture { [weak self] error in
                if let error = error {
                    print("[ScreenCapture] Stop error: \(error.localizedDescription)")
                }
                self?.isCapturing = false
                self?.frameTimer?.invalidate()
                self?.frameTimer = nil
            }
        }
    }

    /// 处理视频帧（在 frameQueue 上执行，保证线程安全）
    private func processFrame(sampleBuffer: CMSampleBuffer) {
        frameQueue.async { [weak self] in
            guard let self = self, self.isCapturing else { return }

            let now = CACurrentMediaTime()
            if now - self.lastCaptureTime < self.captureInterval {
                return // 跳帧控制帧率
            }
            self.lastCaptureTime = now

            guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

            let ciImage = CIImage(cvPixelBuffer: pixelBuffer)

            // 缩放到 maxWidth
            let originalWidth = CVPixelBufferGetWidth(pixelBuffer)
            let scale = min(CGFloat(self.maxWidth) / CGFloat(originalWidth), 1.0)

            let scaledImage = ciImage.transformed(by: CGAffineTransform(scaleX: scale, y: scale))

            guard let cgImage = self.ciContext.createCGImage(scaledImage, from: scaledImage.extent) else { return }

            let uiImage = UIImage(cgImage: cgImage)

            // 压缩为 JPEG
            guard let jpegData = uiImage.jpegData(compressionQuality: CGFloat(self.quality) / 100.0) else { return }

            // 回调（在主线程）
            DispatchQueue.main.async {
                self.frameCallback?(jpegData)
            }
        }
    }
}
