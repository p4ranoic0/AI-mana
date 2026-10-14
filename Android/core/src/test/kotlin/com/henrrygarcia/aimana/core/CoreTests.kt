package com.henrrygarcia.aimana.core

import java.time.Instant
import java.time.LocalDate
import java.time.ZoneOffset
import org.junit.Assert.*
import org.junit.Test

class CoreTests {
    private val now = Instant.parse("2026-10-04T12:00:00Z")
    private fun session(used: Double, elapsed: Long) = UsageWindow("session", used, 300, now.plusSeconds(18000 - elapsed * 60))
    @Test fun paceComfortableMatchesSwift() {
        val pace = UsagePace.from(session(35.0, 150), now)!!
        assertEquals(UsagePace.Status.COMFORTABLE, pace.status)
        assertEquals(50.0, pace.expectedUsedPercent, 0.001)
        assertEquals(70.0, pace.projectedUsedAtReset!!, 0.001)
    }
    @Test fun paceFastMatchesSwift() {
        val pace = UsagePace.from(session(80.0, 150), now)!!
        assertEquals(UsagePace.Status.FAST, pace.status)
        assertEquals(160.0, pace.projectedUsedAtReset!!, 0.001)
        assertEquals(now.plusSeconds(2250), pace.exhaustsAt)
    }
    @Test fun paceEarlyDepletedAndInvalid() {
        assertEquals(UsagePace.Status.TOO_EARLY, UsagePace.from(session(9.0, 10), now)!!.status)
        assertEquals(UsagePace.Status.DEPLETED, UsagePace.from(session(100.0, 100), now)!!.status)
        assertNull(UsagePace.from(UsageWindow("session", 20.0, null, now.plusSeconds(100)), now))
    }

    @Test fun quotaPresentationMatchesSwiftStatesAndThresholds() {
        assertEquals(QuotaStatus.AVAILABLE, quotaStatus(session(1.0, 1), now, now))
        assertEquals(QuotaStatus.ON_PACE, quotaStatus(session(35.0, 150), now, now))
        assertEquals(QuotaStatus.FAST, quotaStatus(session(80.0, 150), now, now))
        assertEquals(QuotaStatus.DEPLETED, quotaStatus(session(100.0, 100), now, now))
        assertEquals(QuotaStatus.LOW, quotaStatus(session(85.0, 10), now, now))
        assertEquals(QuotaStatus.CRITICAL, quotaStatus(session(95.0, 10), now, now))
        assertEquals(QuotaStatus.STALE, quotaStatus(UsageWindow("session", 35.0, 300, now.minusSeconds(60)), now, now))
    }

    @Test fun localeTokenAndCurrencyFormattingMatchesSwiftThresholds() {
        assertEquals("1.2 M", UsageFormat.tokenCount(1_197_000, java.util.Locale.US))
        assertEquals("1,2 M", UsageFormat.tokenCount(1_197_000, java.util.Locale.GERMANY))
        assertEquals("999", UsageFormat.tokenCount(999, java.util.Locale.US))
        assertEquals("$1,000", UsageFormat.moneyDisplay(1000.0, java.util.Locale.US))
    }

    @Test fun demoWeeklyProviderTokensMatchIOSFixture() {
        val totals = demoCostTokenTotals(now, java.time.ZoneOffset.UTC)
        assertEquals(1_197_000L, totals["claude"])
        assertEquals(1_197_000L, totals["codex"])
        val claude = DemoData.envelope(now, java.time.ZoneOffset.UTC).provider("claude").first!!
        assertEquals(listOf("session", "weekly", "model:Sonnet"), claude.windows.map { it.kind })
        assertEquals("extraUsage", claude.details.single().kind)
    }
    @Test fun windowClampsWithoutAssumingReset() {
        assertEquals(100.0, UsageWindow("weekly", 120.0).displayUsedPercent, 0.0)
        assertEquals(0.0, UsageWindow("weekly", -10.0).displayUsedPercent, 0.0)
        assertEquals(20.0, UsageWindow("session", 80.0, 300, now.minusSeconds(1)).remainingPercent, 0.0)
        assertTrue(UsageWindow("session", 80.0, 300, now.minusSeconds(1)).isOutdated(now))
    }
    @Test fun relayToleratesUnknownFieldsAndWindowKinds() {
        val json = """{"version":1,"generatedAt":"2026-10-04T12:00:00Z","newField":7,"entries":[{"providerID":"claude","source":"future","usage":{"providerID":"claude","providerName":"Claude Code","lastUpdated":"2026-10-04T12:00:00Z","windows":[{"kind":"future","usedPercent":90},{"kind":"session","usedPercent":18,"windowMinutes":300,"resetsAt":"2026-10-04T15:00:00Z","extra":true}]}}]}"""
        val envelope = RelayCodec.decode(json)
        assertEquals(18.0, envelope.provider("claude").first!!.primary!!.usedPercent, 0.0)
        assertNull(envelope.entries[0].source)
        assertTrue(envelope.costs.isEmpty())
    }
    @Test(expected = IllegalArgumentException::class) fun rejectsFutureVersion() { RelayCodec.decode("""{"version":99,"generatedAt":"2026-10-04T12:00:00Z","entries":[]}""") }
    @Test fun providerErrorAndMissingEntry() {
        val env = RelayCodec.decode("""{"version":1,"generatedAt":"2026-10-04T12:00:00Z","entries":[{"providerID":"claude","error":"unauthenticated"}]}""")
        assertEquals("unauthenticated", env.provider("claude").second)
        assertEquals("relayUnavailable", env.provider("codex").second)
    }
    @Test fun costTotalsAndModelsMatchSwiftDays() {
        val days = listOf(DailyCost("2026-10-02", TokenUsage(input=2), 10.0, models=listOf(ModelCost("x", TokenUsage(input=2), 10.0))), DailyCost("2026-10-04", TokenUsage(input=3), 5.0, models=listOf(ModelCost("x", TokenUsage(input=3), 5.0))))
        val report = CostReport("claude", now, days)
        assertEquals(15.0, report.total(7, LocalDate.parse("2026-10-04")).usd, 0.0)
        assertEquals(5L, report.models(7, LocalDate.parse("2026-10-04"))[0].tokens.input)
        assertEquals(5.0, report.total(1, LocalDate.parse("2026-10-04")).usd, 0.0)
    }
    @Test fun burndownFiltersAndProjectsLikeSwift() {
        val start = Instant.ofEpochSecond(1800000000); val reset = start.plusSeconds(18000)
        val window = UsageWindow("session", 80.0, 300, reset)
        val points = listOf(HistoryPoint(start.plusSeconds(7200), 38.0, reset.plusSeconds(120)), HistoryPoint(start.plusSeconds(3600),20.0,reset), HistoryPoint(start.plusSeconds(5400),30.0,reset.plusSeconds(121)))
        val curve = Burndown.from("claude",window,listOf(HistorySeries("claude","session",points)),DisplayMode.USED,start.plusSeconds(9000))!!
        assertEquals(listOf(20.0,38.0,80.0),curve.actual.map { it.percent })
        assertEquals(listOf(80.0,100.0,100.0),curve.projection.map { it.percent })
        assertEquals(2,curve.recordedPointCount)
    }
    @Test fun dailyBudgetSpreadsAndOutdates() {
        val window = UsageWindow("weekly", 42.0, 10080, now.plusSeconds(4 * 86400))
        val budget = DailyBudget.from(window, now=now, zone=ZoneOffset.UTC)!!
        assertEquals(DailyBudget.Status.SPREAD,budget.status)
        assertEquals(14.5,budget.perDayPercent,0.001)
        assertEquals(DailyBudget.Status.OUTDATED,DailyBudget.from(window,now=now.plusSeconds(5*86400))!!.status)
    }
    @Test fun demoMatchesIOSHeadlineAndCosts() {
        val env = DemoData.envelope(now, ZoneOffset.UTC)
        assertEquals(18.0,env.provider("claude").first!!.primary!!.usedPercent,0.0)
        assertEquals(42.0,env.provider("claude").first!!.window("weekly")!!.usedPercent,0.0)
        assertEquals(33.0,env.provider("codex").first!!.primary!!.usedPercent,0.0)
        assertEquals(61.0,env.provider("codex").first!!.window("weekly")!!.usedPercent,0.0)
        assertEquals(2.35,env.provider("claude").first!!.cost!!.total(1,LocalDate.parse("2026-10-04")).usd,0.001)
    }
}
