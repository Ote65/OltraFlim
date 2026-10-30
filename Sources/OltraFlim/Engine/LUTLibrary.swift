import Foundation
import Metal

struct LUTPackProgress {
    var loaded: Int
    var total: Int
    var phase: String
}

/// Loads the entire 33³ film pack into GPU 3D textures. The pack is only ~32 MB,
/// so it stays resident and every look preview is a single texture bind away.
final class LUTLibrary {
    private(set) var film: [String: MTLTexture] = [:]
    private(set) var userLUTs: [String: MTLTexture] = [:]
    private(set) var neutral0: MTLTexture?
    private(set) var neutral15: MTLTexture?
    let size: Int
    private let userLock = NSLock()

    init(size: Int = 33) {
        self.size = size
    }

    func registerUserLUT(id: String, texture: MTLTexture) {
        userLock.lock()
        userLUTs[id] = texture
        userLock.unlock()
    }

    func userLUT(_ id: String?) -> MTLTexture? {
        guard let id else { return nil }
        userLock.lock()
        defer { userLock.unlock() }
        return userLUTs[id]
    }

    func removeUserLUT(id: String) {
        userLock.lock()
        userLUTs[id] = nil
        userLock.unlock()
    }

    func load(device: MTLDevice, catalog: FilmCatalog, progress: @escaping (LUTPackProgress) -> Void) throws {
        let total = catalog.stocks.reduce(0) { $0 + $1.variants.count } + 2
        var loaded = 0
        let base = ResourceLocator.resourceURL("LUTs")
        guard FileManager.default.fileExists(atPath: base.path) else {
            throw RendererError.missingResources("LUTs")
        }

        var results: [String: MTLTexture] = [:]
        for stock in catalog.stocks {
            for variant in stock.variants {
                let url = base.appendingPathComponent(variant.lut)
                let texture = try makeTexture(device: device, url: url)
                results[variant.id] = texture
                loaded += 1
                if loaded % 8 == 0 {
                    progress(LUTPackProgress(loaded: loaded, total: total, phase: "Preparing film stock"))
                }
            }
        }

        let n0 = try makeTexture(device: device, url: base.appendingPathComponent("neutral-0.bin"))
        let n15 = try makeTexture(device: device, url: base.appendingPathComponent("neutral-15.bin"))
        loaded += 2
        progress(LUTPackProgress(loaded: loaded, total: total, phase: "Ready"))

        film = results
        neutral0 = n0
        neutral15 = n15
    }

    private func makeTexture(device: MTLDevice, url: URL) throws -> MTLTexture {
        let data = try Data(contentsOf: url, options: [.mappedIfSafe])
        let expected = size * size * size * 8
        guard data.count >= expected else {
            throw RendererError.corruptLUT(url.lastPathComponent)
        }
        let descriptor = MTLTextureDescriptor()
        descriptor.textureType = .type3D
        descriptor.pixelFormat = .rgba16Float
        descriptor.width = size
        descriptor.height = size
        descriptor.depth = size
        descriptor.usage = [.shaderRead]
        descriptor.storageMode = device.hasUnifiedMemory ? .shared : .managed
        guard let texture = device.makeTexture(descriptor: descriptor) else {
            throw RendererError.textureAllocation
        }
        let bytesPerRow = size * 8
        let bytesPerImage = bytesPerRow * size
        data.withUnsafeBytes { raw in
            guard let base = raw.baseAddress else { return }
            texture.replace(
                region: MTLRegionMake3D(0, 0, 0, size, size, size),
                mipmapLevel: 0,
                slice: 0,
                withBytes: base,
                bytesPerRow: bytesPerRow,
                bytesPerImage: bytesPerImage
            )
        }
        if !device.hasUnifiedMemory, let storage = texture as MTLTexture? {
            // Managed textures must be flushed after CPU writes.
            _ = storage
        }
        return texture
    }
}

enum ResourceLocator {
    static var root: URL {
        if let resource = Bundle.main.resourceURL,
           FileManager.default.fileExists(atPath: resource.appendingPathComponent("catalog.json").path) {
            return resource
        }
        // Development / CLI fallback: run from the repository root.
        let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let local = cwd.appendingPathComponent("Resources")
        if FileManager.default.fileExists(atPath: local.appendingPathComponent("catalog.json").path) {
            return local
        }
        if let resource = Bundle.main.resourceURL {
            return resource
        }
        return local
    }

    static func resourceURL(_ name: String) -> URL {
        root.appendingPathComponent(name)
    }
}
