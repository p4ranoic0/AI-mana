import Foundation
import Testing
@testable import AImanaCore

@Suite struct UsageFormatterTests {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let en = Locale(identifier: "en_US")

    @Test func countdownHoursAndMinutes() {
        let reset = now.addingTimeInterval(3 * 3600 + 15 * 60)
        #expect(UsageFormatter.resetCountdown(to: reset, now: now, locale: en) == "3h 15m")
    }

    @Test func countdownRoundsSecondsUp() {
        let reset = now.addingTimeInterval(14 * 60 + 1)
        #expect(UsageFormatter.resetCountdown(to: reset, now: now, locale: en) == "15m")
    }

    @Test func countdownExactHour() {
        #expect(UsageFormatter.resetCountdown(to: now.addingTimeInterval(7200), now: now, locale: en) == "2h")
    }

    @Test func countdownDays() {
        let reset = now.addingTimeInterval(2 * 86400 + 5 * 3600)
        #expect(UsageFormatter.resetCountdown(to: reset, now: now, locale: en) == "2d 5h")
    }

    @Test func countdownLessThanASecondIsNow() {
        #expect(UsageFormatter.resetCountdown(to: now.addingTimeInterval(0.5), now: now, locale: en) == "now")
    }

    @Test func countdownMinimumOneMinute() {
        #expect(UsageFormatter.resetCountdown(to: now.addingTimeInterval(5), now: now, locale: en) == "1m")
    }

    @Test func resetTextPastIsExpired() {
        #expect(UsageFormatter.resetText(for: now.addingTimeInterval(-10), now: now, locale: en) == "Expired")
        #expect(UsageFormatter.resetText(for: nil, now: now, locale: en) == nil)
    }

    @Test func resetTextPrefix() {
        let reset = now.addingTimeInterval(3 * 3600 + 15 * 60)
        #expect(UsageFormatter.resetText(for: reset, now: now, locale: en) == "Resets in 3h 15m")
    }

    @Test func percentText() {
        #expect(UsageFormatter.percentText(82) == "82%")
        #expect(UsageFormatter.percentText(0.4) == "<1%")
        #expect(UsageFormatter.percentText(0) == "0%")
        #expect(UsageFormatter.percentText(140) == "100%")
        #expect(UsageFormatter.percentText(-5) == "0%")
    }

    @Test func costFormattingUsesUSDAndLocalCalendarDay() {
        #expect(UsageFormatter.usdText(1234.5, locale: en) == "$1,235")
        #expect(UsageFormatter.usdText(87.284, locale: en) == "$87.28")
        let instant = Date(timeIntervalSince1970: 1_800_000_000)
        let utc = TimeZone(secondsFromGMT: 0)!
        let west = TimeZone(secondsFromGMT: -9 * 3600)!
        #expect(UsageFormatter.localDayString(for: instant, timeZone: utc) == "2027-01-15")
        #expect(UsageFormatter.localDayString(for: instant, timeZone: west) == "2027-01-14")
    }

    @Test func spanishCountdownAndPace() {
        let es = Locale(identifier: "es")
        let reset = now.addingTimeInterval(3 * 3600 + 15 * 60)
        #expect(UsageFormatter.resetCountdown(to: reset, now: now, locale: es) == "3h 15min")
        #expect(UsageFormatter.resetText(for: reset, now: now, locale: es) == "Se restablece en 3h 15min")
        #expect(UsageFormatter.resetText(for: now, now: now, locale: es) == "Caducado")
    }

    @Test func germanUnitsAndCurrency() {
        let de = Locale(identifier: "de_DE")
        let reset = now.addingTimeInterval(2 * 86_400 + 5 * 3600)
        #expect(UsageFormatter.resetCountdown(to: reset, now: now, locale: de) == "2T 5Std")
        #expect(UsageFormatter.resetText(for: reset, now: now, locale: de) == "Zurückgesetzt in 2T 5Std")
        #expect(UsageFormatter.usdText(1234.5, locale: de).contains("1.235"))
    }

    @Test func modelNamesAreReadable() {
        #expect(UsageFormatter.modelName("claude-opus-5-5") == "Opus 5.5")
        #expect(UsageFormatter.modelName("claude-opus-5") == "Opus 5")
        #expect(UsageFormatter.modelName("claude-fable-5-1") == "Fable 5.1")
        #expect(UsageFormatter.modelName("claude-sonnet-4-5-20250929") == "Sonnet 4.5")
        #expect(UsageFormatter.modelName("gpt-5.3-codex") == "GPT-5.3-Codex")
        #expect(UsageFormatter.modelName("o4-mini") == "o4-mini")
    }

    @Test func tokenCountsAreCompact() {
        let en = Locale(identifier: "en_US")
        #expect(UsageFormatter.tokenCountText(2_839_309_050, locale: en) == "2,839 M")
        #expect(UsageFormatter.tokenCountText(18_407_127, locale: en) == "18.4 M")
        #expect(UsageFormatter.tokenCountText(52_300, locale: en) == "52.3 k")
        #expect(UsageFormatter.tokenCountText(950, locale: en) == "950")
        #expect(UsageFormatter.tokenCountText(2_839_309_050, locale: Locale(identifier: "es_ES")) == "2839 M"
                || UsageFormatter.tokenCountText(2_839_309_050, locale: Locale(identifier: "es_ES")) == "2.839 M")
    }
}
