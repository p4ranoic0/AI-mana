package com.henrrygarcia.aimana

import org.junit.Assert.assertEquals
import org.junit.Test

class ProviderPresentationTest {
    @Test fun signInFailureGivesActionableMessage() { assertEquals(R.string.signin_again, ProviderPresentation.errorText("unauthenticated")) }
    @Test fun missingRelayDoesNotSuggestSignIn() { assertEquals(R.string.relay_missing, ProviderPresentation.errorText("relayUnavailable")) }
    @Test fun sourceCaptionsFollowProvider() {
        assertEquals(R.string.source_claude, ProviderPresentation.sourceText("claude"))
        assertEquals(R.string.source_codex, ProviderPresentation.sourceText("codex"))
    }
}
