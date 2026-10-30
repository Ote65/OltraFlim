import SwiftUI
import AppKit

/// A floating settings panel opened from the library's bottom-right corner.
/// It hosts the same `AppModel` as the main window, so changes apply live.
struct SettingsPanel: View {
    @Environment(AppModel.self) private var model
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(spacing: 12) {
                    appearanceCard
                    exportCard
                    maintenanceCard
                    footer
                }
                .padding(.horizontal, 18)
                .padding(.top, 14)
                .padding(.bottom, 20)
            }
            .scrollIndicators(.never)
        }
        .frame(width: 560, height: 620)
        .background(DS.surface0)
        .preferredColorScheme(.dark)
        .tint(DS.accent)
        .focusEffectDisabled()
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 9) {
            if let mark = AppLogo.mark {
                Image(nsImage: mark)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 19, height: 19)
            }
            Text(T("设置", "SETTINGS"))
                .font(DS.font(10, .medium))
                .tracking(1.7)
                .foregroundStyle(DS.textSecondary)
            Spacer(minLength: 8)
            Text("OltraFlim 1.4")
                .font(DS.mono(8.5))
                .foregroundStyle(DS.textQuaternary)
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(DS.font(9, .semibold))
                    .foregroundStyle(DS.textTertiary)
                    .frame(width: 26, height: 26)
                    .background(
                        RoundedRectangle(cornerRadius: DS.rSmall, style: .continuous)
                            .fill(DS.surface2)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: DS.rSmall, style: .continuous)
                            .stroke(DS.hairline, lineWidth: 1)
                    )
                    .contentShape(Rectangle())
            }
            .buttonStyle(PressableStyle(scale: 0.94))
            .help(T("关闭设置", "Close settings"))
        }
        .padding(.horizontal, 18)
        .frame(height: 50)
        .overlay(alignment: .bottom) {
            Rectangle().fill(DS.hairline).frame(height: 1)
        }
    }

    // MARK: Appearance

    private var appearanceCard: some View {
        SettingsCard(title: T("外观", "APPEARANCE")) {
            SettingsRow(title: T("语言", "Language"),
                        detail: T("切换后立即生效", "Applies immediately")) {
                HStack(spacing: 5) {
                    ForEach(AppLanguage.allCases) { language in
                        ChoiceChip(title: language.label, selected: model.language == language) {
                            model.language = language
                        }
                    }
                }
            }

            SettingsDivider()

            SettingsRow(title: T("界面字号", "Text size"),
                        detail: T("只影响文字，不改变窗口布局", "Scales type only, not the layout")) {
                HStack(spacing: 5) {
                    ForEach(TextSizeOption.allCases) { option in
                        ChoiceChip(title: option.label, selected: model.textScale == option.scale) {
                            model.textScale = option.scale
                        }
                    }
                }
            }

            SettingsDivider()

            SettingsRow(title: T("减弱动画", "Reduce motion"),
                        detail: T("关闭过渡与弹跳动画，更适合长时间修图",
                                   "Skips transitions and springs for long editing sessions")) {
                SettingsSwitch(isOn: Binding(
                    get: { model.reduceMotion },
                    set: { model.reduceMotion = $0 }
                ))
            }
        }
    }

    // MARK: Export

    private var exportCard: some View {
        SettingsCard(title: T("导出", "EXPORT")) {
            SettingsRow(title: T("默认保存位置", "Default save folder"),
                        detail: defaultDirectoryDetail) {
                HStack(spacing: 5) {
                    if model.defaultExportDirectoryPath != nil {
                        Button(T("恢复默认", "Reset")) {
                            model.defaultExportDirectoryPath = nil
                        }
                        .buttonStyle(.plain)
                        .font(DS.font(9.5, .medium))
                        .foregroundStyle(DS.textTertiary)
                        .padding(.horizontal, 8)
                        .frame(height: 24)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(DS.surface3)
                        )
                    }
                    Button(T("选择…", "Choose…")) {
                        model.chooseDefaultExportDirectory()
                    }
                    .buttonStyle(.plain)
                    .font(DS.font(9.5, .medium))
                    .foregroundStyle(DS.accent)
                    .padding(.horizontal, 9)
                    .frame(height: 24)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(DS.accent.opacity(0.1))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .stroke(DS.accent.opacity(0.24), lineWidth: 1)
                    )
                }
            }

            SettingsDivider()

            SettingsRow(title: T("默认格式", "Default format"),
                        detail: T("导出面板会沿用这个格式", "The save panel starts with this format")) {
                HStack(spacing: 5) {
                    ForEach(ExportFormat.allCases) { format in
                        ChoiceChip(title: format.label, selected: model.exportOptions.format == format) {
                            model.exportOptions.format = format
                            model.saveExportOptions()
                        }
                    }
                }
            }

            if model.exportOptions.format.isLossy {
                SettingsDivider()
                SettingsRow(title: T("画质", "Quality"), detail: nil) {
                    HStack(spacing: 8) {
                        Slider(value: Binding(
                            get: { model.exportOptions.quality },
                            set: { model.exportOptions.quality = $0; model.saveExportOptions() }
                        ), in: 0.5...1)
                        .tint(DS.accent)
                        .controlSize(.small)
                        .frame(width: 130)
                        Text("\(Int(round(model.exportOptions.quality * 100)))%")
                            .font(DS.mono(9.5))
                            .foregroundStyle(DS.textTertiary)
                            .frame(width: 34, alignment: .trailing)
                    }
                }
            }
        }
    }

    private var defaultDirectoryDetail: String {
        guard let path = model.defaultExportDirectoryPath else {
            return T("每次导出时由保存面板决定", "Decided by the save panel each time")
        }
        let url = URL(fileURLWithPath: path)
        let parent = url.deletingLastPathComponent().lastPathComponent
        let shortened = "~/\(parent)/\(url.lastPathComponent)"
        return shortened
    }

    // MARK: Maintenance

    private var maintenanceCard: some View {
        SettingsCard(title: T("存储与缓存", "STORAGE & CACHE")) {
            SettingsRow(title: T("图片缓存", "Image cache"),
                        detail: cacheDetail) {
                HStack(spacing: 6) {
                    if model.isClearingCache {
                        Text(T("清理中…", "Clearing…"))
                            .font(DS.label(9))
                            .foregroundStyle(DS.textQuaternary)
                    }
                    Button(T("清理", "Clear")) {
                        model.clearThumbnailCache()
                    }
                    .buttonStyle(.plain)
                    .font(DS.font(9.5, .medium))
                    .foregroundStyle(DS.accent)
                    .disabled(model.isClearingCache)
                    .padding(.horizontal, 11)
                    .frame(height: 24)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(DS.accent.opacity(0.1))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .stroke(DS.accent.opacity(0.24), lineWidth: 1)
                    )
                    .help(T("只清理缩略图与预览缓存，不触碰原图、编辑记录和导入的 LUT",
                            "Clears thumbnail and preview caches only; originals, edits and imported LUTs stay"))
                }
            }

            SettingsDivider()

            SettingsRow(title: T("应用数据", "App data"),
                        detail: dataDetail) {
                Button(T("在访达中显示", "Show in Finder")) {
                    model.revealDataFolder()
                }
                .buttonStyle(.plain)
                .font(DS.font(9, .medium))
                .foregroundStyle(DS.textTertiary)
            }
        }
        .onAppear { model.refreshStorageUsage() }
    }

    private var cacheDetail: String {
        let cache = sized(model.storageUsage.cacheBytes)
        return T("磁盘 \(cache) · 内存 \(model.thumbnailCacheCount) 张缩略图",
                 "On disk \(cache) · \(model.thumbnailCacheCount) thumbnails in memory")
    }

    private var dataDetail: String {
        T("编辑、收藏与导入的 LUT · \(sized(model.storageUsage.dataBytes))，更新软件不会丢失",
           "Edits, favourites and imported LUTs · \(sized(model.storageUsage.dataBytes)) survive updates")
    }

    private func sized(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.isAdaptive = true
        return formatter.string(fromByteCount: bytes)
    }

    private var footer: some View {
        HStack(spacing: 6) {
            Circle().fill(DS.accent.opacity(0.6)).frame(width: 3, height: 3)
            Text(T("设置会自动保存", "Settings are saved automatically"))
                .font(DS.label(9))
                .foregroundStyle(DS.textQuaternary)
            Spacer()
            Button(T("更多设置…", "More settings…")) {
                if !NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil) {
                    NSApp.sendAction(Selector(("showPreferencesWindow:")), to: nil, from: nil)
                }
            }
            .buttonStyle(.plain)
            .font(DS.font(9, .medium))
            .foregroundStyle(DS.textTertiary)
        }
        .padding(.horizontal, 4)
        .padding(.top, 2)
    }
}

// MARK: - Building blocks

enum TextSizeOption: String, CaseIterable, Identifiable {
    case small
    case standard
    case large

    var id: String { rawValue }

    var scale: Double {
        switch self {
        case .small: return 0.92
        case .standard: return 1.0
        case .large: return 1.1
        }
    }

    var label: String {
        switch self {
        case .small: return T("小", "S")
        case .standard: return T("标准", "M")
        case .large: return T("大", "L")
        }
    }
}

struct SettingsCard<Content: View>: View {
    let title: String
    var content: Content

    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(DS.font(8.5, .medium))
                .tracking(1.3)
                .foregroundStyle(DS.textTertiary)
                .padding(.horizontal, 14)
                .padding(.top, 12)
                .padding(.bottom, 8)
            VStack(spacing: 0) {
                content
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 12)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: DS.rMedium, style: .continuous)
                .fill(DS.surface1)
        )
        .overlay(
            RoundedRectangle(cornerRadius: DS.rMedium, style: .continuous)
                .stroke(DS.hairline, lineWidth: 1)
        )
    }
}

struct SettingsRow<Trailing: View>: View {
    let title: String
    let detail: String?
    var trailing: Trailing

    init(title: String, detail: String?, @ViewBuilder trailing: () -> Trailing) {
        self.title = title
        self.detail = detail
        self.trailing = trailing()
    }

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(DS.font(11.5, .medium))
                    .foregroundStyle(DS.textPrimary)
                if let detail {
                    Text(detail)
                        .font(DS.label(9.5))
                        .foregroundStyle(DS.textTertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            Spacer(minLength: 8)
            trailing
        }
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct SettingsDivider: View {
    var body: some View {
        Rectangle().fill(DS.hairline).frame(height: 1)
    }
}

struct SettingsSwitch: View {
    @Binding var isOn: Bool
    @State private var hovering = false

    var body: some View {
        Button {
            withAnimation(DS.easeQuick) { isOn.toggle() }
        } label: {
            ZStack(alignment: isOn ? .trailing : .leading) {
                Capsule()
                    .fill(isOn ? DS.accent : DS.surface4)
                    .frame(width: 36, height: 20)
                Circle()
                    .fill(isOn ? Color(hex: 0x14120E) : DS.textTertiary)
                    .frame(width: 16, height: 16)
                    .padding(2)
            }
            .overlay(
                Capsule().stroke(isOn ? .clear : (hovering ? DS.hairlineStrong : DS.hairline), lineWidth: 1)
            )
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { value in
            withAnimation(DS.easeQuick) { hovering = value }
        }
        .accessibilityLabel(isOn ? T("已开启", "On") : T("已关闭", "Off"))
    }
}

// MARK: - Floating entry button

struct SettingsFloatingButton: View {
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: "gearshape.fill")
                .font(DS.font(14, .medium))
                .foregroundStyle(hovering ? DS.accent : DS.textSecondary)
                .frame(width: 42, height: 42)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(hovering ? DS.surface4 : DS.surface3)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(hovering ? DS.accent.opacity(0.45) : DS.hairlineStrong, lineWidth: 1)
                )
                .shadow(color: .black.opacity(hovering ? 0.48 : 0.32), radius: 12, y: 5)
                .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(PressableStyle(scale: 0.95))
        .onHover { value in
            withAnimation(DS.easeQuick) { hovering = value }
        }
        .help(T("打开设置", "Open settings"))
    }
}

// MARK: - Window

@MainActor
final class SettingsPanelController {
    static let shared = SettingsPanelController()
    private var window: NSWindow?

    func show(model: AppModel) {
        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let panel = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 620),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true
        panel.backgroundColor = NSColor(hex: 0x0B0B0B)
        panel.appearance = NSAppearance(named: .darkAqua)
        panel.isReleasedWhenClosed = false
        panel.standardWindowButton(.closeButton)?.isHidden = true
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true
        panel.center()

        let host = NSHostingView(rootView: SettingsPanel(onClose: { [weak panel] in
            panel?.close()
        }).environment(model))
        panel.contentView = host

        window = panel
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
