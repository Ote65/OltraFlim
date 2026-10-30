import SwiftUI
import AppKit

struct SettingsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                ZStack {
                    Circle().strokeBorder(DS.accent.opacity(0.8), lineWidth: 1)
                        .frame(width: 18, height: 18)
                    Circle().fill(DS.accent).frame(width: 4, height: 4)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("OltraFlim")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(DS.textPrimary)
                    Text(T("macOS 胶片模拟暗房", "Film simulation darkroom for macOS"))
                        .font(DS.label(9.5))
                        .foregroundStyle(DS.textSecondary)
                }
                Spacer()
                Text("1.3")
                    .font(DS.mono(9))
                    .foregroundStyle(DS.textQuaternary)
            }
            .padding(.bottom, 18)

            Rectangle().fill(DS.hairline).frame(height: 1)

            VStack(alignment: .leading, spacing: 10) {
                Text(T("语言", "LANGUAGE"))
                    .font(.system(size: 8.5, weight: .medium))
                    .tracking(1.2)
                    .foregroundStyle(DS.textTertiary)
                HStack(spacing: 5) {
                    ForEach(AppLanguage.allCases) { language in
                        ChoiceChip(title: language.label, selected: model.language == language) {
                            model.language = language
                        }
                    }
                    Spacer()
                    Text(T("切换后立即生效", "Applies immediately"))
                        .font(DS.label(8.5))
                        .foregroundStyle(DS.textQuaternary)
                }
            }
            .padding(.top, 18)

            Rectangle().fill(DS.hairline).frame(height: 1)
                .padding(.vertical, 18)

            VStack(alignment: .leading, spacing: 10) {
                Text(T("导出默认", "EXPORT DEFAULTS"))
                    .font(.system(size: 8.5, weight: .medium))
                    .tracking(1.2)
                    .foregroundStyle(DS.textTertiary)
                HStack(spacing: 5) {
                    ForEach(ExportFormat.allCases) { format in
                        ChoiceChip(title: format.label, selected: model.exportOptions.format == format) {
                            model.exportOptions.format = format
                            model.saveExportOptions()
                        }
                    }
                    Spacer()
                }
                if model.exportOptions.format.isLossy {
                    HStack {
                        Text(T("画质", "Quality"))
                            .font(DS.label(10.5))
                            .foregroundStyle(DS.textSecondary)
                        Slider(value: $model.exportOptions.quality, in: 0.5...1)
                            .tint(DS.accent)
                            .controlSize(.small)
                            .onChange(of: model.exportOptions.quality) { _, _ in model.saveExportOptions() }
                        Text("\(Int(round(model.exportOptions.quality * 100)))%")
                            .font(DS.mono(9.5))
                            .foregroundStyle(DS.textTertiary)
                            .frame(width: 36, alignment: .trailing)
                    }
                }
            }
            .padding(.top, 0)

            Rectangle().fill(DS.hairline).frame(height: 1)
                .padding(.vertical, 18)

            VStack(alignment: .leading, spacing: 8) {
                Text(T("胶片包", "FILM PACK"))
                    .font(.system(size: 8.5, weight: .medium))
                    .tracking(1.2)
                    .foregroundStyle(DS.textTertiary)
                Text(T("\(lookCount) 个外观 · \(model.catalog.stocks.count) 种胶片 · 33³ LUT",
                       "\(lookCount) looks · \(model.catalog.stocks.count) stocks · 33³ LUTs"))
                    .font(DS.label(10))
                    .foregroundStyle(DS.textSecondary)
                Text(T("胶片模型由 Andrea Volpato 的 spektrafilm 驱动，显示变换使用 OpenColorIO 的 ACES 2.0 SDR。LUT 衍生数据按 CC BY-SA 4.0 共享。",
                       "Film modeling powered by spektrafilm by Andrea Volpato, with the ACES 2.0 SDR output transform from OpenColorIO. LUT derivatives are shared under CC BY-SA 4.0."))
                    .font(DS.label(9.5))
                    .foregroundStyle(DS.textTertiary)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 12) {
                    Button(T("spektrafilm GitHub", "spektrafilm on GitHub")) {
                        NSWorkspace.shared.open(URL(string: "https://github.com/andreavolpato/spektrafilm")!)
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundStyle(DS.accent)
                    Button("ACES") {
                        NSWorkspace.shared.open(URL(string: "https://acescentral.com")!)
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundStyle(DS.accent)
                }
                .padding(.top, 2)
            }

            Spacer(minLength: 0)

            HStack {
                Button(T("重置收藏", "Reset favorites")) {
                    model.favorites.removeAll()
                    UserDefaults.standard.set([], forKey: "favorites")
                }
                .buttonStyle(.plain)
                .font(.system(size: 9.5, weight: .medium))
                .foregroundStyle(DS.textTertiary)
                Spacer()
                Text(T("© 2026 Oltra", "© 2026 Oltra"))
                    .font(DS.label(8.5))
                    .foregroundStyle(DS.textQuaternary)
            }
        }
        .padding(24)
        .frame(width: 480, height: 540)
        .background(DS.surface0)
        .background(SettingsWindowTitle())
        .tint(DS.accent)
        .preferredColorScheme(.dark)
        .focusEffectDisabled()
        .id(model.language)
    }

    private var lookCount: Int {
        model.catalog.stocks.reduce(0) { $0 + $1.variants.count }
    }
}


private struct SettingsWindowTitle: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            view.window?.title = T("OltraFlim 设置", "OltraFlim Settings")
            view.window?.appearance = NSAppearance(named: .darkAqua)
            view.window?.makeFirstResponder(nil)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            nsView.window?.title = T("OltraFlim 设置", "OltraFlim Settings")
            nsView.window?.makeFirstResponder(nil)
        }
    }
}
