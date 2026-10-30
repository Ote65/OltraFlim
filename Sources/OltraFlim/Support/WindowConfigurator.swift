import SwiftUI
import AppKit

/// Applies the dark, chrome-less window treatment. SwiftUI has no API for
/// titlebar transparency, so this stays a deliberately narrow AppKit bridge.
struct WindowConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.backgroundColor = NSColor(hex: 0x0B0B0B)
            window.isOpaque = true
            // Only the draggable title strip moves the window; dragging a
            // photograph on the canvas must pan the image, not the window.
            window.isMovableByWindowBackground = false
            window.styleMask.insert(.fullSizeContentView)
            window.minSize = NSSize(width: 1180, height: 740)
            window.appearance = NSAppearance(named: .darkAqua)
            // The traffic lights are drawn inside the 46 pt status strip so
            // they can be optically centred there. Hide the system copies.
            window.standardWindowButton(.closeButton)?.isHidden = true
            window.standardWindowButton(.miniaturizeButton)?.isHidden = true
            window.standardWindowButton(.zoomButton)?.isHidden = true
            if let content = window.contentView {
                content.wantsLayer = true
                content.layer?.backgroundColor = NSColor(hex: 0x0B0B0B).cgColor
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                window.makeFirstResponder(nil)
                // Re-apply after SwiftUI finishes its scene setup; some builds
                // recreate the standard buttons during the first layout pass.
                window.standardWindowButton(.closeButton)?.isHidden = true
                window.standardWindowButton(.miniaturizeButton)?.isHidden = true
                window.standardWindowButton(.zoomButton)?.isHidden = true
            }
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}
