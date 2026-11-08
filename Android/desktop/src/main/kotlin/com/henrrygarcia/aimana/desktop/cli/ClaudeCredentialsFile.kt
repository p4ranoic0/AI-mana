package com.henrrygarcia.aimana.desktop.cli

import com.henrrygarcia.aimana.core.providers.AccessCredential
import com.henrrygarcia.aimana.core.providers.AccessTokenSource
import com.henrrygarcia.aimana.core.providers.UsageError
import java.nio.file.Files
import java.time.Instant
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.doubleOrNull

/// Claude Code's sign-in file, `.credentials.json`. The file also holds other tools' secrets (`mcpOAuth`): only the
/// `claudeAiOauth` fields AI·mana needs are kept, and the file is never written or logged.
class ClaudeCredentialsFile(private val paths: CliPaths) : AccessTokenSource {
    /// Only `accessToken`, `expiresAt` (ms) and `subscriptionType`.
    data class OAuth(val accessToken: String?, val expiresAt: Instant?, val subscriptionType: String?) {
        override fun toString() = "OAuth(accessToken=<redacted>, expiresAt=$expiresAt, subscriptionType=$subscriptionType)"
    }

    fun readOAuth(): OAuth? {
        val file = paths.claudeConfigDir.resolve(".credentials.json")
        if (!Files.isRegularFile(file)) return null
        val block = runCatching { (Json.parseToJsonElement(Files.readString(file)) as JsonObject)["claudeAiOauth"] as? JsonObject }
            .getOrNull() ?: return null
        fun string(key: String) = (block[key] as? JsonPrimitive)?.contentOrNull
        val expires = (block["expiresAt"] as? JsonPrimitive)?.doubleOrNull?.let { Instant.ofEpochMilli(it.toLong()) }
        return OAuth(string("accessToken"), expires, string("subscriptionType"))
    }

    override suspend fun credentials(): AccessCredential {
        val oauth = readOAuth() ?: throw UsageError.Unauthenticated
        val token = oauth.accessToken?.takeIf { it.isNotEmpty() } ?: throw UsageError.Unauthenticated
        // Expired: report "sign in needed" instead of sending a dead token.
        if (oauth.expiresAt?.let { !it.isAfter(Instant.now()) } == true) throw UsageError.Unauthenticated
        return AccessCredential(token, plan = oauth.subscriptionType)
    }
}
