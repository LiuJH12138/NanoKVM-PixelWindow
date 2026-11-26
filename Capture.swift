import AppKit
import AVFoundation
import CoreMedia

/// Camera capture is limited to the NanoKVM video device on this Mac.
final class Capture: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "local.nanokvm.capture")
    private let sampleQueue = DispatchQueue(label: "local.nanokvm.frames")
    private var lastSize = CGSize.zero
    var onSize: ((CGSize) -> Void)?
    var onError: ((String) -> Void)?
    private var lastStamp: CMTime?
    private var count = 0

    func start() {
        AVCaptureDevice.requestAccess(for: .video) { allowed in
            guard allowed else { self.fail("请在系统设置的「隐私与安全性 → 摄像头」中允许此应用，然后重新打开。"); return }
            self.queue.async {
                do {
                    let device = try self.configure()
                    self.session.startRunning()
                    // macOS negotiates its session preset at startup. Apply the UVC timing after negotiation.
                    try device.lockForConfiguration()
                    if let rate = device.activeFormat.videoSupportedFrameRateRanges.max(by: { $0.maxFrameRate < $1.maxFrameRate }) {
                        device.activeVideoMinFrameDuration = rate.minFrameDuration
                        device.activeVideoMaxFrameDuration = rate.minFrameDuration
                    }
                    device.unlockForConfiguration()
                }
                catch { self.fail(error.localizedDescription) }
            }
        }
    }

    private func fail(_ text: String) {
        DispatchQueue.main.async { self.onError?(text) }
    }
    private func configure() throws -> AVCaptureDevice {
        let devices = AVCaptureDevice.DiscoverySession(deviceTypes: [.external], mediaType: .video, position: .unspecified).devices
        let matches = devices.filter {
            $0.localizedName == "USB3 Video" && $0.modelID.contains("VendorID_13407 ProductID_8497")
        }
        guard matches.count == 1, let device = matches.first else {
            throw NSError(domain:"NanoKVM", code:1, userInfo:[NSLocalizedDescriptionKey:"请接入这台 NanoKVM 的 Host USB 线，然后重新打开窗口。"])
        }
        let input = try AVCaptureDeviceInput(device: device)
        session.beginConfiguration()
        defer { session.commitConfiguration() }
        guard session.canAddInput(input) else { throw NSError(domain:"NanoKVM",code:3,userInfo:[NSLocalizedDescriptionKey:"无法打开采集卡，请关闭正在占用它的应用。"]) }
        session.addInput(input)
        guard session.canSetSessionPreset(.hd1920x1080) else {
            throw NSError(domain:"NanoKVM",code:2,userInfo:[NSLocalizedDescriptionKey:"USB 视频设备没有提供 1080p 模式。"])
        }
        session.sessionPreset = .hd1920x1080
        let output = AVCaptureVideoDataOutput()
        output.alwaysDiscardsLateVideoFrames = true
        output.videoSettings = [:]
        output.setSampleBufferDelegate(self, queue: sampleQueue)
        guard session.canAddOutput(output) else { throw NSError(domain:"NanoKVM",code:4,userInfo:[NSLocalizedDescriptionKey:"无法连接视频输出。"]) }
        session.addOutput(output)
        return device
    }
    func captureOutput(_ output: AVCaptureOutput, didOutput sample: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let desc = CMSampleBufferGetFormatDescription(sample) else { return }
        let d = CMVideoFormatDescriptionGetDimensions(desc)
        let size = CGSize(width:Int(d.width), height:Int(d.height))
        if lastSize != size {
            lastSize = size
            DispatchQueue.main.async { self.onSize?(size) }
        }
        if count == 0 { lastStamp = CMSampleBufferGetPresentationTimeStamp(sample) }
        count += 1
        if count == 61, let start = lastStamp {
            let seconds = CMTimeGetSeconds(CMTimeSubtract(CMSampleBufferGetPresentationTimeStamp(sample), start))
            NSLog("NanoKVM video %dx%d, %.2f frames/s", d.width, d.height, 60 / seconds)
        }
    }
}
