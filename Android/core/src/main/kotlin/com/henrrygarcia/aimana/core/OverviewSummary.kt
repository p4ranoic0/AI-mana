package com.henrrygarcia.aimana.core

data class OverviewLane(val providerID: String, val providerName: String, val window: UsageWindow, val displayPercent: Double)
data class OverviewSummary(val lanes: List<OverviewLane>, val highlighted: OverviewLane, val mode: DisplayMode) {
    companion object {
        fun from(usages: List<UsageInfo>, mode: DisplayMode): OverviewSummary? {
            val lanes = usages.take(2).flatMap { usage -> listOfNotNull(usage.window("session"), usage.window("weekly")).map { OverviewLane(usage.providerID, usage.providerName, it, mode.percent(it)) } }
            val highlighted = if (mode == DisplayMode.USED) lanes.maxByOrNull { it.displayPercent } else lanes.minByOrNull { it.displayPercent }
            return highlighted?.let { OverviewSummary(lanes, it, mode) }
        }
    }
}
