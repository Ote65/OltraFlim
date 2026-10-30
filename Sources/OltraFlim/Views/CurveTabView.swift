import SwiftUI
import AppKit

struct CurveTabView: View {
    @Environment(AppModel.self) private var model
    @State private var channel: CurveChannel = .luma

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 4) {
                ForEach(CurveChannel.allCases) { item in
                    CurveChannelChip(channel: item, selected: channel == item) {
                        withAnimation(DS.easeQuick) { channel = item }
                    }
                }
                Spacer(minLength: 0)
                Button {
                    model.resetCurve(channel)
                } label: {
                    Image(systemName: "arrow.uturn.backward")
                        .font(DS.font(8.5, .semibold))
                        .foregroundStyle(model.currentPhoto == nil ? DS.textQuaternary : DS.textTertiary)
                        .frame(width: 22, height: 22)
                        .background(Circle().fill(DS.surface1))
                }
                .buttonStyle(.plain)
                .disabled(model.currentPhoto == nil)
                .help(T("重置当前曲线", "Reset this curve"))
            }

            CurveEditor(
                channel: channel,
                curve: model.currentCurves.curve(channel),
                histogram: histogramFor(channel),
                enabled: model.currentPhoto != nil
            ) { points in
                model.updateCurve(channel, points: points)
            }
            .frame(height: 158)

            HStack {
                Text(T("输入", "Input"))
                Spacer()
                Text(T("输出", "Output"))
            }
            .font(DS.label(7.5))
            .foregroundStyle(DS.textQuaternary)

            Text(T("明暗曲线作用于整体亮度，R / G / B 分通道独立；左键点击曲线新增控制点，右键删除控制点，拖动控制点调整。",
                   "Luma affects overall brightness; R / G / B are independent. Click the curve to add a point, right-click to delete one, drag a point to adjust."))
                .font(DS.label(8.5))
                .foregroundStyle(DS.textQuaternary)
                .lineSpacing(1.5)
                .fixedSize(horizontal: false, vertical: true)

            if model.currentPhoto == nil {
                Text(T("导入照片后可编辑曲线。", "Import a photograph to edit curves."))
                    .font(DS.label(9))
                    .foregroundStyle(DS.textTertiary)
            }
        }
        .padding(.top, 2)
        .opacity(model.currentPhoto == nil ? 0.55 : 1)
    }

    private func histogramFor(_ channel: CurveChannel) -> [Float] {
        switch channel {
        case .luma: return model.histogram.luma
        case .red: return model.histogram.red
        case .green: return model.histogram.green
        case .blue: return model.histogram.blue
        }
    }
}

struct CurveChannelChip: View {
    let channel: CurveChannel
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(channel.title)
                .font(DS.font(9, selected ? .medium : .regular))
                .foregroundStyle(selected ? color : DS.textTertiary)
                .padding(.horizontal, 7)
                .frame(height: 22)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(selected ? color.opacity(0.1) : DS.surface1)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(selected ? color.opacity(0.3) : DS.hairline, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }

    private var color: Color {
        switch channel {
        case .luma: return DS.textPrimary
        case .red: return Color(hex: 0xE06A5A)
        case .green: return Color(hex: 0x79B58A)
        case .blue: return Color(hex: 0x6E9ED8)
        }
    }
}

struct RightClickCatcher: NSViewRepresentable {
    let onRightClick: (CGPoint) -> Void

    func makeNSView(context: Context) -> RightClickView {
        let view = RightClickView()
        view.onRightClick = onRightClick
        return view
    }

    func updateNSView(_ nsView: RightClickView, context: Context) {
        nsView.onRightClick = onRightClick
    }
}

final class RightClickView: NSView {
    var onRightClick: ((CGPoint) -> Void)?

    override var isFlipped: Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let event = NSApp.currentEvent else { return nil }
        switch event.type {
        case .rightMouseDown, .rightMouseUp:
            return self
        default:
            return nil
        }
    }

    override func rightMouseDown(with event: NSEvent) {
        onRightClick?(convert(event.locationInWindow, from: nil))
    }
}

struct CurveEditor: View {
    let channel: CurveChannel
    let curve: ChannelCurve
    let histogram: [Float]
    let enabled: Bool
    let onChange: ([CurvePoint]) -> Void

    @State private var dragIndex: Int?
    @State private var pressOrigin: CGPoint?
    @State private var didDrag = false

    var body: some View {
        GeometryReader { proxy in
            let plot = CGRect(x: 8, y: 8,
                              width: max(1, proxy.size.width - 16),
                              height: max(1, proxy.size.height - 16))
            ZStack(alignment: .topLeading) {
                Canvas { context, _ in
                    drawGrid(context: context, plot: plot)
                    drawHistogram(context: context, plot: plot)
                    drawCurve(context: context, plot: plot)
                    drawPoints(context: context, plot: plot)
                }
                Color.clear
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                guard enabled else { return }
                                if pressOrigin == nil {
                                    pressOrigin = value.startLocation
                                    dragIndex = nearestPoint(to: value.startLocation,
                                                             plot: plot, within: 16)
                                }
                                guard let index = dragIndex else { return }
                                didDrag = true
                                move(index, to: value.location, plot: plot)
                            }
                            .onEnded { value in
                                let start = pressOrigin
                                let dragged = didDrag
                                dragIndex = nil
                                pressOrigin = nil
                                didDrag = false
                                guard enabled, !dragged, let start else { return }
                                guard hypot(value.location.x - start.x,
                                            value.location.y - start.y) < 4 else { return }
                                guard nearestPoint(to: start, plot: plot, within: 16) == nil else { return }
                                addPoint(at: start, plot: plot)
                            }
                    )
                    .overlay(
                        RightClickCatcher { location in
                            guard enabled else { return }
                            removePoint(near: location, plot: plot)
                        }
                    )
            }
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(DS.surface0)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .stroke(DS.hairline, lineWidth: 1)
            )
        }
    }

    private func drawGrid(context: GraphicsContext, plot: CGRect) {
        for i in 0...4 {
            let x = plot.minX + plot.width * CGFloat(i) / 4
            var path = Path()
            path.move(to: CGPoint(x: x, y: plot.minY))
            path.addLine(to: CGPoint(x: x, y: plot.maxY))
            context.stroke(path, with: .color(DS.hairline), lineWidth: 1)
            let y = plot.minY + plot.height * CGFloat(i) / 4
            var h = Path()
            h.move(to: CGPoint(x: plot.minX, y: y))
            h.addLine(to: CGPoint(x: plot.maxX, y: y))
            context.stroke(h, with: .color(DS.hairline), lineWidth: 1)
        }
    }

    private func drawHistogram(context: GraphicsContext, plot: CGRect) {
        guard histogram.count > 1 else { return }
        let bins = smoothed(histogram)
        var path = Path()
        path.move(to: CGPoint(x: plot.minX, y: plot.maxY))
        for i in 0..<bins.count {
            let x = plot.minX + plot.width * CGFloat(i) / CGFloat(bins.count - 1)
            let y = plot.maxY - plot.height * CGFloat(min(1, max(0, bins[i])))
            path.addLine(to: CGPoint(x: x, y: y))
        }
        path.addLine(to: CGPoint(x: plot.maxX, y: plot.maxY))
        path.closeSubpath()
        context.fill(path, with: .color(channelColor.opacity(0.08)))
    }

    private func drawCurve(context: GraphicsContext, plot: CGRect) {
        let values = CurveMath.values(points: curve.points, count: 256)
        var path = Path()
        for i in 0..<values.count {
            let x = plot.minX + plot.width * CGFloat(i) / CGFloat(values.count - 1)
            let y = plot.maxY - plot.height * CGFloat(values[i])
            if i == 0 { path.move(to: CGPoint(x: x, y: y)) }
            else { path.addLine(to: CGPoint(x: x, y: y)) }
        }
        context.stroke(path, with: .color(channelColor.opacity(0.85)), lineWidth: 1.2)
    }

    private func drawPoints(context: GraphicsContext, plot: CGRect) {
        for (index, point) in curve.points.enumerated() {
            let p = CGPoint(x: plot.minX + plot.width * CGFloat(point.x),
                            y: plot.maxY - plot.height * CGFloat(point.y))
            let radius: CGFloat = dragIndex == index ? 4.5 : 3.5
            let circle = Path(ellipseIn: CGRect(x: p.x - radius, y: p.y - radius,
                                                width: radius * 2, height: radius * 2))
            context.fill(circle, with: .color(dragIndex == index ? DS.accent : channelColor))
            context.stroke(circle, with: .color(DS.surface0), lineWidth: 1)
        }
    }

    private func move(_ index: Int, to location: CGPoint, plot: CGRect) {
        var points = curve.points
        guard points.indices.contains(index) else { return }
        let nx = (location.x - plot.minX) / plot.width
        let ny = (plot.maxY - location.y) / plot.height
        var x = min(1, max(0, nx))
        let y = min(1, max(0, ny))
        if index == 0 {
            x = 0
        } else if index == points.count - 1 {
            x = 1
        } else {
            let lower = points[index - 1].x + 0.035
            let upper = points[index + 1].x - 0.035
            x = min(upper, max(lower, x))
        }
        points[index] = CurvePoint(Double(x), Double(y))
        onChange(points)
    }

    private func addPoint(at location: CGPoint, plot: CGRect) {
        guard plot.width > 1, plot.height > 1 else { return }
        let nx = Double((location.x - plot.minX) / plot.width)
        let ny = Double((plot.maxY - location.y) / plot.height)
        let x = min(0.98, max(0.02, nx))
        let y = min(1, max(0, ny))
        var points = curve.points
        guard !points.contains(where: { abs($0.x - x) < 0.03 }) else { return }
        points.append(CurvePoint(x, y))
        points.sort { $0.x < $1.x }
        onChange(points)
    }

    private func removePoint(near location: CGPoint, plot: CGRect) {
        guard let index = nearestPoint(to: location, plot: plot, within: 20) else { return }
        guard index > 0, index < curve.points.count - 1 else { return }
        var points = curve.points
        points.remove(at: index)
        onChange(points)
    }

    private func nearestPoint(to location: CGPoint, plot: CGRect, within limit: CGFloat) -> Int? {
        var best: (index: Int, distance: CGFloat)?
        for (index, point) in curve.points.enumerated() {
            let sx = plot.minX + plot.width * CGFloat(point.x)
            let sy = plot.maxY - plot.height * CGFloat(point.y)
            let distance = hypot(location.x - sx, location.y - sy)
            if distance <= limit, best == nil || distance < best!.distance {
                best = (index, distance)
            }
        }
        return best?.index
    }

    private var channelColor: Color {
        switch channel {
        case .luma: return .white
        case .red: return Color(hex: 0xE06A5A)
        case .green: return Color(hex: 0x79B58A)
        case .blue: return Color(hex: 0x6E9ED8)
        }
    }

    private func smoothed(_ bins: [Float]) -> [Float] {
        guard bins.count > 4 else { return bins }
        var out = bins
        let last = bins.count - 1
        for i in 0...last {
            let a = bins[max(0, i - 2)]
            let b = bins[max(0, i - 1)]
            let c = bins[i]
            let d = bins[min(last, i + 1)]
            let e = bins[min(last, i + 2)]
            out[i] = (a + b * 2 + c * 3 + d * 2 + e) / 9
        }
        return out
    }
}
