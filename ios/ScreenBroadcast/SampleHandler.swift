import ReplayKit

/// Broadcast Upload Extension 的采样处理器
///
/// 当用户从控制中心启动屏幕录制时，
/// 系统会将屏幕帧推送到此处理器。
///
/// 注意：此 Extension 运行在独立进程中，
/// 需要通过 App Group 或 Darwin 通知与主 App 通信。
class SampleHandler: RPBroadcastSampleHandler {

    private var frameCount = 0
    private let maxFps = 15
    private var lastSendTime: TimeInterval = 0

    override func broadcastStarted(withSetupInfo setupInfo: [String: NSObject]?) {
        // 录制开始
        print("[Broadcast] Screen recording started")
        lastSendTime = CACurrentMediaTime()
    }

    override func broadcastPaused() {
        print("[Broadcast] Screen recording paused")
    }

    override func broadcastResumed() {
        print("[Broadcast] Screen recording resumed")
    }

    override func broadcastFinished() {
        print("[Broadcast] Screen recording finished")
    }

    override func processSampleBuffer(_ sampleBuffer: CMSampleBuffer,
                                       with sampleBufferType: RPSampleBufferType) {
        guard sampleBufferType == .video else { return }

        let now = CACurrentMediaTime()
        let interval = 1.0 / TimeInterval(maxFps)

        // 帧率控制
        if now - lastSendTime < interval {
            return
        }
        lastSendTime = now

        // 处理帧
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        // 通过 App Group 共享内存传递给主 App
        // 主 App 读取共享数据后通过 WebSocket 发送
        shareFrameViaAppGroup(pixelBuffer: pixelBuffer)
    }

    private func shareFrameViaAppGroup(pixelBuffer: CVPixelBuffer) {
        guard let containerURL = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: "group.com.remotecontrol.app")
        else { return }

        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        let context = CIContext()

        guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else { return }
        let uiImage = UIImage(cgImage: cgImage)
        guard let jpegData = uiImage.jpegData(compressionQuality: 0.5) else { return }

        // 写入共享文件
        let fileURL = containerURL.appendingPathComponent("latest_frame.jpg")
        try? jpegData.write(to: fileURL, options: .atomic)

        frameCount += 1
    }
}
