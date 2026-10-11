import AppIntents
import SwiftUI
import WidgetKit

/// A quiet refresh control for the medium and large widgets: a small glyph in a muted colour, not a call to action.
/// iOS reloads the widget once the intent finishes.
struct WidgetRefreshButton: View {
    var body: some View {
        Button(intent: RefreshUsageIntent()) {
            Image(systemName: "arrow.clockwise")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.tertiary)
                .frame(width: 26, height: 26)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(WidgetStrings.text("Refresh usage")))
    }
}
