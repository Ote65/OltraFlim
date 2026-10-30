import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

/// Disk cache for the small library thumbnails. Only derived previews live
/// here; the original photographs are never copied. Cache files are keyed by
/// path plus size/modification date so an externally replaced file re-renders.
final class ThumbnailCache {
    static let shared = ThumbnailCache()

    let root: URL
    private let lock = NSLock()

    init() {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Caches")
        root = caches
            .appendingPathComponent("studio.oltra.oltraflim", isDirectory: true)
            .appendingPathComponent("thumbnails-v1", isDirectory: true)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    /// Returns a cached thumbnail, generating and persisting it on first use.
    func thumbnail(for url: URL, maxPixel: CGFloat = 480) -> CGImage? {
        if let cached = cachedThumbnail(for: url) { return cached }
        guard let image = ImageLoader.shared.thumbnail(url: url, maxPixel: maxPixel) else { return nil }
        store(image, for: url)
        return image
    }

    private func cachedThumbnail(for url: URL) -> CGImage? {
        let file = fileURL(for: url)
        guard let source = CGImageSourceCreateWithURL(file as CFURL, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(
            source, 0,
            [kCGImageSourceShouldCacheImmediately: true] as CFDictionary
        )
    }

    private func store(_ image: CGImage, for url: URL) {
        let key = key(for: url)
        let file = root.appendingPathComponent(key + ".jpg")
        let temporary = root.appendingPathComponent(key + ".tmp-\(UUID().uuidString)")
        guard let destination = CGImageDestinationCreateWithURL(
            temporary as CFURL, UTType.jpeg.identifier as CFString, 1, nil
        ) else { return }
        CGImageDestinationAddImage(
            destination, image,
            [kCGImageDestinationLossyCompressionQuality: 0.82] as CFDictionary
        )
        guard CGImageDestinationFinalize(destination) else {
            try? FileManager.default.removeItem(at: temporary)
            return
        }
        lock.lock()
        defer { lock.unlock() }
        if FileManager.default.fileExists(atPath: file.path) {
            _ = try? FileManager.default.replaceItemAt(file, withItemAt: temporary)
        } else {
            try? FileManager.default.moveItem(at: temporary, to: file)
        }
        if FileManager.default.fileExists(atPath: temporary.path) {
            try? FileManager.default.removeItem(at: temporary)
        }
    }

    private func key(for url: URL) -> String {
        let standardized = url.standardizedFileURL
        let values = try? standardized.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
        let stamp = "\(standardized.path)|\(values?.fileSize ?? 0)|\(values?.contentModificationDate?.timeIntervalSince1970 ?? 0)"
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in stamp.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01B3
        }
        let hex = String(hash, radix: 16)
        return String(repeating: "0", count: max(0, 16 - hex.count)) + hex
    }

    private func fileURL(for url: URL) -> URL {
        root.appendingPathComponent(key(for: url) + ".jpg")
    }

    func sizeOnDisk() -> Int64 {
        lock.lock()
        defer { lock.unlock() }
        return StorageInspector.size(of: root)
    }

    func clear() {
        lock.lock()
        defer { lock.unlock() }
        try? FileManager.default.removeItem(at: root)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    /// Keeps the cache bounded without ever touching originals or LUT data.
    func prune(maxBytes: Int64 = 512 * 1024 * 1024) {
        lock.lock()
        defer { lock.unlock() }
        let keys: [URLResourceKey] = [.fileSizeKey, .contentModificationDateKey, .isRegularFileKey]
        guard let enumerator = FileManager.default.enumerator(
            at: root, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles]
        ) else { return }
        var entries: [(url: URL, date: Date, size: Int64)] = []
        var total: Int64 = 0
        for case let file as URL in enumerator {
            guard let values = try? file.resourceValues(forKeys: Set(keys)),
                  values.isRegularFile == true else { continue }
            let size = Int64(values.fileSize ?? 0)
            total += size
            entries.append((file, values.contentModificationDate ?? .distantPast, size))
        }
        guard total > maxBytes else { return }
        let target = maxBytes * 3 / 4
        for entry in entries.sorted(by: { $0.date < $1.date }) {
            try? FileManager.default.removeItem(at: entry.url)
            total -= entry.size
            if total <= target { break }
        }
    }
}

enum StorageInspector {
    static func size(of folder: URL) -> Int64 {
        let keys: [URLResourceKey] = [.isRegularFileKey, .fileSizeKey, .totalFileAllocatedSizeKey, .fileAllocatedSizeKey]
        guard let enumerator = FileManager.default.enumerator(
            at: folder, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles]
        ) else { return 0 }
        var total: Int64 = 0
        for case let file as URL in enumerator {
            guard let values = try? file.resourceValues(forKeys: Set(keys)),
                  values.isRegularFile == true else { continue }
            let size = values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? values.fileSize ?? 0
            total += Int64(size)
        }
        return total
    }
}
