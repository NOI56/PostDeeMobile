package com.postdee.postdee_mobile

import android.content.Intent
import android.net.Uri
import android.os.Build
import androidx.browser.customtabs.CustomTabsClient
import androidx.browser.customtabs.CustomTabsIntent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    companion object {
        private const val SECURE_CUSTOM_TABS_CHANNEL =
            "com.postdee.postdee_mobile/secure_custom_tabs"
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            SECURE_CUSTOM_TABS_CHANNEL,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "launchApp" -> result.success(launchExternalApp(call.argument<String>("url")))
                "launch" -> result.success(launchSecureCustomTab(call.argument<String>("url")))
                else -> result.notImplemented()
            }
        }
    }

    private fun readSocialConnectUri(rawUrl: String?): Uri? {
        if (rawUrl.isNullOrBlank() || rawUrl.contains("\\")) {
            return null
        }

        return try {
            val uri = Uri.parse(rawUrl)
            val host = uri.host?.lowercase() ?: return null
            if (!uri.scheme.equals("https", ignoreCase = true) ||
                host.isBlank() ||
                uri.encodedAuthority?.contains("@") == true
            ) {
                return null
            }
            val trustedDomains = listOf(
                "tiktok.com", "accounts.google.com", "instagram.com",
                "facebook.com", "postpeer.dev",
            )
            if (!trustedDomains.any { host == it || host.endsWith(".$it") }) {
                return null
            }
            uri
        } catch (_: RuntimeException) {
            null
        }
    }

    private fun launchExternalApp(rawUrl: String?): Boolean {
        // Older Android versions cannot exclude browsers reliably. Retain
        // their existing Custom Tab path instead of guessing a native handler.
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R) return false
        val uri = readSocialConnectUri(rawUrl) ?: return false
        return try {
            val intent = Intent(Intent.ACTION_VIEW, uri)
                .addCategory(Intent.CATEGORY_BROWSABLE)
                .addFlags(Intent.FLAG_ACTIVITY_REQUIRE_NON_BROWSER)
            startActivity(intent)
            true
        } catch (_: RuntimeException) {
            // No app supports this exact URL, or the OS rejected the launch.
            // Dart can fall back without exposing credentials in a WebView.
            false
        }
    }

    private fun launchSecureCustomTab(rawUrl: String?): Boolean {
        val uri = readSocialConnectUri(rawUrl) ?: return false
        return try {
            val customTabsPackage =
                CustomTabsClient.getPackageName(this, emptyList()) ?: return false
            val customTab = CustomTabsIntent.Builder()
                .setShowTitle(true)
                .build()
            customTab.intent.setPackage(customTabsPackage)
            customTab.launchUrl(this, uri)
            true
        } catch (_: RuntimeException) {
            // Discovery or launch can fail when a browser disappears or rejects
            // the intent. Dart then uses the external browser; never substitute
            // an embedded WebView for provider credentials.
            false
        }
    }
}
