import AImanaCore
import Charts
import SwiftUI

struct ProviderDetailView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var scheme
    let usage: UsageInfo
    let mode: DisplayMode
    @State private var liveActivityActive = false
    @State private var liveActivityUnavailable = false
    @Environment(\.horizontalSizeClass) private var sizeClass
    /// Width of the scroll view, so a regular-width window only splits into two columns when there is room.
    @State private var containerWidth: CGFloat = 0

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                Group {
                    if isTwoColumn {
                        // iPad / wide windows: where things stand on the left, history and money on the right.
                        HStack(alignment: .top, spacing: SoftTheme.Space.xl) {
                            VStack(alignment: .leading, spacing: SoftTheme.Space.xl) {
                                overview
                                liveActivityButton
                                DailyBudgetSection(usage: usage).id("budget")
                                LimitsAndBalancesSection(usage: usage, mode: mode)
                            }
                            .frame(maxWidth: .infinity, alignment: .topLeading)
                            VStack(alignment: .leading, spacing: SoftTheme.Space.xl) {
                                burndownSection.id("burndown")
                                PatternsSection(usage: usage).id("patterns")
                                costSection.id("cost")
                            }
                            .frame(maxWidth: .infinity, alignment: .topLeading)
                        }
                        .frame(maxWidth: AdaptiveLayout.maxContentWidth)
                        .frame(maxWidth: .infinity)
                    } else {
                        VStack(alignment: .leading, spacing: SoftTheme.Space.xl) {
                            overview
                            liveActivityButton
                            if usage.windows.isEmpty {
                                // Balance-only providers: no lanes to burn down, no history patterns, no local costs.
                                LimitsAndBalancesSection(usage: usage, mode: mode)
                            } else {
                                DailyBudgetSection(usage: usage).id("budget")
                                burndownSection.id("burndown")
                                LimitsAndBalancesSection(usage: usage, mode: mode)
                                PatternsSection(usage: usage).id("patterns")
                                costSection.id("cost")
                            }
                        }
                        // Regular width but too narrow for two columns: a readable centred column.
                        .frame(maxWidth: sizeClass == .regular ? AdaptiveLayout.readableWidth : .infinity)
                        .frame(maxWidth: .infinity)
                    }
                }
                .padding(.horizontal, SoftTheme.cardPadding)
                .padding(.vertical, SoftTheme.Space.xl)
            }
            .hardTopScrollEdge()
            .onGeometryChange(for: CGFloat.self, of: { $0.size.width }) { containerWidth = $0 }
            .onAppear {
                // Debug aid for screenshots: `-detail-scroll-cost` / `-detail-scroll-patterns` jump to that section.
                let args = ProcessInfo.processInfo.arguments
                if args.contains("-detail-scroll-cost") {
                    DispatchQueue.main.async { proxy.scrollTo("cost", anchor: .top) }
                } else if args.contains("-detail-scroll-budget") {
                    DispatchQueue.main.async { proxy.scrollTo("budget", anchor: .top) }
                } else if args.contains("-detail-scroll-burndown") {
                    DispatchQueue.main.async { proxy.scrollTo("burndown", anchor: .top) }
                } else if args.contains("-detail-scroll-patterns") {
                    DispatchQueue.main.async { proxy.scrollTo("patterns", anchor: .top) }
                }
            }
        }
        .background(SoftTheme.canvas(scheme))
        .fontDesign(.rounded)
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                ShareLink(item: UsageSummary.text(for: usage)) {
                    Text("Share").softText(.body)
                }
                .accessibilityLabel("Share usage summary")
            }
        }
        .task {
            // Debug launch arg for screenshots: start the activity without tapping.
            if ProcessInfo.processInfo.arguments.contains("-start-live-activity") {
                _ = await LiveActivityService.shared.startManually(for: usage)
            }
            liveActivityActive = await LiveActivityService.shared.isActive(providerID: usage.providerID)
        }
        .alert("Live Activities unavailable", isPresented: $liveActivityUnavailable) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Enable Live Activities for AImana in iPhone Settings.")
        }
    }

    private var isTwoColumn: Bool {
        sizeClass == .regular && containerWidth >= AdaptiveLayout.twoColumnWidth && !usage.windows.isEmpty
    }

    @ViewBuilder
    private var liveActivityButton: some View {
        // A capability check, not a layout one: iPadOS has no Dynamic Island and does not present Live Activities,
        // so the button could only ever end in the "unavailable" alert there.
        if usage.window(.session)?.resetsAt != nil, UIDevice.current.userInterfaceIdiom != .pad {
            Button {
                Task {
                    if liveActivityActive {
                        await LiveActivityService.shared.end(providerID: usage.providerID)
                        liveActivityActive = false
                    } else {
                        liveActivityActive = await LiveActivityService.shared.startManually(for: usage)
                        liveActivityUnavailable = !liveActivityActive
                    }
                }
            } label: {
                Text(liveActivityActive ? "End Live Activity" : "Show in Dynamic Island")
                    .softText(.body).fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
                    .padding(SoftTheme.Space.lg)
                    .softSurface(tint: SoftTheme.providerTint(usage.providerID))
            }
            .accessibilityHint("Shows this session on the Lock Screen and Dynamic Island")
        }
    }

    private var overview: some View {
        VStack(alignment: .leading, spacing: SoftTheme.Space.md) {
            HStack(alignment: .center, spacing: SoftTheme.Space.md) {
                SoftIconBadge(SoftTheme.providerSymbol(usage.providerID),
                              tint: SoftTheme.providerTint(usage.providerID), size: 28)
                Text(usage.providerName)
                    .softText(.title)
                Spacer()
                if let plan = usage.plan {
                    Text(plan.capitalized).softText(.caption).fontWeight(.semibold)
                        .padding(.horizontal, SoftTheme.Space.sm).padding(.vertical, SoftTheme.Space.xs)
                        .background(SoftTheme.providerTint(usage.providerID).opacity(0.30), in: Capsule())
                }
            }
            if let window = usage.primary {
                let severity = UsageSeverity(remainingPercent: window.remainingPercent)
                HStack(alignment: .firstTextBaseline, spacing: SoftTheme.Space.sm) {
                    Text(UsageFormatter.percentText(mode.percent(for: window)))
                        .softText(.hero)
                        .monospacedDigit()
                        .contentTransition(reduceMotion ? .identity : .numericText())
                        .animation(reduceMotion ? nil : .smooth, value: mode.percent(for: window))
                    Text("\(mode.caption) · \(window.kind.title)")
                        .softText(.body).foregroundStyle(.secondary)
                }
                Text(severity.statusText)
                    .softText(.caption).fontWeight(.semibold)
                    .foregroundStyle(SoftTheme.statusTextColor(severity, scheme: scheme))
            } else if let balance = usage.details.first(where: { $0.kind == .creditBalance }) {
                // Balance-only providers headline their (first) balance instead of a lane.
                VStack(alignment: .leading, spacing: SoftTheme.Space.xs) {
                    Text(balance.title).softText(.body).foregroundStyle(.secondary)
                    Text(balance.summary())
                        .softText(.hero).monospacedDigit()
                        .lineLimit(1).minimumScaleFactor(0.5)
                }
                .accessibilityElement(children: .combine)
                if let caption = balance.caption() {
                    Text(caption)
                        .softText(.caption).fontWeight(.semibold)
                        .foregroundStyle(balance.isExhaustedBalance
                                         ? SoftTheme.statusTextColor(.critical, scheme: scheme) : .secondary)
                }
            }
            Text(AppStrings.updated(usage.lastUpdated, relativeTo: DemoProviders.displayNow()))
                .softText(.caption).foregroundStyle(.secondary)
            if let source = usage.source {
                Text(source.caption)
                    .softText(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(SoftTheme.cardPadding)
        .softSurface(tint: SoftTheme.providerTint(usage.providerID))
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var burndownSection: some View {
        VStack(alignment: .leading, spacing: SoftTheme.Space.lg) {
            Text("Burndown").softText(.headline)
            ForEach([UsageWindow.Kind.session, .weekly], id: \.self) { kind in
                if let window = usage.window(kind) {
                    BurndownWindowView(usage: usage, window: window, mode: mode)
                }
            }
            if usage.window(.session) == nil && usage.window(.weekly) == nil {
                Text("No session or weekly limit reported.")
                    .softText(.body).foregroundStyle(.secondary)
            }
        }
    }

    private var costSection: some View {
        VStack(alignment: .leading, spacing: SoftTheme.Space.lg) {
            Text("Estimated cost").softText(.headline)
            if let report = usage.cost {
                CostReportView(report: report)
            } else {
                Text("No local cost data yet.")
                    .softText(.body).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(SoftTheme.cardPadding)
                    .softSurface()
            }
        }
    }
}

private struct BurndownWindowView: View {
    @Environment(\.colorScheme) private var scheme
    let usage: UsageInfo
    let window: UsageWindow
    let mode: DisplayMode

    private var curve: Burndown? {
        Burndown(providerID: usage.providerID, window: window, history: usage.history,
                 mode: mode, observedAt: usage.lastUpdated)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: SoftTheme.Space.md) {
            HStack(alignment: .center, spacing: SoftTheme.Space.md) {
                Text(window.kind.title).softText(.body).fontWeight(.semibold)
                Spacer()
                Text("\(UsageFormatter.percentText(mode.percent(for: window))) \(mode.caption)")
                    .softText(.headline).monospacedDigit()
                    .foregroundStyle(.primary)
            }
            if let curve, curve.hasEnoughHistory {
                Chart {
                    ForEach(curve.guide) { point in
                        LineMark(x: .value(AppStrings.text("Time"), point.time), y: .value(AppStrings.text("Percent"), point.percent),
                                 series: .value(AppStrings.text("Series"), AppStrings.text("Even pace")))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [2, 4]))
                            .foregroundStyle(scheme == .dark ? SoftTheme.cream.opacity(0.35) : SoftTheme.ink.opacity(0.35))
                    }
                    ForEach(curve.actual) { point in
                        LineMark(x: .value(AppStrings.text("Time"), point.time), y: .value(AppStrings.text("Percent"), point.percent),
                                 series: .value(AppStrings.text("Series"), AppStrings.text("Actual")))
                            .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round))
                            .foregroundStyle(scheme == .dark ? SoftTheme.cream : SoftTheme.ink)
                    }
                    ForEach(curve.projection) { point in
                        LineMark(x: .value(AppStrings.text("Time"), point.time), y: .value(AppStrings.text("Percent"), point.percent),
                                 series: .value(AppStrings.text("Series"), AppStrings.text("Projection")))
                            .lineStyle(StrokeStyle(lineWidth: 2, dash: [6, 4]))
                            .foregroundStyle(scheme == .dark ? SoftTheme.cream.opacity(0.65) : SoftTheme.ink.opacity(0.65))
                    }
                    if let current = curve.current {
                        PointMark(x: .value(AppStrings.text("Time"), current.time), y: .value(AppStrings.text("Percent"), current.percent))
                            .symbolSize(55)
                            .foregroundStyle(scheme == .dark ? SoftTheme.cream : SoftTheme.ink)
                    }
                }
                .chartXScale(domain: curve.start...curve.end)
                .chartYScale(domain: 0...100)
                .chartXAxis {
                    if window.kind == .session {
                        AxisMarks(values: xMarks(for: curve)) {
                            AxisGridLine()
                            AxisValueLabel(format: .dateTime.hour().minute())
                        }
                    } else {
                        AxisMarks(values: xMarks(for: curve)) {
                            AxisGridLine()
                            AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                        }
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading, values: [0, 25, 50, 75, 100]) {
                        AxisGridLine()
                        AxisValueLabel()
                    }
                }
                .frame(height: 190)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(AppStrings.format("%@ quota burndown", window.kind.title))
                .accessibilityValue(chartSummary(curve))
                Text("Solid: recorded · dotted: even pace · dashed: projection")
                    .softText(.caption).foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: SoftTheme.Space.sm) {
                    Text("Collecting data...").softText(.body).fontWeight(.semibold)
                    Text("A reading is recorded each time AImana refreshes, and every few minutes by the relay on your computer.")
                        .softText(.caption).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(SoftTheme.cardPadding)
        .softSurface()
    }

    private func chartSummary(_ curve: Burndown) -> String {
        let current = UsageFormatter.percentText(curve.current?.percent ?? mode.percent(for: window))
        var text = AppStrings.format("%@ %@ now, %d recorded points.", current,
                                     mode.caption, curve.recordedPointCount)
        if let forecast = curve.projection.last {
            text += " " + AppStrings.format("Projected %@ %@ at reset.",
                                             UsageFormatter.percentText(forecast.percent), mode.caption)
        }
        return text
    }

    private func xMarks(for curve: Burndown) -> [Date] {
        [curve.start, curve.start.addingTimeInterval(curve.end.timeIntervalSince(curve.start) / 2), curve.end]
    }
}

struct CostReportView: View {
    @Environment(\.colorScheme) private var scheme
    let report: CostReport

    private var summary: CostOverview { CostOverview(report: report, now: DemoProviders.displayNow()) }

    var body: some View {
        let data = summary
        VStack(alignment: .leading, spacing: SoftTheme.Space.lg) {
            HStack(spacing: SoftTheme.Space.sm) {
                CostTotalTile(title: "Today", total: data.today)
                CostTotalTile(title: "7 days", total: data.week)
                CostTotalTile(title: "30 days", total: data.month)
            }
            if data.month.unpricedTokens > 0 {
                Text(AppStrings.format("%@ tokens have no known price and are excluded from USD totals.",
                                       UsageFormatter.tokenCountText(data.month.unpricedTokens)))
                    .softText(.caption).foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: SoftTheme.Space.md) {
                Text("Daily estimate · 30 days").softText(.body).fontWeight(.semibold)
                Chart(data.days) { day in
                    BarMark(x: .value(AppStrings.text("Day"), day.date, unit: .day),
                            y: .value(AppStrings.text("Estimated USD"), day.usd))
                        .foregroundStyle(scheme == .dark ? SoftTheme.cream.opacity(0.65) : SoftTheme.ink.opacity(0.65))
                }
                .chartXAxis {
                    AxisMarks(values: [4, 14, 24].compactMap { index in
                        data.days.indices.contains(index) ? data.days[index].date : nil
                    }) {
                        AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                    }
                }
                .frame(height: 170)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Daily API-equivalent cost estimate, last 30 days")
                .accessibilityValue(AppStrings.format("%@ total over 30 days; %d days with priced usage",
                                                       UsageFormatter.usdText(data.month.usd),
                                                       data.days.filter { $0.usd > 0 }.count))
            }
            if !data.topModels.isEmpty {
                VStack(alignment: .leading, spacing: SoftTheme.Space.md) {
                    Text("Top models · 30 days").softText(.body).fontWeight(.semibold)
                    ForEach(data.topModels.prefix(5)) { model in
                        HStack(alignment: .top, spacing: SoftTheme.Space.md) {
                            VStack(alignment: .leading, spacing: SoftTheme.Space.xs) {
                                Text(verbatim: UsageFormatter.modelName(model.name)).softText(.body).fontWeight(.medium).lineLimit(2)
                                Text(AppStrings.format("%@ tokens", UsageFormatter.tokenCountText(model.tokens.total)))
                                    .softText(.caption).foregroundStyle(.secondary)
                            }
                            Spacer(minLength: SoftTheme.Space.xs)
                            Text(model.hasPrice ? UsageFormatter.usdText(model.usd) : AppStrings.text("Unpriced"))
                                .softText(.body).fontWeight(.semibold).monospacedDigit()
                            if model.unpricedTokens > 0 {
                                Text("Unpriced tokens").softText(.caption).foregroundStyle(.secondary)
                            }
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
            }
            Text("API-equivalent estimate from logs on your computer; not your subscription bill")
                .softText(.caption).foregroundStyle(.secondary)
        }
        .padding(SoftTheme.cardPadding)
        .softSurface()
    }
}

private struct CostTotalTile: View {
    let title: String
    let total: CostTotal

    var body: some View {
        VStack(alignment: .leading, spacing: SoftTheme.Space.xs) {
            Text(AppStrings.text(title)).softText(.caption).foregroundStyle(.secondary)
            Text(UsageFormatter.usdText(total.usd))
                .softText(.body).fontWeight(.bold)
                .monospacedDigit().minimumScaleFactor(0.7).lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(SoftTheme.Space.md)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: SoftTheme.innerRadius, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(AppStrings.format("%@: %@ estimated", AppStrings.text(title),
                                               UsageFormatter.usdText(total.usd)))
    }
}

private struct CostDayBar: Identifiable {
    let day: String
    let date: Date
    let usd: Double
    var id: String { day }
}

private struct ModelTotal: Identifiable {
    let name: String
    var tokens = TokenUsage()
    var usd = 0.0
    var hasPrice = false
    var unpricedTokens = 0
    var id: String { name }
}

private struct CostOverview {
    let today: CostTotal
    let week: CostTotal
    let month: CostTotal
    let days: [CostDayBar]
    let topModels: [ModelTotal]

    init(report: CostReport, now: Date) {
        let endDay = UsageFormatter.localDayString(for: now)
        today = report.total(lastDays: 1, endingOn: endDay)
        week = report.total(lastDays: 7, endingOn: endDay)
        month = report.total(lastDays: 30, endingOn: endDay)

        let calendar = Calendar.current
        let todayStart = calendar.startOfDay(for: now)
        let byDay = report.days.reduce(into: [String: DailyCost]()) { result, day in
            result[day.day] = day
        }
        days = (0..<30).reversed().compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: -offset, to: todayStart) else { return nil }
            let day = UsageFormatter.localDayString(for: date)
            return CostDayBar(day: day, date: date, usd: byDay[day]?.usd ?? 0)
        }

        let included = Set(days.map(\.day))
        var totals: [String: ModelTotal] = [:]
        for day in report.days where included.contains(day.day) {
            for item in day.models {
                var total = totals[item.model] ?? ModelTotal(name: item.model)
                total.tokens = total.tokens + item.tokens
                if let usd = item.usd {
                    total.usd += usd
                    total.hasPrice = true
                } else {
                    total.unpricedTokens += item.tokens.total
                }
                totals[item.model] = total
            }
        }
        topModels = totals.values.sorted { $0.usd == $1.usd ? $0.tokens.total > $1.tokens.total : $0.usd > $1.usd }
    }
}


// MARK: - Daily budget

/// For each multi-day lane: how much can be spent per day from now on to land at 100 % exactly at reset.
private struct DailyBudgetSection: View {
    let usage: UsageInfo

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            let rows = usage.windows.compactMap { window in
                DailyBudget(window: window, history: usage.history, providerID: usage.providerID,
                            now: DemoProviders.displayNow(context.date),
                            calendar: DemoProviders.displayCalendar).map { (window, $0) }
            }
            if !rows.isEmpty {
                VStack(alignment: .leading, spacing: SoftTheme.Space.lg) {
                    Text("Daily budget").softText(.headline)
                    VStack(alignment: .leading, spacing: SoftTheme.Space.lg) {
                        ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                            if index > 0 { Divider() }
                            DailyBudgetRow(window: row.0, budget: row.1, now: DemoProviders.displayNow(context.date))
                        }
                        Text("Spend about this much per day and you reach 100% right as the limit resets.")
                            .softText(.caption).foregroundStyle(.secondary)
                    }
                    .padding(SoftTheme.cardPadding)
                    .softSurface()
                }
            }
        }
    }
}

private struct DailyBudgetRow: View {
    @Environment(\.colorScheme) private var scheme
    let window: UsageWindow
    let budget: DailyBudget
    let now: Date

    var body: some View {
        VStack(alignment: .leading, spacing: SoftTheme.Space.sm) {
            HStack(alignment: .firstTextBaseline, spacing: SoftTheme.Space.sm) {
                Text(window.kind.title).softText(.body).fontWeight(.semibold)
                Spacer(minLength: SoftTheme.Space.xs)
                Text(budget.headline()).softText(.headline).monospacedDigit()
            }
            Text(budget.caption(now: now)).softText(.caption).foregroundStyle(.secondary)
            if let fraction = budget.todayFraction, let today = budget.todayText() {
                TodayBar(fraction: fraction)
                Text(today)
                    .softText(.caption).monospacedDigit()
                    .foregroundStyle(fraction > 1 ? SoftTheme.statusTextColor(.warning, scheme: scheme) : .secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// Thin neutral bar: share of today's allowance already spent. Over budget simply fills up.
private struct TodayBar: View {
    @Environment(\.colorScheme) private var scheme
    let fraction: Double

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(scheme == .dark ? Color.white.opacity(0.12) : Color.black.opacity(0.07))
                Capsule().fill(scheme == .dark ? SoftTheme.cream.opacity(0.7) : SoftTheme.ink.opacity(0.6))
                    .frame(width: proxy.size.width * min(1, max(0, fraction)))
            }
        }
        .frame(height: 6)
        .accessibilityHidden(true)
    }
}

// MARK: - Other limits and balances

/// Model-scoped lanes and paid extras (extra usage, credits), which have no burndown of their own.
private struct LimitsAndBalancesSection: View {
    let usage: UsageInfo
    let mode: DisplayMode

    private var extraLanes: [UsageWindow] {
        usage.windows.filter { $0.kind != .session && $0.kind != .weekly }
    }

    var body: some View {
        if !extraLanes.isEmpty || !usage.details.isEmpty {
            TimelineView(.periodic(from: .now, by: 60)) { context in
                VStack(alignment: .leading, spacing: SoftTheme.Space.lg) {
                    Text(usage.windows.isEmpty ? LocalizedStringKey("Balances") : LocalizedStringKey("Other limits")).softText(.headline)
                    VStack(alignment: .leading, spacing: SoftTheme.Space.lg) {
                        ForEach(Array(extraLanes.enumerated()), id: \.offset) { index, window in
                            if index > 0 { Divider() }
                            VStack(alignment: .leading, spacing: SoftTheme.Space.sm) {
                                HStack(alignment: .firstTextBaseline, spacing: SoftTheme.Space.sm) {
                                    Text(window.kind.title).softText(.body).fontWeight(.semibold)
                                    Spacer(minLength: SoftTheme.Space.xs)
                                    Text("\(UsageFormatter.percentText(mode.percent(for: window))) \(mode.caption)")
                                        .softText(.body).fontWeight(.semibold).monospacedDigit()
                                }
                                UsageBar(window: window, mode: mode, pace: UsagePace(window: window, now: DemoProviders.displayNow(context.date)))
                                if let reset = UsageFormatter.resetText(for: window.resetsAt, now: DemoProviders.displayNow(context.date)) {
                                    Text(reset).softText(.caption).foregroundStyle(.secondary)
                                }
                            }
                            .accessibilityElement(children: .combine)
                        }
                        if !extraLanes.isEmpty && !usage.details.isEmpty { Divider() }
                        ForEach(usage.details) { detail in
                            DetailRow(detail: detail, now: DemoProviders.displayNow(context.date))
                        }
                    }
                    .padding(SoftTheme.cardPadding)
                    .softSurface()
                }
            }
        }
    }
}

private struct DetailRow: View {
    let detail: UsageDetail
    let now: Date

    var body: some View {
        VStack(alignment: .leading, spacing: SoftTheme.Space.sm) {
            HStack(alignment: .firstTextBaseline, spacing: SoftTheme.Space.sm) {
                Text(detail.title).softText(.body).fontWeight(.semibold)
                Spacer(minLength: SoftTheme.Space.xs)
                Text(detail.summary()).softText(.body).monospacedDigit()
                    .multilineTextAlignment(.trailing)
            }
            if detail.kind == .extraUsage || detail.kind == .cloudCredits, let fraction = detail.usedFraction {
                TodayBar(fraction: fraction)
            }
            if detail.kind == .extraUsage {
                Text("Paid usage beyond your plan, up to your monthly limit.")
                    .softText(.caption).foregroundStyle(.secondary)
            } else if let caption = detail.caption(now: now) {
                Text(caption).softText(.caption).foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Patterns

/// Calm summary of recorded history: exhausted sessions this week and the hours usage usually grows.
private struct PatternsSection: View {
    @Environment(\.colorScheme) private var scheme
    let usage: UsageInfo

    private var insights: UsageInsights {
        UsageInsights(providerID: usage.providerID, history: usage.history, weekly: usage.window(.weekly),
                      now: usage.lastUpdated)
    }

    var body: some View {
        let data = insights
        VStack(alignment: .leading, spacing: SoftTheme.Space.lg) {
            Text("Patterns").softText(.headline)
            VStack(alignment: .leading, spacing: SoftTheme.Space.lg) {
                if !data.hasSessionHistory && !data.hasHourlyPattern {
                    Text("Patterns appear after a few days of readings.")
                        .softText(.body).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    if data.hasSessionHistory {
                        HStack(alignment: .firstTextBaseline, spacing: SoftTheme.Space.sm) {
                            Text("Session limit reached").softText(.body).fontWeight(.semibold)
                            Spacer(minLength: SoftTheme.Space.xs)
                            Text(exhaustionText(data.sessionExhaustions)).softText(.body).monospacedDigit()
                        }
                        .accessibilityElement(children: .combine)
                    }
                    if data.hasHourlyPattern {
                        if data.hasSessionHistory { Divider() }
                        peakHours(data)
                    }
                    if let since = data.coverageStart {
                        Text(AppStrings.format("Based on readings since %@",
                                               since.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))))
                            .softText(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            .padding(SoftTheme.cardPadding)
            .softSurface()
        }
    }

    private func exhaustionText(_ count: Int) -> String {
        switch count {
        case 0: AppStrings.text("Not this week")
        case 1: AppStrings.text("Once this week")
        default: AppStrings.format("%d times this week", count)
        }
    }

    @ViewBuilder private func peakHours(_ data: UsageInsights) -> some View {
        let peaks = data.peakHours(limit: 3)
        VStack(alignment: .leading, spacing: SoftTheme.Space.md) {
            HStack(alignment: .firstTextBaseline, spacing: SoftTheme.Space.sm) {
                Text("Busiest hours").softText(.body).fontWeight(.semibold)
                Spacer(minLength: SoftTheme.Space.xs)
                Text(peaks.map(hourText).joined(separator: ", ")).softText(.body).monospacedDigit()
            }
            Chart(Array(data.hourlyIncrease.enumerated()), id: \.offset) { hour, value in
                BarMark(x: .value(AppStrings.text("Hour"), hour), y: .value(AppStrings.text("Percent"), value))
                    .foregroundStyle(barColor(highlighted: peaks.contains(hour)))
                    .cornerRadius(2)
            }
            .chartXScale(domain: -0.5...23.5)
            .chartXAxis {
                AxisMarks(values: [0, 6, 12, 18]) { value in
                    AxisValueLabel {
                        if let hour = value.as(Int.self) { Text(hourText(hour)) }
                    }
                }
            }
            .chartYAxis(.hidden)
            .frame(height: 110)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Usage by hour of day, last 7 days")
            .accessibilityValue(AppStrings.format("Busiest: %@", peaks.map(hourText).joined(separator: ", ")))
            Text("Growth of weekly usage by hour of day, last 7 days")
                .softText(.caption).foregroundStyle(.secondary)
        }
    }

    private func barColor(highlighted: Bool) -> Color {
        let base = scheme == .dark ? SoftTheme.cream : SoftTheme.ink
        return base.opacity(highlighted ? 0.75 : 0.25)
    }

    private func hourText(_ hour: Int) -> String {
        let date = Calendar.current.date(bySettingHour: hour, minute: 0, second: 0, of: Date()) ?? Date()
        return date.formatted(.dateTime.hour())
    }
}
