import Foundation
import Metal
import MetalKit
import CoreGraphics
import AppKit
import Combine

enum RendererError: LocalizedError {
    case noMetalDevice
    case missingResources(String)
    case corruptLUT(String)
    case textureAllocation
    case shaderCompilation(String)
    case exportFailed

    var errorDescription: String? {
        switch self {
        case .noMetalDevice: return T("没有找到支持 Metal 的 GPU。", "No Metal-capable GPU was found.")
        case .missingResources(let name): return T("缺少应用资源：\(name)。", "Missing app resource: \(name).")
        case .corruptLUT(let name): return T("胶片包数据不完整：\(name)。", "The film pack entry \(name) is incomplete.")
        case .textureAllocation: return T("无法分配 GPU 纹理。", "Could not allocate a GPU texture.")
        case .shaderCompilation(let message): return T("胶片引擎编译失败：\(message)", "Film engine failed to compile: \(message)")
        case .exportFailed: return T("照片导出失败。", "The image could not be exported.")
        }
    }
}

// MARK: - Uniforms (must match Shaders.metal exactly)

struct RenderUniforms {
    var exposure: Float = 0
    var contrast: Float = 0
    var highlights: Float = 0
    var shadows: Float = 0
    var whites: Float = 0
    var blacks: Float = 0
    var temperature: Float = 0
    var tint: Float = 0
    var vibrance: Float = 0
    var saturation: Float = 0
    var clarity: Float = 0
    var sharpen: Float = 0
    var grain: Float = 0
    var grainSize: Float = 38
    var grainSeed: Float = 0
    var halation: Float = 0
    var halationThreshold: Float = 55
    var vignette: Float = 0
    var strength: Float = 1
    var showOriginal: Float = 0
    var useFilm: Float = 1
    var ditherSeed: Float = 0
    var imageWidth: Float = 0
    var imageHeight: Float = 0
    var previewScale: Float = 1
    var exposureBias: Float = 0
    var destOffsetX: Float = 0
    var destOffsetY: Float = 0
    var useDisplayLUT: Float = 0
    var displayLUTStrength: Float = 1
    var tonalTransparency: Float = 0
    var colorTransparency: Float = 0
    var blackPoint: Float = 0
    var whitePoint: Float = 1
    var whiteDeltaR: Float = 0
    var whiteDeltaG: Float = 0
    var whiteDeltaB: Float = 0
    var blackDeltaR: Float = 0
    var blackDeltaG: Float = 0
    var blackDeltaB: Float = 0
    var halationWarmth: Float = 75
    var halationRadius: Float = 50
    var grainChroma: Float = 0
    var grainShadow: Float = 0
    var fade: Float = 0
    var hueShift: Float = 0
    var colorDensity: Float = 0
    var skinSaturation: Float = 0
    var greenSaturation: Float = 0
    var blueSaturation: Float = 0
    var highlightWarmth: Float = 0
    var shadowCoolness: Float = 0
    var midtones: Float = 0
    var highlightRolloff: Float = 0
    var bloom: Float = 0
    var grainRoughness: Float = 50
    var vignetteMidpoint: Float = 50
    var vignetteRoundness: Float = 0
    var vignetteFeather: Float = 50
    var vignetteCenterX: Float = 0
    var vignetteCenterY: Float = 0

    init(edit: PhotoEdit, look: FilmVariant?, size: CGSize, previewScale: CGFloat, showOriginal: Bool) {
        let a = edit.adjustments
        exposure = Float(a.exposure)
        contrast = Float(a.contrast)
        highlights = Float(a.highlights)
        shadows = Float(a.shadows)
        whites = Float(a.whites)
        blacks = Float(a.blacks)
        temperature = Float(a.temperature)
        tint = Float(a.tint)
        vibrance = Float(a.vibrance)
        saturation = Float(a.saturation)
        clarity = Float(a.clarity)
        sharpen = Float(a.sharpen)
        grain = Float(a.grain)
        grainSize = Float(a.grainSize)
        grainSeed = Float(abs(edit.lookID?.hashValue ?? 1) % 4096) / 100.0
        halation = Float(a.halation)
        halationThreshold = Float(a.halationThreshold)
        vignette = Float(a.vignette)
        strength = Float(edit.strength)
        self.showOriginal = showOriginal ? 1 : 0
        useFilm = look == nil ? 0 : 1
        ditherSeed = Float(abs(edit.lookID?.hashValue ?? 0) % 4096) / 100.0
        imageWidth = Float(size.width)
        imageHeight = Float(size.height)
        self.previewScale = Float(max(1, previewScale))
        exposureBias = Float(look?.exposureEV ?? 0)
        displayLUTStrength = Float(edit.lutStrength)
        tonalTransparency = Float(a.tonalTransparency / 100)
        colorTransparency = Float(a.colorTransparency / 100)
        halationWarmth = Float(a.halationWarmth)
        halationRadius = Float(a.halationRadius)
        grainChroma = Float(a.grainChroma)
        grainShadow = Float(a.grainShadow)
        fade = Float(a.fade)
        hueShift = Float(a.hueShift)
        colorDensity = Float(a.colorDensity)
        skinSaturation = Float(a.skinSaturation)
        greenSaturation = Float(a.greenSaturation)
        blueSaturation = Float(a.blueSaturation)
        highlightWarmth = Float(a.highlightWarmth)
        shadowCoolness = Float(a.shadowCoolness)
        midtones = Float(a.midtones)
        highlightRolloff = Float(a.highlightRolloff)
        bloom = Float(a.bloom)
        grainRoughness = Float(a.grainRoughness)
        vignetteMidpoint = Float(a.vignetteMidpoint)
        vignetteRoundness = Float(a.vignetteRoundness)
        vignetteFeather = Float(a.vignetteFeather)
        vignetteCenterX = Float(a.vignetteCenterX)
        vignetteCenterY = Float(a.vignetteCenterY)
    }
}

struct DisplayUniforms {
    var viewWidth: Float = 0
    var viewHeight: Float = 0
    var imageWidth: Float = 0
    var imageHeight: Float = 0
    var fitScale: Float = 1
    var zoom: Float = 1
    var panX: Float = 0
    var panY: Float = 0
    var backingScale: Float = 2
    var compareEnabled: Float = 0
    var splitX: Float = 0.5
    var pad0: Float = 0
    var pad1: Float = 0
}

// MARK: - Canvas state

final class CanvasState: ObservableObject {
    @Published var zoom: CGFloat = 1
    @Published var pan: CGSize = .zero
    @Published var fitScale: CGFloat = 1
    @Published var backingScale: CGFloat = 2

    var imageSize: CGSize = .zero
    var viewSizePixels: CGSize = .zero
    var onUpdate: (() -> Void)?

    private var targetZoom: CGFloat = 1
    private var targetPan: CGSize = .zero
    private var animationTimer: Timer?
    private var lastTick = Date()

    var isFit: Bool {
        abs(zoom - 1) < 0.001 && abs(pan.width) < 0.5 && abs(pan.height) < 0.5
    }

    var percent: Int { Int(round(fitScale * zoom * 100)) }

    func imageRect(in viewSize: CGSize) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0 else { return .zero }
        let scale = fitScale * zoom / max(backingScale, 1)
        let width = imageSize.width * scale
        let height = imageSize.height * scale
        let center = CGPoint(x: viewSize.width / 2 + pan.width,
                             y: viewSize.height / 2 + pan.height)
        return CGRect(x: center.x - width / 2, y: center.y - height / 2,
                      width: width, height: height)
    }

    func setImage(_ size: CGSize) {
        stopAnimation()
        imageSize = size
        zoom = 1
        pan = .zero
        targetZoom = 1
        targetPan = .zero
    }

    func reset(animated: Bool = true) {
        targetZoom = 1
        targetPan = .zero
        if animated { startAnimation() } else {
            zoom = 1
            pan = .zero
            onUpdate?()
        }
    }

    func actualSize(animated: Bool = true) {
        guard fitScale > 0 else { return }
        targetZoom = (1 / fitScale).clamped(to: 0.15...24)
        targetPan = .zero
        if animated { startAnimation() } else {
            zoom = targetZoom
            pan = .zero
            clampCurrentPan()
            onUpdate?()
        }
    }

    /// Zoom relative to the current fit scale. The target is animated with a
    /// damped follow so wheel/pinch input never feels stepped.
    func zoom(by factor: CGFloat, anchor: CGPoint? = nil) {
        let old = targetZoom
        let next = (targetZoom * factor).clamped(to: 0.15...24)
        targetZoom = next
        if let anchor, viewSizePixels.width > 0 {
            let center = CGPoint(x: viewSizePixels.width / 2, y: viewSizePixels.height / 2)
            let dx = (anchor.x - center.x - targetPan.width * backingScale) * (next / max(old, 0.001) - 1)
            let dy = (anchor.y - center.y - targetPan.height * backingScale) * (next / max(old, 0.001) - 1)
            targetPan.width += dx / backingScale
            targetPan.height += dy / backingScale
        }
        clampTargetPan()
        startAnimation()
    }

    func panBy(dx: CGFloat, dy: CGFloat) {
        targetPan.width += dx
        targetPan.height += dy
        clampTargetPan()
        startAnimation()
    }

    func clampPan() {
        clampTargetPan()
        clampCurrentPan()
    }

    private func clampCurrentPan() {
        guard imageSize.width > 0, viewSizePixels.width > 0 else {
            pan = .zero
            return
        }
        let scale = fitScale * zoom
        let contentW = imageSize.width * scale / backingScale
        let contentH = imageSize.height * scale / backingScale
        let maxX = max(0, (contentW - viewSizePixels.width / backingScale) / 2)
        let maxY = max(0, (contentH - viewSizePixels.height / backingScale) / 2)
        pan.width = pan.width.clamped(to: -maxX...maxX)
        pan.height = pan.height.clamped(to: -maxY...maxY)
    }

    private func clampTargetPan() {
        guard imageSize.width > 0, viewSizePixels.width > 0 else {
            targetPan = .zero
            return
        }
        let scale = fitScale * targetZoom
        let contentW = imageSize.width * scale / backingScale
        let contentH = imageSize.height * scale / backingScale
        let maxX = max(0, (contentW - viewSizePixels.width / backingScale) / 2)
        let maxY = max(0, (contentH - viewSizePixels.height / backingScale) / 2)
        targetPan.width = targetPan.width.clamped(to: -maxX...maxX)
        targetPan.height = targetPan.height.clamped(to: -maxY...maxY)
    }

    private func startAnimation() {
        if animationTimer != nil { return }
        lastTick = Date()
        let timer = Timer(timeInterval: 1.0 / 120.0, repeats: true) { [weak self] _ in
            self?.tick()
        }
        RunLoop.main.add(timer, forMode: .common)
        animationTimer = timer
    }

    private func stopAnimation() {
        animationTimer?.invalidate()
        animationTimer = nil
    }

    private func tick() {
        let now = Date()
        let dt = min(0.05, max(0.001, now.timeIntervalSince(lastTick)))
        lastTick = now

        // Exponential follow with a soft spring-like settle. Zoom is slightly
        // lazier than pan so the image glides rather than snaps.
        let zoomAlpha = CGFloat(1 - exp(-dt * 11.0))
        let panAlpha = CGFloat(1 - exp(-dt * 17.0))
        zoom += (targetZoom - zoom) * zoomAlpha
        pan.width += (targetPan.width - pan.width) * panAlpha
        pan.height += (targetPan.height - pan.height) * panAlpha
        clampCurrentPan()
        onUpdate?()

        let zoomSettled = abs(targetZoom - zoom) < 0.0004
        let panSettled = abs(targetPan.width - pan.width) < 0.05 && abs(targetPan.height - pan.height) < 0.05
        if zoomSettled && panSettled {
            zoom = targetZoom
            pan = targetPan
            stopAnimation()
            onUpdate?()
        }
    }
}

// MARK: - Renderer

final class Renderer {
    let device: MTLDevice
    let queue: MTLCommandQueue
    let lutLibrary: LUTLibrary
    let canvas = CanvasState()

    private let library: MTLLibrary
    private let processPipeline: MTLComputePipelineState
    private let bloomExtractPipeline: MTLComputePipelineState
    private let blurHPipeline: MTLComputePipelineState
    private let blurVPipeline: MTLComputePipelineState
    private let histogramPipeline: MTLComputePipelineState
    private let displayPipeline: MTLRenderPipelineState

    private(set) var sourceTexture: MTLTexture?
    private var processedTexture: MTLTexture?
    private var bloomA: MTLTexture?
    private var bloomB: MTLTexture?
    private var blackTexture: MTLTexture

    private var currentEdit = PhotoEdit()
    private var currentLook: FilmVariant?
    private var filmTexture: MTLTexture?
    private var neutralTexture: MTLTexture?
    private var userLUTTexture: MTLTexture?
    private var curveTexture: MTLTexture?
    private let identityCurveTexture: MTLTexture

    var toneStats = ToneStats.empty

    var needsProcess = true
    var histogramRequested = false
    var compareEnabled = false
    var compareSplit: Double = 0.5

    var onHistogram: ((HistogramData, ToneStats) -> Void)?
    var onError: ((String) -> Void)?

    weak var canvasView: MTKView?

    private let histogramBuffer: MTLBuffer
    private let thumbnailQueue = DispatchQueue(label: "studio.oltra.oltraflim.thumbs", qos: .userInitiated)
    private let stateLock = NSLock()

    init?(lutLibrary: LUTLibrary) {
        guard let device = MTLCreateSystemDefaultDevice(),
              let queue = device.makeCommandQueue() else {
            return nil
        }
        self.device = device
        self.queue = queue
        self.lutLibrary = lutLibrary
        do {
            let sourceURL = ResourceLocator.resourceURL("Shaders.metal")
            let source = try String(contentsOf: sourceURL, encoding: .utf8)
            let options = MTLCompileOptions()
            options.fastMathEnabled = true
            options.languageVersion = .version2_4
            self.library = try device.makeLibrary(source: source, options: options)
        } catch {
            NSLog("OltraFlim shader error: \(error)")
            return nil
        }

        do {
            processPipeline = try Renderer.computePipeline(library, "processImage", device: device)
            bloomExtractPipeline = try Renderer.computePipeline(library, "bloomExtract", device: device)
            blurHPipeline = try Renderer.computePipeline(library, "blurHorizontal", device: device)
            blurVPipeline = try Renderer.computePipeline(library, "blurVertical", device: device)
            histogramPipeline = try Renderer.computePipeline(library, "histogram", device: device)
            displayPipeline = try Renderer.renderPipeline(library, device: device)
        } catch {
            NSLog("OltraFlim pipeline error: \(error)")
            return nil
        }

        guard let histogramBuffer = device.makeBuffer(length: 1032 * MemoryLayout<UInt32>.stride,
                                                      options: .storageModeShared) else {
            return nil
        }
        guard let identityCurve = CurveTextureBuilder.make(.identity, device: device) else {
            return nil
        }
        self.identityCurveTexture = identityCurve
        self.histogramBuffer = histogramBuffer
        self.blackTexture = Renderer.makeBlackTexture(device: device)
        canvas.onUpdate = { [weak self] in self?.redraw() }
    }

    private static func computePipeline(_ library: MTLLibrary, _ name: String, device: MTLDevice) throws -> MTLComputePipelineState {
        guard let function = library.makeFunction(name: name) else {
            throw RendererError.shaderCompilation("missing function \(name)")
        }
        return try device.makeComputePipelineState(function: function)
    }

    private static func renderPipeline(_ library: MTLLibrary, device: MTLDevice) throws -> MTLRenderPipelineState {
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = library.makeFunction(name: "displayVertex")
        descriptor.fragmentFunction = library.makeFunction(name: "displayFragment")
        descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
        descriptor.colorAttachments[0].isBlendingEnabled = false
        return try device.makeRenderPipelineState(descriptor: descriptor)
    }

    private static func makeBlackTexture(device: MTLDevice) -> MTLTexture {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm, width: 1, height: 1, mipmapped: false
        )
        descriptor.usage = [.shaderRead]
        descriptor.storageMode = .shared
        let texture = device.makeTexture(descriptor: descriptor)!
        var pixel: UInt32 = 0
        texture.replace(region: MTLRegionMake2D(0, 0, 1, 1), mipmapLevel: 0,
                        withBytes: &pixel, bytesPerRow: 4)
        return texture
    }

    // MARK: - Source

    func setImage(_ image: CGImage) throws {
        stateLock.lock()
        defer { stateLock.unlock() }
        let texture = try makeTexture(from: image)
        replaceSource(with: texture, size: CGSize(width: image.width, height: image.height))
    }

    private func replaceSource(with texture: MTLTexture, size: CGSize) {
        sourceTexture = texture
        canvas.setImage(size)
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm, width: texture.width, height: texture.height, mipmapped: false
        )
        descriptor.usage = [.shaderRead, .shaderWrite]
        descriptor.storageMode = .shared
        processedTexture = device.makeTexture(descriptor: descriptor)
        let bloomW = max(1, texture.width / 2)
        let bloomH = max(1, texture.height / 2)
        let bloomDescriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba16Float, width: bloomW, height: bloomH, mipmapped: false
        )
        bloomDescriptor.usage = [.shaderRead, .shaderWrite]
        bloomDescriptor.storageMode = .private
        bloomA = device.makeTexture(descriptor: bloomDescriptor)
        bloomB = device.makeTexture(descriptor: bloomDescriptor)
        needsProcess = true
        canvasView?.setNeedsDisplay(canvasView?.bounds ?? .zero)
    }

    private func makeTexture(from image: CGImage) throws -> MTLTexture {
        let width = image.width
        let height = image.height
        guard width > 1, height > 1 else { throw RendererError.textureAllocation }
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        guard let context = CGContext(
            data: &bytes,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
        ) else { throw RendererError.textureAllocation }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm, width: width, height: height, mipmapped: false
        )
        descriptor.usage = [.shaderRead]
        descriptor.storageMode = .shared
        guard let texture = device.makeTexture(descriptor: descriptor) else {
            throw RendererError.textureAllocation
        }
        bytes.withUnsafeBytes { raw in
            guard let base = raw.baseAddress else { return }
            texture.replace(
                region: MTLRegionMake2D(0, 0, width, height),
                mipmapLevel: 0,
                withBytes: base,
                bytesPerRow: width * 4
            )
        }
        return texture
    }

    func clearImage() {
        stateLock.lock()
        defer { stateLock.unlock() }
        sourceTexture = nil
        processedTexture = nil
        bloomA = nil
        bloomB = nil
        canvas.setImage(.zero)
        needsProcess = true
        canvasView?.setNeedsDisplay(canvasView?.bounds ?? .zero)
    }

    // MARK: - State

    func update(edit: PhotoEdit, look: FilmVariant?) {
        let builtCurves = CurveTextureBuilder.make(edit.curves, device: device, existing: curveTexture)
        stateLock.lock()
        currentEdit = edit
        currentLook = look
        curveTexture = builtCurves ?? identityCurveTexture
        userLUTTexture = lutLibrary.userLUT(edit.lutID)
        if let look, let texture = lutLibrary.film[look.id] {
            filmTexture = texture
            neutralTexture = look.exposureEV >= 0.75 ? lutLibrary.neutral15 : lutLibrary.neutral0
        } else {
            filmTexture = nil
            neutralTexture = lutLibrary.neutral0
        }
        needsProcess = true
        stateLock.unlock()
        canvasView?.setNeedsDisplay(canvasView?.bounds ?? .zero)
    }

    func setCompare(enabled: Bool, split: Double) {
        compareEnabled = enabled
        compareSplit = split
        redraw()
    }


    func requestHistogram() {
        histogramRequested = true
        canvasView?.setNeedsDisplay(canvasView?.bounds ?? .zero)
    }

    func setToneStats(_ stats: ToneStats) {
        if toneStats != stats {
            toneStats = stats
            needsProcess = true
            redraw()
        }
    }

    func redraw() {
        canvasView?.setNeedsDisplay(canvasView?.bounds ?? .zero)
    }

    // MARK: - Draw

    func draw(in view: MTKView) {
        guard let commandBuffer = queue.makeCommandBuffer(),
              let pass = view.currentRenderPassDescriptor,
              let drawable = view.currentDrawable else { return }

        stateLock.lock()
        let source = sourceTexture
        let processed = processedTexture
        let neutral = neutralTexture ?? lutLibrary.neutral0 ?? blackTexture
        let film = filmTexture ?? neutral
        let userLUT = userLUTTexture
        let curves = curveTexture ?? identityCurveTexture
        let stats = toneStats
        let bloom = bloomA
        let edit = currentEdit
        let look = currentLook
        let compare = compareEnabled
        let split = compareSplit
        let shouldProcess = needsProcess
        needsProcess = false
        let wantsHistogram = histogramRequested
        histogramRequested = false
        stateLock.unlock()

        let viewW = Float(drawable.texture.width)
        let viewH = Float(drawable.texture.height)
        let backing = Float(view.window?.backingScaleFactor ?? 2)

        if let source, let processed, let bloom, shouldProcess {
            var uniforms = RenderUniforms(
                edit: edit, look: look,
                size: CGSize(width: source.width, height: source.height),
                previewScale: 1,
                showOriginal: lutLibrary.neutral0 == nil
            )
            uniforms.useDisplayLUT = (edit.lutID != nil && userLUT != nil) ? 1 : 0
            uniforms.useFilm = uniforms.useDisplayLUT > 0 ? 0 : (look == nil ? 0 : 1)
            uniforms.displayLUTStrength = Float(edit.lutStrength)
            uniforms.tonalTransparency = Float(edit.adjustments.tonalTransparency / 100)
            uniforms.colorTransparency = Float(edit.adjustments.colorTransparency / 100)
            uniforms.blackPoint = Float(stats.blackPoint)
            uniforms.whitePoint = Float(stats.whitePoint)
            uniforms.whiteDeltaR = Float(stats.whiteDeltaR)
            uniforms.whiteDeltaG = Float(stats.whiteDeltaG)
            uniforms.whiteDeltaB = Float(stats.whiteDeltaB)
            uniforms.blackDeltaR = Float(stats.blackDeltaR)
            uniforms.blackDeltaG = Float(stats.blackDeltaG)
            uniforms.blackDeltaB = Float(stats.blackDeltaB)
            encodeBloom(commandBuffer: commandBuffer, source: source, bloom: bloom, uniforms: uniforms)
            encodeProcess(
                commandBuffer: commandBuffer,
                source: source,
                destination: processed,
                film: film,
                neutral: neutral,
                bloom: (uniforms.halation > 0.001 || uniforms.bloom > 0.001) ? bloom : blackTexture,
                userLUT: userLUT ?? neutral,
                curves: curves,
                uniforms: uniforms,
                offset: (0, 0),
                size: (source.width, source.height)
            )
        }
        if wantsHistogram, let processed {
            encodeHistogram(commandBuffer: commandBuffer, texture: processed, callback: true)
        }

        let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: pass)!
        if let processed, source != nil {
            let imageW = Float(source!.width)
            let imageH = Float(source!.height)
            let viewSize = CGSize(width: CGFloat(viewW), height: CGFloat(viewH))
            let fit = min(CGFloat(viewW) / CGFloat(imageW), CGFloat(viewH) / CGFloat(imageH)) * 0.92
            DispatchQueue.main.async {
                self.canvas.viewSizePixels = viewSize
                self.canvas.backingScale = CGFloat(backing)
                self.canvas.fitScale = fit
                self.canvas.clampPan()
            }
            var display = DisplayUniforms(
                viewWidth: viewW,
                viewHeight: viewH,
                imageWidth: imageW,
                imageHeight: imageH,
                fitScale: Float(fit),
                zoom: Float(canvas.zoom),
                panX: Float(canvas.pan.width),
                panY: Float(canvas.pan.height),
                backingScale: backing
            )
            display.compareEnabled = compare ? 1 : 0
            display.splitX = Float(split)
            encoder.setRenderPipelineState(displayPipeline)
            encoder.setFragmentTexture(processed, index: 0)
            encoder.setFragmentTexture(source, index: 1)
            encoder.setFragmentBytes(&display, length: MemoryLayout<DisplayUniforms>.stride, index: 0)
            encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        } else {
            encoder.endEncoding()
            commandBuffer.present(drawable)
            commandBuffer.commit()
            return
        }
        encoder.endEncoding()
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }

    private func encodeBloom(commandBuffer: MTLCommandBuffer, source: MTLTexture, bloom: MTLTexture, uniforms: RenderUniforms) {
        guard uniforms.halation > 0.001 || uniforms.bloom > 0.001, let second = bloomB ?? bloomA else { return }
        var u = uniforms
        // Extract highlights into the half-resolution bloom target.
        if let encoder = commandBuffer.makeComputeCommandEncoder() {
            encoder.setComputePipelineState(bloomExtractPipeline)
            encoder.setTexture(source, index: 0)
            encoder.setTexture(bloom, index: 1)
            encoder.setBytes(&u, length: MemoryLayout<RenderUniforms>.stride, index: 0)
            encoder.dispatchThreads(
                MTLSize(width: bloom.width, height: bloom.height, depth: 1),
                threadsPerThreadgroup: MTLSize(width: 16, height: 16, depth: 1)
            )
            encoder.endEncoding()
        }
        // Two separable passes; ping-pong between the two bloom textures.
        if let encoder = commandBuffer.makeComputeCommandEncoder() {
            encoder.setComputePipelineState(blurHPipeline)
            encoder.setTexture(bloom, index: 0)
            encoder.setTexture(second, index: 1)
            encoder.setBytes(&u, length: MemoryLayout<RenderUniforms>.stride, index: 0)
            encoder.dispatchThreads(
                MTLSize(width: bloom.width, height: bloom.height, depth: 1),
                threadsPerThreadgroup: MTLSize(width: 16, height: 16, depth: 1)
            )
            encoder.endEncoding()
        }
        if let encoder = commandBuffer.makeComputeCommandEncoder() {
            encoder.setComputePipelineState(blurVPipeline)
            encoder.setTexture(second, index: 0)
            encoder.setTexture(bloom, index: 1)
            encoder.setBytes(&u, length: MemoryLayout<RenderUniforms>.stride, index: 0)
            encoder.dispatchThreads(
                MTLSize(width: bloom.width, height: bloom.height, depth: 1),
                threadsPerThreadgroup: MTLSize(width: 16, height: 16, depth: 1)
            )
            encoder.endEncoding()
        }
    }

    private func encodeProcess(
        commandBuffer: MTLCommandBuffer,
        source: MTLTexture,
        destination: MTLTexture,
        film: MTLTexture,
        neutral: MTLTexture,
        bloom: MTLTexture,
        userLUT: MTLTexture,
        curves: MTLTexture,
        uniforms: RenderUniforms,
        offset: (Int, Int),
        size: (Int, Int)
    ) {
        var u = uniforms
        u.destOffsetX = Float(offset.0)
        u.destOffsetY = Float(offset.1)
        guard let encoder = commandBuffer.makeComputeCommandEncoder() else { return }
        encoder.setComputePipelineState(processPipeline)
        encoder.setTexture(source, index: 0)
        encoder.setTexture(destination, index: 1)
        encoder.setTexture(film, index: 2)
        encoder.setTexture(neutral, index: 3)
        encoder.setTexture(bloom, index: 4)
        encoder.setTexture(userLUT, index: 5)
        encoder.setTexture(curves, index: 6)
        encoder.setBytes(&u, length: MemoryLayout<RenderUniforms>.stride, index: 0)
        let w = 16, h = 16
        encoder.dispatchThreads(
            MTLSize(width: size.0, height: size.1, depth: 1),
            threadsPerThreadgroup: MTLSize(width: w, height: h, depth: 1)
        )
        encoder.endEncoding()
    }

    private func encodeHistogram(commandBuffer: MTLCommandBuffer, texture: MTLTexture, callback: Bool) {
        let bins = histogramBuffer.contents().assumingMemoryBound(to: UInt32.self)
        bins.initialize(repeating: 0, count: 1032)
        if let encoder = commandBuffer.makeComputeCommandEncoder() {
            encoder.setComputePipelineState(histogramPipeline)
            encoder.setTexture(texture, index: 0)
            encoder.setBuffer(histogramBuffer, offset: 0, index: 0)
            encoder.dispatchThreads(
                MTLSize(width: 256, height: 256, depth: 1),
                threadsPerThreadgroup: MTLSize(width: 16, height: 16, depth: 1)
            )
            encoder.endEncoding()
        }
        if callback {
            commandBuffer.addCompletedHandler { [weak self] _ in
                guard let self else { return }
                let counts = self.histogramBuffer.contents().assumingMemoryBound(to: UInt32.self)
                var luma = [UInt32](repeating: 0, count: 256)
                var red = [UInt32](repeating: 0, count: 256)
                var green = [UInt32](repeating: 0, count: 256)
                var blue = [UInt32](repeating: 0, count: 256)
                for i in 0..<256 {
                    luma[i] = counts[i]
                    red[i] = counts[256 + i]
                    green[i] = counts[512 + i]
                    blue[i] = counts[768 + i]
                }
                let peak = max(max(luma.max() ?? 1, red.max() ?? 1), max(green.max() ?? 1, blue.max() ?? 1))
                let denominator = log(Double(peak) + 1)
                let data = HistogramData(
                    luma: Renderer.normalize(luma, denominator),
                    red: Renderer.normalize(red, denominator),
                    green: Renderer.normalize(green, denominator),
                    blue: Renderer.normalize(blue, denominator)
                )
                let stats = Renderer.toneStats(from: counts)
                DispatchQueue.main.async {
                    self.onHistogram?(data, stats)
                }
            }
        }
    }

    private static func toneStats(from counts: UnsafeMutablePointer<UInt32>) -> ToneStats {
        var stats = ToneStats.empty
        var luma = [UInt32](repeating: 0, count: 256)
        for i in 0..<256 { luma[i] = counts[i] }
        let total = luma.reduce(0) { $0 + Double($1) }
        if total > 0 {
            var cumulative = 0.0
            var black = 0
            for i in 0..<256 {
                cumulative += Double(luma[i])
                if cumulative >= total * 0.004 {
                    black = i
                    break
                }
            }
            var topCumulative = 0.0
            var white = 255
            for i in stride(from: 255, through: 0, by: -1) {
                topCumulative += Double(luma[i])
                if topCumulative >= total * 0.004 {
                    white = i
                    break
                }
            }
            if white > black + 12 {
                stats.blackPoint = Double(black) / 255.0
                stats.whitePoint = Double(white) / 255.0
            }
        }

        let whiteCount = Int(counts[1024])
        if whiteCount > 80 {
            let scale = Double(whiteCount) * 32767.0
            let r = Double(counts[1025]) / scale
            let g = Double(counts[1026]) / scale
            let b = Double(counts[1027]) / scale
            let mean = (r + g + b) / 3
            stats.whiteAverageR = r
            stats.whiteAverageG = g
            stats.whiteAverageB = b
            stats.whiteDeltaR = (mean - r).clamped(to: -0.18...0.18)
            stats.whiteDeltaG = (mean - g).clamped(to: -0.18...0.18)
            stats.whiteDeltaB = (mean - b).clamped(to: -0.18...0.18)
            stats.whiteCount = whiteCount
        }
        let blackCount = Int(counts[1028])
        if blackCount > 80 {
            let scale = Double(blackCount) * 32767.0
            let r = Double(counts[1029]) / scale
            let g = Double(counts[1030]) / scale
            let b = Double(counts[1031]) / scale
            let mean = (r + g + b) / 3
            stats.blackAverageR = r
            stats.blackAverageG = g
            stats.blackAverageB = b
            stats.blackDeltaR = (mean - r).clamped(to: -0.18...0.18)
            stats.blackDeltaG = (mean - g).clamped(to: -0.18...0.18)
            stats.blackDeltaB = (mean - b).clamped(to: -0.18...0.18)
            stats.blackCount = blackCount
        }
        return stats
    }

    // MARK: - Look thumbnails

    /// Renders every look against the current photo into one atlas, then slices
    /// it into small CGImages for the film browser. The whole batch stays on
    /// the GPU and is read back exactly once.
    func generateLookThumbnails(source: CGImage, looks: [FilmVariant],
                                completion: @escaping ([String: CGImage]) -> Void) {
        thumbnailQueue.async { [weak self] in
            guard let self else { return }
            let cellW = 144, cellH = 96
            let columns = 8
            let rows = max(1, Int(ceil(Double(looks.count) / Double(columns))))
            let atlasW = cellW * columns
            let atlasH = cellH * rows
            guard let sourceTexture = self.makeAspectFillTexture(source, width: cellW, height: cellH),
                  let atlas = self.makeRGBA8Texture(width: atlasW, height: atlasH, write: true),
                  let command = self.queue.makeCommandBuffer() else {
                DispatchQueue.main.async { completion([:]) }
                return
            }
            var thumbnails: [String: CGImage] = [:]
            for (index, look) in looks.enumerated() {
                let col = index % columns
                let row = index / columns
                var uniforms = RenderUniforms(edit: PhotoEdit(lookID: look.id, strength: 1, adjustments: .neutral),
                                              look: look,
                                              size: CGSize(width: cellW, height: cellH),
                                              previewScale: 1,
                                              showOriginal: false)
                uniforms.destOffsetX = Float(col * cellW)
                uniforms.destOffsetY = Float(row * cellH)
                uniforms.ditherSeed = Float(index) * 3.17
                let film = self.lutLibrary.film[look.id] ?? self.lutLibrary.neutral0
                let neutral = look.exposureEV >= 0.75 ? self.lutLibrary.neutral15 : self.lutLibrary.neutral0
                guard let film, let neutral else { continue }
                self.encodeProcess(
                    commandBuffer: command,
                    source: sourceTexture,
                    destination: atlas,
                    film: film,
                    neutral: neutral,
                    bloom: self.blackTexture,
                    userLUT: neutral,
                    curves: self.identityCurveTexture,
                    uniforms: uniforms,
                    offset: (col * cellW, row * cellH),
                    size: (cellW, cellH)
                )
            }
            command.commit()
            command.waitUntilCompleted()

            let bytesPerRow = atlasW * 4
            var atlasBytes = [UInt8](repeating: 0, count: atlasW * atlasH * 4)
            atlas.getBytes(&atlasBytes, bytesPerRow: bytesPerRow,
                           from: MTLRegionMake2D(0, 0, atlasW, atlasH), mipmapLevel: 0)
            for (index, look) in looks.enumerated() {
                let col = index % columns
                let row = index / columns
                var cell = [UInt8](repeating: 0, count: cellW * cellH * 4)
                for y in 0..<cellH {
                    let srcOffset = (row * cellH + y) * bytesPerRow + col * cellW * 4
                    let dstOffset = y * cellW * 4
                    cell[dstOffset..<(dstOffset + cellW * 4)] = atlasBytes[srcOffset..<(srcOffset + cellW * 4)]
                }
                if let image = Renderer.makeCGImage(cell, width: cellW, height: cellH) {
                    thumbnails[look.id] = image
                }
            }
            DispatchQueue.main.async { completion(thumbnails) }
        }
    }

    func generateImportedLUTThumbnails(source: CGImage, luts: [ImportedLUT],
                                      completion: @escaping ([String: CGImage]) -> Void) {
        thumbnailQueue.async { [weak self] in
            guard let self, !luts.isEmpty else {
                DispatchQueue.main.async { completion([:]) }
                return
            }
            let cellW = 144, cellH = 96
            let columns = 8
            let rows = max(1, Int(ceil(Double(luts.count) / Double(columns))))
            let atlasW = cellW * columns
            let atlasH = cellH * rows
            guard let sourceTexture = self.makeAspectFillTexture(source, width: cellW, height: cellH),
                  let atlas = self.makeRGBA8Texture(width: atlasW, height: atlasH, write: true),
                  let neutral = self.lutLibrary.neutral0,
                  let command = self.queue.makeCommandBuffer() else {
                DispatchQueue.main.async { completion([:]) }
                return
            }
            var thumbnails: [String: CGImage] = [:]
            for (index, lut) in luts.enumerated() {
                guard let texture = self.lutLibrary.userLUT(lut.id) else { continue }
                let col = index % columns
                let row = index / columns
                var uniforms = RenderUniforms(
                    edit: PhotoEdit(lookID: nil, lutID: lut.id, strength: 1,
                                    lutStrength: 1, adjustments: .neutral),
                    look: nil,
                    size: CGSize(width: cellW, height: cellH),
                    previewScale: 1,
                    showOriginal: false
                )
                uniforms.destOffsetX = Float(col * cellW)
                uniforms.destOffsetY = Float(row * cellH)
                uniforms.ditherSeed = Float(index) * 3.17
                uniforms.useDisplayLUT = 1
                uniforms.useFilm = 0
                uniforms.displayLUTStrength = 1
                self.encodeProcess(
                    commandBuffer: command,
                    source: sourceTexture,
                    destination: atlas,
                    film: neutral,
                    neutral: neutral,
                    bloom: self.blackTexture,
                    userLUT: texture,
                    curves: self.identityCurveTexture,
                    uniforms: uniforms,
                    offset: (col * cellW, row * cellH),
                    size: (cellW, cellH)
                )
            }
            command.commit()
            command.waitUntilCompleted()

            let bytesPerRow = atlasW * 4
            var atlasBytes = [UInt8](repeating: 0, count: atlasW * atlasH * 4)
            atlas.getBytes(&atlasBytes, bytesPerRow: bytesPerRow,
                           from: MTLRegionMake2D(0, 0, atlasW, atlasH), mipmapLevel: 0)
            for (index, lut) in luts.enumerated() {
                let col = index % columns
                let row = index / columns
                var cell = [UInt8](repeating: 0, count: cellW * cellH * 4)
                for y in 0..<cellH {
                    let srcOffset = (row * cellH + y) * bytesPerRow + col * cellW * 4
                    let dstOffset = y * cellW * 4
                    cell[dstOffset..<(dstOffset + cellW * 4)] = atlasBytes[srcOffset..<(srcOffset + cellW * 4)]
                }
                if let image = Renderer.makeCGImage(cell, width: cellW, height: cellH) {
                    thumbnails[lut.id] = image
                }
            }
            DispatchQueue.main.async { completion(thumbnails) }
        }
    }

    private func makeAspectFillTexture(_ image: CGImage, width: Int, height: Int) -> MTLTexture? {
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        guard let context = CGContext(
            data: &bytes,
            width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: width * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
        ) else { return nil }
        context.interpolationQuality = .high
        let scale = max(CGFloat(width) / CGFloat(image.width), CGFloat(height) / CGFloat(image.height))
        let drawW = CGFloat(image.width) * scale
        let drawH = CGFloat(image.height) * scale
        context.draw(image, in: CGRect(x: (CGFloat(width) - drawW) / 2,
                                       y: (CGFloat(height) - drawH) / 2,
                                       width: drawW, height: drawH))
        return upload(bytes, width: width, height: height, write: false)
    }

    private func makeRGBA8Texture(width: Int, height: Int, write: Bool) -> MTLTexture? {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm, width: width, height: height, mipmapped: false
        )
        descriptor.usage = write ? [.shaderRead, .shaderWrite] : [.shaderRead]
        descriptor.storageMode = .shared
        return device.makeTexture(descriptor: descriptor)
    }

    private func upload(_ bytes: [UInt8], width: Int, height: Int, write: Bool) -> MTLTexture? {
        guard let texture = makeRGBA8Texture(width: width, height: height, write: write) else { return nil }
        bytes.withUnsafeBytes { raw in
            guard let base = raw.baseAddress else { return }
            texture.replace(region: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0,
                            withBytes: base, bytesPerRow: width * 4)
        }
        return texture
    }

    static func makeCGImage(_ bytes: [UInt8], width: Int, height: Int) -> CGImage? {
        guard let provider = CGDataProvider(data: Data(bytes) as CFData) else { return nil }
        return CGImage(
            width: width, height: height,
            bitsPerComponent: 8, bitsPerPixel: 32,
            bytesPerRow: width * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue)
                .union(.byteOrder32Big),
            provider: provider, decode: nil, shouldInterpolate: true,
            intent: .defaultIntent
        )
    }

    /// Builds a CGImage over a owned pixel buffer without copying the readback
    /// twice (Array + Data). Used by the full-resolution export path where a
    /// 45 MP RGBA buffer is large enough that duplicate copies matter.
    static func makeOwnedCGImage(width: Int, height: Int,
                                 fill: (UnsafeMutableRawPointer) -> Void) -> CGImage? {
        let byteCount = width * height * 4
        guard byteCount > 0 else { return nil }
        let buffer = UnsafeMutableRawPointer.allocate(byteCount: byteCount, alignment: 16)
        fill(buffer)
        guard let provider = CGDataProvider(
            dataInfo: buffer,
            data: UnsafeRawPointer(buffer),
            size: byteCount,
            releaseData: { info, _, _ in info?.deallocate() }
        ) else {
            buffer.deallocate()
            return nil
        }
        return CGImage(
            width: width, height: height,
            bitsPerComponent: 8, bitsPerPixel: 32,
            bytesPerRow: width * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue)
                .union(.byteOrder32Big),
            provider: provider, decode: nil, shouldInterpolate: true,
            intent: .defaultIntent
        )
    }

    // MARK: - Full resolution export

    func renderFull(_ image: CGImage, edit: PhotoEdit, look: FilmVariant?) -> CGImage? {
        guard let source = try? makeTexture(from: image) else { return nil }
        let width = image.width, height = image.height
        guard let destination = makeRGBA8Texture(width: width, height: height, write: true),
              let command = queue.makeCommandBuffer() else { return nil }
        let bloomW = max(1, width / 2)
        let bloomH = max(1, height / 2)
        let bloomDescriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba16Float, width: bloomW, height: bloomH, mipmapped: false
        )
        bloomDescriptor.usage = [.shaderRead, .shaderWrite]
        bloomDescriptor.storageMode = .private
        guard let bloomA = device.makeTexture(descriptor: bloomDescriptor),
              let bloomB = device.makeTexture(descriptor: bloomDescriptor) else { return nil }
        var uniforms = RenderUniforms(
            edit: edit, look: look,
            size: CGSize(width: width, height: height),
            previewScale: 1,
            showOriginal: false
        )
        let userLUT = edit.lutID.flatMap { lutLibrary.userLUT($0) }
        if userLUT != nil {
            uniforms.useDisplayLUT = 1
            uniforms.useFilm = 0
            uniforms.displayLUTStrength = Float(edit.lutStrength)
        }
        // The preview path owns the shared curve texture; exports build a local
        // copy so a full-resolution render always honours the current curves.
        let exportCurveTexture = CurveTextureBuilder.make(edit.curves, device: device)
            ?? identityCurveTexture
        uniforms.tonalTransparency = Float(edit.adjustments.tonalTransparency / 100)
        uniforms.colorTransparency = Float(edit.adjustments.colorTransparency / 100)
        uniforms.blackPoint = Float(toneStats.blackPoint)
        uniforms.whitePoint = Float(toneStats.whitePoint)
        uniforms.whiteDeltaR = Float(toneStats.whiteDeltaR)
        uniforms.whiteDeltaG = Float(toneStats.whiteDeltaG)
        uniforms.whiteDeltaB = Float(toneStats.whiteDeltaB)
        uniforms.blackDeltaR = Float(toneStats.blackDeltaR)
        uniforms.blackDeltaG = Float(toneStats.blackDeltaG)
        uniforms.blackDeltaB = Float(toneStats.blackDeltaB)
        let film: MTLTexture
        let neutral: MTLTexture
        if let look, let texture = lutLibrary.film[look.id] {
            film = texture
            neutral = look.exposureEV >= 0.75 ? (lutLibrary.neutral15 ?? texture) : (lutLibrary.neutral0 ?? texture)
        } else {
            film = lutLibrary.neutral0 ?? blackTexture
            neutral = film
            uniforms.useFilm = 0
        }
        if uniforms.halation > 0.001 || uniforms.bloom > 0.001 {
            // Use local bloom textures for this export.
            var u = uniforms
            if let encoder = command.makeComputeCommandEncoder() {
                encoder.setComputePipelineState(bloomExtractPipeline)
                encoder.setTexture(source, index: 0)
                encoder.setTexture(bloomA, index: 1)
                encoder.setBytes(&u, length: MemoryLayout<RenderUniforms>.stride, index: 0)
                encoder.dispatchThreads(MTLSize(width: bloomW, height: bloomH, depth: 1),
                                        threadsPerThreadgroup: MTLSize(width: 16, height: 16, depth: 1))
                encoder.endEncoding()
            }
            if let encoder = command.makeComputeCommandEncoder() {
                encoder.setComputePipelineState(blurHPipeline)
                encoder.setTexture(bloomA, index: 0)
                encoder.setTexture(bloomB, index: 1)
                encoder.setBytes(&u, length: MemoryLayout<RenderUniforms>.stride, index: 0)
                encoder.dispatchThreads(MTLSize(width: bloomW, height: bloomH, depth: 1),
                                        threadsPerThreadgroup: MTLSize(width: 16, height: 16, depth: 1))
                encoder.endEncoding()
            }
            if let encoder = command.makeComputeCommandEncoder() {
                encoder.setComputePipelineState(blurVPipeline)
                encoder.setTexture(bloomB, index: 0)
                encoder.setTexture(bloomA, index: 1)
                encoder.setBytes(&u, length: MemoryLayout<RenderUniforms>.stride, index: 0)
                encoder.dispatchThreads(MTLSize(width: bloomW, height: bloomH, depth: 1),
                                        threadsPerThreadgroup: MTLSize(width: 16, height: 16, depth: 1))
                encoder.endEncoding()
            }
        }
        encodeProcess(
            commandBuffer: command,
            source: source,
            destination: destination,
            film: film,
            neutral: neutral,
            bloom: (uniforms.halation > 0.001 || uniforms.bloom > 0.001) ? bloomA : blackTexture,
            userLUT: userLUT ?? neutral,
            curves: exportCurveTexture,
            uniforms: uniforms,
            offset: (0, 0),
            size: (width, height)
        )
        command.commit()
        command.waitUntilCompleted()
        return Renderer.makeOwnedCGImage(width: width, height: height) { buffer in
            destination.getBytes(
                buffer, bytesPerRow: width * 4,
                from: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0
            )
        }
    }

    private static func normalize(_ bins: [UInt32], _ denominator: Double) -> [Float] {
        guard denominator > 0 else { return Array(repeating: 0, count: 256) }
        return bins.map { Float(log(Double($0) + 1) / denominator) }
    }
}
