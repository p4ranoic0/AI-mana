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
import com.henrrygarcia.aimana.core.auth.ClaudeLoginRequest
import com.henrrygarcia.aimana.core.auth.ClaudeOAuth
import com.henrrygarcia.aimana.core.auth.CodexDeviceCode
import com.henrrygarcia.aimana.core.auth.CodexLoginException
import com.henrrygarcia.aimana.core.auth.CodexLoginRequest
import com.henrrygarcia.aimana.core.auth.CodexOAuth
import com.henrrygarcia.aimana.core.providers.CopilotAllowance
import com.henrrygarcia.aimana.core.providers.CopilotClient
import com.henrrygarcia.aimana.core.providers.CopilotPlan
import com.henrrygarcia.aimana.core.providers.UsageError
import com.henrrygarcia.aimana.core.storage.FileKeyValueStore
import com.henrrygarcia.aimana.net.AndroidHttpTransport
import com.henrrygarcia.aimana.security.KeystoreCredentialStore
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
    val loading: Boolean = false, val fileError: Boolean = false,
    /// Providers shown from the relay because direct access failed (error code).
    val notes: Map<String, String> = emptyMap(),
    val signedIn: Set<DirectProvider> = emptySet(), val consented: Set<DirectProvider> = emptySet(),
    val claudeLogin: ClaudeLoginRequest? = null, val codexDevice: CodexDeviceCode? = null,
    /// ChatGPT's browser fallback (PKCE): waiting for the pasted address of the page it lands on.
    val codexBrowser: CodexLoginRequest? = null,
    /// A sign-in problem to show under that provider's section.
    val loginError: Pair<DirectProvider, Int>? = null,
    /// API providers with a key saved on this phone, the one being checked, and the last result (provider → message).
    val apiKeys: Set<String> = emptySet(), val savingKey: String? = null, val keyMessage: Pair<String, Int>? = null,
    val copilot: CopilotAllowance = CopilotAllowance(CopilotPlan.PRO),
    /// A newer public release, and whether this phone asks GitHub for one once a day.
    val update: AppUpdate? = null, val updateChecks: Boolean = true)

class AppModel(private val context: Context, demo: Boolean): ViewModel() {
    private val _state = MutableStateFlow(AppState(demo = demo))
    val state = _state.asStateFlow()
    /// This phone's own sign-ins (encrypted with the Keystore) and the direct-access consent.
    private val direct = DirectServices(KeystoreCredentialStore(context),
        FileKeyValueStore(java.io.File(context.filesDir, "direct-preferences.json").toPath()), AndroidHttpTransport())
    private var codexLogin: kotlinx.coroutines.Job? = null
    val appVersion: String = runCatching { context.packageManager.getPackageInfo(context.packageName, 0).versionName }.getOrNull() ?: ""
    private val updates = UpdateCheck(AndroidHttpTransport(), appVersion,
        FileKeyValueStore(java.io.File(context.filesDir, "updates.json").toPath()))

    /// At most one request a day (the check remembers); never while showing the demo.
    private fun checkUpdates() { if (_state.value.demo) return; viewModelScope.launch {
        val update = withContext(Dispatchers.IO) { updates.refresh() }
        _state.value = _state.value.copy(update = update, updateChecks = updates.enabled)
    } }

    fun updateChecks(on: Boolean) {
        updates.enabled = on
        _state.value = _state.value.copy(updateChecks = on, update = updates.available())
        if (on) checkUpdates()
    }

    private fun directFlags() = _state.value.copy(
        signedIn = DirectProvider.entries.filter { if (it == DirectProvider.CLAUDE) direct.claudeTokens.isSignedIn else direct.codexTokens.isSignedIn }.toSet(),
        consented = DirectProvider.entries.filter(direct.consent::isGranted).toSet(),
        apiKeys = direct.apiProviders.map { it.id }.filter(direct::hasKey).toSet(), copilot = direct.copilotAllowance)

    val apiProviders get() = direct.apiProviders

    fun saveKey(id: String, key: String) { viewModelScope.launch {
        _state.value = _state.value.copy(savingKey = id, keyMessage = null)
        val message = try {
            withContext(Dispatchers.IO) { direct.saveKey(id, key) }
            R.string.key_saved
        } catch (e: kotlinx.coroutines.CancellationException) {
            throw e
        } catch (e: UsageError.Unauthenticated) {
            R.string.key_rejected
        } catch (e: Exception) {
            R.string.key_check_failed
        }
        _state.value = withContext(Dispatchers.IO) { directFlags() }.copy(savingKey = null, keyMessage = id to message)
        if (message == R.string.key_saved) refresh()
    } }

    fun removeKey(id: String) { viewModelScope.launch {
        withContext(Dispatchers.IO) { direct.removeKey(id) }
        _state.value = directFlags().copy(relay = withoutReading(id), keyMessage = null)
        refresh()
    } }

    fun copilotAllowance(allowance: CopilotAllowance) {
        direct.copilotAllowance = allowance
        _state.value = directFlags()
        if (CopilotClient.PROVIDER_ID in _state.value.apiKeys) refresh()
    }
    init { viewModelScope.launch {
        val settings = context.prefs.data.first()
        _state.value = _state.value.copy(uri = settings[URI_KEY], mode = if (settings[MODE_KEY] == "remaining") UsageDisplayMode.REMAINING else UsageDisplayMode.USED, theme = settings[THEME_KEY] ?: "system")
        refresh()
    } }
    /// Only the newest refresh publishes: an older one finishing late must not overwrite it.
    private var refreshes = 0

    /// Drops a provider's reading at once (sign-out, key removed); the refresh that follows brings back the relay's.
    private fun withoutReading(id: String) = _state.value.relay?.let { relay -> relay.copy(entries = relay.entries.filter { it.providerID != id }) }

    fun refresh() { val mine = ++refreshes; checkUpdates(); viewModelScope.launch {
        if (_state.value.demo) { _state.value = _state.value.copy(relay = DemoData.envelope(), loading = false, fileError = false); return@launch }
        _state.value = directFlags().copy(loading = true)
        val uri = _state.value.uri
        val result = if (uri == null) null else withContext(Dispatchers.IO) { runCatching {
            val stream = context.contentResolver.openInputStream(Uri.parse(uri)) ?: error("Missing file")
            stream.bufferedReader().use { RelayCodec.decode(it.readText()) }
        } }
        // Direct readings (with consent) on top of the relay; the relay alone otherwise.
        val merged = withContext(Dispatchers.IO) { direct.merge(result?.getOrNull()) }
        if (mine != refreshes) return@launch
        _state.value = directFlags().copy(relay = merged.envelope, notes = merged.notes, loading = false,
            fileError = result?.isFailure == true,
            fileName = uri?.let { runCatching { Uri.parse(it).lastPathSegment?.substringAfterLast('/') }.getOrNull() })
    } }

    fun grantConsent(provider: DirectProvider) { direct.consent.grant(provider); _state.value = directFlags(); refresh() }

    fun signOut(provider: DirectProvider) { viewModelScope.launch {
        if (provider == DirectProvider.CODEX) codexCancel()
        direct.signOut(provider)
        _state.value = directFlags().copy(relay = withoutReading(provider.id), claudeLogin = null, loginError = null)
        refresh()
    } }

    /// Claude: the page shows `code#state`; the user pastes it back.
    fun claudeBegin(): String {
        val request = ClaudeOAuth.beginLogin()
        _state.value = _state.value.copy(claudeLogin = request, loginError = null)
        return request.url
    }

    fun claudeConnect(pasted: String) { viewModelScope.launch {
        val request = _state.value.claudeLogin ?: return@launch
        try {
            val code = ClaudeOAuth.parsePastedCode(pasted, request.state)
            direct.claudeTokens.save(ClaudeOAuth.exchange(code, request, AndroidHttpTransport()))
            _state.value = directFlags().copy(claudeLogin = null, loginError = null)
            refresh()
        } catch (e: Exception) {
            _state.value = _state.value.copy(loginError = DirectProvider.CLAUDE to R.string.login_failed)
        }
    } }

    /// ChatGPT: device code; the polling stops when cancelled or when the app goes away.
    fun codexStart() { codexLogin?.cancel(); codexLogin = viewModelScope.launch {
        val transport = AndroidHttpTransport()
        try {
            val device = CodexOAuth.requestDeviceCode(transport)
            _state.value = _state.value.copy(codexDevice = device, loginError = null)
            direct.codexTokens.save(CodexOAuth.completeDeviceLogin(device, transport))
            _state.value = directFlags().copy(codexDevice = null)
            refresh()
        } catch (e: kotlinx.coroutines.CancellationException) {
            throw e
        } catch (e: CodexLoginException) {
            val message = if (e.reason == CodexLoginException.Reason.EXPIRED) R.string.code_expired else R.string.device_unavailable
            _state.value = _state.value.copy(codexDevice = null, loginError = DirectProvider.CODEX to message)
        } catch (e: Exception) {
            _state.value = _state.value.copy(codexDevice = null, loginError = DirectProvider.CODEX to R.string.login_failed)
        }
    } }

    fun codexCancel() { codexLogin?.cancel(); codexLogin = null; _state.value = _state.value.copy(codexDevice = null, codexBrowser = null) }

    /// ChatGPT browser fallback, for accounts without device-code sign-in.
    fun codexBrowserBegin(): String {
        codexCancel()
        val request = CodexOAuth.beginBrowserLogin()
        _state.value = _state.value.copy(codexBrowser = request, loginError = null)
        return request.url
    }

    fun codexBrowserConnect(pasted: String) { viewModelScope.launch {
        val request = _state.value.codexBrowser ?: return@launch
        try {
            val code = CodexOAuth.parsePastedRedirect(pasted, request.state)
            direct.codexTokens.save(CodexOAuth.exchange(code, request, AndroidHttpTransport()))
            _state.value = directFlags().copy(codexBrowser = null, loginError = null)
            refresh()
        } catch (e: kotlinx.coroutines.CancellationException) {
            throw e
        } catch (e: Exception) {
            _state.value = _state.value.copy(loginError = DirectProvider.CODEX to R.string.address_failed)
        }
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
                composable("settings") { SettingsScreen(state, choose, model::disconnect, model::mode, model::theme, model) }
            }
        }
    }
}
