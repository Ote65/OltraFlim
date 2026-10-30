import Foundation
import Metal

enum CurveTextureBuilder {
    static let size = 256

    static func make(_ curves: CurveSet, device: MTLDevice, existing: MTLTexture? = nil) -> MTLTexture? {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba16Float, width: size, height: 1, mipmapped: false
        )
        descriptor.usage = [.shaderRead]
        descriptor.storageMode = device.hasUnifiedMemory ? .shared : .managed
        let texture: MTLTexture
        if let existing, existing.width == size, existing.height == 1 {
            texture = existing
        } else {
            guard let created = device.makeTexture(descriptor: descriptor) else { return nil }
            texture = created
        }

        let luma = CurveMath.values(points: curves.luma.points, count: size)
        let red = CurveMath.values(points: curves.red.points, count: size)
        let green = CurveMath.values(points: curves.green.points, count: size)
        let blue = CurveMath.values(points: curves.blue.points, count: size)

        var data = [UInt8](repeating: 0, count: size * 8)
        data.withUnsafeMutableBytes { raw in
            guard let base = raw.baseAddress else { return }
            let u16 = base.bindMemory(to: UInt16.self, capacity: size * 4)
            for i in 0..<size {
                u16[i * 4 + 0] = Float16(red[i]).bitPattern
                u16[i * 4 + 1] = Float16(green[i]).bitPattern
                u16[i * 4 + 2] = Float16(blue[i]).bitPattern
                u16[i * 4 + 3] = Float16(luma[i]).bitPattern
            }
        }
        data.withUnsafeBytes { raw in
            guard let base = raw.baseAddress else { return }
            texture.replace(region: MTLRegionMake2D(0, 0, size, 1),
                            mipmapLevel: 0,
                            withBytes: base,
                            bytesPerRow: size * 8)
        }
        return texture
    }
}
