import SwiftUI

struct ExportSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        @Bindable var model = model
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(T("导出", "Export"))
                        .font(DS.font(18, .medium))
                        .foregroundStyle(DS.textPrimary)
                    Text(T("基于 \(model.currentImportedLUT?.name ?? model.currentStock?.name ?? "OltraFlim")", "Developed with \(model.currentImportedLUT?.name ?? model.currentStock?.name ?? "OltraFlim")"))
                        .font(DS.label(10))
                        .foregroundStyle(DS.textSecondary)
                }
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(DS.font(10, .semibold))
                        .foregroundStyle(DS.textTertiary)
                        .frame(width: 24, height: 24)
                        .background(Circle().fill(DS.surface2))
                }
                .buttonStyle(.plain)
                .tint(DS.accent)
                .focusEffectDisabled()
            }
            .padding(.bottom, 20)

            FieldLabel(T("格式", "FORMAT"))
            ChipRow {
                ForEach(ExportFormat.allCases) { format in
                    ChoiceChip(title: format.label,
                               selected: model.exportOptions.format == format) {
                        model.exportOptions.format = format
                        model.saveExportOptions()
                    }
                }
            }
            .padding(.bottom, 16)

            if model.exportOptions.format.isLossy {
                HStack {
                    FieldLabel(T("画质", "QUALITY"))
                    Spacer()
                    Text("\(Int(round(model.exportOptions.quality * 100)))%")
                        .font(DS.mono(10))
                        .foregroundStyle(DS.accent)
                }
                Slider(value: $model.exportOptions.quality, in: 0.5...1)
                    .tint(DS.accent)
                    .controlSize(.small)
                    .onChange(of: model.exportOptions.quality) { _, _ in model.saveExportOptions() }
                    .padding(.bottom, 16)
            }

            FieldLabel(T("尺寸", "SIZE"))
            ChipRow {
                ChoiceChip(title: T("完整分辨率", "Full resolution"), selected: model.exportOptions.longEdge == nil) {
                    model.exportOptions.longEdge = nil
                    model.saveExportOptions()
                }
                ChoiceChip(title: "4096 px", selected: model.exportOptions.longEdge == 4096) {
                    model.exportOptions.longEdge = 4096
                    model.saveExportOptions()
                }
                ChoiceChip(title: "2048 px", selected: model.exportOptions.longEdge == 2048) {
                    model.exportOptions.longEdge = 2048
                    model.saveExportOptions()
                }
            }
            .padding(.bottom, 18)

            if let photo = model.currentPhoto {
                HStack(spacing: 6) {
                    Image(systemName: "info.circle")
                        .font(DS.font(9))
                        .foregroundStyle(DS.textQuaternary)
                    Text("\(Int(photo.pixelSize.width)) × \(Int(photo.pixelSize.height)) px · \(photo.name)")
                        .font(DS.label(9))
                        .foregroundStyle(DS.textTertiary)
                        .lineLimit(1)
                }
                .padding(.bottom, 18)
            }

            HStack(spacing: 8) {
                Spacer()
                Button(T("取消", "Cancel")) { dismiss() }
                    .buttonStyle(.plain)
                    .font(DS.font(11, .medium))
                    .foregroundStyle(DS.textSecondary)
                    .padding(.horizontal, 12)
                    .frame(height: 30)
                    .background(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(DS.surface2)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .stroke(DS.hairline, lineWidth: 1)
                    )
                Button {
                    let options = model.exportOptions
                    model.exportOptions = options
                    dismiss()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        model.beginExport()
                    }
                } label: {
                    Text(T("选择保存位置…", "Choose destination…"))
                        .font(DS.font(11, .medium))
                        .foregroundStyle(Color(hex: 0x14120E))
                        .padding(.horizontal, 14)
                        .frame(height: 30)
                        .background(
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill(DS.accent)
                        )
                }
                .buttonStyle(PressableStyle())
                .disabled(model.currentPhoto == nil)
            }
        }
        .padding(22)
        .frame(width: 380)
        .background(DS.surface1)
        .onAppear {
            DispatchQueue.main.async {
                NSApp.keyWindow?.makeFirstResponder(nil)
            }
        }
        .tint(DS.accent)
        .preferredColorScheme(.dark)
        .focusEffectDisabled()
        .id(model.language)
    }
}

struct FieldLabel: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text)
            .font(DS.font(8.5, .medium))
            .tracking(1.2)
            .foregroundStyle(DS.textTertiary)
            .padding(.bottom, 7)
    }
}

struct ChipRow<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        HStack(spacing: 5) {
            content
            Spacer(minLength: 0)
        }
    }
}

struct ChoiceChip: View {
    let title: String
    let selected: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(DS.font(10, selected ? .medium : .regular))
                .foregroundStyle(selected ? DS.accent : (hovering ? DS.textSecondary : DS.textTertiary))
                .padding(.horizontal, 9)
                .frame(height: 26)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(selected ? DS.accent.opacity(0.1) : (hovering ? DS.surface2 : DS.surface1))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(selected ? DS.accent.opacity(0.3) : DS.hairline, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
        .onHover { hovering = $0 }
    }
}
