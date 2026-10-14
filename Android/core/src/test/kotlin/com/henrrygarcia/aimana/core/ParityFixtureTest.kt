package com.henrrygarcia.aimana.core

import java.io.File
import java.time.Instant
import java.time.ZoneId
import java.time.LocalDate
import kotlinx.serialization.json.*
import org.junit.Assert.*
import org.junit.Test

class ParityFixtureTest {
    @Test fun dashboardDetailAndCostsShareSwiftFixture() {
        val root = Json.parseToJsonElement(File("../../AImana/Fixtures/parity/usage-costs.json").readText()).jsonObject
        val now = Instant.parse(root.getValue("now").jsonPrimitive.content)
        val zone = ZoneId.of(root.getValue("zone").jsonPrimitive.content)
        val inputs = root.getValue("providers").jsonArray.map { it.jsonObject }
        val usages = inputs.map { item ->
            val id = item.getValue("id").jsonPrimitive.content
            UsageInfo(id, item.getValue("name").jsonPrimitive.content,
                item.getValue("windows").jsonArray.map { RelayCodec.json.decodeFromJsonElement<UsageWindow>(it) },
                null, now,
                history = item.getValue("history").jsonArray.map { RelayCodec.json.decodeFromJsonElement<HistorySeries>(it) })
        }
        val dashboard = root.getValue("dashboard").jsonObject
        val summary = OverviewSummary.from(usages, DisplayMode.USED)!!
        assertEquals(dashboard.getValue("lanePercents").jsonArray.map { it.jsonPrimitive.double }, summary.lanes.map { it.displayPercent })
        assertEquals(dashboard.getValue("highlightedProvider").jsonPrimitive.content, summary.highlighted.providerID)
        assertEquals(dashboard.getValue("highlightedKind").jsonPrimitive.content, summary.highlighted.window.kind)
        val fractional = root.getValue("fractional").jsonObject
        val fractionNow = Instant.parse(fractional.getValue("now").jsonPrimitive.content)
        val fractionWindow = RelayCodec.json.decodeFromJsonElement<UsageWindow>(fractional.getValue("window"))
        val fractionExpected = fractional.getValue("expected").jsonObject
        val fractionBudget = DailyBudget.from(fractionWindow, now = fractionNow, zone = zone)!!
        assertEquals(fractionExpected.getValue("perDay").jsonPrimitive.double, fractionBudget.perDayPercent, 0.000001)
        val fractionPace = UsagePace.from(fractionWindow, fractionNow)!!
        assertEquals(fractionExpected.getValue("pace").jsonPrimitive.content, fractionPace.status.name.lowercase())
        assertEquals(fractionExpected.getValue("projectedUsedAtReset").jsonPrimitive.double, fractionPace.projectedUsedAtReset!!, 0.000001)
        val exhaustSeconds = java.time.Duration.between(fractionNow, fractionPace.exhaustsAt).toNanos() / 1_000_000_000.0
        assertEquals(fractionExpected.getValue("exhaustSecondsFromNow").jsonPrimitive.double, exhaustSeconds, 0.0001)
        val fractionCurve = Burndown.from("fractional", fractionWindow, emptyList(), DisplayMode.USED, fractionNow)!!
        assertEquals(fractionExpected.getValue("projectionPercents").jsonArray.map { it.jsonPrimitive.double }, fractionCurve.projection.map { it.percent })
        assertEquals(3, fractionCurve.projection.size)
        val demoExpected = root.getValue("demo").jsonObject
        val demoClaude = DemoData.envelope(now).provider("claude").first!!
        val demoWeekly = demoClaude.window("weekly")!!
        val demoBudget = DailyBudget.from(demoWeekly, demoClaude.history, "claude", now, zone)!!
        assertEquals(demoExpected.getValue("claudeWeeklyUsedToday").jsonPrimitive.double, demoBudget.usedToday!!, 0.000001)
        assertEquals(demoExpected.getValue("claudeWeeklyTodayAllowance").jsonPrimitive.double, demoBudget.todayBudgetPercent!!, 0.000001)
        assertEquals(demoExpected.getValue("claudeWeeklyHistoryPoints").jsonPrimitive.int, demoClaude.history[0].points.size)
        assertEquals(demoExpected.getValue("claudeWeeklyFirstUsed").jsonPrimitive.double, demoClaude.history[0].points.first().used, 0.000001)
        val demoCost = DemoData.envelope(now).costs.first { it.providerID == "claude" }
        val demoDay = LocalDate.parse("2026-10-13")
        for ((period, key) in listOf(1 to "costClaudeTodayUSD", 7 to "costClaudeWeekUSD", 30 to "costClaudeMonthUSD"))
            assertEquals(demoExpected.getValue(key).jsonPrimitive.double, demoCost.total(period, demoDay).usd, 0.000001)
        assertEquals(demoExpected.getValue("claudeWeeklyPerDay").jsonPrimitive.double, demoBudget.perDayPercent, 0.000001)
        val sonnetBudget = DailyBudget.from(demoClaude.window("model:Sonnet")!!, now = now, zone = zone)!!
        assertEquals(demoExpected.getValue("claudeModelPerDay").jsonPrimitive.double, sonnetBudget.perDayPercent, 0.000001)
        val sessionPace = UsagePace.from(demoClaude.window("session")!!, now)!!
        assertEquals(demoExpected.getValue("claudeSessionProjection").jsonPrimitive.double, sessionPace.projectedUsedAtReset!!, 0.000001)
        val demoCodex = DemoData.envelope(now).provider("codex").first!!
        val codexBudget = DailyBudget.from(demoCodex.window("weekly")!!, demoCodex.history, "codex", now, zone)!!
        assertEquals(demoExpected.getValue("codexWeeklyPerDay").jsonPrimitive.double, codexBudget.perDayPercent, 0.000001)
        assertEquals(demoExpected.getValue("codexWeeklyUsedToday").jsonPrimitive.double, codexBudget.usedToday!!, 0.000001)
        assertEquals(demoExpected.getValue("codexWeeklyTodayAllowance").jsonPrimitive.double, codexBudget.todayBudgetPercent!!, 0.000001)
        val codexModelBudget = DailyBudget.from(demoCodex.window("model:GPT-5.3-Codex-Spark")!!, now = now, zone = zone)!!
        assertEquals(demoExpected.getValue("codexModelPerDay").jsonPrimitive.double, codexModelBudget.perDayPercent, 0.000001)
        val codexCost = DemoData.envelope(now).costs.first { it.providerID == "codex" }
        for ((period, key) in listOf(1 to "costCodexTodayUSD", 7 to "costCodexWeekUSD", 30 to "costCodexMonthUSD"))
            assertEquals(demoExpected.getValue(key).jsonPrimitive.double, codexCost.total(period, demoDay).usd, 0.000001)
        for ((usage, input) in usages.zip(inputs)) {
            val expected = input.getValue("expected").jsonObject
            val weekly = usage.window("weekly")!!
            val budget = DailyBudget.from(weekly, usage.history, usage.providerID, now, zone)!!
            assertEquals(expected.getValue("weeklyPerDay").jsonPrimitive.double, budget.perDayPercent, 0.000001)
            assertEquals(expected.getValue("weeklyUsedToday").jsonPrimitive.double, budget.usedToday!!, 0.000001)
            assertEquals(expected.getValue("weeklyTodayAllowance").jsonPrimitive.double, budget.todayBudgetPercent!!, 0.000001)
            val pace = UsagePace.from(weekly, now)!!
            assertEquals(expected.getValue("weeklyPace").jsonPrimitive.content, pace.status.name.lowercase())
            assertEquals(expected.getValue("weeklyProjection").jsonPrimitive.double, pace.projectedUsedAtReset!!, 0.000001)
            val curve = Burndown.from(usage.providerID, weekly, usage.history, DisplayMode.USED, now)!!
            val actual = expected.getValue("weeklyActualPercents").jsonArray.map { it.jsonPrimitive.double }
            assertEquals(actual.size, curve.actual.size)
            actual.zip(curve.actual).forEach { (value, point) -> assertEquals(value, point.percent, 0.000001) }
            assertEquals(expected.getValue("weeklyActualTimes").jsonArray.map { Instant.parse(it.jsonPrimitive.content) }, curve.actual.map { it.time })
            assertEquals(expected.getValue("weeklyProjectionTimes").jsonArray.map { Instant.parse(it.jsonPrimitive.content) }, curve.projection.map { it.time })
            assertEquals(expected.getValue("weeklyGuidePercents").jsonArray.map { it.jsonPrimitive.double }, curve.guide.map { it.percent })
            assertEquals(2, curve.projection.size)
            assertEquals(expected.getValue("weeklyProjection").jsonPrimitive.double.coerceAtMost(100.0), curve.projection.last().percent, 0.000001)
            val report = RelayCodec.json.decodeFromJsonElement<CostReport>(input.getValue("cost"))
            val day = LocalDate.parse("2026-10-13")
            for ((period, prefix) in listOf(1 to "Today", 7 to "Week", 30 to "Month")) {
                val total = report.total(period, day)
                assertEquals(expected.getValue("cost${prefix}USD").jsonPrimitive.double, total.usd, 0.000001)
                assertEquals(expected.getValue("cost${prefix}Tokens").jsonPrimitive.long, total.tokens.total)
            }
        }
    }
}
