package com.postdee.postdee_mobile

import android.net.Uri
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
            if (call.method != "launch") {
                result.notImplemented()
                return@setMethodCallHandler
            }

            result.success(launchSecureCustomTab(call.argument<String>("url")))
        }
    }

    private fun launchSecureCustomTab(rawUrl: String?): Boolean {
        if (rawUrl.isNullOrBlank() || rawUrl.contains("\\")) {
            return false
        }

        return try {
            val uri = Uri.parse(rawUrl)
            if (!uri.scheme.equals("https", ignoreCase = true) ||
                uri.host.isNullOrBlank() ||
                uri.encodedAuthority?.contains("@") == true
            ) {
                return false
            }

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
