package com.henrrygarcia.aimana

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.compose.LocalActivity
import androidx.activity.result.contract.ActivityResultContracts
import androidx.activity.enableEdgeToEdge
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.detectVerticalDragGestures
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalContext
import androidx.core.view.WindowInsetsControllerCompat
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.res.pluralStringResource
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.datastore.preferences.core.*
import androidx.datastore.preferences.preferencesDataStore
import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.rememberNavController
import androidx.navigation.compose.currentBackStackEntryAsState
import com.henrrygarcia.aimana.core.*
import com.henrrygarcia.aimana.core.DisplayMode as UsageDisplayMode
import java.time.Instant
import java.time.LocalDate
import java.util.Locale
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.launch
import androidx.lifecycle.viewModelScope
import kotlinx.coroutines.withContext

private val Context.prefs by preferencesDataStore("settings")
private val URI_KEY = stringPreferencesKey("relay_uri")
private val MODE_KEY = stringPreferencesKey("display_mode")
private val THEME_KEY = stringPreferencesKey("theme")
private val Coral = Color(0xFFE17865)
private val Ink = ContrastPalette.lightText
private val Cream = ContrastPalette.lightCanvas
private val Muted = ContrastPalette.lightMuted
private val Mint = Color(0xFF72AA90)

data class AppState(val relay: RelayEnvelope? = null, val uri: String? = null, val fileName: String? = null,
    val mode: UsageDisplayMode = UsageDisplayMode.USED, val theme: String = "system", val demo: Boolean = false,
    val loading: Boolean = false, val fileError: Boolean = false)

class AppModel(private val context: Context, demo: Boolean): ViewModel() {
    private val _state = MutableStateFlow(AppState(demo = demo))
    val state = _state.asStateFlow()
    init { viewModelScope.launch {
        val settings = context.prefs.data.first()
        _state.value = _state.value.copy(uri = settings[URI_KEY], mode = if (settings[MODE_KEY] == "remaining") UsageDisplayMode.REMAINING else UsageDisplayMode.USED, theme = settings[THEME_KEY] ?: "system")
        refresh()
    } }
    fun refresh() { viewModelScope.launch {
        if (_state.value.demo) { _state.value = _state.value.copy(relay = DemoData.envelope(), loading = false, fileError = false); return@launch }
        val uri = _state.value.uri ?: run { _state.value = _state.value.copy(relay = null); return@launch }
        _state.value = _state.value.copy(loading = true)
        val result = withContext(Dispatchers.IO) { runCatching {
            val stream = context.contentResolver.openInputStream(Uri.parse(uri)) ?: error("Missing file")
            stream.bufferedReader().use { RelayCodec.decode(it.readText()) }
        } }
        _state.value = _state.value.copy(relay = result.getOrNull(), loading = false, fileError = result.isFailure,
            fileName = runCatching { Uri.parse(uri).lastPathSegment?.substringAfterLast('/') }.getOrNull())
    } }
    fun select(uri: Uri) { viewModelScope.launch {
        runCatching { context.contentResolver.takePersistableUriPermission(uri, Intent.FLAG_GRANT_READ_URI_PERMISSION) }
        context.prefs.edit { it[URI_KEY] = uri.toString() }
        _state.value = _state.value.copy(uri = uri.toString(), fileError = false)
        refresh()
    } }
    fun disconnect() { viewModelScope.launch {
        _state.value.uri?.let { runCatching { context.contentResolver.releasePersistableUriPermission(Uri.parse(it), Intent.FLAG_GRANT_READ_URI_PERMISSION) } }
        context.prefs.edit { it.remove(URI_KEY) }
        _state.value = _state.value.copy(uri = null, relay = null, fileError = false, fileName = null)
    } }
    fun mode(mode: UsageDisplayMode) { viewModelScope.launch { context.prefs.edit { it[MODE_KEY] = mode.name.lowercase() }; _state.value = _state.value.copy(mode = mode) } }
    fun theme(theme: String) { viewModelScope.launch { context.prefs.edit { it[THEME_KEY] = theme }; _state.value = _state.value.copy(theme = theme) } }
}

class MainActivity: ComponentActivity() {
    private lateinit var model: AppModel
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        model = ViewModelProvider(this, object: ViewModelProvider.Factory {
            @Suppress("UNCHECKED_CAST") override fun <T: ViewModel> create(modelClass: Class<T>): T = AppModel(applicationContext, intent.getBooleanExtra("demo", false)) as T
        })[AppModel::class.java]
        setContent { App(model) }
    }
    override fun onResume() { super.onResume(); if (::model.isInitialized) model.refresh() }
}

@Composable private fun App(model: AppModel) {
    val state by model.state.collectAsStateWithLifecycle()
    val dark = when (state.theme) { "dark" -> true; "light" -> false; else -> androidx.compose.foundation.isSystemInDarkTheme() }
    val background = if (dark) ContrastPalette.darkCanvas else Cream
    val surface = if (dark) ContrastPalette.darkCard else ContrastPalette.lightCard
    val text = if (dark) ContrastPalette.darkText else Ink
    val scheme = if (dark) darkColorScheme(primary = Coral, background = background, surface = surface, onSurface = text, onBackground = text, secondaryContainer = Coral.copy(alpha = 0.18f), onSecondaryContainer = text, onPrimary = Color.White, onSurfaceVariant = ContrastPalette.darkMuted, outline = Color(0xFF777D76))
                 else lightColorScheme(primary = Coral, background = background, surface = surface, onSurface = text, onBackground = text, secondaryContainer = Coral.copy(alpha = 0.18f), onSecondaryContainer = text, onPrimary = Color.White, onSurfaceVariant = Muted, outline = Muted.copy(alpha = 0.5f))
    val picker = rememberLauncherForActivityResult(ActivityResultContracts.OpenDocument()) { uri -> if (uri != null) model.select(uri) }
    val choose = { picker.launch(arrayOf("application/json", "*/*")) }
    val nav = rememberNavController()
    val entry by nav.currentBackStackEntryAsState()
    val route = entry?.destination?.route
    val activity = LocalActivity.current
    val initialRoute = remember { when (activity?.intent?.getStringExtra("open_screen")) {
        "costs" -> "costs"
        "detail" -> "detail/${activity.intent.getStringExtra("provider") ?: "claude"}"
        else -> "home"
    } }
    SideEffect {
        activity?.let { WindowInsetsControllerCompat(it.window, it.window.decorView).apply {
            isAppearanceLightStatusBars = !dark
            isAppearanceLightNavigationBars = !dark
        } }
    }
    MaterialTheme(colorScheme = scheme) {
        Scaffold(containerColor = background, bottomBar = {
            AppBottomBar(route = route, navigate = { destination ->
                nav.navigate(destination) { popUpTo("home") { saveState = true }; launchSingleTop = true; restoreState = true }
            }, refresh = model::refresh)
        }) { padding ->
            NavHost(navController = nav, startDestination = initialRoute, modifier = Modifier.padding(padding)) {
                composable("home") { HomeScreen(state, choose, model::refresh, model::mode, { id -> nav.navigate("detail/$id") }) }
                composable("detail/{id}") { back -> DetailScreen(state, back.arguments?.getString("id") ?: "claude", { nav.popBackStack() }) }
                composable("costs") { CostsScreen(state) }
                composable("settings") { SettingsScreen(state, choose, model::disconnect, model::mode, model::theme) }
            }
        }
    }
}
