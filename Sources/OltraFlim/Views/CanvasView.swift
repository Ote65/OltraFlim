import SwiftUI
import MetalKit
import AppKit

struct CanvasView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ZStack {
            DS.surface0
            if let renderer = model.renderer {
                MetalCanvasHost(renderer: renderer)
                    .ignoresSafeArea()
                if model.currentPhoto == nil {
                    EmptyStateView()
                        .transition(.opacity)
                } else if let photo = model.currentPhoto, (!photo.previewLoaded || model.libraryIsLoading) {
                    LoadingPhotoView()
                        .transition(.opacity)
                } else {
                    if model.showOriginal {
                        CompareOverlay(canvas: renderer.canvas)
                            .environment(model)
                    }
                    canvasOverlays(renderer: renderer)
                }
            } else {
                EngineErrorView()
            }
        }
        .clipped()
        .animation(DS.easeOutExpo, value: model.currentPhoto?.id)
        .animation(DS.easeQuick, value: model.showOriginal)
    }

    @MainActor
    @ViewBuilder
    private func canvasOverlays(renderer: Renderer) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 7) {
                CompareButton()
                FilmIdentityChip()
            }
            Spacer()
            HStack(alignment: .bottom) {
                PhotoMetadataLine()
                Spacer()
                CanvasZoomControls(canvas: renderer.canvas, renderer: renderer)
            }
        }
        .padding(18)
    }
}

// MARK: - Metal host

struct MetalCanvasHost: NSViewRepresentable {
    let renderer: Renderer

    func makeNSView(context: Context) -> CanvasMTKView {
        let view = CanvasMTKView(renderer: renderer)
        renderer.canvasView = view
        DispatchQueue.main.async {
            renderer.redraw()
        }
        return view
    }

    func updateNSView(_ nsView: CanvasMTKView, context: Context) {}
}

final class CanvasMTKView: MTKView {
    private let renderer: Renderer
    private var lastDragPoint: NSPoint?
    private var tracking: NSTrackingArea?
    private var keyMonitor: Any?

    init(renderer: Renderer) {
        self.renderer = renderer
        super.init(frame: .zero, device: renderer.device)
        colorPixelFormat = .bgra8Unorm
        clearColor = MTLClearColor(red: 0.043, green: 0.043, blue: 0.043, alpha: 1)
        isPaused = true
        enableSetNeedsDisplay = true
        autoResizeDrawable = true
        framebufferOnly = true
        wantsLayer = true
        layer?.isOpaque = true
        if let metalLayer = layer as? CAMetalLayer {
            metalLayer.colorspace = CGColorSpace(name: CGColorSpace.itur_709)
            metalLayer.wantsExtendedDynamicRangeContent = false
        }
        (layer as? CAMetalLayer)?.backgroundColor = NSColor(hex: 0x0B0B0B).cgColor

        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.window?.isKeyWindow == true else { return event }
            guard event.keyCode == 49 else { return event }
            if self.window?.firstResponder is NSTextView { return event }
            self.renderer.canvas.reset()
            return nil
        }
    }

    deinit {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var acceptsFirstResponder: Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        renderer.draw(in: self)
    }

    override func layout() {
        super.layout()
        if let metalLayer = layer as? CAMetalLayer {
            metalLayer.colorspace = CGColorSpace(name: CGColorSpace.itur_709)
        }
        renderer.canvas.backingScale = window?.backingScaleFactor ?? 2
        renderer.redraw()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: bounds,
                                  options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
                                  owner: self, userInfo: nil)
        addTrackingArea(area)
        tracking = area
    }

    override func mouseEntered(with event: NSEvent) {
        if renderer.canvas.zoom > 1.01 {
            NSCursor.openHand.set()
        }
    }

    override func mouseExited(with event: NSEvent) {
        NSCursor.arrow.set()
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        lastDragPoint = convert(event.locationInWindow, from: nil)
        if event.clickCount == 2 {
            if renderer.canvas.isFit {
                renderer.canvas.actualSize()
            } else {
                renderer.canvas.reset()
            }
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard let last = lastDragPoint else { return }
        let point = convert(event.locationInWindow, from: nil)
        renderer.canvas.panBy(dx: point.x - last.x, dy: -(point.y - last.y))
        lastDragPoint = point
        if renderer.canvas.zoom > 1.01 {
            NSCursor.closedHand.set()
        }
    }

    override func mouseUp(with event: NSEvent) {
        lastDragPoint = nil
        if renderer.canvas.zoom > 1.01 {
            NSCursor.openHand.set()
        }
    }

    override func scrollWheel(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let backing = window?.backingScaleFactor ?? 2
        let anchor = CGPoint(x: point.x * backing, y: (bounds.height - point.y) * backing)

        if event.modifierFlags.contains(.control)
            || event.modifierFlags.contains(.command)
            || event.modifierFlags.contains(.option) {
            // A curved, exponential zoom response: small trackpad gestures stay
            // gentle, fast gestures accelerate without becoming a step function.
            let raw = event.scrollingDeltaY
            let magnitude = CGFloat(pow(Double(abs(raw)), 0.88))
            let curved = raw < 0 ? -magnitude : magnitude
            let sensitivity: CGFloat = event.hasPreciseScrollingDeltas ? 0.016 : 0.048
            let factor = CGFloat(exp(Double(curved) * Double(sensitivity)))
            renderer.canvas.zoom(by: factor, anchor: anchor)
        } else {
            let factor = event.hasPreciseScrollingDeltas ? 1.0 : 1.6
            renderer.canvas.panBy(dx: event.scrollingDeltaX * factor,
                                  dy: event.scrollingDeltaY * factor)
        }
    }

    override func magnify(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let backing = window?.backingScaleFactor ?? 2
        let anchor = CGPoint(x: point.x * backing, y: (bounds.height - point.y) * backing)
        renderer.canvas.zoom(by: 1 + event.magnification, anchor: anchor)
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 49 { // Space: back to fit
            renderer.canvas.reset()
            return
        }
        super.keyDown(with: event)
    }
}

// MARK: - Overlays

struct FilmIdentityChip: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if let lut = model.currentImportedLUT {
            HStack(spacing: 8) {
                Circle().fill(DS.accent).frame(width: 4, height: 4)
                Text(lut.name)
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(DS.textPrimary)
                    .lineLimit(1)
                Rectangle().fill(DS.hairlineStrong).frame(width: 1, height: 10)
                Text("LUT")
                    .font(DS.label(9.5))
                    .foregroundStyle(DS.accent.opacity(0.9))
                if model.currentEdit.lutStrength < 0.999 {
                    Text("\(Int(round(model.currentEdit.lutStrength * 100)))%")
                        .font(DS.mono(9))
                        .foregroundStyle(DS.textTertiary)
                }
            }
            .padding(.horizontal, 10)
            .frame(height: 28)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(.ultraThinMaterial)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .stroke(DS.hairlineStrong, lineWidth: 1)
            )
        } else if let stock = model.currentStock, let look = model.currentLook {
            HStack(spacing: 8) {
                Circle()
                    .fill(DS.accent)
                    .frame(width: 4, height: 4)
                Text(stock.name)
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(DS.textPrimary)
                Rectangle().fill(DS.hairlineStrong).frame(width: 1, height: 10)
                Text(look.localizedLabel)
                    .font(DS.label(9.5))
                    .foregroundStyle(DS.textSecondary)
                if model.currentEdit.strength < 0.999 {
                    Text("\(Int(round(model.currentEdit.strength * 100)))%")
                        .font(DS.mono(9))
                        .foregroundStyle(DS.textTertiary)
                }
            }
            .padding(.horizontal, 10)
            .frame(height: 28)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(.ultraThinMaterial)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .stroke(DS.hairlineStrong, lineWidth: 1)
            )
        }
    }
}

struct CompareButton: View {
    @Environment(AppModel.self) private var model
    @State private var hovering = false

    var body: some View {
        Button {
            withAnimation(DS.snappy) { model.toggleShowOriginal() }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "rectangle.split.2x1")
                    .font(.system(size: 9.5, weight: .semibold))
                Text(model.showOriginal ? T("对比中", "Comparing") : T("原图", "Original"))
                    .font(.system(size: 10, weight: .medium))
            }
            .foregroundStyle(model.showOriginal ? DS.accent : DS.textSecondary)
            .padding(.horizontal, 9)
            .frame(height: 26)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(.ultraThinMaterial)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .stroke(model.showOriginal ? DS.accent.opacity(0.45) : DS.hairlineStrong, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(model.currentPhoto == nil)
        .opacity(model.currentPhoto == nil ? 0.5 : 1)
        .onHover { hovering = $0 }
        .help(T("拖动分割线对比原图与显影", "Drag the divider to compare original and developed"))
    }
}

struct CompareOverlay: View {
    @ObservedObject var canvas: CanvasState
    @Environment(AppModel.self) private var model

    var body: some View {
        GeometryReader { proxy in
            let rect = canvas.imageRect(in: proxy.size)
            let splitX = rect.minX + rect.width * model.compareSplit
            ZStack(alignment: .topLeading) {
                Path { path in
                    path.move(to: CGPoint(x: splitX, y: rect.minY))
                    path.addLine(to: CGPoint(x: splitX, y: rect.maxY))
                }
                .stroke(Color.white.opacity(0.28), lineWidth: 1)
                .allowsHitTesting(false)

                compareLabel(T("原图", "Original"), color: .white.opacity(0.82))
                    .position(x: min(rect.maxX - 34, rect.minX + 34), y: rect.minY + 11)
                    .allowsHitTesting(false)
                compareLabel(T("显影", "Developed"), color: DS.accent.opacity(0.95))
                    .position(x: max(rect.minX + 34, rect.maxX - 34), y: rect.minY + 11)
                    .allowsHitTesting(false)

                ZStack {
                    Circle()
                        .fill(DS.surface3.opacity(0.92))
                        .frame(width: 24, height: 24)
                    HStack(spacing: 2) {
                        Image(systemName: "chevron.left")
                        Image(systemName: "chevron.right")
                    }
                    .font(.system(size: 6.5, weight: .bold))
                    .foregroundStyle(DS.accent)
                }
                .shadow(color: .black.opacity(0.45), radius: 8, y: 3)
                .contentShape(Rectangle().inset(by: -10))
                .position(x: splitX, y: rect.midY)
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            guard rect.width > 1 else { return }
                            model.setCompareSplit(Double((value.location.x - rect.minX) / rect.width))
                        }
                )
            }
        }
    }

    private func compareLabel(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: 8.5, weight: .medium))
            .tracking(0.6)
            .foregroundStyle(color)
            .padding(.horizontal, 7)
            .frame(height: 20)
            .background(
                Capsule().fill(Color.black.opacity(0.36))
            )
            .overlay(Capsule().stroke(Color.white.opacity(0.08), lineWidth: 1))
    }
}

struct PhotoMetadataLine: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if let photo = model.currentPhoto, photo.metadata.hasContent {
            HStack(spacing: 6) {
                let parts = metadataParts(photo.metadata)
                ForEach(Array(parts.enumerated()), id: \.offset) { item in
                    Text(item.element)
                    if item.offset < parts.count - 1 {
                        Text("·").foregroundStyle(DS.textQuaternary)
                    }
                }
            }
            .font(DS.label(9))
            .foregroundStyle(DS.textTertiary)
            .lineLimit(1)
            .padding(.horizontal, 9)
            .frame(height: 24)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(.ultraThinMaterial)
            )
        }
    }

    private func metadataParts(_ metadata: PhotoMetadata) -> [String] {
        [metadata.camera, metadata.lens, metadata.iso, metadata.aperture, metadata.shutter]
            .compactMap { $0 }
    }
}

struct CanvasZoomControls: View {
    @ObservedObject var canvas: CanvasState
    let renderer: Renderer

    var body: some View {
        HStack(spacing: 0) {
            zoomButton("minus", help: T("缩小", "Zoom out")) {
                canvas.zoom(by: 0.72)
                renderer.redraw()
            }
            Button {
                if canvas.isFit {
                    canvas.actualSize()
                } else {
                    canvas.reset()
                }
                renderer.redraw()
            } label: {
                Text(canvas.isFit ? T("适应", "FIT") : "\(canvas.percent)%")
                    .font(DS.mono(9))
                    .foregroundStyle(DS.textSecondary)
                    .frame(width: 50, height: 26)
            }
            .buttonStyle(.plain)
            .help(T("切换适应 / 100%", "Toggle fit / 100%"))
            zoomButton("plus", help: T("放大", "Zoom in")) {
                canvas.zoom(by: 1.4)
                renderer.redraw()
            }
            Rectangle().fill(DS.hairlineStrong).frame(width: 1, height: 14)
            zoomButton("arrow.up.left.and.arrow.down.right", help: T("实际大小", "Actual size")) {
                canvas.actualSize()
                renderer.redraw()
            }
        }
        .frame(height: 26)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(.ultraThinMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .stroke(DS.hairlineStrong, lineWidth: 1)
        )
    }

    private func zoomButton(_ symbol: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 9.5, weight: .medium))
                .foregroundStyle(DS.textSecondary)
                .frame(width: 26, height: 26)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
    }
}

// MARK: - States

struct LoadingPhotoView: View {
    var body: some View {
        VStack(spacing: 12) {
            ProgressView()
                .controlSize(.small)
                .tint(DS.accent)
            Text(T("正在读取照片", "READING PHOTOGRAPH"))
                .font(.system(size: 9, weight: .medium))
                .tracking(1.8)
                .foregroundStyle(DS.textTertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DS.surface0)
    }
}

struct EngineErrorView: View {
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 24, weight: .light))
                .foregroundStyle(DS.danger)
            Text(T("胶片引擎无法启动。", "The film engine could not start."))
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(DS.textPrimary)
            Text(T("OltraFlim 需要支持 Metal 的 Mac，并运行 macOS 14 或更新版本。", "OltraFlim needs a Metal-capable Mac running macOS 14 or newer."))
                .font(DS.label(10))
                .foregroundStyle(DS.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct EmptyStateView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ZStack {
            DS.surface0
            RadialGradient(
                colors: [DS.accent.opacity(0.045), .clear],
                center: .top,
                startRadius: 0,
                endRadius: 520
            )
            VStack(spacing: 0) {
                FilmStripMark()
                    .padding(.bottom, 28)
                Text(T("从一张照片开始。", "Begin with a photograph."))
                    .font(.system(size: 26, weight: .medium))
                    .tracking(-0.3)
                    .foregroundStyle(DS.textPrimary)
                Text(T("拖入照片，选择一款胶片。其余的交给暗房。", "Drop a photograph, choose a film, and let the darkroom do the rest."))
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(DS.textSecondary)
                    .padding(.top, 8)
                Button {
                    model.chooseFiles()
                } label: {
                    HStack(spacing: 7) {
                        Image(systemName: "plus")
                            .font(.system(size: 10, weight: .semibold))
                        Text(T("导入照片", "Import photograph"))
                            .font(.system(size: 11.5, weight: .medium))
                    }
                    .foregroundStyle(Color(hex: 0x14120E))
                    .padding(.horizontal, 14)
                    .frame(height: 32)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(DS.accent)
                    )
                }
                .buttonStyle(PressableStyle())
                .padding(.top, 22)
                Text("JPEG · PNG · TIFF · HEIC · RAW")
                    .font(.system(size: 8.5, weight: .medium))
                    .tracking(1.4)
                    .foregroundStyle(DS.textQuaternary)
                    .padding(.top, 16)
                if case .loading(let progress, let phase) = model.libraryState {
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.mini)
                            .tint(DS.accent)
                        Text("\(phase) · \(Int(progress * 100))%")
                            .font(DS.label(9))
                            .foregroundStyle(DS.textTertiary)
                    }
                    .padding(.top, 26)
                }
                if let error = model.startupError {
                    Text(error)
                        .font(DS.label(10))
                        .foregroundStyle(DS.danger)
                        .padding(.top, 22)
                }
            }
            .padding(.bottom, 30)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct FilmStripMark: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(DS.surface1)
                .frame(width: 168, height: 104)
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(DS.hairlineStrong, lineWidth: 1)
                )
            HStack(spacing: 0) {
                perforations
                Spacer()
                ZStack {
                    Circle()
                        .stroke(DS.accent.opacity(0.75), lineWidth: 1)
                        .frame(width: 46, height: 46)
                    Circle()
                        .fill(DS.accent.opacity(0.12))
                        .frame(width: 30, height: 30)
                    Circle()
                        .fill(DS.accent)
                        .frame(width: 3, height: 3)
                }
                Spacer()
                perforations
            }
            .padding(.horizontal, 12)
        }
        .shadow(color: .black.opacity(0.45), radius: 26, y: 14)
    }

    private var perforations: some View {
        VStack(spacing: 8) {
            ForEach(0..<5, id: \.self) { _ in
                RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                    .fill(DS.textQuaternary.opacity(0.8))
                    .frame(width: 5, height: 7)
            }
        }
    }
}
