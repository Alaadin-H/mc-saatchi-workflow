import Foundation
import AVFoundation

/// A tiny 1-second black movie, made once and cached.
/// The timeline lays it under everything for its full length, so the timeline
/// has a picture track even where there is only a title or a gap.
enum BlackVideo {
    private static var cached: URL?
    private static let lock = NSLock()

    static func url() -> URL? {
        lock.lock(); defer { lock.unlock() }
        if let cached, FileManager.default.fileExists(atPath: cached.path) { return cached }

        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let url = caches.appendingPathComponent("corestudio-black-v1.mov")
        if FileManager.default.fileExists(atPath: url.path), AVURLAsset(url: url).tracks(withMediaType: .video).first != nil {
            cached = url
            return url
        }
        try? FileManager.default.removeItem(at: url)

        let size = 64
        do {
            let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
            let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
                AVVideoCodecKey: AVVideoCodecType.h264,
                AVVideoWidthKey: size,
                AVVideoHeightKey: size
            ])
            input.expectsMediaDataInRealTime = false
            let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: size,
                kCVPixelBufferHeightKey as String: size
            ])
            guard writer.canAdd(input) else { return nil }
            writer.add(input)
            guard writer.startWriting() else { return nil }
            writer.startSession(atSourceTime: .zero)

            var buffer: CVPixelBuffer?
            CVPixelBufferCreate(kCFAllocatorDefault, size, size, kCVPixelFormatType_32BGRA, nil, &buffer)
            guard let black = buffer else { return nil }
            CVPixelBufferLockBaseAddress(black, [])
            if let base = CVPixelBufferGetBaseAddress(black) {
                memset(base, 0, CVPixelBufferGetDataSize(black))
            }
            CVPixelBufferUnlockBaseAddress(black, [])

            for frame in 0..<30 {
                var waited = 0
                while !input.isReadyForMoreMediaData && waited < 400 {
                    Thread.sleep(forTimeInterval: 0.005)
                    waited += 1
                }
                adaptor.append(black, withPresentationTime: CMTime(value: CMTimeValue(frame), timescale: 30))
            }
            input.markAsFinished()
            writer.endSession(atSourceTime: CMTime(value: 30, timescale: 30))

            let done = DispatchSemaphore(value: 0)
            writer.finishWriting { done.signal() }
            _ = done.wait(timeout: .now() + 5)

            guard writer.status == .completed else {
                CrashReporter.log("black video failed: \(writer.error?.localizedDescription ?? "unknown")")
                return nil
            }
            cached = url
            return url
        } catch {
            CrashReporter.log("black video failed: \(error.localizedDescription)")
            return nil
        }
    }
}
