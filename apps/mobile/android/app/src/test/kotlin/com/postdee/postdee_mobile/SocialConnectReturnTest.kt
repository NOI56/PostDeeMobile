package com.postdee.postdee_mobile

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class SocialConnectReturnTest {
    private val production = "com.postdee.postdee_mobile"
    private val staging = "com.postdee.postdee_mobile.staging"

    @Test
    fun acceptsEachEnvironmentOnlyForItsOwnInstalledPackage() {
        assertTrue(SocialConnectReturn.matches("postdee://social-connect/return", production))
        assertTrue(SocialConnectReturn.matches("postdee-staging://social-connect/return", staging))
        assertFalse(SocialConnectReturn.matches("postdee://social-connect/return", staging))
        assertFalse(SocialConnectReturn.matches("postdee-staging://social-connect/return", production))
        assertFalse(SocialConnectReturn.matches("postdee://social-connect/return", "another.app"))
    }

    @Test
    fun keepsBillingAndOtherDeepLinksOutsideTheSocialReturnHandler() {
        listOf(
            "postdee://billing",
            "postdee://social-connect",
            "postdee://social-connect/return/other",
            "postdee://another-host/return",
            "https://social-connect/return",
        ).forEach { assertFalse(it, SocialConnectReturn.matches(it, production)) }
    }

    @Test
    fun rejectsAmbiguousAuthoritiesAndEncodedPaths() {
        listOf(
            "postdee://user@social-connect/return",
            "postdee://social-connect:443/return",
            "postdee://social-connect.example.com/return",
            "postdee://social-connect/%72eturn",
            "postdee://social-connect/../return",
            "postdee://social-connect\\evil/return",
            "postdee:/social-connect/return",
            "POSTDEE://social-connect/return",
            "postdee://SOCIAL-CONNECT/return",
        ).forEach { assertFalse(it, SocialConnectReturn.matches(it, production)) }
    }

    @Test
    fun toleratesReturnMetadataWithoutUsingItToAuthenticateAnything() {
        assertTrue(SocialConnectReturn.matches(
            "postdee://social-connect/return?success=false&profileId=untrusted#ignored",
            production,
        ))
    }

    @Test
    fun rejectsMissingAndMalformedUris() {
        listOf(null, "", "not a URI", "postdee://[invalid/return").forEach {
            assertFalse(SocialConnectReturn.matches(it, production))
        }
    }
}
