package com.henrrygarcia.aimana

import androidx.compose.ui.graphics.Color
import org.junit.Assert.assertTrue
import org.junit.Test
import kotlin.math.pow

class ThemeContrastTest {
    private fun composite(front: Color, back: Color, alpha: Double): Color = Color(
        (front.red * alpha + back.red * (1 - alpha)).toFloat(),
        (front.green * alpha + back.green * (1 - alpha)).toFloat(),
        (front.blue * alpha + back.blue * (1 - alpha)).toFloat()
    )

    private fun luminance(color: Color): Double {
        fun channel(value: Float): Double {
            val s = value.toDouble()
            return if (s <= 0.04045) s / 12.92 else ((s + 0.055) / 1.055).pow(2.4)
        }
        return .2126 * channel(color.red) + .7152 * channel(color.green) + .0722 * channel(color.blue)
    }

    private fun assertAA(label: String, foreground: Color, background: Color) {
        val a = luminance(foreground)
        val b = luminance(background)
        val contrast = (maxOf(a, b) + .05) / (minOf(a, b) + .05)
        assertTrue("$label contrast is $contrast, expected at least 4.5", contrast >= 4.5)
    }

    @Test fun themeTextPairsMeetAA() {
        val p = ContrastPalette
        val lightPeach = composite(Color(0xFFF6C9A8), p.lightCanvas, .42)
        val dark = p.darkCard
        assertAA("light canvas", p.lightText, p.lightCanvas)
        assertAA("light card", p.lightText, p.lightCard)
        assertAA("dark canvas", p.darkText, p.darkCanvas)
        assertAA("dark card", p.darkText, dark)
        assertAA("light secondary card", p.lightMuted, lightPeach)
        assertAA("dark secondary card", p.darkMuted, dark)
        assertAA("dark accent on detail", p.darkAccent, dark)
        assertAA("light accent on detail", p.lightAccent, p.lightCard)
        assertAA("dark plan pill", p.pastelInk, composite(Color.White, dark, .45))
        assertAA("dark provider badge", p.lightText, composite(Color.White, dark, .55))
        val costTile = composite(p.darkText, dark, .045)
        assertAA("dark cost tile", p.darkText, costTile)
        assertAA("dark cost tile caption", p.darkMuted, costTile)
        for ((name, tint) in listOf(
            "peach" to Color(0xFFF6C9A8), "pink" to Color(0xFFF5B8DB),
            "sky" to Color(0xFFB6CAEB), "olive" to Color(0xFF9AAB63)
        )) {
            assertAA("$name pill light", p.pastelInk, composite(tint, lightPeach, .9))
            assertAA("$name pill dark", p.pastelInk, composite(tint, dark, .9))
        }
        for ((name, ink) in listOf(
            "normal" to p.darkNormal, "warning" to p.darkWarning,
            "critical" to p.darkCritical
        )) assertAA("dark $name status", ink, dark)
    }
}
