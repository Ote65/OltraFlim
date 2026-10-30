import SwiftUI

struct ContentView: View {
    @Environment(AppModel.self) private var model
    @State private var showExportSheet = false

    var body: some View {
        ZStack {
            DS.surface0
            VStack(spacing: 0) {
                TopBar()
                Rectangle().fill(DS.hairline).frame(height: 1)
                if model.screen == .library {
                    HomeLibraryView()
                        .transition(.opacity.combined(with: .scale(scale: 0.994)))
                } else {
                    editorBody
                        .transition(.opacity.combined(with: .scale(scale: 0.994)))
                }
            }
            .background(DS.surface0)
        }
        .ignoresSafeArea(.container, edges: .top)
        .overlay(alignment: .top) {
            if let toast = model.toast {
                ToastView(toast: toast)
                    .padding(.top, 72)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .allowsHitTesting(false)
            }
        }
        .overlay {
            if model.isExporting {
                ExportProgressOverlay()
                    .transition(.opacity)
            }
        }
        .overlay(alignment: .topLeading) {
            if let error = model.startupError, model.catalog.stocks.isEmpty {
                StartupErrorBanner(text: error)
                    .padding(.top, 72)
                    .padding(.leading, 300)
            }
        }
        .animation(DS.easeOutExpo, value: model.toast?.id)
        .animation(DS.easeOutExpo, value: model.isExporting)
        .animation(DS.snappy, value: model.screen)
        .dropDestination(for: URL.self) { urls, _ in
            model.importDroppedURLs(urls)
            return true
        } isTargeted: { targeted in
            withAnimation(DS.easeQuick) { model.isDropTarget = targeted }
        }
        .overlay {
            if model.isDropTarget {
                DropOverlay()
                    .transition(.opacity)
                    .allowsHitTesting(false)
            }
        }
        .tint(DS.accent)
        .preferredColorScheme(.dark)
        .focusEffectDisabled()
        .id("\(model.language.rawValue)-\(model.textScale)")
        .sheet(isPresented: $showExportSheet) {
            ExportSheet()
                .environment(model)
        }
        .onChange(of: model.exportPresented) { _, newValue in
            if newValue {
                showExportSheet = true
                model.exportPresented = false
            }
        }
        .alert("OltraFlim", isPresented: Binding(
            get: { model.alertMessage != nil },
            set: { if !$0 { model.alertMessage = nil } }
        )) {
            Button(T("好", "OK"), role: .cancel) { model.alertMessage = nil }
        } message: {
            Text(model.alertMessage ?? "")
        }
    }
}

private extension ContentView {
    var editorBody: some View {
        HStack(spacing: 0) {
            FilmBrowserView()
                .frame(width: 286)
            Rectangle().fill(DS.hairline).frame(width: 1)
            VStack(spacing: 0) {
                CanvasView()
                if !model.photos.isEmpty {
                    Rectangle().fill(DS.hairline).frame(height: 1)
                    FilmstripView()
                        .frame(height: 88)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            Rectangle().fill(DS.hairline).frame(width: 1)
            InspectorView()
                .frame(width: 342)
        }
    }
}

// MARK: - Toast

struct ToastView: View {
    let toast: ToastMessage

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: toast.symbol)
                .font(DS.font(11, .semibold))
                .foregroundStyle(DS.accent)
                .frame(width: 18, height: 18)
                .background(Circle().fill(DS.accent.opacity(0.12)))
            VStack(alignment: .leading, spacing: 1) {
                Text(toast.text)
                    .font(DS.font(11.5, .medium))
                    .foregroundStyle(DS.textPrimary)
                if let detail = toast.detail {
                    Text(detail)
                        .font(DS.label(10))
                        .foregroundStyle(DS.textSecondary)
                }
            }
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(DS.surface3.opacity(0.94))
                .shadow(color: .black.opacity(0.5), radius: 20, y: 10)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(DS.hairlineStrong, lineWidth: 1)
        )
    }
}

// MARK: - Drop / Error / Export overlays

struct DropOverlay: View {
    var body: some View {
        ZStack {
            DS.surface0.opacity(0.86)
            VStack(spacing: 12) {
                Image(systemName: "photo.on.rectangle.angled")
                    .font(DS.font(30, .light))
                    .foregroundStyle(DS.accent)
                Text(T("松开以加入照片库", "Drop to add to the library"))
                    .font(DS.font(15, .medium))
                    .foregroundStyle(DS.textPrimary)
                Text(T("JPEG · PNG · TIFF · HEIC · RAW · DNG · 文件夹",
                       "JPEG · PNG · TIFF · HEIC · RAW · DNG · Folders"))
                    .font(DS.label(10))
                    .foregroundStyle(DS.textSecondary)
                    .tracking(0.8)
            }
            .padding(42)
            .background(
                RoundedRectangle(cornerRadius: DS.rLarge, style: .continuous)
                    .fill(DS.surface1)
            )
            .overlay(
                RoundedRectangle(cornerRadius: DS.rLarge, style: .continuous)
                    .stroke(DS.accent.opacity(0.5), lineWidth: 1)
            )
        }
    }
}

struct ExportProgressOverlay: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ZStack {
            DS.surface0.opacity(0.55)
            HStack(spacing: 14) {
                ProgressView()
                    .controlSize(.small)
                    .tint(DS.accent)
                VStack(alignment: .leading, spacing: 3) {
                    Text(T("正在显影", "Developing"))
                        .font(DS.font(12, .medium))
                        .foregroundStyle(DS.textPrimary)
                    Text(model.exportStatus)
                        .font(DS.label(10))
                        .foregroundStyle(DS.textSecondary)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .background(
                RoundedRectangle(cornerRadius: DS.rMedium, style: .continuous)
                    .fill(DS.surface3)
                    .shadow(color: .black.opacity(0.55), radius: 28, y: 14)
            )
            .overlay(
                RoundedRectangle(cornerRadius: DS.rMedium, style: .continuous)
                    .stroke(DS.hairlineStrong, lineWidth: 1)
            )
        }
    }
}

struct StartupErrorBanner: View {
    let text: String

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: "exclamationmark.triangle")
                .font(DS.font(11, .medium))
                .foregroundStyle(DS.danger)
            Text(text)
                .font(DS.label(11))
                .foregroundStyle(DS.textPrimary)
                .lineLimit(2)
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(DS.surface3)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .stroke(DS.danger.opacity(0.35), lineWidth: 1)
        )
    }
}
