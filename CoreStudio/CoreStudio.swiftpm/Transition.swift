import Foundation
import CoreImage

// MARK: - Transitions
//
// A transition belongs to the clip it leads INTO (`Clip.transitionIn`).
// - If the clip directly follows another clip on the same track, the two are
//   blended across the cut: half the duration before it, half after (using
//   the media beyond each clip's edges where there is some).
// - If nothing comes before it, the clip transitions in from what's beneath
//   (a fade / slide in).

struct ClipTransition: Codable, Hashable {
    var type: String
    var duration: Double

    static let defaultDuration = 0.8
}

struct TransitionKind: Identifiable {
    let id: String
    let name: String
    let icon: String

    static let all: [TransitionKind] = [
        TransitionKind(id: "crossDissolve", name: "Cross Dissolve", icon: "circle.lefthalf.filled"),
        TransitionKind(id: "dipToBlack", name: "Dip to Black", icon: "circle.fill"),
        TransitionKind(id: "dipToWhite", name: "Dip to White", icon: "circle"),
        TransitionKind(id: "slideLeft", name: "Slide Left", icon: "arrow.left.square"),
        TransitionKind(id: "slideRight", name: "Slide Right", icon: "arrow.right.square"),
        TransitionKind(id: "pushLeft", name: "Push Left", icon: "rectangle.lefthalf.inset.filled.arrow.left"),
        TransitionKind(id: "wipeLeft", name: "Wipe Left", icon: "rectangle.righthalf.filled"),
        TransitionKind(id: "zoomIn", name: "Zoom In", icon: "plus.magnifyingglass")
    ]

    static func named(_ id: String) -> TransitionKind? { all.first { $0.id == id } }
}

enum TransitionRenderer {
    /// Blends `outgoing` (may be nil = whatever is beneath) into `incoming` at progress 0...1.
    /// Returns the image to composite over the lower tracks.
    static func blend(type: String, outgoing: CIImage?, incoming: CIImage, progress raw: Double, canvas: CGRect) -> CIImage {
        let p = min(max(raw, 0), 1)
        let eased = p * p * (3 - 2 * p) // smoothstep
        let clear = CIImage(color: .clear).cropped(to: canvas)
        let a = outgoing ?? clear

        func faded(_ image: CIImage, _ alpha: Double) -> CIImage {
            image.applyingFilter("CIColorMatrix", parameters: ["inputAVector": CIVector(x: 0, y: 0, z: 0, w: CGFloat(max(0, alpha)))])
        }
        func solid(_ color: CIColor) -> CIImage { CIImage(color: color).cropped(to: canvas) }

        switch type {
        case "dipToBlack", "dipToWhite":
            let base = solid(type == "dipToBlack" ? CIColor(red: 0, green: 0, blue: 0) : CIColor(red: 1, green: 1, blue: 1))
            if eased < 0.5 {
                // A fades into the colour
                return faded(base, eased * 2).composited(over: a)
            } else {
                // The colour fades into B
                return faded(base, (1 - eased) * 2).composited(over: incoming)
            }

        case "slideLeft":
            let b = incoming.transformed(by: CGAffineTransform(translationX: canvas.width * CGFloat(1 - eased), y: 0))
            return b.composited(over: a).cropped(to: canvas)

        case "slideRight":
            let b = incoming.transformed(by: CGAffineTransform(translationX: -canvas.width * CGFloat(1 - eased), y: 0))
            return b.composited(over: a).cropped(to: canvas)

        case "pushLeft":
            let movedA = a.transformed(by: CGAffineTransform(translationX: -canvas.width * CGFloat(eased), y: 0))
            let b = incoming.transformed(by: CGAffineTransform(translationX: canvas.width * CGFloat(1 - eased), y: 0))
            return b.composited(over: movedA).cropped(to: canvas)

        case "wipeLeft":
            let edge = canvas.width * CGFloat(1 - eased)
            let b = incoming.cropped(to: CGRect(x: edge, y: canvas.minY, width: canvas.width - edge, height: canvas.height))
            return b.composited(over: a)

        case "zoomIn":
            // B grows from 80% while fading in
            let s = CGFloat(0.8 + 0.2 * eased)
            let center = CGPoint(x: canvas.midX, y: canvas.midY)
            let zoom = CGAffineTransform(translationX: center.x, y: center.y).scaledBy(x: s, y: s).translatedBy(x: -center.x, y: -center.y)
            return faded(incoming.transformed(by: zoom), eased).composited(over: a).cropped(to: canvas)

        default: // crossDissolve
            return faded(incoming, eased).composited(over: a)
        }
    }
}
