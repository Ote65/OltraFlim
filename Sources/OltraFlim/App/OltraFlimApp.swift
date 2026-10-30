import SwiftUI

@main
struct OltraFlimApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var model = AppModel.shared

    var body: some Scene {
        WindowGroup("OltraFlim", id: "main") {
            ContentView()
                .environment(model)
                .frame(minWidth: 1180, minHeight: 740)
                .configureWindow()
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentMinSize)
        .defaultSize(width: 1520, height: 940)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button(model.localized("导入照片…", "Import Photos…")) {
                    model.chooseFiles()
                }
                .keyboardShortcut("o", modifiers: .command)
                Button(model.localized("导入文件夹…", "Import Folder…")) {
                    model.chooseFolder()
                }
                .keyboardShortcut("o", modifiers: [.command, .shift])
                Button(model.localized("导入 LUT…", "Import LUT…")) {
                    model.chooseLUTFiles()
                }
                .keyboardShortcut("l", modifiers: [.command, .option])
                Button(model.localized("导出…", "Export…")) {
                    model.exportPresented = true
                }
                .keyboardShortcut("e", modifiers: .command)
                .disabled(model.currentPhoto == nil)
            }

            CommandMenu(model.localized("胶片", "Film")) {
                Button(model.localized("下一张照片", "Next Photograph")) { model.nextPhoto() }
                    .keyboardShortcut("]", modifiers: .command)
                    .disabled(model.photos.count < 2)
                Button(model.localized("上一张照片", "Previous Photograph")) { model.previousPhoto() }
                    .keyboardShortcut("[", modifiers: .command)
                    .disabled(model.photos.count < 2)
                Divider()
                Button(model.localized("自动影调", "Auto Tone")) { model.autoTone() }
                    .keyboardShortcut("a", modifiers: [.command, .shift])
                    .disabled(model.currentPhoto == nil)
                Button(model.localized("重置调整", "Reset Adjustments")) { model.resetAdjustments() }
                    .keyboardShortcut("r", modifiers: [.command, .option])
                    .disabled(model.currentPhoto == nil)
                Button(model.localized("重置胶片与调整", "Reset Film & Adjustments")) { model.resetAll() }
                    .disabled(model.currentPhoto == nil)
                Divider()
                Button(model.showOriginal
                       ? model.localized("关闭原图对比", "Close Compare")
                       : model.localized("原图对比", "Compare Original")) {
                    model.toggleShowOriginal()
                }
                .keyboardShortcut("b", modifiers: [.option])
                .disabled(model.currentPhoto == nil)
                Divider()
                Button(model.localized("智能通透分析", "Analyze Transparency")) {
                    model.analyzeTone()
                }
                .keyboardShortcut("t", modifiers: [.command, .shift])
                .disabled(model.currentPhoto == nil)
            }

            CommandGroup(after: .sidebar) {
                Button(model.localized("在访达中显示照片", "Reveal Photograph in Finder")) {
                    model.revealCurrentPhoto()
                }
                .disabled(model.currentPhoto == nil)
            }
        }

        Settings {
            SettingsView()
                .environment(model)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        NSApp.appearance = NSAppearance(named: .darkAqua)
    }

    func application(_ sender: NSApplication, openFiles filenames: [String]) {
        let urls = filenames.map { URL(fileURLWithPath: $0) }
        AppModel.shared.importURLs(urls)
        sender.reply(toOpenOrPrint: .success)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func applicationWillTerminate(_ notification: Notification) {
        AppModel.shared.saveEditsNow()
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        true
    }
}
