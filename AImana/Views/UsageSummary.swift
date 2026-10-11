import AImanaCore
import Foundation

enum UsageSummary {
    static func text(for usage: UsageInfo) -> String {
        var lines = [usage.providerName]
        for window in usage.windows {
            var line = AppStrings.format("%@: %@ used, %@ remaining", window.kind.title,
                                         UsageFormatter.percentText(window.displayUsedPercent),
                                         UsageFormatter.percentText(window.remainingPercent))
            if let reset = window.resetsAt {
                line += AppStrings.format("; resets %@", reset.formatted(date: .abbreviated, time: .shortened))
            }
            lines.append(line)
            if let budget = DailyBudget(window: window, history: usage.history, providerID: usage.providerID),
               budget.status == .spread || budget.status == .lastDay {
                var text = "  " + AppStrings.format("Daily budget: %@", budget.headline())
                if let today = budget.todayText() { text += " (\(today))" }
                lines.append(text)
            }
        }
        for detail in usage.details {
            lines.append("\(detail.title): \(detail.summary())")
        }
        if let cost = usage.cost {
            let day = UsageFormatter.localDayString(for: .now)
            lines.append(AppStrings.format("30-day API-equivalent estimate: %@",
                                           UsageFormatter.usdText(cost.total(lastDays: 30, endingOn: day).usd)))
        }
        return lines.joined(separator: "\n")
    }
}
