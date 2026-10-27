import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

typedef SocialConnectionUrlOpener = Future<bool> Function(Uri uri);

const _browserChannel = MethodChannel('postdee/social_connection_browser');

/// Opens provider OAuth in the browser, without an embedded WebView fallback.
Future<bool> launchSocialConnectionUrl(
  Uri uri, {
  TargetPlatform? platform,
  SocialConnectionUrlOpener? openCustomTab,
  SocialConnectionUrlOpener? openExternalBrowser,
}) async {
  if (uri.scheme != 'https' || uri.host.isEmpty) return false;

  if (!kIsWeb &&
      (platform ?? defaultTargetPlatform) == TargetPlatform.android) {
    final opened = await _tryOpen(openCustomTab ?? _openCustomTab, uri);
    if (opened) return true;
  }

  return _tryOpen(openExternalBrowser ?? _openExternalBrowser, uri);
}

Future<bool> _openCustomTab(Uri uri) async =>
    await _browserChannel.invokeMethod<bool>('openCustomTab', uri.toString()) ??
    false;

Future<bool> _openExternalBrowser(Uri uri) =>
    launchUrl(uri, mode: LaunchMode.externalApplication);

Future<bool> _tryOpen(SocialConnectionUrlOpener open, Uri uri) async {
  try {
    return await open(uri);
  } on PlatformException {
    return false;
  } on MissingPluginException {
    return false;
  }
}
