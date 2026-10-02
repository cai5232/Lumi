import ReplayKit
import CoreImage
import CoreMedia

/// Broadcast Upload Extension entry point.
///
/// Add this file to a separate `com.apple.broadcast-services-upload` target in
/// Xcode. The extension cannot present UI or receive push notifications, so it
/// only samples, scales, JPEG-encodes, and forwards frames to Lumi's relay.
final class LumiBroadcastUploadHandler: RPBroadcastSampleHandler {
    private let relayURL = URL(string: "https://lumi-tokyo-api.zeabur.app/v1/chats/default/screen-share/frame")!
    private let queue = DispatchQueue(label: "lumi.broadcast.upload", qos: .utility)
    private var lastSentAt: TimeInterval = 0
    private var session = URLSession(configuration: .ephemeral)

    override func broadcastStarted(withSetupInfo setupInfo: [String : NSObject]?) {
        lastSentAt = 0
    }

    override func processSampleBuffer(_ sampleBuffer: CMSampleBuffer, with sampleBufferType: RPSampleBufferType) {
        guard sampleBufferType == .video else { return }
        let now = Date.timeIntervalSinceReferenceDate
        guard now - lastSentAt >= 0.25 else { return }
        lastSentAt = now
        queue.async { [weak self] in self?.send(sampleBuffer) }
    }

    private func send(_ sampleBuffer: CMSampleBuffer) {
        guard let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let ciImage = CIImage(cvPixelBuffer: imageBuffer)
        let scale = min(1, 720 / max(ciImage.extent.width, 1))
        let scaled = ciImage.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let context = CIContext(options: [.useSoftwareRenderer: true])
        guard let data = context.jpegRepresentation(of: scaled, colorSpace: CGColorSpaceCreateDeviceRGB(), options: [:]) else { return }
        var request = URLRequest(url: relayURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["jpegBase64": data.base64EncodedString(), "width": Int(scaled.extent.width), "height": Int(scaled.extent.height)])
        session.dataTask(with: request).resume()
    }
}
