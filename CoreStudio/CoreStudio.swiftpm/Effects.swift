import Foundation
import CoreImage

// MARK: - Effects as data
//
// Idea from Concat: an effect is a *description* (id, name, parameters, which
// filter runs it), not code. The catalogue below is JSON; adding an effect means
// adding an entry. Nothing in the renderer names an individual effect.
// Every effect here runs on a built-in Core Image filter.

struct EffectParameter: Codable, Hashable, Identifiable {
    /// Core Image input key, e.g. "inputRadius"
    let key: String
    let name: String
    let min: Double
    let max: Double
    let defaultValue: Double
    /// "scalar" (default) or "vectorX" (passed as CIVector(x: value, y: 0))
    let kind: String?

    var id: String { key }
}

struct EffectDefinition: Codable, Hashable, Identifiable {
    let id: String
    let name: String
    let category: String
    let icon: String
    /// Core Image filter name
    let filter: String
    let parameters: [EffectParameter]
    /// Blur-like filters spread past the edges; clamp first so borders don't go transparent.
    let clampEdges: Bool?
}

/// An effect placed on a clip.
struct AppliedEffect: Codable, Hashable, Identifiable {
    var id: UUID = UUID()
    var effectID: String
    var params: [String: Double]
    var enabled: Bool = true
}

enum EffectCatalogue {
    static let all: [EffectDefinition] = {
        guard let data = catalogueJSON.data(using: .utf8),
              let list = try? JSONDecoder().decode([EffectDefinition].self, from: data) else {
            CrashReporter.log("effect catalogue failed to load")
            return []
        }
        return list
    }()

    static func definition(_ id: String) -> EffectDefinition? { all.first { $0.id == id } }

    static var categories: [String] {
        var seen: [String] = []
        for e in all where !seen.contains(e.category) { seen.append(e.category) }
        return seen
    }

    static func defaults(for definition: EffectDefinition) -> [String: Double] {
        Dictionary(uniqueKeysWithValues: definition.parameters.map { ($0.key, $0.defaultValue) })
    }

    /// Runs one applied effect on an image. Unknown or disabled effects pass the image through.
    static func apply(_ effect: AppliedEffect, to image: CIImage) -> CIImage {
        guard effect.enabled, let def = definition(effect.effectID),
              let filter = CIFilter(name: def.filter) else { return image }
        let extent = image.extent
        let input = (def.clampEdges ?? false) ? image.clampedToExtent() : image
        filter.setValue(input, forKey: kCIInputImageKey)
        for p in def.parameters {
            let v = effect.params[p.key] ?? p.defaultValue
            if p.kind == "vectorX" {
                filter.setValue(CIVector(x: CGFloat(v), y: 0), forKey: p.key)
            } else {
                filter.setValue(NSNumber(value: v), forKey: p.key)
            }
        }
        guard let output = filter.outputImage else { return image }
        return output.cropped(to: extent)
    }

    private static let catalogueJSON = """
    [
      {"id":"color.adjust","name":"Color Adjust","category":"Color","icon":"slider.horizontal.3","filter":"CIColorControls","parameters":[
        {"key":"inputBrightness","name":"Brightness","min":-0.5,"max":0.5,"defaultValue":0},
        {"key":"inputContrast","name":"Contrast","min":0.5,"max":1.5,"defaultValue":1},
        {"key":"inputSaturation","name":"Saturation","min":0,"max":2,"defaultValue":1}]},
      {"id":"color.exposure","name":"Exposure","category":"Color","icon":"sun.max","filter":"CIExposureAdjust","parameters":[
        {"key":"inputEV","name":"Exposure","min":-2,"max":2,"defaultValue":0}]},
      {"id":"color.vibrance","name":"Vibrance","category":"Color","icon":"drop","filter":"CIVibrance","parameters":[
        {"key":"inputAmount","name":"Amount","min":-1,"max":1,"defaultValue":0.5}]},
      {"id":"color.temperature","name":"Temperature","category":"Color","icon":"thermometer.medium","filter":"CITemperatureAndTint","parameters":[
        {"key":"inputNeutral","name":"Warm ↔ Cool","min":3000,"max":10000,"defaultValue":6500,"kind":"vectorX"}]},
      {"id":"color.highlights","name":"Highlights & Shadows","category":"Color","icon":"circle.lefthalf.filled","filter":"CIHighlightShadowAdjust","parameters":[
        {"key":"inputHighlightAmount","name":"Highlights","min":0,"max":1,"defaultValue":1},
        {"key":"inputShadowAmount","name":"Shadows","min":-1,"max":1,"defaultValue":0.3}]},

      {"id":"look.mono","name":"Mono","category":"Looks","icon":"circle.fill","filter":"CIPhotoEffectMono","parameters":[]},
      {"id":"look.noir","name":"Noir","category":"Looks","icon":"moon.fill","filter":"CIPhotoEffectNoir","parameters":[]},
      {"id":"look.chrome","name":"Chrome","category":"Looks","icon":"sparkles","filter":"CIPhotoEffectChrome","parameters":[]},
      {"id":"look.fade","name":"Fade","category":"Looks","icon":"cloud","filter":"CIPhotoEffectFade","parameters":[]},
      {"id":"look.instant","name":"Instant","category":"Looks","icon":"camera","filter":"CIPhotoEffectInstant","parameters":[]},
      {"id":"look.process","name":"Process","category":"Looks","icon":"film","filter":"CIPhotoEffectProcess","parameters":[]},
      {"id":"look.transfer","name":"Transfer","category":"Looks","icon":"photo","filter":"CIPhotoEffectTransfer","parameters":[]},
      {"id":"look.sepia","name":"Sepia","category":"Looks","icon":"leaf","filter":"CISepiaTone","parameters":[
        {"key":"inputIntensity","name":"Intensity","min":0,"max":1,"defaultValue":0.8}]},

      {"id":"blur.gaussian","name":"Blur","category":"Blur & Sharpen","icon":"aqi.medium","filter":"CIGaussianBlur","clampEdges":true,"parameters":[
        {"key":"inputRadius","name":"Radius","min":0,"max":50,"defaultValue":10}]},
      {"id":"sharpen","name":"Sharpen","category":"Blur & Sharpen","icon":"triangle","filter":"CISharpenLuminance","parameters":[
        {"key":"inputSharpness","name":"Sharpness","min":0,"max":2,"defaultValue":0.4}]},

      {"id":"stylize.vignette","name":"Vignette","category":"Stylize","icon":"circle.dashed","filter":"CIVignette","parameters":[
        {"key":"inputIntensity","name":"Intensity","min":0,"max":2,"defaultValue":1},
        {"key":"inputRadius","name":"Radius","min":0,"max":2,"defaultValue":1}]},
      {"id":"stylize.bloom","name":"Glow","category":"Stylize","icon":"light.max","filter":"CIBloom","clampEdges":true,"parameters":[
        {"key":"inputRadius","name":"Radius","min":0,"max":30,"defaultValue":10},
        {"key":"inputIntensity","name":"Intensity","min":0,"max":1,"defaultValue":0.5}]},
      {"id":"stylize.pixellate","name":"Pixelate","category":"Stylize","icon":"square.grid.3x3","filter":"CIPixellate","clampEdges":true,"parameters":[
        {"key":"inputScale","name":"Size","min":1,"max":100,"defaultValue":20}]},
      {"id":"stylize.posterize","name":"Posterize","category":"Stylize","icon":"square.stack.3d.up","filter":"CIColorPosterize","parameters":[
        {"key":"inputLevels","name":"Levels","min":2,"max":30,"defaultValue":6}]},
      {"id":"stylize.invert","name":"Invert","category":"Stylize","icon":"circle.righthalf.filled","filter":"CIColorInvert","parameters":[]}
    ]
    """
}
