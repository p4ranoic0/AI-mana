import AImanaCore
import SwiftUI

struct CostsView: View {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.horizontalSizeClass) private var sizeClass
    let usages: [UsageInfo]
    let bottomBarHeight: CGFloat

    var body: some View {
        ScrollViewReader { scroll in
            ScrollView {
                VStack(alignment: .leading, spacing: SoftTheme.Space.xl) {
                    VStack(alignment: .leading, spacing: SoftTheme.Space.xs) {
                        Text("Costs").softText(.title)
                        Text("API-equivalent estimates from logs on your computer")
                            .softText(.body).foregroundStyle(.secondary)
                    }
                    if sizeClass == .regular {
                        // iPad / wide windows: provider cost cards side by side.
                        LazyVGrid(columns: AdaptiveLayout.gridColumns(spacing: SoftTheme.Space.xl), alignment: .leading,
                                  spacing: SoftTheme.Space.xl) {
                            ForEach(usages) { costCard($0) }
                        }
                    } else {
                        ForEach(usages) { costCard($0) }
                    }
                    if usages.isEmpty {
                        VStack(alignment: .leading, spacing: SoftTheme.Space.sm) {
                            Text("No usage data").softText(.headline)
                            Text("Connect the relay to see cost estimates.")
                                .softText(.body).foregroundStyle(.secondary)
                        }
                    }
                }
                .frame(maxWidth: sizeClass == .regular ? AdaptiveLayout.maxContentWidth : .infinity)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, SoftTheme.cardPadding)
                .padding(.top, SoftTheme.Space.xl)
                .padding(.bottom, SoftTheme.Space.xl + bottomBarHeight + SoftTheme.Space.lg)
                .id("costs-content")
            }
            .background(SoftTheme.canvas(scheme))
            .fontDesign(.rounded)
            .task {
                guard ProcessInfo.processInfo.arguments.contains("-scroll-bottom") else { return }
                await Task.yield()
                scroll.scrollTo("costs-content", anchor: .bottom)
            }
        }
    }

    private func costCard(_ usage: UsageInfo) -> some View {
        VStack(alignment: .leading, spacing: SoftTheme.Space.md) {
            HStack(spacing: SoftTheme.Space.md) {
                SoftIconBadge(SoftTheme.providerSymbol(usage.providerID),
                              tint: SoftTheme.providerTint(usage.providerID), size: 28)
                Text(usage.providerName)
                    .softText(.headline)
                Spacer()
                if let plan = usage.plan {
                    Text(plan.capitalized)
                        .softText(.caption).fontWeight(.semibold)
                        .padding(.horizontal, SoftTheme.Space.sm)
                        .padding(.vertical, SoftTheme.Space.xs)
                        .background(SoftTheme.providerTint(usage.providerID).opacity(0.35), in: Capsule())
                }
            }
            if let cost = usage.cost {
                CostReportView(report: cost)
            } else {
                Text("No local cost data yet")
                    .softText(.body).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, SoftTheme.Space.lg)
                    .softSurface(tint: SoftTheme.providerTint(usage.providerID))
            }
        }
    }
}
