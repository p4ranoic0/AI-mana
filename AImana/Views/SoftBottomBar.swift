import AImanaCore
import SwiftUI

enum SoftPage { case dashboard, costs }

struct SoftBottomBar: View {
    @Environment(\.colorScheme) private var scheme
    @Binding var page: SoftPage
    let settingsPresented: Bool
    let isRefreshing: Bool
    let refresh: () -> Void
    let settings: () -> Void

    var body: some View {
        HStack(spacing: SoftTheme.Space.sm) {
            tab("Dashboard", symbol: page == .dashboard ? "square.grid.2x2.fill" : "square.grid.2x2",
                tint: SoftTheme.peach, page: .dashboard)
            Spacer(minLength: 0)
            tab("Costs", symbol: "chart.bar.xaxis", tint: SoftTheme.blue, page: .costs)
            Spacer(minLength: 0)
            Button(action: refresh) {
                Group {
                    if isRefreshing { ProgressView().tint(scheme == .dark ? SoftTheme.ink : .white) }
                    else { Image(systemName: "arrow.clockwise")
                            .font(.system(size: 20, weight: .medium))
                            .symbolRenderingMode(.hierarchical)
                            .accessibilityHidden(true) }
                }
                .frame(width: 52, height: 52)
                .foregroundStyle(scheme == .dark ? SoftTheme.ink : .white)
                .background(scheme == .dark ? SoftTheme.cream : SoftTheme.ink, in: Circle())
            }
            .disabled(isRefreshing)
            .accessibilityLabel("Refresh usage")
            Spacer(minLength: 0)
            Button(action: settings) {
                VStack(spacing: SoftTheme.Space.xs) {
                    SoftIconBadge(settingsPresented ? "gearshape.fill" : "gearshape", tint: SoftTheme.pink)
                    Text("Settings").softText(.caption)
                        .foregroundStyle(settingsPresented ? Color.primary : Color.secondary)
                        .lineLimit(1).minimumScaleFactor(0.8)
                }
            }
            .accessibilityLabel("Settings")
        }
        .padding(.horizontal, SoftTheme.Space.lg)
        .padding(.vertical, SoftTheme.Space.sm)
        .frame(maxWidth: .infinity)
        .background(SoftTheme.canvas(scheme).opacity(scheme == .dark ? 0.86 : 0.94), in: Capsule())
        .softSurface(radius: 38)
        .padding(.horizontal, SoftTheme.cardPadding)
        .padding(.top, SoftTheme.Space.sm)
        .padding(.bottom, SoftTheme.Space.sm)
    }

    private func tab(_ title: String, symbol: String, tint: Color, page target: SoftPage) -> some View {
        Button {
            page = target
        } label: {
            VStack(spacing: SoftTheme.Space.xs) {
                SoftIconBadge(symbol, tint: tint)
                Text(AppStrings.text(title))
                    .softText(.caption).fontWeight(page == target ? .semibold : .regular)
                    .foregroundStyle(page == target ? Color.primary : Color.secondary)
                    .lineLimit(1).minimumScaleFactor(0.8)
            }
        }
        .accessibilityAddTraits(page == target ? .isSelected : [])
    }
}
