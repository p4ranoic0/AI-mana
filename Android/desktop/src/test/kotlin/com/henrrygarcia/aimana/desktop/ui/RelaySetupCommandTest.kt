package com.henrrygarcia.aimana.desktop.ui

import java.nio.file.Path
import org.junit.Assert.assertEquals
import org.junit.Test

class RelaySetupCommandTest {
    @Test fun settingsSetupKeepsTheChosenFolderAndNeverSchedules() {
        val synced = Path.of("C:/Profiles/alex/OneDrive/AImana/usage-relay.json")
        assertEquals(listOf("cmd", "/c", "start", "\"AI·mana setup\"", "cmd", "/k", "C:/AImana/usage-relay.exe", "setup", "--no-schedule",
                            "--output", synced.toString()),
                     relaySetupCommand("C:/AImana/usage-relay.exe", windows = true, output = synced))
        assertEquals(listOf("x-terminal-emulator", "-e", "/usr/bin/usage-relay", "setup", "--no-schedule"),
                     relaySetupCommand("/usr/bin/usage-relay", windows = false, output = null))
    }
}
