import SwiftUI
import AppKit

enum InspectorTab: String, CaseIterable, Identifiable {
    case light
    case color
    case curves

    var id: String { rawValue }

    var title: String {
        switch self {
        case .light: return T("光线", "LIGHT")
        case .color: return T("色彩", "COLOR")
        case .curves: return T("曲线", "CURVES")
        }
    }

    var index: Int {
        switch self {
        case .light: return 0
        case .color: return 1
        case .curves: return 2
        }
    }
}

struct InspectorView: View {
    @Environment(AppModel.self) private var model
    @State private var tabDirection: CGFloat = 1
    @State private var transparencyOpen = true
    @State private var detailOpen = false
    @State private var textureOpen = false
    @State private var infoOpen = false
    @Namespace private var tabNamespace

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(spacing: 10) {
                    histogram
                    if model.currentImportedLUT != nil {
                        ImportedLookCard()
                    } else {
                        LookCard()
                    }
                    tabBar
                    tabContent
                        .padding(12)
                        .background(
                            RoundedRectangle(cornerRadius: DS.rMedium, style: .continuous)
                                .fill(DS.surface2)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: DS.rMedium, style: .continuous)
                                .stroke(DS.hairline, lineWidth: 1)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: DS.rMedium, style: .continuous))
                    transparencySection
                    detailSection
                    textureSection
                    infoSection
                    footer
                }
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 24)
            }
            .scrollIndicators(.never)
        }
        .background(DS.surface1)
    }

    private var header: some View {
        HStack(spacing: 6) {
            Text(T("显影", "DEVELOP"))
                .font(DS.font(10, .medium))
                .tracking(1.7)
                .foregroundStyle(DS.textSecondary)
            if model.currentEdit.adjustments.activeCount > 0 {
                Text("\(model.currentEdit.adjustments.activeCount)")
                    .font(DS.mono(8.5))
                    .foregroundStyle(DS.accent)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1.5)
                    .background(Capsule().fill(DS.accent.opacity(0.1)))
            }
            Spacer(minLength: 6)
            Button {
                model.resetAll()
            } label: {
                HeaderActionButton(title: T("重置", "Reset"),
                                   symbol: "arrow.uturn.backward",
                                   accent: false)
            }
            .buttonStyle(PressableStyle())
            .disabled(model.currentPhoto == nil)
            .opacity(model.currentPhoto == nil ? 0.4 : 1)
            .help(T("重置胶片与所有调整", "Reset film and all adjustments"))

            Button {
                model.exportPresented = true
            } label: {
                HeaderActionButton(title: T("导出", "Export"),
                                   symbol: "square.and.arrow.up",
                                   accent: true)
            }
            .buttonStyle(PressableStyle())
            .disabled(model.currentPhoto == nil || model.isExporting)
            .opacity(model.currentPhoto == nil ? 0.4 : 1)
            .help(T("导出当前照片（⌘E）", "Export the developed photograph (⌘E)"))

            SettingsGear()
        }
        .padding(.horizontal, 14)
        .frame(height: 50)
        .background(DS.surface1)
        .overlay(alignment: .bottom) {
            Rectangle().fill(DS.hairline).frame(height: 1)
        }
    }

    private var histogram: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(T("直方图", "HISTOGRAM"))
                    .font(DS.font(8.5, .medium))
                    .tracking(1.3)
                    .foregroundStyle(DS.textTertiary)
                Spacer()
                if model.currentPhoto != nil {
                    Text(T("亮度 / RGB", "LUMA / RGB"))
                        .font(DS.font(7.5, .medium))
                        .tracking(0.8)
                        .foregroundStyle(DS.textQuaternary)
                }
            }
            HistogramView(data: model.histogram, hasPhoto: model.currentPhoto != nil)
                .frame(height: 74)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(DS.surface0)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .stroke(DS.hairline, lineWidth: 1)
        )
    }

    private var tabBar: some View {
        HStack(spacing: 2) {
            ForEach(InspectorTab.allCases) { tab in
                Button {
                    guard tab != model.inspectorTab else { return }
                    tabDirection = CGFloat(tab.index > model.inspectorTab.index ? 1 : -1)
                    withAnimation(DS.snappy) { model.inspectorTab = tab }
                } label: {
                    Text(tab.title)
                        .font(DS.font(9.5, model.inspectorTab == tab ? .medium : .regular))
                        .tracking(0.7)
                        .foregroundStyle(model.inspectorTab == tab ? DS.accent : DS.textTertiary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 27)
                        .contentShape(Rectangle())
                        .background {
                            if model.inspectorTab == tab {
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .fill(DS.surface2)
                                    .matchedGeometryEffect(id: "inspectorTab", in: tabNamespace)
                            }
                        }
                        .overlay(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .stroke(model.inspectorTab == tab ? DS.accent.opacity(0.24) : .clear, lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(DS.surface1)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(DS.hairline, lineWidth: 1)
        )
    }

    @ViewBuilder
    private var tabContent: some View {
        Group {
            switch model.inspectorTab {
            case .light:
                lightContent
            case .color:
                colorContent
            case .curves:
                CurveTabView()
            }
        }
        .id(model.inspectorTab)
        .transition(.asymmetric(
            insertion: .move(edge: tabDirection > 0 ? .trailing : .leading).combined(with: .opacity),
            removal: .move(edge: tabDirection > 0 ? .leading : .trailing).combined(with: .opacity)
        ))
        .clipped()
    }

    private var lightContent: some View {
        VStack(spacing: 3) {
            SliderRow(label: T("曝光", "Exposure"), value: binding(\.exposure), range: -5...5,
                      valueText: String(format: "%+.1f EV", model.currentAdjustments.exposure),
                      defaultValue: 0)
            SliderRow(label: T("对比度", "Contrast"), value: binding(\.contrast), range: -100...100,
                      valueText: signed(model.currentAdjustments.contrast), defaultValue: 0)
            SliderRow(label: T("高光", "Highlights"), value: binding(\.highlights), range: -100...100,
                      valueText: signed(model.currentAdjustments.highlights), defaultValue: 0)
            SliderRow(label: T("阴影", "Shadows"), value: binding(\.shadows), range: -100...100,
                      valueText: signed(model.currentAdjustments.shadows), defaultValue: 0)
            SliderRow(label: T("白色", "Whites"), value: binding(\.whites), range: -100...100,
                      valueText: signed(model.currentAdjustments.whites), defaultValue: 0)
            SliderRow(label: T("黑色", "Blacks"), value: binding(\.blacks), range: -100...100,
                      valueText: signed(model.currentAdjustments.blacks), defaultValue: 0)
            SliderRow(label: T("中间调", "Midtones"), value: binding(\.midtones), range: -100...100,
                      valueText: signed(model.currentAdjustments.midtones), defaultValue: 0)
            SliderRow(label: T("高光过渡", "Highlight rolloff"), value: binding(\.highlightRolloff), range: 0...100,
                      valueText: "\(Int(model.currentAdjustments.highlightRolloff))", defaultValue: 0)
        }
        .padding(.top, 2)
    }

    private var colorContent: some View {
        VStack(alignment: .leading, spacing: 3) {
            InspectorGroupLabel(title: T("白平衡", "WHITE BALANCE"))
            SliderRow(label: T("色温", "Temperature"), value: binding(\.temperature), range: -100...100,
                      valueText: signed(model.currentAdjustments.temperature), defaultValue: 0)
            SliderRow(label: T("色调", "Tint"), value: binding(\.tint), range: -100...100,
                      valueText: signed(model.currentAdjustments.tint), defaultValue: 0)

            InspectorGroupLabel(title: T("色彩", "COLOR"))
                .padding(.top, 5)
            SliderRow(label: T("自然饱和", "Vibrance"), value: binding(\.vibrance), range: -100...100,
                      valueText: signed(model.currentAdjustments.vibrance), defaultValue: 0)
            SliderRow(label: T("饱和度", "Saturation"), value: binding(\.saturation), range: -100...100,
                      valueText: signed(model.currentAdjustments.saturation), defaultValue: 0)
            SliderRow(label: T("色相偏移", "Hue shift"), value: binding(\.hueShift), range: -100...100,
                      valueText: signed(model.currentAdjustments.hueShift), defaultValue: 0)
            SliderRow(label: T("色彩密度", "Color density"), value: binding(\.colorDensity), range: -100...100,
                      valueText: signed(model.currentAdjustments.colorDensity), defaultValue: 0)

            InspectorGroupLabel(title: T("色彩混合", "COLOR MIX"))
                .padding(.top, 5)
            SliderRow(label: T("肤色饱和", "Skin tone"), value: binding(\.skinSaturation), range: -100...100,
                      valueText: signed(model.currentAdjustments.skinSaturation), defaultValue: 0)
            SliderRow(label: T("绿色饱和", "Foliage"), value: binding(\.greenSaturation), range: -100...100,
                      valueText: signed(model.currentAdjustments.greenSaturation), defaultValue: 0)
            SliderRow(label: T("蓝色饱和", "Sky"), value: binding(\.blueSaturation), range: -100...100,
                      valueText: signed(model.currentAdjustments.blueSaturation), defaultValue: 0)

            InspectorGroupLabel(title: T("分离色调", "SPLIT TONING"))
                .padding(.top, 5)
            SliderRow(label: T("高光暖度", "Highlight warmth"), value: binding(\.highlightWarmth), range: -100...100,
                      valueText: signed(model.currentAdjustments.highlightWarmth), defaultValue: 0)
            SliderRow(label: T("阴影冷度", "Shadow coolness"), value: binding(\.shadowCoolness), range: -100...100,
                      valueText: signed(model.currentAdjustments.shadowCoolness), defaultValue: 0)
        }
        .padding(.top, 2)
    }

    private var transparencySection: some View {
        CollapsibleSection(
            title: T("通透", "TRANSPARENCY"),
            count: clarityActiveCount,
            open: $transparencyOpen,
            trailing: {
                Button {
                    model.analyzeTone()
                } label: {
                    Text(T("分析", "ANALYZE"))
                        .font(DS.font(8.5, .semibold))
                        .tracking(0.6)
                        .foregroundStyle(model.currentPhoto == nil ? DS.textQuaternary : DS.accent)
                        .padding(.horizontal, 6)
                        .frame(height: 19)
                        .background(
                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .fill(DS.accent.opacity(model.currentPhoto == nil ? 0 : 0.1))
                        )
                }
                .buttonStyle(.plain)
                .disabled(model.currentPhoto == nil)
                .help(T("按当前画面重新分析黑白场与杂色", "Re-analyze levels and casts"))
            }
        ) {
            VStack(spacing: 6) {
                SliderRow(label: T("明暗通透", "Tonal clarity"),
                          value: binding(\.tonalTransparency), range: 0...100,
                          valueText: "\(Int(model.currentAdjustments.tonalTransparency))%",
                          defaultValue: 0)
                SliderRow(label: T("颜色通透", "Color clarity"),
                          value: binding(\.colorTransparency), range: 0...100,
                          valueText: "\(Int(model.currentAdjustments.colorTransparency))%",
                          defaultValue: 0)
                toneReadout
                Text(T("明暗通透按直方图边缘重新定义黑白场；颜色通透用互补色去除高光与阴影杂色。",
                       "Tonal clarity remaps black/white to the histogram edges; colour clarity neutralises highlight and shadow casts."))
                    .font(DS.label(8.5))
                    .foregroundStyle(DS.textQuaternary)
                    .lineSpacing(1.5)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 2)
            }
        }
    }

    private var toneReadout: some View {
        let black = Int(round(model.toneStats.blackPoint * 100))
        let white = Int(round(model.toneStats.whitePoint * 100))
        let hasStats = model.currentPhoto != nil && (model.toneStats.whiteCount > 0 || model.toneStats.blackCount > 0)
        return HStack(spacing: 7) {
            Text(T("黑白场", "Levels"))
                .font(DS.label(9))
                .foregroundStyle(DS.textTertiary)
            Text(hasStats ? "\(black)–\(white)%" : T("未分析", "not analysed"))
                .font(DS.mono(9))
                .foregroundStyle(hasStats ? DS.textSecondary : DS.textQuaternary)
            if hasStats, !model.toneStats.castDescription.isEmpty {
                Rectangle().fill(DS.hairline).frame(width: 1, height: 9)
                Text(model.toneStats.castDescription)
                    .font(DS.label(8.5))
                    .foregroundStyle(DS.accent.opacity(0.85))
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .frame(height: 24)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(DS.surface0)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(DS.hairline, lineWidth: 1)
        )
    }

    private var detailSection: some View {
        CollapsibleSection(title: T("细节", "DETAIL"), count: detailActiveCount, open: $detailOpen) {
            VStack(spacing: 3) {
                SliderRow(label: T("清晰度", "Clarity"), value: binding(\.clarity), range: -100...100,
                          valueText: signed(model.currentAdjustments.clarity), defaultValue: 0)
                SliderRow(label: T("锐化", "Sharpen"), value: binding(\.sharpen), range: 0...100,
                          valueText: "\(Int(model.currentAdjustments.sharpen))", defaultValue: 0)
            }
        }
    }

    private var textureSection: some View {
        CollapsibleSection(title: T("胶片质感", "FILM TEXTURE"), count: textureActiveCount, open: $textureOpen) {
            VStack(alignment: .leading, spacing: 3) {
                InspectorGroupLabel(title: T("颗粒", "GRAIN"))
                SliderRow(label: T("颗粒", "Grain"), value: binding(\.grain), range: 0...100,
                          valueText: "\(Int(model.currentAdjustments.grain))", defaultValue: 0)
                SliderRow(label: T("颗粒尺寸", "Grain size"), value: binding(\.grainSize), range: 0...100,
                          valueText: "\(Int(model.currentAdjustments.grainSize))", defaultValue: 38,
                          dimmed: model.currentAdjustments.grain == 0)
                SliderRow(label: T("颗粒粗糙度", "Grain roughness"), value: binding(\.grainRoughness), range: 0...100,
                          valueText: "\(Int(model.currentAdjustments.grainRoughness))", defaultValue: 50,
                          dimmed: model.currentAdjustments.grain == 0)
                SliderRow(label: T("彩色颗粒", "Color grain"), value: binding(\.grainChroma), range: 0...100,
                          valueText: "\(Int(model.currentAdjustments.grainChroma))", defaultValue: 0,
                          dimmed: model.currentAdjustments.grain == 0)
                SliderRow(label: T("暗部颗粒", "Shadow grain"), value: binding(\.grainShadow), range: 0...100,
                          valueText: "\(Int(model.currentAdjustments.grainShadow))", defaultValue: 0,
                          dimmed: model.currentAdjustments.grain == 0)

                InspectorGroupLabel(title: T("光晕 / 柔光", "GLOW"))
                    .padding(.top, 5)
                SliderRow(label: T("光晕", "Halation"), value: binding(\.halation), range: 0...100,
                          valueText: "\(Int(model.currentAdjustments.halation))", defaultValue: 0)
                SliderRow(label: T("高光阈值", "Highlight threshold"), value: binding(\.halationThreshold), range: 0...100,
                          valueText: "\(Int(model.currentAdjustments.halationThreshold))", defaultValue: 55,
                          dimmed: model.currentAdjustments.halation == 0 && model.currentAdjustments.bloom == 0)
                SliderRow(label: T("扩散半径", "Glow radius"), value: binding(\.halationRadius), range: 0...100,
                          valueText: "\(Int(model.currentAdjustments.halationRadius))", defaultValue: 50,
                          dimmed: model.currentAdjustments.halation == 0 && model.currentAdjustments.bloom == 0)
                SliderRow(label: T("光晕暖度", "Halation warmth"), value: binding(\.halationWarmth), range: 0...100,
                          valueText: "\(Int(model.currentAdjustments.halationWarmth))", defaultValue: 75,
                          dimmed: model.currentAdjustments.halation == 0)
                SliderRow(label: T("柔光", "Bloom"), value: binding(\.bloom), range: 0...100,
                          valueText: "\(Int(model.currentAdjustments.bloom))", defaultValue: 0)

                InspectorGroupLabel(title: T("暗角", "VIGNETTE"))
                    .padding(.top, 5)
                SliderRow(label: T("暗角", "Vignette"), value: binding(\.vignette), range: -100...100,
                          valueText: signed(model.currentAdjustments.vignette), defaultValue: 0)
                SliderRow(label: T("中点", "Midpoint"), value: binding(\.vignetteMidpoint), range: 0...100,
                          valueText: "\(Int(model.currentAdjustments.vignetteMidpoint))", defaultValue: 50,
                          dimmed: model.currentAdjustments.vignette == 0)
                SliderRow(label: T("圆度", "Roundness"), value: binding(\.vignetteRoundness), range: -100...100,
                          valueText: signed(model.currentAdjustments.vignetteRoundness), defaultValue: 0,
                          dimmed: model.currentAdjustments.vignette == 0)
                SliderRow(label: T("柔和度", "Feather"), value: binding(\.vignetteFeather), range: 0...100,
                          valueText: "\(Int(model.currentAdjustments.vignetteFeather))", defaultValue: 50,
                          dimmed: model.currentAdjustments.vignette == 0)
                SliderRow(label: T("中心 X", "Center X"), value: binding(\.vignetteCenterX), range: -100...100,
                          valueText: signed(model.currentAdjustments.vignetteCenterX), defaultValue: 0,
                          dimmed: model.currentAdjustments.vignette == 0)
                SliderRow(label: T("中心 Y", "Center Y"), value: binding(\.vignetteCenterY), range: -100...100,
                          valueText: signed(model.currentAdjustments.vignetteCenterY), defaultValue: 0,
                          dimmed: model.currentAdjustments.vignette == 0)

                SliderRow(label: T("褪色", "Fade"), value: binding(\.fade), range: 0...100,
                          valueText: "\(Int(model.currentAdjustments.fade))", defaultValue: 0)
                    .padding(.top, 5)
            }
        }
    }

    private var infoSection: some View {
        CollapsibleSection(title: T("信息", "INFORMATION"), open: $infoOpen) {
            InfoGrid()
        }
    }

    private var footer: some View {
        HStack(spacing: 6) {
            Circle().fill(DS.accent.opacity(0.7)).frame(width: 3, height: 3)
            Text("ACES 2.0 · SpektraFilm")
                .font(DS.label(8.5))
                .foregroundStyle(DS.textQuaternary)
            Spacer()
            Text(model.currentImportedLUT != nil
                 ? T("Rec.709 LUT", "Rec.709 LUT")
                 : T("\(model.currentStock?.variants.count ?? 0) 个外观", "\(model.currentStock?.variants.count ?? 0) looks"))
                .font(DS.label(8.5))
                .foregroundStyle(DS.textQuaternary)
        }
        .padding(.top, 6)
    }

    private func binding(_ keyPath: WritableKeyPath<Adjustments, Double>) -> Binding<Double> {
        Binding(
            get: { model.currentAdjustments[keyPath: keyPath] },
            set: { newValue in
                model.updateAdjustments { $0[keyPath: keyPath] = newValue }
            }
        )
    }

    private func signed(_ value: Double) -> String {
        value >= 0 ? "+\(Int(round(value)))" : "\(Int(round(value)))"
    }

    private var clarityActiveCount: Int {
        let a = model.currentAdjustments
        return (a.tonalTransparency > 0 ? 1 : 0) + (a.colorTransparency > 0 ? 1 : 0)
    }

    private var detailActiveCount: Int {
        let a = model.currentAdjustments
        return (abs(a.clarity) > 0.01 ? 1 : 0) + (a.sharpen > 0.01 ? 1 : 0)
    }

    private var textureActiveCount: Int {
        let a = model.currentAdjustments
        var count = 0
        if a.grain > 0 {
            count += 1
            if abs(a.grainSize - 38) > 0.01 { count += 1 }
            if abs(a.grainRoughness - 50) > 0.01 { count += 1 }
            if a.grainChroma > 0 { count += 1 }
            if a.grainShadow > 0 { count += 1 }
        }
        if a.halation > 0 {
            count += 1
            if abs(a.halationThreshold - 55) > 0.01 { count += 1 }
            if abs(a.halationRadius - 50) > 0.01 { count += 1 }
            if abs(a.halationWarmth - 75) > 0.01 { count += 1 }
        }
        if a.bloom > 0 { count += 1 }
        if a.vignette != 0 {
            count += 1
            if abs(a.vignetteMidpoint - 50) > 0.01 { count += 1 }
            if abs(a.vignetteRoundness) > 0.01 { count += 1 }
            if abs(a.vignetteFeather - 50) > 0.01 { count += 1 }
            if abs(a.vignetteCenterX) > 0.01 { count += 1 }
            if abs(a.vignetteCenterY) > 0.01 { count += 1 }
        }
        if a.fade > 0 { count += 1 }
        return count
    }
}

struct InspectorGroupLabel: View {
    let title: String
    var body: some View {
        Text(title)
            .font(DS.font(8, .medium))
            .tracking(1.1)
            .foregroundStyle(DS.textQuaternary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 2)
            .padding(.bottom, 1)
    }
}

// MARK: - Header actions

struct HeaderActionButton: View {
    let title: String
    let symbol: String
    let accent: Bool
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: symbol)
                .font(DS.font(8.5, .semibold))
            Text(title)
                .font(DS.font(9.5, .medium))
        }
        .foregroundStyle(accent ? Color(hex: 0x14120E) : DS.textPrimary)
        .padding(.horizontal, 8)
        .frame(height: 24)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(accent ? (hovering ? DS.accentStrong : DS.accent) : (hovering ? DS.surface3 : DS.surface2))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(accent ? .clear : DS.hairline, lineWidth: 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .animation(DS.easeQuick, value: hovering)
        .onHover { hovering = $0 }
    }
}

// MARK: - Horizontal wheel scroller

/// A single-line horizontal row that also scrolls with a plain vertical wheel
/// while the pointer is over it, so chips pushed past the right edge stay
/// reachable without a trackpad swipe.
struct HorizontalWheelScroll<Content: View>: NSViewRepresentable {
    var height: CGFloat = 24
    var content: Content

    init(height: CGFloat = 24, @ViewBuilder content: () -> Content) {
        self.height = height
        self.content = content()
    }

    func makeNSView(context: Context) -> WheelScrollView {
        let scroll = WheelScrollView()
        scroll.drawsBackground = false
        scroll.hasHorizontalScroller = false
        scroll.hasVerticalScroller = false
        scroll.horizontalScrollElasticity = .allowed
        scroll.verticalScrollElasticity = .none
        scroll.autohidesScrollers = true
        let host = NSHostingView(rootView: content)
        host.autoresizingMask = [.height]
        scroll.documentView = host
        context.coordinator.host = host
        return scroll
    }

    func updateNSView(_ scroll: WheelScrollView, context: Context) {
        guard let host = context.coordinator.host else { return }
        host.rootView = content
        host.layoutSubtreeIfNeeded()
        var fitting = host.fittingSize
        if fitting.width < 1 { fitting.width = 600 }
        host.frame = NSRect(x: 0, y: 0, width: fitting.width, height: max(fitting.height, height))
        scroll.tile()
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        var host: NSHostingView<Content>?
    }
}

final class WheelScrollView: NSScrollView {
    override func layout() {
        super.layout()
        guard let document = documentView else { return }
        if document.frame.height < contentSize.height {
            document.frame.size.height = contentSize.height
        }
    }

    override func scrollWheel(with event: NSEvent) {
        let maxX = max(0, (documentView?.frame.width ?? 0) - contentView.bounds.width)
        guard maxX > 0.5 else {
            // Nothing to scroll sideways: let the inspector scroll normally.
            super.scrollWheel(with: event)
            return
        }
        let delta = event.scrollingDeltaY
        guard abs(delta) > 0.001 else { return }
        let step: CGFloat = event.hasPreciseScrollingDeltas ? 1.4 : 14
        var origin = contentView.bounds.origin
        origin.x -= delta * step
        origin.x = min(max(0, origin.x), maxX)
        contentView.scroll(to: origin)
        reflectScrolledClipView(contentView)
    }
}

// MARK: - Look cards

struct LookCard: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            if let stock = model.currentStock, let look = model.currentLook {
                HStack(spacing: 11) {
                    lookThumbnail(stock: stock, look: look)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(stock.name)
                            .font(DS.font(14, .semibold))
                            .foregroundStyle(DS.textPrimary)
                            .lineLimit(1)
                        Text(stock.typeLine)
                            .font(DS.label(10))
                            .foregroundStyle(DS.textTertiary)
                        HStack(spacing: 5) {
                            Text(stock.brand.uppercased())
                                .font(DS.font(7.5, .semibold))
                                .tracking(0.9)
                                .foregroundStyle(DS.accent.opacity(0.85))
                            Rectangle().fill(DS.hairlineStrong).frame(width: 1, height: 8)
                            Text(look.engine)
                                .font(DS.font(8, .regular))
                                .foregroundStyle(DS.textQuaternary)
                        }
                        .padding(.top, 3)
                    }
                    Spacer(minLength: 0)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text(T("相纸 / 渲染", "PRINT / RENDER"))
                        .font(DS.font(8, .medium))
                        .tracking(1.1)
                        .foregroundStyle(DS.textQuaternary)
                    HorizontalWheelScroll(height: 24) {
                        HStack(spacing: 5) {
                            ForEach(stock.variants) { variant in
                                VariantChip(
                                    variant: variant,
                                    selected: variant.id == look.id,
                                    enabled: model.currentPhoto != nil
                                ) {
                                    model.selectVariant(variant)
                                }
                            }
                        }
                        .padding(.vertical, 1)
                        .padding(.trailing, 4)
                    }
                    .frame(height: 24)
                }

                Rectangle().fill(DS.hairline).frame(height: 1)

                VStack(spacing: 5) {
                    HStack {
                        Text(T("胶片强度", "Film strength"))
                            .font(DS.font(10.5, .regular))
                            .foregroundStyle(DS.textSecondary)
                        Spacer()
                        Text("\(Int(round(model.currentEdit.strength * 100)))%")
                            .font(DS.mono(10))
                            .foregroundStyle(model.currentEdit.strength == 1 ? DS.textSecondary : DS.accent)
                    }
                    Slider(
                        value: Binding(
                            get: { model.currentEdit.strength },
                            set: { model.setStrength($0) }
                        ),
                        in: 0...1
                    )
                    .tint(DS.accent)
                    .controlSize(.small)
                    .disabled(model.currentPhoto == nil)
                    .accessibilityLabel(T("胶片强度", "Film strength"))
                }
            } else {
                Text(T("选择一款胶片开始", "Choose a film to begin"))
                    .font(DS.label(11))
                    .foregroundStyle(DS.textSecondary)
            }
        }
        .padding(11)
        .background(
            RoundedRectangle(cornerRadius: DS.rMedium, style: .continuous)
                .fill(DS.surface3)
        )
        .overlay(
            RoundedRectangle(cornerRadius: DS.rMedium, style: .continuous)
                .stroke(DS.hairlineStrong, lineWidth: 1)
        )
    }

    private func lookThumbnail(stock: FilmStock, look: FilmVariant) -> some View {
        ZStack {
            if let image = model.lookThumbs[look.id] ?? model.lookThumbs[stock.defaultLook] {
                Image(decorative: image, scale: 1)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                LinearGradient(
                    colors: {
                        let parsed = stock.swatch.compactMap { Color(hexString: $0) }
                        return parsed.count >= 2 ? parsed : [DS.surface2, DS.surface4]
                    }(),
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
        }
        .frame(width: 64, height: 64)
        .clipShape(RoundedRectangle(cornerRadius: DS.rSmall, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: DS.rSmall, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }
}

struct ImportedLookCard: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if let lut = model.currentImportedLUT {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    ZStack {
                        LinearGradient(colors: swatchColors(lut), startPoint: .topLeading, endPoint: .bottomTrailing)
                    }
                    .frame(width: 82, height: 56)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .stroke(Color.white.opacity(0.05), lineWidth: 1)
                    )
                    VStack(alignment: .leading, spacing: 2) {
                        Text(lut.name)
                            .font(DS.font(14, .medium))
                            .foregroundStyle(DS.textPrimary)
                            .lineLimit(1)
                        Text(lut.subtitle)
                            .font(DS.label(9))
                            .foregroundStyle(DS.textTertiary)
                        HStack(spacing: 5) {
                            Text("LUT")
                                .font(DS.font(7.5, .semibold))
                                .tracking(0.9)
                                .foregroundStyle(DS.accent.opacity(0.85))
                            Rectangle().fill(DS.hairlineStrong).frame(width: 1, height: 8)
                            Text(T("Rec.709 显示", "Rec.709 display"))
                                .font(DS.font(8))
                                .foregroundStyle(DS.textQuaternary)
                        }
                        .padding(.top, 2)
                    }
                    Spacer(minLength: 0)
                    Button {
                        model.clearLUT()
                    } label: {
                        Image(systemName: "xmark")
                            .font(DS.font(8, .semibold))
                            .foregroundStyle(DS.textTertiary)
                            .frame(width: 21, height: 21)
                            .background(Circle().fill(DS.surface1))
                    }
                    .buttonStyle(.plain)
                    .help(T("移除 LUT", "Remove LUT"))
                }

                Rectangle().fill(DS.hairline).frame(height: 1)

                VStack(spacing: 5) {
                    HStack {
                        Text(T("LUT 强度", "LUT strength"))
                            .font(DS.font(10.5, .regular))
                            .foregroundStyle(DS.textSecondary)
                        Spacer()
                        Text("\(Int(round(model.currentEdit.lutStrength * 100)))%")
                            .font(DS.mono(10))
                            .foregroundStyle(model.currentEdit.lutStrength == 1 ? DS.textSecondary : DS.accent)
                    }
                    Slider(
                        value: Binding(
                            get: { model.currentEdit.lutStrength },
                            set: { model.setLUTStrength($0) }
                        ),
                        in: 0...1
                    )
                    .tint(DS.accent)
                    .controlSize(.mini)
                    .disabled(model.currentPhoto == nil)
                    .accessibilityLabel(T("LUT 强度", "LUT strength"))
                }
            }
            .padding(11)
            .background(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(DS.surface2)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .stroke(DS.hairline, lineWidth: 1)
            )
        }
    }

    private func swatchColors(_ lut: ImportedLUT) -> [Color] {
        let parsed = lut.swatch.compactMap { Color(hexString: $0) }
        return parsed.count >= 2 ? parsed : [DS.surface2, DS.surface4]
    }
}

struct VariantChip: View {
    let variant: FilmVariant
    let selected: Bool
    let enabled: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Text(variant.localizedLabel)
                    .font(DS.font(9, selected ? .medium : .regular))
                Text(variant.engineShort)
                    .font(DS.font(6.5, .semibold))
                    .tracking(0.4)
                    .foregroundStyle(selected ? DS.accent.opacity(0.75) : DS.textQuaternary)
            }
            .foregroundStyle(selected ? DS.accent : (hovering ? DS.textSecondary : DS.textTertiary))
            .padding(.horizontal, 7)
            .frame(height: 22)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(selected ? DS.accent.opacity(0.09) : (hovering ? DS.surface3 : DS.surface1))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(selected ? DS.accent.opacity(0.25) : DS.hairline, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.55)
        .onHover { hovering = $0 }
        .animation(DS.easeQuick, value: hovering)
        .animation(DS.snappy, value: selected)
        .help(variant.displayRequirement ?? variant.engine)
    }
}

// MARK: - Section

struct CollapsibleSection<Content: View, Trailing: View>: View {
    let title: String
    var count: Int = 0
    @Binding var open: Bool
    @ViewBuilder var trailing: Trailing
    @ViewBuilder var content: Content

    init(title: String, count: Int = 0, open: Binding<Bool>,
         @ViewBuilder trailing: () -> Trailing,
         @ViewBuilder content: () -> Content) {
        self.title = title
        self.count = count
        self._open = open
        self.trailing = trailing()
        self.content = content()
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Button {
                    withAnimation(DS.snappy) { open.toggle() }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "chevron.right")
                            .font(DS.font(8, .semibold))
                            .foregroundStyle(open ? DS.accent : DS.textTertiary)
                            .rotationEffect(.degrees(open ? 90 : 0))
                            .frame(width: 9)
                        Text(title)
                            .font(DS.font(9.5, .medium))
                            .tracking(1.1)
                            .foregroundStyle(open ? DS.textSecondary : DS.textTertiary)
                        Spacer(minLength: 0)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                if count > 0 {
                    Text("\(count)")
                        .font(DS.mono(8.5))
                        .foregroundStyle(DS.accent)
                        .transition(.opacity.combined(with: .scale(scale: 0.8)))
                }
                trailing
            }
            .padding(.horizontal, 12)
            .frame(height: 34)
            .animation(DS.easeQuick, value: count)

            if open {
                content
                    .padding(.horizontal, 12)
                    .padding(.top, 2)
                    .padding(.bottom, 11)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(
            RoundedRectangle(cornerRadius: DS.rMedium, style: .continuous)
                .fill(DS.surface2)
        )
        .overlay(
            RoundedRectangle(cornerRadius: DS.rMedium, style: .continuous)
                .stroke(DS.hairline, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: DS.rMedium, style: .continuous))
        .animation(DS.snappy, value: open)
    }
}

extension CollapsibleSection where Trailing == EmptyView {
    init(title: String, count: Int = 0, open: Binding<Bool>, @ViewBuilder content: () -> Content) {
        self.init(title: title, count: count, open: open, trailing: { EmptyView() }, content: content)
    }
}

// MARK: - Slider row

struct SliderRow: View {
    let label: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let valueText: String
    let defaultValue: Double
    var dimmed = false
    @State private var hovering = false

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 6) {
                Text(label)
                    .font(DS.font(10.5, .regular))
                    .foregroundStyle(dimmed ? DS.textQuaternary : (hovering ? DS.textPrimary : DS.textSecondary))
                    .onTapGesture(count: 2) {
                        withAnimation(DS.easeQuick) { value = defaultValue }
                    }
                Spacer()
                Text(valueText)
                    .font(DS.mono(9.5))
                    .foregroundStyle(isModified ? DS.accent : DS.textTertiary)
                    .frame(minWidth: 46, alignment: .trailing)
            }
            Slider(value: $value, in: range)
                .tint(isModified ? DS.accent : Color.white.opacity(0.24))
                .controlSize(.mini)
                .opacity(dimmed ? 0.4 : 1)
                .accessibilityLabel(label)
                .accessibilityValue(valueText)
        }
        .padding(.vertical, 3)
        .frame(height: 38)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .help(T("双击标签重置", "Double-click the label to reset"))
    }

    private var isModified: Bool {
        abs(value - defaultValue) > 0.001
    }
}

// MARK: - Histogram

struct HistogramView: View {
    let data: HistogramData
    let hasPhoto: Bool

    var body: some View {
        Canvas { context, size in
            for fraction in [0.25, 0.5, 0.75] {
                var path = Path()
                path.move(to: CGPoint(x: size.width * fraction, y: 0))
                path.addLine(to: CGPoint(x: size.width * fraction, y: size.height))
                context.stroke(path, with: .color(DS.hairline), lineWidth: 1)
            }
            var horizontal = Path()
            horizontal.move(to: CGPoint(x: 0, y: size.height * 0.5))
            horizontal.addLine(to: CGPoint(x: size.width, y: size.height * 0.5))
            context.stroke(horizontal, with: .color(DS.hairline), lineWidth: 1)

            guard hasPhoto else { return }

            let lumaPath = curve(smooth(data.luma), size: size)
            context.fill(lumaPath, with: .color(.white.opacity(0.10)))
            context.stroke(lumaPath, with: .color(.white.opacity(0.22)), lineWidth: 1)

            context.blendMode = .plusLighter
            for (bins, color) in [
                (data.red, Color(hex: 0xE06A5A)),
                (data.green, Color(hex: 0x79B58A)),
                (data.blue, Color(hex: 0x6E9ED8))
            ] {
                let path = curve(smooth(bins), size: size)
                context.stroke(path, with: .color(color.opacity(0.45)), lineWidth: 1)
            }
            context.blendMode = .normal

            if data.luma[0] > 0.55 {
                context.fill(Path(CGRect(x: 0, y: 0, width: 4, height: 4)), with: .color(DS.danger.opacity(0.8)))
            }
            if data.luma[255] > 0.55 {
                context.fill(Path(CGRect(x: size.width - 4, y: 0, width: 4, height: 4)), with: .color(DS.textPrimary.opacity(0.8)))
            }
        }
        .overlay(alignment: .center) {
            if !hasPhoto {
                Text(T("无照片", "No photograph"))
                    .font(DS.label(9))
                    .foregroundStyle(DS.textQuaternary)
            }
        }
    }

    private func smooth(_ bins: [Float]) -> [Float] {
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

    private func curve(_ bins: [Float], size: CGSize) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: 0, y: size.height))
        let count = max(bins.count, 1)
        for index in 0..<count {
            let x = CGFloat(index) / CGFloat(count - 1) * size.width
            let value = CGFloat(min(max(bins[index], 0), 1))
            let y = size.height - value * (size.height - 2)
            path.addLine(to: CGPoint(x: x, y: y))
        }
        path.addLine(to: CGPoint(x: size.width, y: size.height))
        path.closeSubpath()
        return path
    }
}

// MARK: - Info

struct InfoGrid: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if let photo = model.currentPhoto {
            VStack(spacing: 6) {
                row(T("文件", "File"), photo.name)
                if photo.pixelSize.width > 0 {
                    row(T("尺寸", "Dimensions"), "\(Int(photo.pixelSize.width)) × \(Int(photo.pixelSize.height))")
                }
                if let camera = photo.metadata.camera { row(T("相机", "Camera"), camera) }
                if let lens = photo.metadata.lens { row(T("镜头", "Lens"), lens) }
                if let iso = photo.metadata.iso { row("ISO", iso) }
                if let aperture = photo.metadata.aperture { row(T("光圈", "Aperture"), aperture) }
                if let shutter = photo.metadata.shutter { row(T("快门", "Shutter"), shutter) }
                if let focal = photo.metadata.focalLength { row(T("焦距", "Focal length"), focal) }
                if let lut = model.currentImportedLUT {
                    row("LUT", "\(lut.name) · \(lut.subtitle)")
                } else if let look = model.currentLook {
                    row(T("外观", "Look"), "\(look.localizedLabel) · \(look.engine)")
                }
            }
        } else {
            Text(T("导入照片后显示元数据。", "Import a photograph to see its metadata."))
                .font(DS.label(10))
                .foregroundStyle(DS.textTertiary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 4)
        }
    }

    private func row(_ key: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(key)
                .font(DS.label(9.5))
                .foregroundStyle(DS.textTertiary)
                .frame(width: 74, alignment: .leading)
            Text(value)
                .font(DS.font(9.5, .regular))
                .foregroundStyle(DS.textSecondary)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
    }
}
