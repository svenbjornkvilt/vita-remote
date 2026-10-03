import ReplayKit
import VideoToolbox

let kAppGroup = "group.fo.vita.remote"

class SampleHandler: RPBroadcastSampleHandler {
    // Extensions are capped at ~50 MB, so frames are scaled down before they reach Rust.
    private let maxLongSide = 1280
    private let minFrameInterval = 1.0 / 15.0

    private var transfer: VTPixelTransferSession?
    private var pool: CVPixelBufferPool?
    private var poolSize = (w: 0, h: 0)
    private var lastFrameTime = 0.0
    private let queue = DispatchQueue(label: "fo.vita.remote.broadcast")

    override func broadcastStarted(withSetupInfo setupInfo: [String: NSObject]?) {
        guard let dir = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: kAppGroup)?.path
        else {
            finishBroadcastWithError(error("App Group is missing"))
            return
        }
        VTPixelTransferSessionCreate(allocator: nil, pixelTransferSessionOut: &transfer)
        if let transfer = transfer {
            VTSessionSetProperty(transfer, key: kVTPixelTransferPropertyKey_ScalingMode,
                                 value: kVTScalingMode_Trim)
        }
        if vita_broadcast_start(dir) != 0 {
            finishBroadcastWithError(error("Could not start sharing"))
        }
    }

    override func broadcastFinished() {
        vita_broadcast_stop()
        transfer.map { VTPixelTransferSessionInvalidate($0) }
        transfer = nil
        pool = nil
    }

    override func processSampleBuffer(_ sampleBuffer: CMSampleBuffer,
                                      with sampleBufferType: RPSampleBufferType) {
        guard sampleBufferType == .video,
              let source = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let now = CACurrentMediaTime()
        if now - lastFrameTime < minFrameInterval { return }
        lastFrameTime = now
        queue.sync { self.forward(source) }
    }

    private func forward(_ source: CVPixelBuffer) {
        guard let transfer = transfer else { return }
        let sw = CVPixelBufferGetWidth(source), sh = CVPixelBufferGetHeight(source)
        let scale = min(1.0, Double(maxLongSide) / Double(max(sw, sh)))
        // Even sizes keep the YUV conversion in the encoder happy.
        let w = Int(Double(sw) * scale) & ~1, h = Int(Double(sh) * scale) & ~1
        guard w > 0, h > 0, let dest = makeBuffer(w, h) else { return }
        guard VTPixelTransferSessionTransferImage(transfer, from: source, to: dest) == noErr
        else { return }

        CVPixelBufferLockBaseAddress(dest, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(dest, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(dest) else { return }
        let stride = CVPixelBufferGetBytesPerRow(dest)
        vita_broadcast_frame(base.assumingMemoryBound(to: UInt8.self), UInt(stride * h),
                             UInt32(w), UInt32(h), UInt32(stride))
    }

    private func makeBuffer(_ w: Int, _ h: Int) -> CVPixelBuffer? {
        if pool == nil || poolSize.w != w || poolSize.h != h {
            let attrs: [CFString: Any] = [
                kCVPixelBufferPixelFormatTypeKey: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey: w,
                kCVPixelBufferHeightKey: h,
                kCVPixelBufferIOSurfacePropertiesKey: [:] as CFDictionary,
            ]
            pool = nil
            CVPixelBufferPoolCreate(nil, nil, attrs as CFDictionary, &pool)
            poolSize = (w, h)
        }
        guard let pool = pool else { return nil }
        var buffer: CVPixelBuffer?
        CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer)
        return buffer
    }

    private func error(_ message: String) -> Error {
        NSError(domain: "fo.vita.remote.broadcast", code: 1,
                userInfo: [NSLocalizedDescriptionKey: message])
    }
}
