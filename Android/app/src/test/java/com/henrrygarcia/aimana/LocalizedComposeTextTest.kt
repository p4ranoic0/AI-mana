package com.henrrygarcia.aimana

import java.io.File
import org.junit.Assert.assertTrue
import org.junit.Test

class LocalizedComposeTextTest {
    @Test fun composablesDoNotPassLiteralCopyToTextOrAccessibilityLabels() {
        val source = File("src/main/java/com/henrrygarcia/aimana")
        assertTrue("Compose source directory should be available to unit tests", source.isDirectory)
        val literalText = Regex("\\bText\\s*\\(\\s*\"(?=[^\"$]*[A-Za-z])[^\"$]*\"")
        val literalAccessibility = Regex("contentDescription\\s*=\\s*\"(?=[^\"$]*[A-Za-z])[^\"$]*\"")
        val violations = source.walkTopDown().filter { it.isFile && it.extension == "kt" }.flatMap { file ->
            val lines = file.readLines()
            lines.mapIndexedNotNull { index, line ->
                if (literalText.containsMatchIn(line) || literalAccessibility.containsMatchIn(line))
                    "${file.name}:${index + 1}: $line" else null
            }
        }.toList()
        assertTrue("Hard-coded user-facing text must use string resources:\n${violations.joinToString("\n")}", violations.isEmpty())
    }
}
