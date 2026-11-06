import Foundation
import UIKit
import CoreImage

// MARK: - Titles
//
// A title is a clip with no media behind it: its content is its TitleStyle.
// It sits on a video track like any clip, so position / scale / rotation /
// opacity keyframes, effects and transitions all work on it.

struct TitleStyle: Codable, Hashable {
    var text: String = "Your Title"
    /// system, rounded, serif, mono
    var font: String = "system"
    /// regular, medium, bold, black
    var weight: String = "bold"
    /// Font size in pixels on a 1080-pixel-high frame (scales with the sequence)
    var size: Double = 110
    var color: String = "#FFFFFF"
    /// left, center, right
    var alignment: String = "center"
    var background: Bool = false
    var backgroundColor: String = "#000000"
    var backgroundOpacity: Double = 0.55
    var shadow: Bool = true
    /// Outline width in pixels (0 = none)
    var stroke: Double = 0
    var strokeColor: String = "#000000"

    static let fonts = ["system", "rounded", "serif", "mono"]
    static let weights = ["regular", "medium", "bold", "black"]
    static let alignments = ["left", "center", "right"]
}

struct TitlePreset: Identifiable {
    let id: String
    let name: String
    let icon: String
    let style: TitleStyle
    /// Where it sits, in pixels from the center of a 1080-high frame (positive = down)
    let positionY: Double

    static let all: [TitlePreset] = {
        var basic = TitleStyle()
        basic.text = "Your Title"

        var big = TitleStyle()
        big.text = "BIG IMPACT"
        big.weight = "black"
        big.size = 170
        big.stroke = 6

        var lower = TitleStyle()
        lower.text = "Name Surname"
        lower.size = 58
        lower.weight = "bold"
        lower.alignment = "left"
        lower.background = true
        lower.backgroundColor = "#7C5CFF"
        lower.backgroundOpacity = 0.9
        lower.shadow = false

        var caption = TitleStyle()
        caption.text = "Subtitle text goes here"
        caption.size = 52
        caption.weight = "medium"
        caption.background = true
        caption.backgroundOpacity = 0.6
        caption.shadow = false

        var elegant = TitleStyle()
        elegant.text = "Chapter One"
        elegant.font = "serif"
        elegant.weight = "regular"
        elegant.size = 120

        return [
            TitlePreset(id: "basic", name: "Basic", icon: "textformat", style: basic, positionY: 0),
            TitlePreset(id: "impact", name: "Big Impact", icon: "bold", style: big, positionY: 0),
            TitlePreset(id: "lower-third", name: "Lower Third", icon: "rectangle.bottomthird.inset.filled", style: lower, positionY: 330),
            TitlePreset(id: "caption", name: "Caption", icon: "captions.bubble", style: caption, positionY: 420),
            TitlePreset(id: "elegant", name: "Elegant", icon: "textformat.alt", style: elegant, positionY: 0)
        ]
    }()

    static func named(_ id: String) -> TitlePreset { all.first { $0.id == id } ?? all[0] }
}

extension Clip {
    /// Title clips point at this id instead of a media asset.
    static let titleAssetID = UUID(uuidString: "00000000-0000-0000-0000-00000000717E")!

    var isTitle: Bool { title != nil }
}

// MARK: - Colors as hex strings (keeps project files readable)

extension UIColor {
    convenience init(hexString: String, alpha: CGFloat = 1) {
        var s = hexString.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") { s.removeFirst() }
        var value: UInt64 = 0
        Scanner(string: s).scanHexInt64(&value)
        self.init(red: CGFloat((value >> 16) & 0xFF) / 255,
                  green: CGFloat((value >> 8) & 0xFF) / 255,
                  blue: CGFloat(value & 0xFF) / 255,
                  alpha: alpha)
    }

    var hexString: String {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        getRed(&r, green: &g, blue: &b, alpha: &a)
        func c(_ v: CGFloat) -> Int { Int((min(max(v, 0), 1) * 255).rounded()) }
        return String(format: "#%02X%02X%02X", c(r), c(g), c(b))
    }
}

// MARK: - Drawing a title

enum TitleRenderer {
    private static let cache = NSCache<NSString, CIImage>()

    /// The title drawn on a transparent, canvas-sized image (Core Image coordinates).
    static func image(for style: TitleStyle, canvas: CGSize) -> CIImage {
        let key = "\(style.hashValue)-\(Int(canvas.width))x\(Int(canvas.height))" as NSString
        if let cached = cache.object(forKey: key) { return cached }

        let k = canvas.height / 1080 // style sizes are for a 1080-high frame
        let font = makeFont(style, size: CGFloat(style.size) * k)
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = style.alignment == "left" ? .left : (style.alignment == "right" ? .right : .center)

        var attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: UIColor(hexString: style.color),
            .paragraphStyle: paragraph
        ]
        if style.stroke > 0 {
            // Negative width = fill AND outline
            attributes[.strokeColor] = UIColor(hexString: style.strokeColor)
            attributes[.strokeWidth] = -CGFloat(style.stroke) / max(font.pointSize, 1) * 100
        }
        if style.shadow {
            let shadow = NSShadow()
            shadow.shadowColor = UIColor.black.withAlphaComponent(0.6)
            shadow.shadowOffset = CGSize(width: 0, height: 4 * k)
            shadow.shadowBlurRadius = 12 * k
            attributes[.shadow] = shadow
        }

        let text = NSAttributedString(string: style.text.isEmpty ? " " : style.text, attributes: attributes)
        let maxWidth = canvas.width * 0.9
        let bounds = text.boundingRect(with: CGSize(width: maxWidth, height: .greatestFiniteMagnitude),
                                       options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil).integral
        let textRect = CGRect(x: (canvas.width - bounds.width) / 2, y: (canvas.height - bounds.height) / 2,
                              width: bounds.width, height: bounds.height)

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        let rendered = UIGraphicsImageRenderer(size: canvas, format: format).image { _ in
            if style.background {
                let pad = 0.35 * font.pointSize
                let box = textRect.insetBy(dx: -pad, dy: -pad * 0.5)
                UIColor(hexString: style.backgroundColor, alpha: CGFloat(style.backgroundOpacity)).setFill()
                UIBezierPath(roundedRect: box, cornerRadius: pad * 0.4).fill()
            }
            text.draw(with: textRect, options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil)
        }

        let image: CIImage = rendered.cgImage.map { CIImage(cgImage: $0) }
            ?? CIImage(color: .clear).cropped(to: CGRect(origin: .zero, size: canvas))
        cache.setObject(image, forKey: key)
        return image
    }

    static func makeFont(_ style: TitleStyle, size: CGFloat) -> UIFont {
        let weight: UIFont.Weight
        switch style.weight {
        case "regular": weight = .regular
        case "medium": weight = .medium
        case "black": weight = .black
        default: weight = .bold
        }
        let base = UIFont.systemFont(ofSize: size, weight: weight)
        let design: UIFontDescriptor.SystemDesign
        switch style.font {
        case "rounded": design = .rounded
        case "serif": design = .serif
        case "mono": design = .monospaced
        default: return base
        }
        guard let descriptor = base.fontDescriptor.withDesign(design) else { return base }
        return UIFont(descriptor: descriptor, size: size)
    }
}
