package com.henrrygarcia.aimana.core

import java.io.File
import org.junit.Assert.assertEquals
import org.junit.Test

/// `:core` runs on Android from API 26 (minSdk), but it is a plain JVM module, so Android lint does not see it. These
/// Java APIs compile fine on JDK 17 and crash on most phones (`NoSuchMethodError`); `api-versions.xml` lists when each
/// arrived on Android.
class AndroidApiLevelTest {
    private val newerThanMinSdk = mapOf(
        "Files.readString(" to "36.1", "Files.writeString(" to "36.1", "Path.of(" to "36.1",
        "URLEncoder.encode(" to "33 with a Charset", "URLDecoder.decode(" to "33 with a Charset",
    )

    @Test fun coreUsesOnlyApisAvailableOnApi26() {
        val offenders = File("src/main/kotlin").walk().filter { it.extension == "kt" }.flatMap { file ->
            file.readLines().withIndex().flatMap { (index, line) ->
                newerThanMinSdk.keys.filter { api ->
                    api in line && !(api.startsWith("URL") && line.contains("\"UTF-8\""))
                }.map { "${file.name}:${index + 1} $it (Android ${newerThanMinSdk[it]})" }
            }
        }.toList()
        assertEquals(emptyList<String>(), offenders)
    }
}
