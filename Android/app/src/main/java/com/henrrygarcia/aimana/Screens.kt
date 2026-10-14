package com.henrrygarcia.aimana

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.PathEffect
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalLocale
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.res.pluralStringResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.navigation.NavHostController
import com.henrrygarcia.aimana.core.*
import com.henrrygarcia.aimana.core.DisplayMode as UsageDisplayMode
import java.text.NumberFormat
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.time.format.FormatStyle
import java.util.Locale
import kotlin.math.ceil
import kotlin.math.cos
import kotlin.math.sin

private val Peach = Color(0xFFF6C9A8)
private val Pink = Color(0xFFF5B8DB)
private val Sky = Color(0xFFB6CAEB)
private val Olive = Color(0xFF9AAB63)
private val Warning = Color(0xFF9A4D08)
private val Critical = Color(0xFFAB1726)
private val Coral = Color(0xFFE17865)
private val Ink = Color(0xFF282A27)
private val PastelInk = ContrastPalette.pastelInk

@Composable private fun statusInk(status: QuotaStatus): Color {
    val dark = MaterialTheme.colorScheme.background.red < .2f
    return when (status) {
        QuotaStatus.FAST, QuotaStatus.LOW -> if (dark) ContrastPalette.darkWarning else Warning
        QuotaStatus.CRITICAL, QuotaStatus.DEPLETED -> if (dark) ContrastPalette.darkCritical else Critical
        QuotaStatus.STALE -> MaterialTheme.colorScheme.onSurfaceVariant
        else -> if (dark) ContrastPalette.darkNormal else Color(0xFF176632)
    }
}

@Composable
internal fun AppBottomBar(route: String?, navigate: (String) -> Unit, refresh: () -> Unit) {
    val selectedHome = route == "home" || route?.startsWith("detail/") == true
    val refreshDescription = stringResource(R.string.refresh_label)
    Surface(
        modifier = Modifier.fillMaxWidth().padding(horizontal = 12.dp, vertical = 6.dp),
        shape = CircleShape,
        color = MaterialTheme.colorScheme.surface.copy(alpha = 0.98f),
        shadowElevation = 7.dp
    ) {
        Row(Modifier.fillMaxWidth().height(78.dp).padding(horizontal = 8.dp), verticalAlignment = Alignment.CenterVertically) {
            BottomItem(stringResource(R.string.home_tab), AppIcon.GRID, selectedHome, Modifier.weight(1f)) { navigate("home") }
            BottomItem(stringResource(R.string.costs_tab), AppIcon.CHART, route == "costs", Modifier.weight(1f)) { navigate("costs") }
            Box(Modifier.weight(1f), contentAlignment = Alignment.Center) {
                IconButton(onClick = refresh, modifier = Modifier.size(54.dp).clip(CircleShape).background(Coral)
                    .semantics { contentDescription = refreshDescription }) {
                    Icon(Icons.Filled.Refresh, null, tint = Color.White, modifier = Modifier.size(28.dp))
                }
            }
            BottomItem(stringResource(R.string.settings_tab), AppIcon.GEAR, route == "settings", Modifier.weight(1f)) { navigate("settings") }
        }
    }
}

private enum class AppIcon { GRID, CHART, GEAR }
@Composable private fun BottomItem(label: String, icon: AppIcon, selected: Boolean, modifier: Modifier, onClick: () -> Unit) {
    Column(modifier.clickable(onClick = onClick).padding(vertical = 6.dp), horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(4.dp)) {
        val ink = if (selected) MaterialTheme.colorScheme.onSurface else MaterialTheme.colorScheme.onSurfaceVariant
        if (icon == AppIcon.GEAR) {
            Canvas(Modifier.size(23.dp)) {
                val center = androidx.compose.ui.geometry.Offset(size.width / 2, size.height / 2)
                val gear = Path()
                for (index in 0..32) {
                    val angle = -Math.PI / 2 + index * Math.PI / 16
                    val radius = size.minDimension * (if (index % 4 == 1 || index % 4 == 2) .46f else .34f)
                    val x = center.x + radius * cos(angle).toFloat()
                    val y = center.y + radius * sin(angle).toFloat()
                    if (index == 0) gear.moveTo(x, y) else gear.lineTo(x, y)
                }
                drawPath(gear, ink, style = Stroke(1.8.dp.toPx(), cap = StrokeCap.Round))
                drawCircle(ink, radius = size.minDimension * .12f, center = center, style = Stroke(1.8.dp.toPx()))
            }
        } else Canvas(Modifier.size(21.dp)) {
            val w = size.width; val h = size.height; val stroke = 2.dp.toPx()
            if (icon == AppIcon.GRID) {
                val box = w * .33f
                for (x in listOf(.08f, .59f)) for (y in listOf(.08f, .59f))
                    drawRoundRect(ink, androidx.compose.ui.geometry.Offset(w*x,h*y), androidx.compose.ui.geometry.Size(box,box),
                        androidx.compose.ui.geometry.CornerRadius(2.dp.toPx()), style = Stroke(stroke))
            } else {
                for ((x, height) in listOf(.12f to .42f, .43f to .72f, .74f to .95f))
                    drawRoundRect(ink, androidx.compose.ui.geometry.Offset(w*x,h*(1-height)),
                        androidx.compose.ui.geometry.Size(w*.15f,h*height), androidx.compose.ui.geometry.CornerRadius(1.dp.toPx()))
            }
        }
        Text(label, fontSize = 11.sp, color = ink, fontWeight = if (selected) FontWeight.SemiBold else FontWeight.Normal)
    }
}

@Composable private fun ProviderBadge(id: String, size: Int = 38) {
    Box(Modifier.size(size.dp).clip(CircleShape).background(Color.White.copy(alpha = .55f)), contentAlignment = Alignment.Center) {
        Text(if (id == "claude") "✦" else "</>", fontSize = if (id == "claude") 23.sp else 14.sp,
            fontWeight = FontWeight.Bold, color = Ink)
    }
}

@Composable private fun SoftCard(modifier: Modifier = Modifier, tint: Color = MaterialTheme.colorScheme.surface,
                                  content: @Composable ColumnScope.() -> Unit) {
    // Translucent pastels become mid-tone brown in dark mode: neither the light nor dark labels
    // maintain AA contrast. Keep the pastel lanes, but use a solid dark card surface.
    val cardColor = if (MaterialTheme.colorScheme.background.red < .2f) ContrastPalette.darkCard else tint
    Surface(modifier, shape = RoundedCornerShape(28.dp), color = cardColor) {
        Column(Modifier.padding(20.dp), verticalArrangement = Arrangement.spacedBy(11.dp), content = content)
    }
}

@Composable private fun BrandHeader() {
    Column(Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(1.dp)) {
        Row {
            Text(stringResource(R.string.brand_ai), color = Coral, fontWeight = FontWeight.Black, fontSize = 34.sp, lineHeight = 38.sp)
            Text(stringResource(R.string.brand_mana), color = MaterialTheme.colorScheme.onBackground, fontWeight = FontWeight.SemiBold, fontSize = 34.sp, lineHeight = 38.sp)
        }
        Text(stringResource(R.string.tagline), color = MaterialTheme.colorScheme.onSurfaceVariant, fontSize = 16.sp)
    }
}

@Composable private fun ModeToggle(state: AppState, change: (UsageDisplayMode) -> Unit, modifier: Modifier = Modifier) {
    Row(modifier.fillMaxWidth().clip(CircleShape).background(MaterialTheme.colorScheme.onSurface.copy(alpha = 0.06f)).padding(3.dp)) {
        ToggleItem(stringResource(R.string.used_title), state.mode == UsageDisplayMode.USED, Modifier.weight(1f)) { change(UsageDisplayMode.USED) }
        ToggleItem(stringResource(R.string.remaining_title), state.mode == UsageDisplayMode.REMAINING, Modifier.weight(1f)) { change(UsageDisplayMode.REMAINING) }
    }
}
@Composable private fun ToggleItem(label: String, selected: Boolean, modifier: Modifier, onClick: () -> Unit) {
    Box(modifier.clip(CircleShape).background(if (selected) MaterialTheme.colorScheme.surface else Color.Transparent)
        .clickable(onClick = onClick).padding(vertical = 10.dp), contentAlignment = Alignment.Center) {
        Text(label, fontSize = 15.sp, fontWeight = if (selected) FontWeight.SemiBold else FontWeight.Medium,
            color = MaterialTheme.colorScheme.onSurface)
    }
}

@Composable internal fun HomeScreen(state: AppState, choose: () -> Unit, refresh: () -> Unit,
                                      changeMode: (UsageDisplayMode) -> Unit, detail: (String) -> Unit) {
    val context = LocalContext.current
    val locale = LocalLocale.current.platformLocale
    val now = remember(state.demo) { if (state.demo) DemoData.referenceTime else Instant.now() }
    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(horizontal = 20.dp, vertical = 18.dp),
        verticalArrangement = Arrangement.spacedBy(18.dp)) {
        BrandHeader()
        ModeToggle(state, changeMode)
        if (state.uri == null && !state.demo) ConnectCard(choose, state.fileError)
        else if (state.fileError) ConnectCard(choose, true)
        else if (state.loading && state.relay == null) CircularProgressIndicator()
        else {
            val relay = state.relay
            if (relay == null) Text(stringResource(R.string.no_reading), color = MaterialTheme.colorScheme.onSurfaceVariant)
            else {
                val usages = listOfNotNull(relay.provider("claude").first, relay.provider("codex").first)
                val summary = OverviewSummary.from(usages, state.mode)
                if (summary != null) OverviewHero(summary, now, locale)
                for (id in listOf("claude", "codex")) {
                    val usage = relay.provider(id).first
                    if (usage != null) ProviderCard(usage, state.mode, now, locale) { detail(id) }
                    else relay.provider(id).second?.let { error -> ErrorCard(id, error, choose) }
                }
            }
        }
        Spacer(Modifier.height(14.dp))
    }
}

@Composable private fun ConnectCard(choose: () -> Unit, error: Boolean) {
    SoftCard(Modifier.fillMaxWidth(), tint = Peach.copy(alpha = 0.45f)) {
        Text(stringResource(R.string.connect), fontSize = 24.sp, fontWeight = FontWeight.Bold)
        Text(stringResource(R.string.setup_description), color = MaterialTheme.colorScheme.onSurfaceVariant)
        Text(stringResource(R.string.step_one_numbered, stringResource(R.string.step_one)), color = MaterialTheme.colorScheme.onSurface)
        Text(stringResource(R.string.step_two_numbered, stringResource(R.string.step_two)), color = MaterialTheme.colorScheme.onSurface)
        if (error) Text(stringResource(R.string.file_access), color = statusInk(QuotaStatus.CRITICAL))
        Button(onClick = choose, colors = ButtonDefaults.buttonColors(containerColor = Coral)) { Text(stringResource(R.string.choose_file)) }
    }
}

@Composable private fun OverviewHero(summary: OverviewSummary, now: Instant, locale: Locale) {
    val featured = summary.highlighted
    val kindTitle = windowTitle(featured.window)
    val providerShort = providerShortName(featured.providerID, featured.providerName)
    val reset = countdownText(featured.window.resetsAt, now)
    val budget = featured.window.takeIf { it.kind == "weekly" }?.let { DailyBudget.from(it, now = now) }
    val fontScale = LocalDensity.current.fontScale
    SoftCard(Modifier.fillMaxWidth(), tint = Peach.copy(alpha = 0.38f)) {
        val ringSize = (132 * fontScale).dp
        if (fontScale >= 1.3f) {
            Column(verticalArrangement = Arrangement.spacedBy(14.dp)) {
                OverviewRings(summary, Modifier.size(ringSize).align(Alignment.CenterHorizontally), locale)
                OverviewDetails(summary, providerShort, kindTitle, reset, budget, locale)
            }
        } else {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(14.dp)) {
                OverviewRings(summary, Modifier.size(ringSize), locale)
                OverviewDetails(summary, providerShort, kindTitle, reset, budget, locale, Modifier.weight(1f))
            }
        }
    }
}

@Composable private fun OverviewDetails(summary: OverviewSummary, providerShort: String, kindTitle: String,
                                         reset: String, budget: DailyBudget?, locale: Locale, modifier: Modifier = Modifier) {
    Column(modifier, verticalArrangement = Arrangement.spacedBy(5.dp)) {
        Text(stringResource(if (summary.mode == UsageDisplayMode.USED) R.string.mode_highest else R.string.mode_lowest),
            color = MaterialTheme.colorScheme.onSurfaceVariant, fontSize = 14.sp)
        Text(stringResource(R.string.overview_featured, providerShort, kindTitle), fontSize = 18.sp, fontWeight = FontWeight.SemiBold, lineHeight = 22.sp)
        Text(stringResource(R.string.reset_in, reset), color = MaterialTheme.colorScheme.onSurfaceVariant, fontSize = 13.sp)
        budget?.takeIf { it.status == DailyBudget.Status.SPREAD }?.let {
            Text(stringResource(R.string.daily_budget_compact, UsageFormat.percent(it.perDayPercent, locale)),
                color = MaterialTheme.colorScheme.onSurfaceVariant, fontSize = 13.sp)
        }
        Column(verticalArrangement = Arrangement.spacedBy(5.dp), modifier = Modifier.padding(top = 3.dp)) {
            summary.lanes.forEach { lane ->
                val tint = laneTint(lane.providerID, lane.window.kind)
                Row(Modifier.fillMaxWidth().clip(CircleShape).background(tint.copy(alpha = 0.9f)).padding(horizontal = 9.dp, vertical = 5.dp),
                    verticalAlignment = Alignment.CenterVertically) {
                    Text(providerShortName(lane.providerID, lane.providerName), fontSize = 12.sp, fontWeight = FontWeight.SemiBold, color = PastelInk, maxLines = 1)
                    Spacer(Modifier.width(5.dp))
                    Text(windowCompact(lane.window), fontSize = 11.sp, color = PastelInk, maxLines = 1)
                    Spacer(Modifier.weight(1f))
                    Text(UsageFormat.percent(lane.displayPercent, locale), fontSize = 12.sp, fontWeight = FontWeight.Bold, color = PastelInk)
                }
            }
        }
    }
}

@Composable private fun OverviewRings(summary: OverviewSummary, modifier: Modifier, locale: Locale) {
    val scale = LocalDensity.current.fontScale
    Box(modifier, contentAlignment = Alignment.Center) {
        Canvas(Modifier.fillMaxSize()) {
            val sw = (7 * scale).dp.toPx()
            val lanes = summary.lanes.take(4)
            lanes.forEachIndexed { index, lane ->
                val inset = (index * 11 * scale).dp.toPx() + sw / 2
                val diameter = size.minDimension - 2 * inset
                val color = laneTint(lane.providerID, lane.window.kind)
                drawArc(color.copy(alpha = .20f), -90f, 360f, false,
                    topLeft = androidx.compose.ui.geometry.Offset(inset, inset), size = androidx.compose.ui.geometry.Size(diameter, diameter), style = Stroke(sw))
                drawArc(color, -90f, (360f * lane.displayPercent.coerceIn(0.0, 100.0) / 100).toFloat(), false,
                    topLeft = androidx.compose.ui.geometry.Offset(inset, inset), size = androidx.compose.ui.geometry.Size(diameter, diameter), style = Stroke(sw, cap = StrokeCap.Round))
            }
        }
        Column(Modifier.width((48 * scale).dp), horizontalAlignment = Alignment.CenterHorizontally) {
            Text(UsageFormat.percent(summary.highlighted.displayPercent, locale), fontSize = 16.sp, lineHeight = 19.sp,
                fontWeight = FontWeight.Bold, textAlign = TextAlign.Center, maxLines = 1)
            Text(stringResource(if (summary.mode == UsageDisplayMode.USED) R.string.used else R.string.remaining),
                fontSize = 10.sp, color = MaterialTheme.colorScheme.onSurfaceVariant, maxLines = 1)
        }
    }
}

@Composable private fun ProviderCard(usage: UsageInfo, mode: UsageDisplayMode, now: Instant, locale: Locale, onClick: () -> Unit) {
    val primary = usage.primary
    val tint = if (usage.providerID == "claude") Peach.copy(alpha = .42f) else Sky.copy(alpha = .40f)
    SoftCard(Modifier.fillMaxWidth().clickable(onClick = onClick), tint = tint) {
        Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
            ProviderBadge(usage.providerID)
            Spacer(Modifier.width(10.dp))
            Text(usage.providerName, fontSize = 20.sp, fontWeight = FontWeight.SemiBold, modifier = Modifier.weight(1f), maxLines = 1, overflow = TextOverflow.Ellipsis)
            usage.plan?.let { Text(planName(it), fontSize = 13.sp, fontWeight = FontWeight.SemiBold, color = PastelInk,
                modifier = Modifier.clip(CircleShape).background(Color.White.copy(alpha = .45f)).padding(horizontal = 11.dp, vertical = 6.dp)) }
        }
        if (primary != null) {
            Text(windowTitle(primary), fontSize = 14.sp, color = MaterialTheme.colorScheme.onSurfaceVariant)
            Row(verticalAlignment = Alignment.Bottom, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                Text(UsageFormat.percent(mode.percent(primary), locale), fontSize = 53.sp, lineHeight = 58.sp,
                    fontWeight = FontWeight.Bold)
                Text(stringResource(if (mode == UsageDisplayMode.USED) R.string.used else R.string.remaining),
                    color = MaterialTheme.colorScheme.onSurfaceVariant, modifier = Modifier.padding(bottom = 7.dp))
            }
            QuotaProgress(primary, mode, usage.providerID, now)
            StatusLine(primary, usage.lastUpdated, now, locale)
            Text(stringResource(R.string.reset_in, countdownText(primary.resetsAt, now)), fontSize = 13.sp,
                color = MaterialTheme.colorScheme.onSurfaceVariant)
            usage.windows.filter { it != primary }.forEach { window ->
                HorizontalDivider(color = MaterialTheme.colorScheme.onSurface.copy(alpha = .08f))
                WindowRow(window, usage.providerID, usage.lastUpdated, mode, now, locale, compact = true)
            }
            if (usage.details.isNotEmpty()) {
                HorizontalDivider(color = MaterialTheme.colorScheme.onSurface.copy(alpha = .08f))
                usage.details.forEach { Text(detailSummary(it, locale), fontSize = 13.sp, color = MaterialTheme.colorScheme.onSurfaceVariant) }
            }
            val age = (now.epochSecond - usage.lastUpdated.epochSecond).coerceAtLeast(0)
            Row(horizontalArrangement = Arrangement.spacedBy(5.dp)) {
                Text(if (age < 60) stringResource(R.string.updated_just_now) else stringResource(R.string.updated, relativeAge(age)),
                    fontSize = 12.sp, color = MaterialTheme.colorScheme.onSurfaceVariant)
                if (age > 3600 || usage.windows.any { it.isOutdated(now) })
                    Text(stringResource(R.string.status_outdated), fontSize = 12.sp, color = statusInk(QuotaStatus.LOW))
            }
            Text(stringResource(if (usage.providerID == "claude") R.string.source_claude else R.string.source_codex),
                fontSize = 12.sp, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
    }
}

@Composable private fun QuotaProgress(window: UsageWindow, mode: UsageDisplayMode, providerID: String, now: Instant) {
    val value = mode.percent(window).coerceIn(0.0, 100.0).toFloat()
    val color = when (quotaStatus(window, now, now)) {
        QuotaStatus.CRITICAL, QuotaStatus.DEPLETED -> Critical
        QuotaStatus.LOW, QuotaStatus.FAST -> Warning
        else -> MaterialTheme.colorScheme.primary
    }
    BoxWithConstraints(Modifier.fillMaxWidth().height(8.dp).clip(CircleShape).background(MaterialTheme.colorScheme.onSurface.copy(alpha = .07f))) {
        Box(Modifier.width(maxWidth * value / 100f).fillMaxHeight().background(color))
    }
}

@Composable private fun StatusLine(window: UsageWindow, updated: Instant, now: Instant, locale: Locale) {
    val state = quotaStatus(window, updated, now)
    val color = statusInk(state)
    val label = when (state) {
        QuotaStatus.FAST -> {
            val pace = UsagePace.from(window, now)
            val time = pace?.exhaustsAt?.let { countdownText(it, now) }
            if (time == null) stringResource(R.string.fast_pace) else stringResource(R.string.pace_fast, time) + stringResource(R.string.before_reset)
        }
        QuotaStatus.ON_PACE -> stringResource(R.string.pace_on, UsagePace.from(window, now)?.projectedUsedAtReset?.toInt() ?: 0)
        QuotaStatus.LOW -> stringResource(R.string.status_low)
        QuotaStatus.CRITICAL -> stringResource(R.string.status_critical)
        QuotaStatus.DEPLETED -> stringResource(R.string.status_depleted)
        QuotaStatus.STALE -> stringResource(R.string.status_stale)
        QuotaStatus.AVAILABLE -> stringResource(R.string.status_available)
    }
    Text(label, color = color, fontSize = 13.sp, fontWeight = FontWeight.SemiBold)
}

@Composable private fun WindowRow(window: UsageWindow, providerID: String, updated: Instant, mode: UsageDisplayMode,
                                  now: Instant, locale: Locale, compact: Boolean = false) {
    val title = windowTitle(window)
    val status = quotaStatus(window, updated, now)
    Column(verticalArrangement = Arrangement.spacedBy(if (compact) 5.dp else 8.dp), modifier = Modifier.fillMaxWidth()) {
        Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
            Text(title, fontSize = if (compact) 14.sp else 16.sp, fontWeight = FontWeight.SemiBold, modifier = Modifier.weight(1f))
            Text("${UsageFormat.percent(mode.percent(window), locale)} ${stringResource(if (mode == UsageDisplayMode.USED) R.string.used else R.string.remaining)}",
                fontSize = 14.sp, fontWeight = FontWeight.SemiBold, maxLines = 1)
        }
        val progress = mode.percent(window).coerceIn(0.0, 100.0).toFloat()
        BoxWithConstraints(Modifier.fillMaxWidth().height(6.dp).clip(CircleShape).background(MaterialTheme.colorScheme.onSurface.copy(alpha = .07f))) {
            Box(Modifier.width(maxWidth * progress / 100f).fillMaxHeight().background(laneTint(providerID, window.kind)))
        }
        if (status == QuotaStatus.STALE) Text(stringResource(R.string.status_stale), fontSize = 12.sp, color = MaterialTheme.colorScheme.onSurfaceVariant)
        else if (window.resetsAt != null) Text(stringResource(R.string.reset_in, countdownText(window.resetsAt, now)), fontSize = 12.sp, color = MaterialTheme.colorScheme.onSurfaceVariant)
        if (window.kind == "weekly") {
            DailyBudget.from(window, now = now)?.takeIf { it.status == DailyBudget.Status.SPREAD }?.let {
                    Text(stringResource(R.string.daily_budget_compact, UsageFormat.percent(it.perDayPercent, locale)), fontSize = 12.sp, color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
        }
    }
}

@Composable private fun ErrorCard(id: String, error: String, choose: () -> Unit) {
    SoftCard(Modifier.fillMaxWidth(), tint = if (id == "claude") Peach.copy(alpha = .4f) else Sky.copy(alpha = .4f)) {
        Text(stringResource(if (id == "claude") R.string.provider_claude else R.string.provider_codex), fontSize = 20.sp, fontWeight = FontWeight.SemiBold)
        Text(stringResource(ProviderPresentation.errorText(error)), color = statusInk(QuotaStatus.CRITICAL))
        TextButton(onClick = choose) { Text(stringResource(R.string.choose_file)) }
    }
}

@Composable internal fun DetailScreen(state: AppState, id: String, back: () -> Unit) {
    BackHandler(onBack = back)
    val usage = state.relay?.provider(id)?.first
    val now = remember(state.demo) { if (state.demo) DemoData.referenceTime else Instant.now() }
    val locale = LocalLocale.current.platformLocale
    val backText = "Back"
    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(horizontal = 20.dp, vertical = 10.dp),
        verticalArrangement = Arrangement.spacedBy(20.dp)) {
        val backInk = MaterialTheme.colorScheme.onSurface
        IconButton(onClick = back, modifier = Modifier.size(42.dp).clip(CircleShape)
            .background(MaterialTheme.colorScheme.surface).semantics { contentDescription = backText }) {
            Canvas(Modifier.size(20.dp)) {
                val c = androidx.compose.ui.geometry.Offset(size.width*.25f, size.height*.5f)
                drawLine(backInk, androidx.compose.ui.geometry.Offset(size.width*.8f,size.height*.5f), c, 2.dp.toPx())
                drawLine(backInk, androidx.compose.ui.geometry.Offset(size.width*.5f,size.height*.2f), c, 2.dp.toPx())
                drawLine(backInk, androidx.compose.ui.geometry.Offset(size.width*.5f,size.height*.8f), c, 2.dp.toPx())
            }
        }
        if (usage == null) Text(stringResource(R.string.no_reading))
        else {
            val primary = usage.primary
            SoftCard(Modifier.fillMaxWidth(), tint = (if (id == "claude") Peach else Sky).copy(alpha = .42f)) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    ProviderBadge(id, 32)
                    Spacer(Modifier.width(9.dp))
                    Text(usage.providerName, fontSize = 22.sp, fontWeight = FontWeight.SemiBold, modifier = Modifier.weight(1f))
                    usage.plan?.let { Text(planName(it), fontSize = 13.sp, fontWeight = FontWeight.SemiBold, color = PastelInk,
                        modifier = Modifier.clip(CircleShape).background(Color.White.copy(alpha = .45f)).padding(horizontal = 10.dp, vertical = 6.dp)) }
                }
                if (primary != null) {
                    Row(verticalAlignment = Alignment.Bottom, horizontalArrangement = Arrangement.spacedBy(7.dp)) {
                        Text(UsageFormat.percent(state.mode.percent(primary), locale), fontSize = 58.sp, lineHeight = 62.sp, fontWeight = FontWeight.Bold)
                        Text("${stringResource(if (state.mode == UsageDisplayMode.USED) R.string.used else R.string.remaining)} · ${windowTitle(primary)}",
                            fontSize = 14.sp, color = MaterialTheme.colorScheme.onSurfaceVariant, modifier = Modifier.padding(bottom = 9.dp))
                    }
                    val remaining = primary.remainingPercent
                    Text(stringResource(when {
                        remaining <= 0 -> R.string.status_depleted
                        remaining < 10 -> R.string.status_critical
                        remaining < 20 -> R.string.status_low
                        else -> R.string.status_available
                    }), fontSize = 13.sp, fontWeight = FontWeight.SemiBold,
                        color = statusInk(if (remaining < 10) QuotaStatus.CRITICAL else if (remaining < 20) QuotaStatus.LOW else QuotaStatus.AVAILABLE))
                }
                Text(if (now.epochSecond - usage.lastUpdated.epochSecond < 60) stringResource(R.string.updated_just_now)
                    else stringResource(R.string.updated, relativeAge((now.epochSecond - usage.lastUpdated.epochSecond).coerceAtLeast(0))),
                    fontSize = 12.sp, color = MaterialTheme.colorScheme.onSurfaceVariant)
                Text(stringResource(if (id == "claude") R.string.source_claude else R.string.source_codex),
                    fontSize = 12.sp, color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
            val budgets = usage.windows.mapNotNull { window -> DailyBudget.from(window, usage.history, usage.providerID, now, if (state.demo) DemoData.demoZone else ZoneId.systemDefault())?.let { window to it } }
            if (budgets.isNotEmpty()) {
                SectionTitle(stringResource(R.string.daily_budget_title))
                SoftCard(Modifier.fillMaxWidth()) {
                    budgets.forEachIndexed { index, (window, budget) ->
                        if (index > 0) HorizontalDivider()
                        Text(windowTitle(window), fontSize = 14.sp, fontWeight = FontWeight.SemiBold)
                        Text(budgetHeadline(budget, locale), fontSize = 28.sp, fontWeight = FontWeight.Bold,
                            color = if (MaterialTheme.colorScheme.background.red < .2f) ContrastPalette.darkAccent else ContrastPalette.lightAccent)
                        Text(budgetCaption(budget, now), fontSize = 13.sp, color = MaterialTheme.colorScheme.onSurfaceVariant)
                        budget.todayFraction?.let { fraction ->
                            LinearProgressIndicator(progress = { fraction.coerceIn(0.0, 1.0).toFloat() }, Modifier.fillMaxWidth(), color = Coral)
                            budget.todayBudgetPercent?.let { budgetPct ->
                                Text(stringResource(R.string.budget_today, UsageFormat.percent(budget.usedToday ?: 0.0, locale), UsageFormat.percent(budgetPct, locale)),
                                    fontSize = 12.sp, color = MaterialTheme.colorScheme.onSurfaceVariant)
                            }
                        }
                    }
                    Text(stringResource(R.string.budget_explanation), fontSize = 12.sp, color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
            }
            SectionTitle(stringResource(R.string.burndown))
            for (window in usage.windows.filter { it.kind == "session" || it.kind == "weekly" }) {
                val curve = Burndown.from(usage.providerID, window, usage.history, state.mode, usage.lastUpdated)
                SoftCard(Modifier.fillMaxWidth()) {
                    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                        Text(windowTitle(window), fontWeight = FontWeight.SemiBold)
                        Text("${UsageFormat.percent(state.mode.percent(window), locale)} ${stringResource(if (state.mode == UsageDisplayMode.USED) R.string.used else R.string.remaining)}",
                            fontWeight = FontWeight.SemiBold)
                    }
                    if (curve != null && curve.actual.isNotEmpty()) BurndownChart(curve, window, locale, now)
                    else Text(stringResource(R.string.no_history), color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
            }
            SectionTitle(stringResource(R.string.windows))
            SoftCard(Modifier.fillMaxWidth()) {
                usage.windows.forEachIndexed { index, window ->
                    if (index > 0) HorizontalDivider()
                    WindowRow(window, usage.providerID, usage.lastUpdated, state.mode, now, locale)
                }
                usage.details.forEach { detail ->
                    HorizontalDivider()
                    Text(detailSummary(detail, locale), fontSize = 14.sp, color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
            }
            SectionTitle(stringResource(R.string.history))
            SoftCard(Modifier.fillMaxWidth()) {
                val start = now.minusSeconds(7 * 86400L)
                val points = usage.history.filter { it.providerID == usage.providerID && it.kind == "weekly" }
                    .flatMap { it.points }.filter { it.t.isAfter(start) && !it.t.isAfter(now) }.sortedBy { it.t }
                if (points.size >= 2) HistoryChart(points, locale)
                else Text(stringResource(R.string.no_history), color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
            usage.cost?.let { report ->
                SectionTitle(stringResource(R.string.estimated_cost))
                CostReportCard(report, locale, now)
            }
        }
        Spacer(Modifier.height(14.dp))
    }
}

@Composable private fun SectionTitle(title: String) {
    Text(title, fontSize = 20.sp, fontWeight = FontWeight.SemiBold, modifier = Modifier.padding(top = 2.dp))
}

@Composable private fun BurndownChart(curve: Burndown, window: UsageWindow, locale: Locale, now: Instant) {
    val onSurface = MaterialTheme.colorScheme.onSurfaceVariant
    val axis = MaterialTheme.colorScheme.onSurface.copy(alpha = .13f)
    val actualColor = MaterialTheme.colorScheme.primary
    val widthLabel = stringResource(R.string.burndown)
    Column(verticalArrangement = Arrangement.spacedBy(3.dp)) {
        Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
            Column(Modifier.width(38.dp).height(154.dp), verticalArrangement = Arrangement.SpaceBetween, horizontalAlignment = Alignment.End) {
                Text(stringResource(R.string.axis_100), fontSize = 10.sp, color = onSurface)
                Text(stringResource(R.string.axis_50), fontSize = 10.sp, color = onSurface)
                Text(stringResource(R.string.axis_0), fontSize = 10.sp, color = onSurface)
            }
            Spacer(Modifier.width(5.dp))
            Canvas(Modifier.weight(1f).height(154.dp).semantics { contentDescription = widthLabel }) {
                fun y(value: Double) = size.height * (1f - value.coerceIn(0.0, 100.0).toFloat() / 100f)
                listOf(0.0, 50.0, 100.0).forEach { val yy = y(it); drawLine(axis, androidx.compose.ui.geometry.Offset(0f, yy), androidx.compose.ui.geometry.Offset(size.width, yy), 1.dp.toPx()) }
                val span = (curve.end.epochSecond - curve.start.epochSecond).coerceAtLeast(1)
                fun xy(p: ChartPoint) = androidx.compose.ui.geometry.Offset(((p.time.epochSecond - curve.start.epochSecond).toFloat() / span).coerceIn(0f,1f)*size.width, y(p.percent))
                fun path(points: List<ChartPoint>) = Path().apply { points.forEachIndexed { i,p -> val at=xy(p); if(i==0) moveTo(at.x,at.y) else lineTo(at.x,at.y) } }
                if (curve.guide.size >= 2) drawPath(path(curve.guide), onSurface.copy(alpha=.48f), style=Stroke(1.dp.toPx(), pathEffect=PathEffect.dashPathEffect(floatArrayOf(3.dp.toPx(),4.dp.toPx()))) )
                if (curve.actual.size >= 2) drawPath(path(curve.actual), actualColor, style=Stroke(2.5.dp.toPx(), cap=StrokeCap.Round))
                if (curve.projection.size >= 2) drawPath(path(curve.projection), Coral, style=Stroke(2.dp.toPx(), cap=StrokeCap.Round, pathEffect=PathEffect.dashPathEffect(floatArrayOf(7.dp.toPx(),5.dp.toPx()))))
                curve.current?.let { p -> val at=xy(p); drawLine(Warning.copy(alpha=.75f), androidx.compose.ui.geometry.Offset(at.x,0f), androidx.compose.ui.geometry.Offset(at.x,size.height), 1.dp.toPx(), pathEffect=PathEffect.dashPathEffect(floatArrayOf(3.dp.toPx(),3.dp.toPx()))); drawCircle(actualColor, 4.dp.toPx(), at) }
            }
        }
        val startLabel = axisTime(curve.start, window, locale)
        val midLabel = axisTime(curve.start.plusSeconds((curve.end.epochSecond-curve.start.epochSecond)/2), window, locale)
        val endLabel = axisTime(curve.end, window, locale)
        Row(Modifier.fillMaxWidth().padding(start = 43.dp), horizontalArrangement = Arrangement.SpaceBetween) {
            Text(startLabel, fontSize = 10.sp, color = onSurface)
            Text(midLabel, fontSize = 10.sp, color = onSurface)
            Text(endLabel, fontSize = 10.sp, color = onSurface)
        }
        Row(horizontalArrangement = Arrangement.spacedBy(10.dp), modifier = Modifier.padding(top = 4.dp)) {
            LegendDot(actualColor); Text(stringResource(R.string.actual), fontSize = 10.sp, color = onSurface)
            LegendLine(onSurface.copy(alpha=.55f), dotted=true); Text(stringResource(R.string.even_pace), fontSize = 10.sp, color = onSurface)
            LegendLine(Coral, dotted=false); Text(stringResource(R.string.projection), fontSize = 10.sp, color = onSurface)
        }
        Text(stringResource(R.string.reset_in, countdownText(curve.end, now)), fontSize = 11.sp, color = onSurface)
    }
}

@Composable private fun HistoryChart(points: List<HistoryPoint>, locale: Locale) {
    val onSurface = MaterialTheme.colorScheme.onSurfaceVariant
    val grid = MaterialTheme.colorScheme.onSurface.copy(alpha=.13f)
    val chartDescription = stringResource(R.string.history)
    Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
        Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
            Column(Modifier.width(38.dp).height(142.dp), verticalArrangement = Arrangement.SpaceBetween, horizontalAlignment = Alignment.End) {
                Text(stringResource(R.string.axis_100), fontSize=10.sp, color=onSurface); Text(stringResource(R.string.axis_50), fontSize=10.sp, color=onSurface); Text(stringResource(R.string.axis_0), fontSize=10.sp, color=onSurface)
            }
            Spacer(Modifier.width(5.dp))
            Canvas(Modifier.weight(1f).height(142.dp).semantics { contentDescription = chartDescription }) {
                listOf(0.0,50.0,100.0).forEach { v -> val y=size.height*(1f-v.toFloat()/100f); drawLine(grid, androidx.compose.ui.geometry.Offset(0f,y), androidx.compose.ui.geometry.Offset(size.width,y),1.dp.toPx()) }
                val start=points.first().t.epochSecond; val end=points.last().t.epochSecond; val span=(end-start).coerceAtLeast(1)
                val path=Path(); points.forEachIndexed { i,p -> val x=(p.t.epochSecond-start).toFloat()/span*size.width; val y=(1f-p.used.coerceIn(0.0,100.0).toFloat()/100f)*size.height; if(i==0)path.moveTo(x,y) else path.lineTo(x,y) }
                drawPath(path, Coral, style=Stroke(2.5.dp.toPx(), cap=StrokeCap.Round))
                points.forEachIndexed { i,p -> if(i % (points.size/8).coerceAtLeast(1)==0){ val x=(p.t.epochSecond-start).toFloat()/span*size.width; val y=(1f-p.used.coerceIn(0.0,100.0).toFloat()/100f)*size.height; drawCircle(Coral, 2.7.dp.toPx(), androidx.compose.ui.geometry.Offset(x,y)) } }
            }
        }
        val first=points.first().t; val last=points.last().t
        Row(Modifier.fillMaxWidth().padding(start=43.dp),horizontalArrangement=Arrangement.SpaceBetween){ Text(dateLabel(first,locale),fontSize=10.sp,color=onSurface); Text(dateLabel(midPoint(first,last),locale),fontSize=10.sp,color=onSurface); Text(dateLabel(last,locale),fontSize=10.sp,color=onSurface) }
        Text(stringResource(R.string.history_range),fontSize=11.sp,color=onSurface)
    }
}

@Composable private fun LegendDot(color: Color) { Box(Modifier.size(7.dp).clip(CircleShape).background(color)) }
@Composable private fun LegendLine(color: Color, dotted: Boolean) {
    Canvas(Modifier.width(16.dp).height(8.dp)) { drawLine(color, androidx.compose.ui.geometry.Offset(0f,size.height/2), androidx.compose.ui.geometry.Offset(size.width,size.height/2), 1.5.dp.toPx(), pathEffect=if(dotted) PathEffect.dashPathEffect(floatArrayOf(2.dp.toPx(),3.dp.toPx())) else PathEffect.dashPathEffect(floatArrayOf(4.dp.toPx(),3.dp.toPx()))) }
}

@Composable internal fun CostsScreen(state: AppState) {
    val locale=LocalLocale.current.platformLocale
    val now=remember(state.demo) { if (state.demo) DemoData.referenceTime else Instant.now() }
    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(horizontal=20.dp,vertical=18.dp),verticalArrangement=Arrangement.spacedBy(18.dp)) {
        Column(verticalArrangement=Arrangement.spacedBy(3.dp)) {
            Text(stringResource(R.string.costs),fontSize=30.sp,fontWeight=FontWeight.Bold)
            Text(stringResource(R.string.cost_subtitle),fontSize=15.sp,color=MaterialTheme.colorScheme.onSurfaceVariant)
        }
        val reports=state.relay?.costs.orEmpty()
        if(reports.isEmpty()) {
            SoftCard(Modifier.fillMaxWidth()) { Text(stringResource(R.string.no_costs),color=MaterialTheme.colorScheme.onSurfaceVariant) }
        } else reports.forEach { report -> CostReportCard(report,locale,now,state.relay?.provider(report.providerID)?.first?.plan) }
        Spacer(Modifier.height(14.dp))
    }
}

@Composable private fun CostReportCard(report: CostReport, locale: Locale, now: Instant, plan: String? = null) {
    val zone=if (now == DemoData.referenceTime) DemoData.demoZone else ZoneId.systemDefault(); val day=now.atZone(zone).toLocalDate()
    val tint=if(report.providerID=="claude") Peach.copy(alpha=.38f) else Sky.copy(alpha=.36f)
    SoftCard(Modifier.fillMaxWidth(),tint=tint) {
        Row(Modifier.fillMaxWidth(),verticalAlignment=Alignment.CenterVertically) {
            ProviderBadge(report.providerID, 32)
            Spacer(Modifier.width(9.dp))
            Text(stringResource(if(report.providerID=="claude") R.string.provider_claude else R.string.provider_codex),fontSize=20.sp,fontWeight=FontWeight.SemiBold,modifier=Modifier.weight(1f))
            plan?.let { Text(planName(it),fontSize=12.sp,fontWeight=FontWeight.SemiBold,color=PastelInk,modifier=Modifier.clip(CircleShape).background(Color.White.copy(alpha=.45f)).padding(horizontal=10.dp,vertical=5.dp)) }
        }
        val today=report.total(1,day); val week=report.total(7,day); val month=report.total(30,day)
        Row(Modifier.fillMaxWidth(),horizontalArrangement=Arrangement.spacedBy(6.dp)) {
            CostTile(stringResource(R.string.today),today,locale,Modifier.weight(1f))
            CostTile(stringResource(R.string.seven_days),week,locale,Modifier.weight(1f))
            CostTile(stringResource(R.string.thirty_days),month,locale,Modifier.weight(1f))
        }
        if(month.unpricedTokens>0) Text(stringResource(R.string.unpriced_tokens,UsageFormat.tokenCount(month.unpricedTokens,locale)),fontSize=11.sp,color=MaterialTheme.colorScheme.onSurfaceVariant)
        Text(stringResource(R.string.daily_estimate),fontSize=15.sp,fontWeight=FontWeight.SemiBold)
        CostBarChart(report,now,locale)
        val models=report.models(30,day)
        if(models.isNotEmpty()) {
            Text(stringResource(R.string.top_models),fontSize=15.sp,fontWeight=FontWeight.SemiBold)
            models.take(5).forEach { model ->
                Row(Modifier.fillMaxWidth(),horizontalArrangement=Arrangement.spacedBy(8.dp),verticalAlignment=Alignment.CenterVertically) {
                    Column(Modifier.weight(1f),verticalArrangement=Arrangement.spacedBy(2.dp)) {
                        Text(modelName(model.model),fontSize=13.sp,fontWeight=FontWeight.Medium,maxLines=2,overflow=TextOverflow.Ellipsis)
                        Text(stringResource(R.string.model_tokens,UsageFormat.tokenCount(model.tokens.total,locale)),fontSize=11.sp,color=MaterialTheme.colorScheme.onSurfaceVariant)
                    }
                    Text(model.usd?.let { UsageFormat.moneyDisplay(it,locale) } ?: stringResource(R.string.unpriced),fontSize=13.sp,fontWeight=FontWeight.SemiBold)
                }
            }
        }
        Text(stringResource(R.string.api_disclaimer),fontSize=11.sp,color=MaterialTheme.colorScheme.onSurfaceVariant)
    }
}

@Composable private fun CostTile(title:String,total:CostTotal,locale:Locale,modifier:Modifier) {
    Column(modifier.clip(RoundedCornerShape(15.dp)).background(MaterialTheme.colorScheme.onSurface.copy(alpha=.045f)).padding(9.dp),verticalArrangement=Arrangement.spacedBy(4.dp)) {
        Text(title,fontSize=11.sp,color=MaterialTheme.colorScheme.onSurfaceVariant,maxLines=1)
        Text(UsageFormat.moneyDisplay(total.usd,locale),fontSize=14.sp,fontWeight=FontWeight.Bold,maxLines=1,overflow=TextOverflow.Clip)
    }
}

@Composable private fun CostBarChart(report:CostReport,now:Instant,locale:Locale) {
    val zone=if (now == DemoData.referenceTime) DemoData.demoZone else ZoneId.systemDefault(); val today=now.atZone(zone).toLocalDate(); val days=report.days.associateBy { runCatching { LocalDate.parse(it.day) }.getOrNull() }
    val points=(29 downTo 0).map { today.minusDays(it.toLong()) to (days[today.minusDays(it.toLong())]?.usd ?: 0.0) }
    val max=points.maxOfOrNull { it.second }?.coerceAtLeast(.01) ?: 1.0
    val color=MaterialTheme.colorScheme.primary
    val chartDescription=stringResource(R.string.daily_estimate)
    Canvas(Modifier.fillMaxWidth().height(112.dp).semantics { contentDescription = chartDescription }) {
        val gap=3.dp.toPx(); val barW=(size.width-gap*29)/30
        points.forEachIndexed { i,p -> val h=(p.second/max).toFloat()*size.height*.9f; drawRoundRect(color.copy(alpha=if(i==29)1f else .55f), androidx.compose.ui.geometry.Offset(i*(barW+gap),size.height-h), androidx.compose.ui.geometry.Size(barW,h), androidx.compose.ui.geometry.CornerRadius(2.dp.toPx())) }
    }
    Row(Modifier.fillMaxWidth(),horizontalArrangement=Arrangement.SpaceBetween) {
        Text(dateLabel(points.first().first.atStartOfDay(zone).toInstant(),locale),fontSize=10.sp,color=MaterialTheme.colorScheme.onSurfaceVariant)
        Text(dateLabel(points[14].first.atStartOfDay(zone).toInstant(),locale),fontSize=10.sp,color=MaterialTheme.colorScheme.onSurfaceVariant)
        Text(dateLabel(now,locale),fontSize=10.sp,color=MaterialTheme.colorScheme.onSurfaceVariant)
    }
}

@Composable internal fun SettingsScreen(state:AppState,choose:()->Unit,disconnect:()->Unit,changeMode:(UsageDisplayMode)->Unit,changeTheme:(String)->Unit) {
    val context=LocalContext.current
    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(horizontal=20.dp,vertical=18.dp),verticalArrangement=Arrangement.spacedBy(18.dp)) {
        Text(stringResource(R.string.settings),fontSize=30.sp,fontWeight=FontWeight.Bold)
        SectionTitle(stringResource(R.string.your_computer))
        SoftCard(Modifier.fillMaxWidth(),tint=Sky.copy(alpha=.32f)) {
            Text(state.fileName?.let { stringResource(R.string.connected_file,it) } ?: if(state.demo) stringResource(R.string.demo_label) else stringResource(R.string.no_file_connected),fontWeight=FontWeight.SemiBold)
            Text(stringResource(R.string.settings_hint),fontSize=12.sp,color=MaterialTheme.colorScheme.onSurfaceVariant)
            Button(onClick=choose,colors=ButtonDefaults.buttonColors(containerColor=Coral)){Text(stringResource(if(state.uri==null)R.string.choose_file else R.string.pick_again))}
            if(state.uri!=null) TextButton(onClick=disconnect){Text(stringResource(R.string.disconnect),color=Critical)}
            if(state.fileError) Text(stringResource(R.string.file_access),color=Critical)
        }
        SectionTitle(stringResource(R.string.display_title))
        SoftCard(Modifier.fillMaxWidth(),tint=Peach.copy(alpha=.28f)) {
            ModeToggle(state,changeMode)
            Text(stringResource(R.string.warning_description),fontSize=12.sp,color=MaterialTheme.colorScheme.onSurfaceVariant)
        }
        SectionTitle(stringResource(R.string.appearance))
        SoftCard(Modifier.fillMaxWidth(),tint=Pink.copy(alpha=.25f)) {
            Text(stringResource(R.string.theme),fontWeight=FontWeight.SemiBold)
            Row(horizontalArrangement=Arrangement.spacedBy(6.dp)) {
                listOf("system" to R.string.system,"light" to R.string.light,"dark" to R.string.dark).forEach { (value,label)->
                    FilterChip(selected=state.theme==value,onClick={changeTheme(value)},label={Text(stringResource(label))})
                }
            }
        }
        SectionTitle(stringResource(R.string.about))
        SoftCard(Modifier.fillMaxWidth()) {
            Text(stringResource(R.string.version))
            TextButton(onClick={context.startActivity(android.content.Intent(android.content.Intent.ACTION_VIEW,android.net.Uri.parse("https://github.com/p4ranoic0/AI-mana")))}){Text(stringResource(R.string.open_source))}
        }
        Spacer(Modifier.height(12.dp))
    }
}

@Composable private fun planName(plan:String):String=when(plan.lowercase(Locale.ROOT)) {
    "free"->stringResource(R.string.plan_free);"plus"->stringResource(R.string.plan_plus);"pro"->stringResource(R.string.plan_pro)
    "max"->stringResource(R.string.plan_max);"team"->stringResource(R.string.plan_team);"enterprise"->stringResource(R.string.plan_enterprise);else->plan
}
private fun providerShortName(id:String,fallback:String)=when(id){"claude"->"Claude";"codex"->"Codex";else->fallback}
private fun laneTint(providerID:String,kind:String):Color=when {
    providerID=="claude"&&kind=="session"->Peach
    providerID=="claude"->Pink
    providerID=="codex"&&kind=="session"->Sky
    else->Olive
}
@Composable private fun windowTitle(window:UsageWindow):String=when {
    window.kind=="session"->stringResource(R.string.window_session_title)
    window.kind=="weekly"->stringResource(R.string.window_weekly_title)
    window.kind.startsWith("model-session:")->stringResource(R.string.window_session_model,window.kind.removePrefix("model-session:"))
    window.kind.startsWith("model:")->stringResource(R.string.window_weekly_model,window.kind.removePrefix("model:"))
    window.kind=="monthly"->stringResource(R.string.window_monthly)
    window.kind=="spend-limit"->stringResource(R.string.window_spend_limit)
    window.kind=="free-requests"->stringResource(R.string.window_free_requests)
    else->window.kind
}
@Composable private fun windowCompact(window:UsageWindow):String=when(window.kind){"session"->window.windowMinutes?.let{stringResource(R.string.compact_hours,it/60)}?:"";"weekly"->window.windowMinutes?.let{stringResource(R.string.compact_days,it/1440)}?:"";else->window.kind.substringAfter(':')}
@Composable private fun countdownText(reset:Instant?,now:Instant):String {
    if(reset==null)return ""
    val minutes=ceil((reset.epochSecond-now.epochSecond).coerceAtLeast(0)/60.0).toLong()
    val days=minutes/1440;val hours=minutes/60%24;val mins=minutes%60
    val d=stringResource(R.string.unit_day);val h=stringResource(R.string.unit_hour);val m=stringResource(R.string.unit_minute)
    return when { days>0&&hours>0->"$days$d $hours$h";days>0&&mins>0->"$days$d $mins$m";days>0->"$days$d";hours>0&&mins>0->"$hours$h $mins$m";hours>0->"$hours$h";else->"${mins.coerceAtLeast(1)}$m"}
}
private fun relativeAge(seconds:Long)=when{seconds<3600->"${seconds/60}m";seconds<86400->"${seconds/3600}h";else->"${seconds/86400}d"}
@Composable private fun budgetHeadline(budget:DailyBudget,locale:Locale):String=when(budget.status){
    DailyBudget.Status.SPREAD->stringResource(R.string.budget_per_day,UsageFormat.percent(budget.perDayPercent,locale))
    DailyBudget.Status.LAST_DAY->stringResource(R.string.budget_until_reset,UsageFormat.percent(budget.perDayPercent,locale))
    DailyBudget.Status.DEPLETED->stringResource(R.string.budget_used_up)
    DailyBudget.Status.OUTDATED->stringResource(R.string.status_outdated)
}
@Composable private fun budgetCaption(budget:DailyBudget,now:Instant):String=when(budget.status){
    DailyBudget.Status.SPREAD->stringResource(R.string.budget_next,countdownText(budget.resetsAt,now))
    DailyBudget.Status.LAST_DAY,DailyBudget.Status.DEPLETED->stringResource(R.string.reset_in,countdownText(budget.resetsAt,now))
    DailyBudget.Status.OUTDATED->stringResource(R.string.budget_refresh)
}
private fun axisTime(time:Instant,window:UsageWindow,locale:Locale):String {
    val z=time.atZone(ZoneId.systemDefault())
    return if((window.windowMinutes ?: 10080)<=1440) DateTimeFormatter.ofLocalizedTime(java.time.format.FormatStyle.SHORT).withLocale(locale).format(z)
    else DateTimeFormatter.ofLocalizedDate(FormatStyle.MEDIUM).withLocale(locale).format(z)
}
private fun dateLabel(time:Instant,locale:Locale)=DateTimeFormatter.ofLocalizedDate(FormatStyle.MEDIUM).withLocale(locale).format(time.atZone(ZoneId.systemDefault()))
private fun dateLabel(date:LocalDate,locale:Locale)=DateTimeFormatter.ofLocalizedDate(FormatStyle.MEDIUM).withLocale(locale).format(date)
private fun midPoint(a:Instant,b:Instant)=a.plusSeconds((b.epochSecond-a.epochSecond)/2)
private fun modelName(id:String):String {
    val parts=id.split('-').toMutableList();if(parts.lastOrNull()?.length==8&&parts.last().all(Char::isDigit))parts.removeAt(parts.lastIndex)
    if(parts.firstOrNull()=="claude"&&parts.size>=2){val family=parts[1].replaceFirstChar{it.uppercase()};val version=parts.drop(2).filter{it.all(Char::isDigit)}.joinToString(".");return if(version.isEmpty())family else "$family $version"}
    if(parts.firstOrNull()=="gpt")return (listOf("GPT")+parts.drop(1).map{it.replaceFirstChar{c->c.uppercase()}}).joinToString("-")
    return id
}
@Composable private fun detailSummary(detail:UsageDetail,locale:Locale):String {
    val amount=detail.remaining.let { NumberFormat.getNumberInstance(locale).format(it) }
    return when(detail.kind){
        "extraUsage"->"${stringResource(R.string.extra_usage)} · ${UsageFormat.moneyDisplay(detail.remaining,locale)}"
        else->"${detail.kind} · $amount ${detail.currency.orEmpty()}"
    }
}
