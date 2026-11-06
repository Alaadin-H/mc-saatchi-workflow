import Foundation
import AVFoundation
import CoreImage

// MARK: - Rendering
//
// Idea from Concat's renderer: split rendering in two.
//  1. A *plan* says what is on screen during a time range (which clips, from which track).
//     It is built once per edit, with no pixels involved (PlaybackEngine builds it).
//  2. The *compositor* takes the plan + a time + the decoded frames and draws one frame.
// Because we draw every frame ourselves (Core Image), keyframes are exact per frame
// and effects can run on each clip.

/// One clip on screen, as the compositor needs it.
struct RenderLayer {
    let trackID: CMPersistentTrackID
    let clip: Clip
    /// The source video's own rotation (e.g. portrait phone footage)
    let preferredTransform: CGAffineTransform
    /// Size of the decoded frames
    let naturalSize: CGSize
}

/// What is on screen during `timeRange`. Layers are bottom first.
final class CompositionInstruction: NSObject, AVVideoCompositionInstructionProtocol {
    let timeRange: CMTimeRange
    let enablePostProcessing: Bool = false
    let containsTweening: Bool = true
    let requiredSourceTrackIDs: [NSValue]?
    let passthroughTrackID: CMPersistentTrackID = kCMPersistentTrackID_Invalid

    let layers: [RenderLayer]

    init(timeRange: CMTimeRange, layers: [RenderLayer]) {
        self.timeRange = timeRange
        self.layers = layers
        self.requiredSourceTrackIDs = layers.isEmpty ? nil : layers.map { NSNumber(value: $0.trackID) }
        super.init()
    }
}

enum FrameRenderer {
    /// Flips between Core Image coordinates (origin bottom-left) and video coordinates (origin top-left).
    static func flip(height: CGFloat) -> CGAffineTransform {
        CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: 0, ty: height)
    }

    /// Where a clip's picture goes on the canvas, in top-left coordinates:
    /// fit inside the canvas, then the clip's scale / rotation / position (keyframes included).
    static func placement(for layer: RenderLayer, at time: Double, canvas: CGSize) -> CGAffineTransform {
        let pref = layer.preferredTransform
        let bounds = CGRect(origin: .zero, size: layer.naturalSize).applying(pref)
        let w = abs(bounds.width), h = abs(bounds.height)
        guard w > 0, h > 0 else { return .identity }
        let fit = min(canvas.width / w, canvas.height / h)

        let clip = layer.clip
        let scale = CGFloat(clip.value(of: .scale, atTimeline: time))
        let rotation = CGFloat(clip.value(of: .rotation, atTimeline: time)) * .pi / 180
        let cx = canvas.width / 2 + CGFloat(clip.value(of: .positionX, atTimeline: time))
        let cy = canvas.height / 2 + CGFloat(clip.value(of: .positionY, atTimeline: time))

        var m = CGAffineTransform(translationX: cx, y: cy)
        m = m.rotated(by: rotation)
        m = m.scaledBy(x: fit * scale, y: fit * scale)
        m = m.translatedBy(x: -bounds.midX, y: -bounds.midY)
        return pref.concatenating(m)
    }

    /// One clip's finished picture on the canvas (Core Image coordinates).
    static func render(_ layer: RenderLayer, source: CIImage, at time: Double, canvas: CGSize) -> CIImage {
        var image = source
        for effect in layer.clip.effects ?? [] {
            image = EffectCatalogue.apply(effect, to: image)
        }

        let placement = placement(for: layer, at: time, canvas: canvas)
        let toCI = flip(height: layer.naturalSize.height)
            .concatenating(placement)
            .concatenating(flip(height: canvas.height))
        image = image.transformed(by: toCI)

        let opacity = layer.clip.value(of: .opacity, atTimeline: time)
        if opacity < 0.999 {
            image = image.applyingFilter("CIColorMatrix", parameters: [
                "inputAVector": CIVector(x: 0, y: 0, z: 0, w: CGFloat(max(0, opacity)))
            ])
        }
        return image
    }
}

/// Draws every frame of the timeline. AVFoundation calls this for playback and for export.
final class CoreStudioCompositor: NSObject, AVVideoCompositing {
    private let context = CIContext(options: [.cacheIntermediates: false])
    private let queue = DispatchQueue(label: "corestudio.compositor", qos: .userInteractive)

    private static let pixelAttributes: [String: Any] = [
        kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
        kCVPixelBufferIOSurfacePropertiesKey as String: [String: Any]()
    ]

    var sourcePixelBufferAttributes: [String: Any]? { Self.pixelAttributes }
    var requiredPixelBufferAttributesForRenderContext: [String: Any] { Self.pixelAttributes }

    func renderContextChanged(_ newRenderContext: AVVideoCompositionRenderContext) {}

    func startRequest(_ request: AVAsynchronousVideoCompositionRequest) {
        let context = self.context
        queue.async {
            autoreleasepool {
                guard let output = request.renderContext.newPixelBuffer() else {
                    request.finish(with: NSError(domain: "CoreStudio", code: 1,
                                                 userInfo: [NSLocalizedDescriptionKey: "No output buffer"]))
                    return
                }
                let canvas = request.renderContext.size
                let canvasRect = CGRect(origin: .zero, size: canvas)
                var frame = CIImage(color: CIColor(red: 0, green: 0, blue: 0)).cropped(to: canvasRect)

                if let instruction = request.videoCompositionInstruction as? CompositionInstruction {
                    let time = request.compositionTime.seconds
                    for layer in instruction.layers {
                        guard let buffer = request.sourceFrame(byTrackID: layer.trackID) else { continue }
                        let picture = FrameRenderer.render(layer, source: CIImage(cvPixelBuffer: buffer), at: time, canvas: canvas)
                        frame = picture.composited(over: frame)
                    }
                }

                context.render(frame.cropped(to: canvasRect), to: output, bounds: canvasRect,
                               colorSpace: CGColorSpaceCreateDeviceRGB())
                request.finish(withComposedVideoFrame: output)
            }
        }
    }

    func cancelAllPendingVideoCompositionRequests() {
        queue.sync {}
    }
}
