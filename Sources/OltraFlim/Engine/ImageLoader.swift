import Foundation
import CoreImage
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

struct LoadedImage {
    let image: CGImage
    let pixelSize: CGSize
    let metadata: PhotoMetadata
    let stats: ImageStats
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

    private let context: CIContext
    private let srgb = CGColorSpace(name: CGColorSpace.sRGB)!

    private init() {
        context = CIContext(options: [
            .workingColorSpace: CGColorSpace(name: CGColorSpace.linearSRGB)!,
            .outputColorSpace: srgb,
            .cacheIntermediates: false
        ])
    }

    func loadPreview(url: URL, maxPixel: CGFloat = 2600) throws -> LoadedImage {
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
        let output: CIImage
        if scale < 0.999 {
            output = full.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        } else {
            output = full
        }
        guard let cg = context.createCGImage(output, from: output.extent, format: .RGBA8, colorSpace: srgb) else {
            throw ImageLoaderError.unreadable(url.lastPathComponent)
        }
        let properties = metadata(for: url)
        let stats = analyze(cg)
        return LoadedImage(
            image: cg,
            pixelSize: CGSize(width: extent.width, height: extent.height),
            metadata: properties,
            stats: stats,
            thumbnail: nil
        )
    }

    func loadFull(url: URL) throws -> CGImage {
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
        return cg
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

    // MARK: - Metadata

    private func metadata(for url: URL) -> PhotoMetadata {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else {
            return PhotoMetadata()
        }
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
