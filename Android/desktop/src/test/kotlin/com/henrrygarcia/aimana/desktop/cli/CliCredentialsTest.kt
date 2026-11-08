package com.henrrygarcia.aimana.desktop.cli

import com.henrrygarcia.aimana.core.providers.UsageError
import java.nio.file.Files
import java.nio.file.Path
import java.security.MessageDigest
import java.time.Instant
import java.util.Base64
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.fail
import org.junit.Test

private val fixtures: Path = Path.of("../../AImana/Fixtures/parity")

class CliCredentialsTest {
    private val home: Path = Files.createTempDirectory("aimana-cli-test")
    private fun paths(env: Map<String, String> = emptyMap()) = CliPaths(home, env, isWindows = false)
    private fun write(relative: String, text: String): Path =
        home.resolve(relative).also { Files.createDirectories(it.parent); Files.writeString(it, text) }
    private fun copyFixture(name: String, relative: String) = write(relative, Files.readString(fixtures.resolve(name)))
    private fun jwt(exp: Instant): String {
        val payload = Base64.getUrlEncoder().withoutPadding().encodeToString("""{"exp":${exp.epochSecond}}""".toByteArray())
        return "eyJhbGciOiJub25lIn0.$payload."
    }
    private fun sha(path: Path) = MessageDigest.getInstance("SHA-256").digest(Files.readAllBytes(path)).joinToString("") { "%02x".format(it) }
    private suspend fun expectError(block: suspend () -> Unit): UsageError =
        try { block(); fail("expected a UsageError"); throw IllegalStateException() } catch (e: UsageError) { e }

    @Test fun readsDefaultHome() = runBlocking {
        copyFixture("codex-auth-file.json", ".codex/auth.json")
        assertEquals("acct-fake", CodexAuthFile(paths()).credentials().accountID)
    }

    @Test fun codexHonorsCodexHome() = runBlocking {
        copyFixture("codex-auth-file.json", "custom-codex/auth.json")
        val paths = paths(mapOf("CODEX_HOME" to home.resolve("custom-codex").toString()))
        assertEquals("acct-fake", CodexAuthFile(paths).credentials().accountID)
    }

    @Test fun codexExpiredIsUnauthenticated() = runBlocking {
        write(".codex/auth.json", """{"auth_mode":"chatgpt","tokens":{"access_token":"${jwt(Instant.now().minusSeconds(60))}","account_id":"a"}}""")
        assertEquals(UsageError.Unauthenticated, expectError { CodexAuthFile(paths()).credentials() })
    }

    @Test fun codexKeyringIsUnsupported() = runBlocking {
        write(".codex/config.toml", "model = \"x\"\ncli_auth_credentials_store = \"keyring\"\n")
        assertEquals(UsageError.UnsupportedCredentialStore, expectError { CodexAuthFile(paths()).credentials() })
    }

    @Test fun codexKeyringWithInlineCommentIsUnsupported() = runBlocking {
        write(".codex/config.toml", "cli_auth_credentials_store = \"auto\"   # keep it in the OS keyring\n")
        assertEquals(UsageError.UnsupportedCredentialStore, expectError { CodexAuthFile(paths()).credentials() })
    }

    @Test fun codexApiKeyModeIsUnauthenticated() = runBlocking {
        write(".codex/auth.json", """{"auth_mode":"apikey","OPENAI_API_KEY":"sk-fake"}""")
        assertEquals(UsageError.Unauthenticated, expectError { CodexAuthFile(paths()).credentials() })
    }

    @Test fun codexMissingIsUnauthenticated() = runBlocking {
        assertEquals(UsageError.Unauthenticated, expectError { CodexAuthFile(paths()).credentials() })
    }

    @Test fun claudeFileReadsOnlyClaudeBlock() = runBlocking {
        copyFixture("claude-credentials-file.json", ".claude/.credentials.json")
        val credential = ClaudeCredentialsFile(paths()).credentials()
        assertEquals("fake-claude-access", credential.token)
        assertEquals("max", credential.plan)
        val oauth = ClaudeCredentialsFile(paths()).readOAuth()!!
        assertFalse(oauth.toString().contains("fake-mcp-secret"))
        assertFalse(oauth.toString().contains("mcpOAuth"))
        assertFalse(credential.toString().contains("fake-claude-access"))
    }

    @Test fun claudeFileHonorsConfigDir() = runBlocking {
        copyFixture("claude-credentials-file.json", "alt-claude/.credentials.json")
        val paths = paths(mapOf("CLAUDE_CONFIG_DIR" to home.resolve("alt-claude").toString()))
        assertEquals("fake-claude-access", ClaudeCredentialsFile(paths).credentials().token)
    }

    @Test fun claudeExpiredIsUnauthenticated() = runBlocking {
        write(".claude/.credentials.json", """{"claudeAiOauth":{"accessToken":"old","expiresAt":${Instant.now().minusSeconds(60).toEpochMilli()}}}""")
        assertEquals(UsageError.Unauthenticated, expectError { ClaudeCredentialsFile(paths()).credentials() })
    }

    @Test fun readersNeverWrite() = runBlocking {
        val claude = copyFixture("claude-credentials-file.json", ".claude/.credentials.json")
        val codex = copyFixture("codex-auth-file.json", ".codex/auth.json")
        val before = sha(claude) to sha(codex)
        repeat(3) { ClaudeCredentialsFile(paths()).credentials(); CodexAuthFile(paths()).credentials() }
        assertEquals(before, sha(claude) to sha(codex))
    }

    @Test fun windowsPathsUseUserProfile() {
        val paths = CliPaths(Path.of("C:/Profiles/alex"), mapOf("LOCALAPPDATA" to "C:/Profiles/alex/AppData/Local"), isWindows = true)
        assertEquals(Path.of("C:/Profiles/alex/.codex"), paths.codexHome)
        assertEquals(Path.of("C:/Profiles/alex/.claude"), paths.claudeConfigDir)
        assertEquals(Path.of("C:/Profiles/alex/AppData/Local/AImana"), paths.stateDir)
    }
}
