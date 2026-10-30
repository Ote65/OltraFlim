import Foundation
import Metal

struct CubeLUT {
    var title: String
    var size: Int
    /// n³ × 3 floats. Index = ((blue * n + green) * n + red) * 3,
    /// matching .cube's red-fastest ordering and Metal's 3D layout.
    var values: [Float]
}

enum LUTImportError: LocalizedError {
    case unreadable
    case missingSize
    case oneDimensional
    case badSize(Int)
    case badEntryCount(expected: Int, actual: Int)
    case unsupported

    var errorDescription: String? {
        switch self {
        case .unreadable:
            return T("无法读取这个 .cube 文件。", "The .cube file could not be read.")
        case .missingSize:
            return T("缺少 LUT_3D_SIZE，无法识别这个 3D LUT。", "LUT_3D_SIZE is missing; this is not a usable 3D LUT.")
        case .oneDimensional:
            return T("暂不支持 1D LUT，请导入 3D .cube。", "1D LUTs are not supported yet. Import a 3D .cube.")
        case .badSize(let size):
            return T("LUT 尺寸 \(size)³ 不支持（支持 2–65）。", "Unsupported LUT size \(size)³ (allowed 2–65).")
        case .badEntryCount(let expected, let actual):
            return T("LUT 数据不完整：应为 \(expected) 个采样，实际 \(actual) 个。",
                     "The LUT is incomplete: expected \(expected) samples, found \(actual).")
        case .unsupported:
            return T("这个 LUT 格式暂时无法导入。", "This LUT format is not supported.")
        }
    }
}

enum LUTImporter {
    static func parse(url: URL) throws -> CubeLUT {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else {
            throw LUTImportError.unreadable
        }
        var size: Int?
        var title: String?
        var domainMin = SIMD3<Float>(0, 0, 0)
        var domainMax = SIMD3<Float>(1, 1, 1)
        var values: [Float] = []
        var valuesReserve = 0

        for rawLine in text.split(whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("#") { continue }
            let upper = line.uppercased()
            if upper.hasPrefix("TITLE") {
                if let range = line.range(of: "\"") {
                    title = String(line[range.upperBound...]).trimmingCharacters(in: CharacterSet(charactersIn: "\""))
                }
                continue
            }
            if upper.hasPrefix("LUT_3D_SIZE") {
                let parts = line.split(whereSeparator: { $0 == " " || $0 == "\t" })
                guard parts.count >= 2, let n = Int(parts[1]) else { throw LUTImportError.missingSize }
                size = n
                valuesReserve = n * n * n * 3
                continue
            }
            if upper.hasPrefix("LUT_3D_INPUT_RANGE") {
                let parts = line.split(whereSeparator: { $0 == " " || $0 == "\t" })
                if parts.count >= 3, let lo = Float(parts[1]), let hi = Float(parts[2]) {
                    domainMin = SIMD3<Float>(lo, lo, lo)
                    domainMax = SIMD3<Float>(hi, hi, hi)
                }
                continue
            }
            if upper.hasPrefix("DOMAIN_MIN") {
                let parts = line.split(whereSeparator: { $0 == " " || $0 == "\t" })
                if parts.count >= 4, let r = Float(parts[1]), let g = Float(parts[2]), let b = Float(parts[3]) {
                    domainMin = SIMD3<Float>(r, g, b)
                }
                continue
            }
            if upper.hasPrefix("DOMAIN_MAX") {
                let parts = line.split(whereSeparator: { $0 == " " || $0 == "\t" })
                if parts.count >= 4, let r = Float(parts[1]), let g = Float(parts[2]), let b = Float(parts[3]) {
                    domainMax = SIMD3<Float>(r, g, b)
                }
                continue
            }
            if upper.hasPrefix("LUT_1D_SIZE") {
                throw LUTImportError.oneDimensional
            }
            let parts = line.split(whereSeparator: { $0 == " " || $0 == "\t" })
            if parts.count == 3 {
                if values.isEmpty { values.reserveCapacity(valuesReserve) }
                if let r = Float(parts[0]), let g = Float(parts[1]), let b = Float(parts[2]) {
                    let minV = min(domainMin.x, min(domainMin.y, domainMin.z))
                    let maxV = max(domainMax.x, max(domainMax.y, domainMax.z))
                    let span = max(maxV - minV, 1e-6)
                    values.append(((r - domainMin.x) / span).clamped(to: 0...1))
                    values.append(((g - domainMin.y) / span).clamped(to: 0...1))
                    values.append(((b - domainMin.z) / span).clamped(to: 0...1))
                }
            }
        }

        guard let n = size else { throw LUTImportError.missingSize }
        guard n >= 2, n <= 65 else { throw LUTImportError.badSize(n) }
        let expected = n * n * n * 3
        guard values.count == expected else {
            throw LUTImportError.badEntryCount(expected: expected, actual: values.count)
        }
        let name = title?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
            ?? url.deletingPathExtension().lastPathComponent
        return CubeLUT(title: name, size: n, values: values)
    }

    static func writeBinary(_ lut: CubeLUT, to url: URL) throws {
        let count = lut.size * lut.size * lut.size
        var data = Data(count: count * 8)
        data.withUnsafeMutableBytes { raw in
            guard let base = raw.baseAddress else { return }
            let u16 = base.bindMemory(to: UInt16.self, capacity: count * 4)
            for i in 0..<count {
                let src = i * 3
                u16[i * 4 + 0] = Float16(lut.values[src]).bitPattern
                u16[i * 4 + 1] = Float16(lut.values[src + 1]).bitPattern
                u16[i * 4 + 2] = Float16(lut.values[src + 2]).bitPattern
                u16[i * 4 + 3] = Float16(1.0).bitPattern
            }
        }
        try data.write(to: url, options: .atomic)
    }

    static func makeTexture(_ lut: CubeLUT, device: MTLDevice) throws -> MTLTexture {
        let n = lut.size
        let descriptor = MTLTextureDescriptor()
        descriptor.textureType = .type3D
        descriptor.pixelFormat = .rgba16Float
        descriptor.width = n
        descriptor.height = n
        descriptor.depth = n
        descriptor.usage = [.shaderRead]
        descriptor.storageMode = device.hasUnifiedMemory ? .shared : .managed
        guard let texture = device.makeTexture(descriptor: descriptor) else {
            throw RendererError.textureAllocation
        }
        let count = n * n * n
        var data = Data(count: count * 8)
        data.withUnsafeMutableBytes { raw in
            guard let base = raw.baseAddress else { return }
            let u16 = base.bindMemory(to: UInt16.self, capacity: count * 4)
            for i in 0..<count {
                let src = i * 3
                u16[i * 4 + 0] = Float16(lut.values[src]).bitPattern
                u16[i * 4 + 1] = Float16(lut.values[src + 1]).bitPattern
                u16[i * 4 + 2] = Float16(lut.values[src + 2]).bitPattern
                u16[i * 4 + 3] = Float16(1.0).bitPattern
            }
        }
        data.withUnsafeBytes { raw in
            guard let base = raw.baseAddress else { return }
            texture.replace(
                region: MTLRegionMake3D(0, 0, 0, n, n, n),
                mipmapLevel: 0,
                slice: 0,
                withBytes: base,
                bytesPerRow: n * 8,
                bytesPerImage: n * 8 * n
            )
        }
        return texture
    }

    static func makeTexture(fromBinary url: URL, size: Int, device: MTLDevice) throws -> MTLTexture {
        let n = size
        let expected = n * n * n * 8
        let data = try Data(contentsOf: url, options: [.mappedIfSafe])
        guard data.count >= expected else { throw LUTImportError.unsupported }
        let descriptor = MTLTextureDescriptor()
        descriptor.textureType = .type3D
        descriptor.pixelFormat = .rgba16Float
        descriptor.width = n
        descriptor.height = n
        descriptor.depth = n
        descriptor.usage = [.shaderRead]
        descriptor.storageMode = device.hasUnifiedMemory ? .shared : .managed
        guard let texture = device.makeTexture(descriptor: descriptor) else {
            throw RendererError.textureAllocation
        }
        data.withUnsafeBytes { raw in
            guard let base = raw.baseAddress else { return }
            texture.replace(
                region: MTLRegionMake3D(0, 0, 0, n, n, n),
                mipmapLevel: 0,
                slice: 0,
                withBytes: base,
                bytesPerRow: n * 8,
                bytesPerImage: n * 8 * n
            )
        }
        return texture
    }

    static func swatch(for lut: CubeLUT) -> [String] {
        let probes: [(Float, Float, Float)] = [
            (0.22, 0.42, 0.75),  // sky
            (0.55, 0.36, 0.28),  // skin
            (0.18, 0.42, 0.16),  // foliage
            (0.72, 0.72, 0.72)   // highlight
        ]
        let n = lut.size
        return probes.map { probe in
            let r = Int(round(probe.0 * Float(n - 1)))
            let g = Int(round(probe.1 * Float(n - 1)))
            let b = Int(round(probe.2 * Float(n - 1)))
            let idx = ((b * n + g) * n + r) * 3
            let rgb = (lut.values[idx], lut.values[idx + 1], lut.values[idx + 2])
            return String(format: "#%02X%02X%02X",
                          Int(round(rgb.0 * 255)),
                          Int(round(rgb.1 * 255)),
                          Int(round(rgb.2 * 255)))
        }
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
