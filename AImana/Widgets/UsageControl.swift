import AImanaCore
import AppIntents
import SwiftUI
import WidgetKit

/// Control Center / Lock Screen control (iOS 18+): the fullest session right now; a tap opens the dashboard, which
/// refreshes as it comes forward.
@available(iOS 18.0, *)
struct UsageControl: ControlWidget {
    static let kind = "\(AppGroup.keychainService).UsageControl"

    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: Self.kind, provider: Provider()) { value in
            ControlWidgetButton(action: OpenAImanaIntent()) {
                Label(value.title, systemImage: "gauge.with.dots.needle.33percent")
            }
        }
        .displayName(LocalizedStringResource("Session usage"))
        .description(LocalizedStringResource("The fullest session across Claude Code and OpenAI Codex. Opens AI·mana."))
    }

    struct Value: Sendable {
        let title: String
    }

    struct Provider: ControlValueProvider {
        var previewValue: Value { Value(title: "Claude Code 22%") }

        func currentValue() async throws -> Value {
            let items = AppGroup.sharedContainerAvailable ? AppGroup.snapshotStore().load() : []
            let mode = DisplayPreferences.mode()
            guard let urgent = UsageAnswer.urgentSession(items: items, mode: mode) else {
                return Value(title: "AI·mana")
            }
            return Value(title: UsageAnswer.compact(urgent.info, window: urgent.window, mode: mode))
        }
    }
}
