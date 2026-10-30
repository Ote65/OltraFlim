import SwiftUI
import AppKit

struct TopBar: View {
    @Environment(AppModel.self) private var model
    @State private var dragStartMouse: CGPoint?
    @State private var dragStartOrigin: CGPoint?

    var body: some View {
        HStack(spacing: 10) {
            if model.screen == .editor {
                Button {
                    model.showLibrary()
                } label: {
                    CompactBarButton(title: T("照片库", "Library"), symbol: "chevron.left", accent: false)
                }
                .buttonStyle(PressableStyle())
                .help(T("返回照片库", "Back to library"))
            } else {
                if !model.folderTrail.isEmpty {
                    Button {
                        model.goUpFolder()
                    } label: {
                        CompactBarButton(
                            title: model.libraryParentTitle,
                            symbol: "chevron.left",
                            accent: false
                        )
                    }
                    .buttonStyle(PressableStyle())
                    .help(T("返回上一级", "Back one level"))

                    Rectangle()
                        .fill(DS.hairlineStrong)
                        .frame(width: 1, height: 16)
                        .padding(.horizontal, 2)
                }
                libraryIdentity
            }
            Spacer(minLength: 16)
            logo
        }
        .padding(.leading, 84)
        .padding(.trailing, 16)
        .frame(height: 46)
        .background(DS.surface0)
        .contentShape(Rectangle())
        .simultaneousGesture(windowDragGesture)
        .overlay(alignment: .topLeading) {
            WindowTrafficLights()
                .padding(.leading, 20)
                .frame(height: 46)
        }
        .overlay(alignment: .bottom) {
            libraryProgress
                .allowsHitTesting(false)
        }
    }

    /// Dragging the title strip moves the window. It is attached only here so
    /// the canvas keeps its own drag-to-pan gesture. Tracking the screen mouse
    /// position keeps the window 1:1 under the cursor instead of drifting when
    /// the window itself moves during a SwiftUI gesture.
    private var windowDragGesture: some Gesture {
        DragGesture(minimumDistance: 3)
            .onChanged { _ in
                guard let window = NSApp.mainWindow ?? NSApp.keyWindow else { return }
                let mouse = NSEvent.mouseLocation
                if dragStartMouse == nil {
                    dragStartMouse = mouse
                    dragStartOrigin = window.frame.origin
                }
                guard let startMouse = dragStartMouse, let startOrigin = dragStartOrigin else { return }
                window.setFrameOrigin(NSPoint(
                    x: startOrigin.x + mouse.x - startMouse.x,
                    y: startOrigin.y + mouse.y - startMouse.y
                ))
            }
            .onEnded { _ in
                dragStartMouse = nil
                dragStartOrigin = nil
            }
    }

    private var libraryIdentity: some View {
        HStack(spacing: 8) {
            Text(model.libraryTitle)
                .font(DS.font(11, .medium))
                .tracking(0.2)
                .foregroundStyle(DS.textPrimary)
                .lineLimit(1)
            Text(model.libraryStatusText)
                .font(DS.mono(9))
                .foregroundStyle(DS.textTertiary)
                .lineLimit(1)
        }
        .lineLimit(1)
    }

    private var logo: some View {
        HStack(spacing: 6) {
            if let mark = AppLogo.mark {
                Image(nsImage: mark)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 17, height: 17)
            }
            Text("OLTRAFLIM")
                .font(DS.font(9, .semibold))
                .tracking(1.5)
                .foregroundStyle(DS.textSecondary.opacity(0.72))
        }
        .help("OltraFlim")
    }

    @ViewBuilder
    private var libraryProgress: some View {
        if case .loading(let progress, _) = model.libraryState {
            GeometryReader { proxy in
                Rectangle()
                    .fill(DS.accent.opacity(0.7))
                    .frame(width: max(2, proxy.size.width * progress), height: 1.5)
            }
            .frame(height: 1.5)
        } else {
            Rectangle().fill(DS.hairline).frame(height: 1)
        }
    }
}

struct CompactBarButton: View {
    let title: String
    let symbol: String
    let accent: Bool
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: symbol)
                .font(DS.font(9, .semibold))
            Text(title)
                .font(DS.font(10, .medium))
        }
        .foregroundStyle(accent ? Color(hex: 0x14120E) : DS.textPrimary)
        .padding(.horizontal, 9)
        .frame(height: 26)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(accent ? (hovering ? DS.accentStrong : DS.accent) : (hovering ? DS.surface2 : DS.surface1))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(accent ? .clear : DS.hairline, lineWidth: 1)
        )
        .animation(DS.easeQuick, value: hovering)
        .onHover { hovering = $0 }
    }
}


struct SettingsGear: View {
    @State private var hovering = false

    var body: some View {
        Image(systemName: "gearshape")
            .font(DS.font(10, .medium))
            .foregroundStyle(hovering ? DS.accent : DS.textTertiary)
            .frame(width: 26, height: 26)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(hovering ? DS.surface2 : DS.surface1)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .stroke(DS.hairline, lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            .onTapGesture {
                if !NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil) {
                    NSApp.sendAction(Selector(("showPreferencesWindow:")), to: nil, from: nil)
                }
            }
            .onHover { hovering = $0 }
            .help(T("设置", "Settings"))
            .animation(DS.easeQuick, value: hovering)
    }
}

/// Native traffic lights are hidden by `WindowConfigurator`; these are drawn
/// inside the 46 pt status strip so they sit exactly on its vertical centre.
struct WindowTrafficLights: View {
    @State private var hovering = false
    @State private var active = NSApp.isActive

    private var window: NSWindow? {
        NSApp.mainWindow ?? NSApp.keyWindow ?? NSApp.windows.first(where: { $0.isVisible && $0.canBecomeMain })
    }

    var body: some View {
        HStack(spacing: 8) {
            light(color: Color(hex: 0xE05A4C), symbol: "xmark", help: T("关闭", "Close")) {
                window?.performClose(nil)
            }
            light(color: Color(hex: 0xE0B445), symbol: "minus", help: T("最小化", "Minimize")) {
                window?.miniaturize(nil)
            }
            light(color: Color(hex: 0x66BE63), symbol: "plus", help: T("全屏", "Full screen")) {
                window?.toggleFullScreen(nil)
            }
        }
        .onHover { value in
            withAnimation(DS.easeQuick) { hovering = value }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            active = true
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)) { _ in
            active = false
        }
    }

    private func light(
        color: Color,
        symbol: String,
        help: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(color.opacity(active ? 1 : 0.42))
                    .overlay(
                        Circle().stroke(.black.opacity(0.18), lineWidth: 0.5)
                    )
                if hovering && active {
                    Image(systemName: symbol)
                        .font(DS.font(6.5, .bold))
                        .foregroundStyle(.black.opacity(0.62))
                }
            }
            .frame(width: 12, height: 12)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(help))
        .help(help)
    }
}

