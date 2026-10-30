import Foundation
import CoreImage
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

struct LoadedImage {
    let image: CGImage
    /// Scene-linear CIImage with highlight headroom. RAW files go through
    /// CIRAWFilter so values above 1.0 survive; everything else is color
    /// managed by Core Image into the same linear working space.
    let linearImage: CIImage?
    let pixelSize: CGSize
    let metadata: PhotoMetadata
    let stats: ImageStats
    /// Upstream-style baseline exposure: center-weighted mean luma normalised
    /// to 18% grey. The film LUT expects that scale.
    let autoExposureEV: Double
    let thumbnail: CGImage?
}

enum ImageLoaderError: LocalizedError {
    case unreadable(String)
    case tooLarge

    var errorDescription: String? {
        switch self {
        case .unreadable(let name): return T("无法读取 \(name)。", "Could not read \(name).")
        case .tooLarge: return T("这张照片太大，无法打开。", "This image is too large to open.")
        }
    }
}

final class ImageLoader {
    static let shared = ImageLoader()

    /// Grey target used by spektrafilm's auto exposure.
    static let midGray: Double = 0.184

    private let context: CIContext
    private let srgb = CGColorSpace(name: CGColorSpace.sRGB)!
    private let linearSRGB = CGColorSpace(name: CGColorSpace.extendedLinearSRGB)!

    private init() {
        context = CIContext(options: [
            .workingColorSpace: CGColorSpace(name: CGColorSpace.linearSRGB)!,
            .outputColorSpace: srgb,
            .cacheIntermediates: false
        ])
    }

    /// Decodes a display-sized preview through ImageIO so a 45 MP original is
    /// never expanded into a full-resolution RGBA buffer just to fill a window.
    /// RAW files take the CIRAWFilter path so the film engine receives
    /// scene-linear data instead of Apple's display rendering.
    func loadPreview(url: URL, maxPixel: CGFloat = 2600) throws -> LoadedImage {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              CGImageSourceGetCount(source) > 0 else {
            throw ImageLoaderError.unreadable(url.lastPathComponent)
        }
        let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]

        if let raw = rawImage(url: url, maxPixel: maxPixel, props: props) {
            return raw
        }

        let thumbOptions: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: Int(max(maxPixel, 1)),
            kCGImageSourceShouldCacheImmediately: true
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbOptions as CFDictionary) else {
            return try loadPreviewWithCoreImage(url: url, maxPixel: maxPixel)
        }
        let pixelSize = Self.orientedPixelSize(props, fallback: cg)
        guard pixelSize.width > 1, pixelSize.height > 1 else {
            throw ImageLoaderError.unreadable(url.lastPathComponent)
        }
        let linear = CIImage(cgImage: cg)
        return LoadedImage(
            image: cg,
            linearImage: linear,
            pixelSize: pixelSize,
            metadata: metadata(from: props),
            stats: analyze(cg),
            autoExposureEV: autoExposureEV(for: linear),
            thumbnail: nil
        )
    }

    /// Rare formats that cannot produce an ImageIO thumbnail keep the old
    /// Core Image path so opening them still works.
    private func loadPreviewWithCoreImage(url: URL, maxPixel: CGFloat) throws -> LoadedImage {
        let options: [CIImageOption: Any] = [
            .applyOrientationProperty: true,
            .cacheImmediately: true
        ]
        guard let full = CIImage(contentsOf: url, options: options) else {
            throw ImageLoaderError.unreadable(url.lastPathComponent)
        }
        let extent = full.extent
        guard extent.width > 1, extent.height > 1 else {
            throw ImageLoaderError.unreadable(url.lastPathComponent)
        }
        let maxSide = max(extent.width, extent.height)
        let scale = min(1.0, maxPixel / maxSide)
        let output = scale < 0.999
            ? full.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
            : full
        guard let cg = context.createCGImage(output, from: output.extent, format: .RGBA8, colorSpace: srgb) else {
            throw ImageLoaderError.unreadable(url.lastPathComponent)
        }
        return LoadedImage(
            image: cg,
            linearImage: output,
            pixelSize: CGSize(width: extent.width, height: extent.height),
            metadata: metadata(for: url),
            stats: analyze(cg),
            autoExposureEV: autoExposureEV(for: output),
            thumbnail: nil
        )
    }

    func loadFull(url: URL) throws -> LoadedImage {
        let props: [CFString: Any]?
        if let source = CGImageSourceCreateWithURL(url as CFURL, nil) {
            props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        } else {
            props = nil
        }

        if let raw = rawImage(url: url, maxPixel: 16000, props: props) {
            return raw
        }

        let options: [CIImageOption: Any] = [
            .applyOrientationProperty: true,
            .cacheImmediately: true
        ]
        guard let full = CIImage(contentsOf: url, options: options) else {
            throw ImageLoaderError.unreadable(url.lastPathComponent)
        }
        let extent = full.extent
        guard extent.width > 1, extent.height > 1 else {
            throw ImageLoaderError.unreadable(url.lastPathComponent)
        }
        // Metal's practical maximum texture is 16384 px on a side. Scale down
        // anything larger rather than failing the export outright.
        let maxSide = max(extent.width, extent.height)
        let limit: CGFloat = 16000
        var output = full
        if maxSide > limit {
            let scale = limit / maxSide
            output = full.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        }
        guard let cg = context.createCGImage(output, from: output.extent, format: .RGBA8, colorSpace: srgb) else {
            throw ImageLoaderError.unreadable(url.lastPathComponent)
        }
        return LoadedImage(
            image: cg,
            linearImage: output,
            pixelSize: CGSize(width: output.extent.width, height: output.extent.height),
            metadata: metadata(for: url),
            stats: analyze(cg),
            autoExposureEV: autoExposureEV(for: output),
            thumbnail: nil
        )
    }

    func thumbnail(url: URL, maxPixel: CGFloat = 320) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
            kCGImageSourceShouldCacheImmediately: true
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    // MARK: - RAW

    /// Scene-linear RAW decode. `boostAmount` and the local tone curve are
    /// switched off so Core Image returns a linear response with values above
    /// 1.0 for highlights, instead of the display rendering ImageIO would give.
    private func rawImage(url: URL, maxPixel: CGFloat, props: [CFString: Any]?) -> LoadedImage? {
        guard let filter = CIRAWFilter(imageURL: url) else { return nil }
        filter.isDraftModeEnabled = false
        filter.boostAmount = 0
        filter.boostShadowAmount = 0
        filter.localToneMapAmount = 0
        // Without this the RAW is clipped at 1.0; the ACEScc domain needs the
        // highlight headroom. 1.0 is Apple's default EDR amount.
        filter.extendedDynamicRangeAmount = 1
        filter.exposure = 0
        filter.isGamutMappingEnabled = false
        if filter.isLensCorrectionSupported {
            filter.isLensCorrectionEnabled = true
        }
        let native = filter.nativeSize
        guard native.width > 1, native.height > 1 else { return nil }
        let scale = min(1.0, maxPixel / max(native.width, native.height))
        filter.scaleFactor = Float(scale)
        if let raw = (props?[kCGImagePropertyOrientation] as? NSNumber)?.uint32Value,
           let orientation = CGImagePropertyOrientation(rawValue: raw) {
            filter.orientation = orientation
        }
        guard let linear = filter.outputImage else { return nil }
        let extent = linear.extent.integral
        guard extent.width > 1, extent.height > 1 else { return nil }
        guard let display = context.createCGImage(linear, from: extent, format: .RGBA8, colorSpace: srgb) else {
            return nil
        }
        return LoadedImage(
            image: display,
            linearImage: linear,
            pixelSize: CGSize(width: extent.width, height: extent.height),
            metadata: metadata(from: props),
            stats: analyze(display),
            autoExposureEV: autoExposureEV(for: linear),
            thumbnail: nil
        )
    }

    // MARK: - Auto exposure

    /// Center-weighted mean luminance buffered to 18% grey, mirroring
    /// spektrafilm's `measure_autoexposure_ev(method: .center_weighted)`.
    private func autoExposureEV(for image: CIImage) -> Double {
        let width = 128, height = 128
        let maxSide = max(image.extent.width, image.extent.height)
        guard maxSide > 1 else { return 0 }
        let scale = maxSide / CGFloat(max(width, height))
        let small = image.transformed(by: CGAffineTransform(scaleX: 1 / scale, y: 1 / scale))
        var buffer = [Float](repeating: 0, count: width * height * 4)
        buffer.withUnsafeMutableBytes { raw in
            guard let base = raw.baseAddress else { return }
            context.render(
                small, toBitmap: base, rowBytes: width * 4 * 4,
                bounds: CGRect(x: 0, y: 0, width: width, height: height),
                format: .RGBAf, colorSpace: linearSRGB
            )
        }
        // Upstream normalises so the long edge spans [-0.5, 0.5]; sigma is 0.2.
        let longSide = Double(max(width, height))
        let sx = Double(width) / longSide
        let sy = Double(height) / longSide
        var weighted = 0.0
        var total = 0.0
        for y in 0..<height {
            let ny = (Double(y) / Double(height) - 0.5) * sy
            for x in 0..<width {
                let nx = (Double(x) / Double(width) - 0.5) * sx
                let weight = exp(-(nx * nx + ny * ny) / (2 * 0.2 * 0.2))
                let index = (y * width + x) * 4
                let luma = 0.2126 * Double(buffer[index])
                    + 0.7152 * Double(buffer[index + 1])
                    + 0.0722 * Double(buffer[index + 2])
                weighted += max(luma, 0) * weight
                total += weight
            }
        }
        guard total > 0, weighted > 1e-9 else { return 0 }
        let mean = weighted / total
        return (-log2(mean / Self.midGray)).clamped(to: -4...4)
    }

    // MARK: - Metadata

    private func metadata(for url: URL) -> PhotoMetadata {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else {
            return PhotoMetadata()
        }
        return metadata(from: props)
    }

    private func metadata(from props: [CFString: Any]?) -> PhotoMetadata {
        guard let props else { return PhotoMetadata() }
        let exif = props[kCGImagePropertyExifDictionary] as? [CFString: Any]
        let tiff = props[kCGImagePropertyTIFFDictionary] as? [CFString: Any]
        var meta = PhotoMetadata()
        meta.camera = [tiff?[kCGImagePropertyTIFFMake], tiff?[kCGImagePropertyTIFFModel]]
            .compactMap { $0 as? String }
            .joined(separator: " ")
            .nilIfEmpty
        meta.lens = (exif?[kCGImagePropertyExifLensModel] as? String)?.nilIfEmpty
        if let isoValues = exif?[kCGImagePropertyExifISOSpeedRatings] as? [NSNumber], let first = isoValues.first {
            meta.iso = "ISO \(first.intValue)"
        }
        if let aperture = exif?[kCGImagePropertyExifFNumber] as? NSNumber {
            meta.aperture = String(format: "f/%.1f", aperture.doubleValue)
        }
        if let shutter = exif?[kCGImagePropertyExifExposureTime] as? NSNumber {
            let value = shutter.doubleValue
            if value > 0 {
                if value >= 1 {
                    meta.shutter = String(format: "%.1fs", value)
                } else {
                    meta.shutter = "1/\(Int(round(1 / value)))s"
                }
            }
        }
        if let focal = exif?[kCGImagePropertyExifFocalLength] as? NSNumber {
            meta.focalLength = "\(Int(round(focal.doubleValue)))mm"
        }
        if let dateString = exif?[kCGImagePropertyExifDateTimeOriginal] as? String {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy:MM:dd HH:mm:ss"
            meta.captured = formatter.date(from: dateString)
        }
        return meta
    }

    private static func orientedPixelSize(_ props: [CFString: Any]?, fallback image: CGImage) -> CGSize {
        let width = (props?[kCGImagePropertyPixelWidth] as? NSNumber)?.doubleValue ?? Double(image.width)
        let height = (props?[kCGImagePropertyPixelHeight] as? NSNumber)?.doubleValue ?? Double(image.height)
        let orientation = (props?[kCGImagePropertyOrientation] as? NSNumber)?.intValue ?? 1
        if (5...8).contains(orientation) {
            return CGSize(width: height, height: width)
        }
        return CGSize(width: width, height: height)
    }

    // MARK: - Analysis

    private func analyze(_ image: CGImage) -> ImageStats {
        let width = min(image.width, 256)
        let height = min(image.height, 256)
        guard width > 2, height > 2 else { return .empty }
        var buffer = [UInt8](repeating: 0, count: width * height * 4)
        guard let ctx = CGContext(
            data: &buffer,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: srgb,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return .empty }
        ctx.interpolationQuality = .low
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        var lumas: [Double] = []
        lumas.reserveCapacity(width * height)
        for index in stride(from: 0, to: buffer.count, by: 4) {
            let r = Double(buffer[index]) / 255
            let g = Double(buffer[index + 1]) / 255
            let b = Double(buffer[index + 2]) / 255
            lumas.append(0.2126 * r + 0.7152 * g + 0.0722 * b)
        }
        lumas.sort()
        let count = lumas.count
        let sum = lumas.reduce(0, +)
        return ImageStats(
            meanLuma: sum / Double(count),
            p05: lumas[Int(Double(count) * 0.05)],
            p50: lumas[Int(Double(count) * 0.50)],
            p95: lumas[min(count - 1, Int(Double(count) * 0.95))]
        )
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
