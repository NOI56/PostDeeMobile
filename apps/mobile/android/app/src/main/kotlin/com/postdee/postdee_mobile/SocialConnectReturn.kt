package com.postdee.postdee_mobile

import java.net.URI

/** Recognizes an app return only. Connection state comes from the authenticated API. */
internal object SocialConnectReturn {
    fun matches(rawUrl: String?, applicationId: String): Boolean {
        val expectedScheme = when (applicationId) {
            "com.postdee.postdee_mobile" -> "postdee"
            "com.postdee.postdee_mobile.staging" -> "postdee-staging"
            else -> return false
        }
        if (rawUrl.isNullOrBlank() || rawUrl.contains("\\")) return false

        return runCatching {
            val uri = URI(rawUrl)
            uri.scheme == expectedScheme &&
                uri.rawAuthority == "social-connect" &&
                uri.rawPath == "/return"
        }.getOrDefault(false)
    }
}
