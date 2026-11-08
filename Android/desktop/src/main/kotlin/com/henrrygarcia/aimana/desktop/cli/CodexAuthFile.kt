package com.henrrygarcia.aimana.desktop.cli

import com.henrrygarcia.aimana.core.providers.AccessCredential
import com.henrrygarcia.aimana.core.providers.AccessTokenSource
import com.henrrygarcia.aimana.core.providers.UsageError
import java.nio.file.Files
import java.time.Instant
import java.util.Base64
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.doubleOrNull

/// Reads the session the Codex CLI keeps in `auth.json`. Read-only, re-read on every call, never renewed: an expired
/// token means "sign in to Codex", and a keyring store is reported as such, not as a sign-out.
class CodexAuthFile(private val paths: CliPaths) : AccessTokenSource {
    override suspend fun credentials(): AccessCredential {
        val file = paths.codexHome.resolve("auth.json")
        if (!Files.isRegularFile(file)) {
            throw if (keepsSessionOutsideFile()) UsageError.UnsupportedCredentialStore else UsageError.Unauthenticated
        }
        val root = runCatching { Json.parseToJsonElement(Files.readString(file)) as JsonObject }.getOrNull()
            ?: throw UsageError.Unauthenticated
        // An API-key login has no subscription quota to read.
        val mode = (root["auth_mode"] as? JsonPrimitive)?.contentOrNull
        if (mode != null && mode != "chatgpt") throw UsageError.Unauthenticated
        val tokens = root["tokens"] as? JsonObject ?: throw UsageError.Unauthenticated
        val access = (tokens["access_token"] as? JsonPrimitive)?.contentOrNull?.takeIf { it.isNotEmpty() }
            ?: throw UsageError.Unauthenticated
        if (jwtExpiry(access)?.let { !it.isAfter(Instant.now()) } == true) throw UsageError.Unauthenticated
        return AccessCredential(access, (tokens["account_id"] as? JsonPrimitive)?.contentOrNull)
    }

    /// `cli_auth_credentials_store = "keyring"` or `"auto"` in `config.toml`, with an optional trailing comment.
    private fun keepsSessionOutsideFile(): Boolean {
        val config = paths.codexHome.resolve("config.toml")
        if (!Files.isRegularFile(config)) return false
        return Files.readAllLines(config).any { line ->
            val parts = line.split("=", limit = 2).map { it.trim() }
            if (parts.size != 2 || parts[0] != "cli_auth_credentials_store") return@any false
            val raw = parts[1]
            val value = if (raw.startsWith("\"") || raw.startsWith("'")) raw.drop(1).takeWhile { it != raw[0] }
                        else raw.takeWhile { it != '#' }
            value.trim() == "keyring" || value.trim() == "auto"
        }
    }

    companion object {
        fun jwtExpiry(jwt: String): Instant? {
            val payload = jwt.split(".").getOrNull(1) ?: return null
            val json = runCatching { String(Base64.getUrlDecoder().decode(payload.padEnd((payload.length + 3) / 4 * 4, '='))) }
                .getOrNull() ?: return null
            val exp = runCatching { (Json.parseToJsonElement(json) as JsonObject)["exp"] as? JsonPrimitive }.getOrNull()?.doubleOrNull
            return exp?.let { Instant.ofEpochSecond(it.toLong()) }
        }
    }
}
