import SwiftUI
import AppKit

struct SettingsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                if let mark = AppLogo.mark {
                    Image(nsImage: mark)
                        .resizable()
                        .interpolation(.high)
                        .frame(width: 28, height: 28)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Oltrafilm")
                        .font(DS.font(15, .medium))
                        .foregroundStyle(DS.textPrimary)
                    Text(T("macOS 胶片模拟暗房", "Film simulation darkroom for macOS"))
                        .font(DS.label(9.5))
                        .foregroundStyle(DS.textSecondary)
                }
                Spacer()
                Text("1.4")
                    .font(DS.mono(9))
                    .foregroundStyle(DS.textQuaternary)
            }
            .padding(.bottom, 18)

            Rectangle().fill(DS.hairline).frame(height: 1)

            VStack(alignment: .leading, spacing: 10) {
                Text(T("语言", "LANGUAGE"))
                    .font(DS.font(8.5, .medium))
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
                    .font(DS.font(8.5, .medium))
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

            VStack(alignment: .leading, spacing: 10) {
                Text(T("显影", "DEVELOP"))
                    .font(DS.font(8.5, .medium))
                    .tracking(1.2)
                    .foregroundStyle(DS.textTertiary)
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(T("自动曝光", "Auto exposure"))
                            .font(DS.label(10.5))
                            .foregroundStyle(DS.textSecondary)
                        Text(T("按画面加权亮度把中间调归一到 18% 灰；关闭后 RAW 保留原始曝光",
                               "Normalises the weighted mean to 18% grey; off keeps the RAW's own exposure"))
                            .font(DS.label(9))
                            .foregroundStyle(DS.textTertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 12)
                    Toggle("", isOn: $model.autoExposure)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .tint(DS.accent)
                }
            }

            Rectangle().fill(DS.hairline).frame(height: 1)
                .padding(.vertical, 18)

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(T("存储与缓存", "STORAGE & CACHE"))
                        .font(DS.font(8.5, .medium))
                        .tracking(1.2)
                        .foregroundStyle(DS.textTertiary)
                    Spacer()
                    if model.isClearingCache {
                        Text(T("清理中…", "Clearing…"))
                            .font(DS.label(9))
                            .foregroundStyle(DS.textQuaternary)
                    }
                    Button(T("清理缓存", "Clear cache")) {
                        model.clearThumbnailCache()
                    }
                    .buttonStyle(.plain)
                    .font(DS.font(9.5, .medium))
                    .foregroundStyle(DS.accent)
                    .disabled(model.isClearingCache)
                    .help(T("只清理缩略图与预览缓存，不触碰原图、编辑记录和导入的 LUT",
                            "Clears thumbnail and preview caches only; originals, edits and imported LUTs stay"))
                }
                Text(T("缓存 \(sized(model.storageUsage.cacheBytes)) · 数据 \(sized(model.storageUsage.dataBytes))",
                       "Cache \(sized(model.storageUsage.cacheBytes)) · Data \(sized(model.storageUsage.dataBytes))"))
                    .font(DS.mono(9.5))
                    .foregroundStyle(DS.textSecondary)
                Text(T("照片始终从原位置读取，不会复制进应用目录；编辑、收藏与导入的 LUT 保存在应用数据文件夹，更新软件不会丢失。",
                       "Photographs stay in their original locations and are never copied. Edits, favourites and imported LUTs live in the app data folder and survive updates."))
                    .font(DS.label(9.5))
                    .foregroundStyle(DS.textTertiary)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
                Button(T("在访达中显示数据文件夹", "Show data folder in Finder")) {
                    model.revealDataFolder()
                }
                .buttonStyle(.plain)
                .font(.system(size: 9.5, weight: .medium))
                .foregroundStyle(DS.accent)
                .padding(.top, 2)
            }

            Rectangle().fill(DS.hairline).frame(height: 1)
                .padding(.vertical, 18)

            VStack(alignment: .leading, spacing: 8) {
                Text(T("胶片包", "FILM PACK"))
                    .font(DS.font(8.5, .medium))
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
                    .font(DS.font(9.5, .medium))
                    .foregroundStyle(DS.accent)
                    Button("ACES") {
                        NSWorkspace.shared.open(URL(string: "https://acescentral.com")!)
                    }
                    .buttonStyle(.plain)
                    .font(DS.font(9.5, .medium))
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
                .font(DS.font(9.5, .medium))
                .foregroundStyle(DS.textTertiary)
                Spacer()
                Text(T("© 2026 Oltra", "© 2026 Oltra"))
                    .font(DS.label(8.5))
                    .foregroundStyle(DS.textQuaternary)
            }
        }
        .padding(24)
        .frame(width: 480, height: 640)
        .background(DS.surface0)
        .background(SettingsWindowTitle())
        .tint(DS.accent)
        .preferredColorScheme(.dark)
        .focusEffectDisabled()
        .onAppear { model.refreshStorageUsage() }
        .id(model.language)
    }

    private var lookCount: Int {
        model.catalog.stocks.reduce(0) { $0 + $1.variants.count }
    }

    private func sized(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.isAdaptive = true
        return formatter.string(fromByteCount: bytes)
    }
}


private struct SettingsWindowTitle: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            view.window?.title = T("Oltrafilm 设置", "Oltrafilm Settings")
            view.window?.appearance = NSAppearance(named: .darkAqua)
            view.window?.makeFirstResponder(nil)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            nsView.window?.title = T("Oltrafilm 设置", "Oltrafilm Settings")
            nsView.window?.makeFirstResponder(nil)
        }
    }
}
