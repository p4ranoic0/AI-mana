import AImanaCore
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
            SettingsView(controller: controller)
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
    }
}
