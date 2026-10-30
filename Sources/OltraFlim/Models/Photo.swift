import Foundation
import CoreGraphics

struct Adjustments: Codable, Equatable {
    var exposure: Double = 0          // -5…+5 EV
    var contrast: Double = 0          // -100…+100
    var highlights: Double = 0
    var shadows: Double = 0
    var whites: Double = 0
    var blacks: Double = 0
    var midtones: Double = 0          // -100…+100, 18% grey band
    var highlightRolloff: Double = 0  // 0…100, film shoulder above white
    var temperature: Double = 0       // -100…+100
    var tint: Double = 0              // -100…+100
    var vibrance: Double = 0
    var saturation: Double = 0
    var hueShift: Double = 0
    var colorDensity: Double = 0
    var skinSaturation: Double = 0
    var greenSaturation: Double = 0
    var blueSaturation: Double = 0
    var highlightWarmth: Double = 0
    var shadowCoolness: Double = 0
    var clarity: Double = 0
    var sharpen: Double = 0
    var grain: Double = 0
    var grainSize: Double = 38
    var grainRoughness: Double = 50
    var grainChroma: Double = 0
    var grainShadow: Double = 0
    var halation: Double = 0
    var halationThreshold: Double = 55
    var halationRadius: Double = 50
    var halationWarmth: Double = 75
    var bloom: Double = 0
    var vignette: Double = 0
    var vignetteMidpoint: Double = 50
    var vignetteRoundness: Double = 0
    var vignetteFeather: Double = 50
    var vignetteCenterX: Double = 0
    var vignetteCenterY: Double = 0
    var fade: Double = 0
    var tonalTransparency: Double = 0
    var colorTransparency: Double = 0

    static let neutral = Adjustments()

    init() {}

    enum CodingKeys: String, CodingKey {
        case exposure, contrast, highlights, shadows, whites, blacks
        case midtones, highlightRolloff
        case temperature, tint, vibrance, saturation
        case hueShift, colorDensity, skinSaturation, greenSaturation, blueSaturation
        case highlightWarmth, shadowCoolness
        case clarity, sharpen, grain, grainSize, grainRoughness, grainChroma, grainShadow
        case halation, halationThreshold, halationRadius, halationWarmth, bloom
        case vignette, vignetteMidpoint, vignetteRoundness, vignetteFeather
        case vignetteCenterX, vignetteCenterY
        case fade, tonalTransparency, colorTransparency
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        exposure = try c.decodeIfPresent(Double.self, forKey: .exposure) ?? 0
        contrast = try c.decodeIfPresent(Double.self, forKey: .contrast) ?? 0
        highlights = try c.decodeIfPresent(Double.self, forKey: .highlights) ?? 0
        shadows = try c.decodeIfPresent(Double.self, forKey: .shadows) ?? 0
        whites = try c.decodeIfPresent(Double.self, forKey: .whites) ?? 0
        blacks = try c.decodeIfPresent(Double.self, forKey: .blacks) ?? 0
        midtones = try c.decodeIfPresent(Double.self, forKey: .midtones) ?? 0
        highlightRolloff = try c.decodeIfPresent(Double.self, forKey: .highlightRolloff) ?? 0
        temperature = try c.decodeIfPresent(Double.self, forKey: .temperature) ?? 0
        tint = try c.decodeIfPresent(Double.self, forKey: .tint) ?? 0
        vibrance = try c.decodeIfPresent(Double.self, forKey: .vibrance) ?? 0
        saturation = try c.decodeIfPresent(Double.self, forKey: .saturation) ?? 0
        hueShift = try c.decodeIfPresent(Double.self, forKey: .hueShift) ?? 0
        colorDensity = try c.decodeIfPresent(Double.self, forKey: .colorDensity) ?? 0
        skinSaturation = try c.decodeIfPresent(Double.self, forKey: .skinSaturation) ?? 0
        greenSaturation = try c.decodeIfPresent(Double.self, forKey: .greenSaturation) ?? 0
        blueSaturation = try c.decodeIfPresent(Double.self, forKey: .blueSaturation) ?? 0
        highlightWarmth = try c.decodeIfPresent(Double.self, forKey: .highlightWarmth) ?? 0
        shadowCoolness = try c.decodeIfPresent(Double.self, forKey: .shadowCoolness) ?? 0
        clarity = try c.decodeIfPresent(Double.self, forKey: .clarity) ?? 0
        sharpen = try c.decodeIfPresent(Double.self, forKey: .sharpen) ?? 0
        grain = try c.decodeIfPresent(Double.self, forKey: .grain) ?? 0
        grainSize = try c.decodeIfPresent(Double.self, forKey: .grainSize) ?? 38
        grainRoughness = try c.decodeIfPresent(Double.self, forKey: .grainRoughness) ?? 50
        grainChroma = try c.decodeIfPresent(Double.self, forKey: .grainChroma) ?? 0
        grainShadow = try c.decodeIfPresent(Double.self, forKey: .grainShadow) ?? 0
        halation = try c.decodeIfPresent(Double.self, forKey: .halation) ?? 0
        halationThreshold = try c.decodeIfPresent(Double.self, forKey: .halationThreshold) ?? 55
        halationRadius = try c.decodeIfPresent(Double.self, forKey: .halationRadius) ?? 50
        halationWarmth = try c.decodeIfPresent(Double.self, forKey: .halationWarmth) ?? 75
        bloom = try c.decodeIfPresent(Double.self, forKey: .bloom) ?? 0
        vignette = try c.decodeIfPresent(Double.self, forKey: .vignette) ?? 0
        vignetteMidpoint = try c.decodeIfPresent(Double.self, forKey: .vignetteMidpoint) ?? 50
        vignetteRoundness = try c.decodeIfPresent(Double.self, forKey: .vignetteRoundness) ?? 0
        vignetteFeather = try c.decodeIfPresent(Double.self, forKey: .vignetteFeather) ?? 50
        vignetteCenterX = try c.decodeIfPresent(Double.self, forKey: .vignetteCenterX) ?? 0
        vignetteCenterY = try c.decodeIfPresent(Double.self, forKey: .vignetteCenterY) ?? 0
        fade = try c.decodeIfPresent(Double.self, forKey: .fade) ?? 0
        tonalTransparency = try c.decodeIfPresent(Double.self, forKey: .tonalTransparency) ?? 0
        colorTransparency = try c.decodeIfPresent(Double.self, forKey: .colorTransparency) ?? 0
    }

    var isNeutral: Bool {
        self == Adjustments.neutral
    }

    var activeCount: Int {
        var count = 0
        if exposure != 0 { count += 1 }
        if contrast != 0 { count += 1 }
        if highlights != 0 { count += 1 }
        if shadows != 0 { count += 1 }
        if whites != 0 { count += 1 }
        if blacks != 0 { count += 1 }
        if midtones != 0 { count += 1 }
        if highlightRolloff != 0 { count += 1 }
        if temperature != 0 { count += 1 }
        if tint != 0 { count += 1 }
        if vibrance != 0 { count += 1 }
        if saturation != 0 { count += 1 }
        if hueShift != 0 { count += 1 }
        if colorDensity != 0 { count += 1 }
        if skinSaturation != 0 { count += 1 }
        if greenSaturation != 0 { count += 1 }
        if blueSaturation != 0 { count += 1 }
        if highlightWarmth != 0 { count += 1 }
        if shadowCoolness != 0 { count += 1 }
        if clarity != 0 { count += 1 }
        if sharpen != 0 { count += 1 }
        if grain != 0 { count += 1 }
        if halation != 0 { count += 1 }
        if bloom != 0 { count += 1 }
        if vignette != 0 { count += 1 }
        if fade != 0 { count += 1 }
        if tonalTransparency != 0 { count += 1 }
        if colorTransparency != 0 { count += 1 }
        return count
    }
}

struct PhotoEdit: Codable, Equatable {
    var lookID: String?
    var lutID: String?
    var strength: Double = 1
    var lutStrength: Double = 1
    var adjustments = Adjustments.neutral
    var curves = CurveSet.identity

    enum CodingKeys: String, CodingKey {
        case lookID, lutID, strength, lutStrength, adjustments, curves
    }

    init(lookID: String? = nil, lutID: String? = nil, strength: Double = 1,
         lutStrength: Double = 1, adjustments: Adjustments = .neutral,
         curves: CurveSet = .identity) {
        self.lookID = lookID
        self.lutID = lutID
        self.strength = strength
        self.lutStrength = lutStrength
        self.adjustments = adjustments
        self.curves = curves
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        lookID = try c.decodeIfPresent(String.self, forKey: .lookID)
        lutID = try c.decodeIfPresent(String.self, forKey: .lutID)
        strength = try c.decodeIfPresent(Double.self, forKey: .strength) ?? 1
        lutStrength = try c.decodeIfPresent(Double.self, forKey: .lutStrength) ?? 1
        adjustments = try c.decodeIfPresent(Adjustments.self, forKey: .adjustments) ?? .neutral
        curves = try c.decodeIfPresent(CurveSet.self, forKey: .curves) ?? .identity
    }

    var usesLUT: Bool { lutID != nil }
}

// MARK: - Photo

struct PhotoMetadata: Equatable {
    var camera: String?
    var lens: String?
    var iso: String?
    var aperture: String?
    var shutter: String?
    var focalLength: String?
    var captured: Date?

    var hasContent: Bool {
        [camera, lens, iso, aperture, shutter, focalLength].contains { $0 != nil }
    }
}

/// Lightroom-style colour labels for the library. They are metadata only and
/// never affect the developed image.
enum PhotoColorLabel: String, Codable, CaseIterable, Identifiable {
    case red
    case yellow
    case green
    case blue
    case purple

    var id: String { rawValue }

    var title: String {
        switch self {
        case .red: return T("红", "Red")
        case .yellow: return T("黄", "Yellow")
        case .green: return T("绿", "Green")
        case .blue: return T("蓝", "Blue")
        case .purple: return T("紫", "Purple")
        }
    }
}

struct Photo: Identifiable {
    let id: UUID
    let url: URL
    let name: String
    var metadata: PhotoMetadata
    var pixelSize: CGSize
    var edit: PhotoEdit
    var thumbnail: CGImage?
    var previewImage: CGImage? = nil
    var previewLoaded = false
    var previewError: String?
    var sourceStats: ImageStats = .empty
    /// Folder this photograph was discovered in. `nil` means it was imported
    /// directly and belongs to the root library.
    var folder: URL? = nil
    var isFavorite = false
    var colorLabel: PhotoColorLabel? = nil
}

struct ImageStats: Equatable {
    var meanLuma: Double
    var p05: Double
    var p50: Double
    var p95: Double

    static let empty = ImageStats(meanLuma: 0.5, p05: 0.0, p50: 0.5, p95: 1.0)
}

struct HistogramData: Equatable {
    var luma: [Float]
    var red: [Float]
    var green: [Float]
    var blue: [Float]

    static let empty = HistogramData(
        luma: Array(repeating: 0, count: 256),
        red: Array(repeating: 0, count: 256),
        green: Array(repeating: 0, count: 256),
        blue: Array(repeating: 0, count: 256)
    )
}

/// Histogram-derived measurements used by the two Transparency sliders.
struct ToneStats: Equatable {
    var blackPoint: Double = 0.0
    var whitePoint: Double = 1.0
    var whiteAverageR: Double = 0.9
    var whiteAverageG: Double = 0.9
    var whiteAverageB: Double = 0.9
    var blackAverageR: Double = 0.1
    var blackAverageG: Double = 0.1
    var blackAverageB: Double = 0.1
    var whiteDeltaR: Double = 0
    var whiteDeltaG: Double = 0
    var whiteDeltaB: Double = 0
    var blackDeltaR: Double = 0
    var blackDeltaG: Double = 0
    var blackDeltaB: Double = 0
    var whiteCount: Int = 0
    var blackCount: Int = 0

    static let empty = ToneStats()

    var hasWhiteCast: Bool {
        whiteCount > 80 && (abs(whiteDeltaR) + abs(whiteDeltaG) + abs(whiteDeltaB)) > 0.012
    }

    var hasBlackCast: Bool {
        blackCount > 80 && (abs(blackDeltaR) + abs(blackDeltaG) + abs(blackDeltaB)) > 0.012
    }

    var castDescription: String {
        var parts: [String] = []
        if hasWhiteCast {
            parts.append(T("高光偏\(dominantWhiteCast)", "highlights \(whiteHueEn)"))
        }
        if hasBlackCast {
            parts.append(T("阴影偏\(dominantBlackCast)", "shadows \(blackHueEn)"))
        }
        return parts.joined(separator: " · ")
    }

    private var dominantWhiteCast: String {
        let r = whiteDeltaR, g = whiteDeltaG, b = whiteDeltaB
        // Positive delta means the channel must be raised to neutralise a cast.
        if b > max(r, g) + 0.01 { return "黄" }
        if r > max(g, b) + 0.01 { return "青" }
        if g > max(r, b) + 0.01 { return "洋红" }
        return "色偏"
    }

    private var dominantBlackCast: String {
        let r = blackDeltaR, g = blackDeltaG, b = blackDeltaB
        if g < min(r, b) - 0.008 { return "绿" }
        if r < min(g, b) - 0.008 { return "青" }
        if b < min(r, g) - 0.008 { return "黄" }
        return "色偏"
    }

    private var whiteHueEn: String {
        if whiteDeltaB > max(whiteDeltaR, whiteDeltaG) + 0.01 { return "yellow" }
        if whiteDeltaR > max(whiteDeltaG, whiteDeltaB) + 0.01 { return "cyan" }
        if whiteDeltaG > max(whiteDeltaR, whiteDeltaB) + 0.01 { return "magenta" }
        return "cast"
    }

    private var blackHueEn: String {
        if blackDeltaG < min(blackDeltaR, blackDeltaB) - 0.008 { return "green" }
        if blackDeltaR < min(blackDeltaG, blackDeltaB) - 0.008 { return "cyan" }
        if blackDeltaB < min(blackDeltaR, blackDeltaG) - 0.008 { return "yellow" }
        return "cast"
    }
}
