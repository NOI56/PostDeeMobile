package com.postdee.postdee_mobile

import android.content.ActivityNotFoundException
import android.content.Intent
import android.net.Uri
import androidx.browser.customtabs.CustomTabsClient
import androidx.browser.customtabs.CustomTabsIntent
import androidx.browser.customtabs.CustomTabsService
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "postdee/social_connection_browser"
        ).setMethodCallHandler { call, result ->
            if (call.method == "openCustomTab") {
                result.success(openSocialConnectionCustomTab(call.arguments as? String))
            } else {
                result.notImplemented()
            }
        }
    }

    private fun openSocialConnectionCustomTab(url: String?): Boolean {
        val uri = url?.let(Uri::parse) ?: return false
        if (uri.scheme != "https" || uri.host.isNullOrBlank()) return false

        return try {
            val providers = packageManager.queryIntentServices(
                Intent(CustomTabsService.ACTION_CUSTOM_TABS_CONNECTION), 0
            ).map { it.serviceInfo.packageName }.distinct()
            val browserPackage = CustomTabsClient.getPackageName(this, providers)
                ?: return false
            // Do not use url_launcher's inAppBrowserView: it can fall back to
            // an embedded WebView when a Custom Tab cannot launch.
            val customTab = CustomTabsIntent.Builder()
                .setShowTitle(true)
                .setSendToExternalDefaultHandlerEnabled(true)
                .build()
            customTab.intent.setPackage(browserPackage)
            customTab.launchUrl(this, uri)
            true
        } catch (_: ActivityNotFoundException) {
            false
        } catch (_: SecurityException) {
            false
        }
    }
}
