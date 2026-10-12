import AImanaCore
import AppKit
import SwiftUI

@main
struct AImanaMacApp: App {
    @State private var controller = RelayController()

    var body: some Scene {
        MenuBarExtra {
            MenuView(controller: controller)
        } label: {
            MenuBarLabel(controller: controller)
        }
        .menuBarExtraStyle(.window)

        Settings {
            if !controller.isDemo { SettingsView(controller: controller) }
        }
    }
}

/// Icon plus the highest current session usage, so the menu bar shows something useful at a glance.
private struct MenuBarLabel: View {
    let controller: RelayController

    var body: some View {
        let used = ["claude", "codex"]
            .compactMap { controller.entry($0)?.usage?.window(.session) }
            .filter { !$0.isOutdated() }
            .map(\.displayUsedPercent)
            .max()
        HStack(spacing: 3) {
            Image(systemName: "gauge.with.dots.needle.33percent")
            if let used { Text(UsageFormatter.percentText(used)) }
        }
        .onAppear {
            if controller.isDemo && ProcessInfo.processInfo.arguments.contains("-open-menu") {
                DemoMenuWindow.show(controller: controller)
            }
        }
    }
}

@MainActor private enum DemoMenuWindow {
    static var window: NSWindow?

    static func show(controller: RelayController) {
        guard window == nil else { return }
        let panel = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 340, height: 620),
                             styleMask: [.titled, .closable], backing: .buffered, defer: false)
        panel.title = "AI·mana"
        panel.contentViewController = NSHostingController(rootView: MenuView(controller: controller))
        panel.center()
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        window = panel
    }
}
