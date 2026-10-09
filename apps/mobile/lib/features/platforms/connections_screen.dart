import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/auth/auth_session.dart';
import '../../core/network/postdee_api_client.dart';
import '../../core/theme/app_theme.dart';
import 'social_platform.dart';
import 'social_platform_logo.dart';

typedef ConnectUrlLauncher = Future<bool> Function(Uri uri);
typedef SocialConnectBrowserLauncher = Future<bool> Function(
  Uri uri, {
  required LaunchMode mode,
  required BrowserConfiguration browserConfiguration,
});
typedef SocialConnectCustomTabLauncher = Future<bool> Function(Uri uri);

const MethodChannel _secureCustomTabsChannel = MethodChannel(
  'com.postdee.postdee_mobile/secure_custom_tabs',
);

Future<bool> _launchNativeAndroidCustomTab(Uri uri) async =>
    await _secureCustomTabsChannel.invokeMethod<bool>(
      'launch',
      {'url': uri.toString()},
    ) ??
    false;

/// Opens social authorization without ever giving provider credentials to an
/// embedded WebView. Android uses a native Custom Tab channel that fails closed;
/// all other cases use the external system browser.
Future<bool> launchSocialConnectUrl(
  Uri uri, {
  SocialConnectBrowserLauncher? launch,
  SocialConnectCustomTabLauncher? launchCustomTab,
  bool? preferAndroidCustomTab,
}) async {
  final shouldPreferAndroidCustomTab = preferAndroidCustomTab ??
      (!kIsWeb && defaultTargetPlatform == TargetPlatform.android);
  if (shouldPreferAndroidCustomTab) {
    try {
      final opened = await (launchCustomTab ?? _launchNativeAndroidCustomTab)(
        uri,
      );
      if (opened) {
        return true;
      }
    } on Object {
      // A missing Custom Tab provider or platform-channel failure must fall
      // through to the external browser, never url_launcher's WebView path.
    }
  }
  const mode = LaunchMode.externalApplication;
  const browserConfiguration = BrowserConfiguration(showTitle: true);

  if (launch != null) {
    return launch(
      uri,
      mode: mode,
      browserConfiguration: browserConfiguration,
    );
  }

  return launchUrl(
    uri,
    mode: mode,
    browserConfiguration: browserConfiguration,
  );
}

const Map<SocialPlatform, List<String>> _trustedSocialConnectDomains = {
  SocialPlatform.tiktok: ['tiktok.com'],
  SocialPlatform.youtubeShorts: ['accounts.google.com'],
  SocialPlatform.instagramReels: ['instagram.com', 'facebook.com'],
  SocialPlatform.facebookReels: ['facebook.com'],
};

bool _matchesDomain(String host, String domain) =>
    host == domain || host.endsWith('.$domain');

/// Defense in depth for the URL returned by the PostDee API. PostPeer normally
/// returns the provider's OAuth URL directly, so accepting arbitrary HTTPS
/// hosts here would make a bad upstream response look like a legitimate login.
bool isTrustedSocialConnectUrl(String rawUrl, SocialPlatform platform) {
  // Browsers treat a backslash like a path separator while URI parsers do not
  // always agree. Reject it before parsing so the allowlist sees the same host
  // that the browser will open.
  if (rawUrl.contains('\\')) return false;

  final uri = Uri.tryParse(rawUrl);
  if (uri == null) return false;

  final hasUserInfo = RegExp(
    r'^https://[^/?#]*@',
    caseSensitive: false,
  ).hasMatch(rawUrl);
  if (!uri.isAbsolute ||
      uri.scheme.toLowerCase() != 'https' ||
      !uri.hasAuthority ||
      uri.host.isEmpty ||
      hasUserInfo) {
    return false;
  }

  final host = uri.host.toLowerCase();
  final trustedDomains = [
    ...?_trustedSocialConnectDomains[platform],
    'postpeer.dev',
  ];
  return trustedDomains.any((domain) => _matchesDomain(host, domain));
}

/// Platforms PostPeer can connect a user account for. Only supported
/// destinations appear in the connection list; Shopee/Lazada are future targets.
const List<SocialPlatform> connectablePlatforms = [
  SocialPlatform.tiktok,
  SocialPlatform.youtubeShorts,
  SocialPlatform.instagramReels,
  SocialPlatform.facebookReels,
];

/// Pushed from the profile "เชื่อมต่อช่องทาง" row (design screen #18).
class ConnectionsScreen extends StatelessWidget {
  const ConnectionsScreen({
    super.key,
    this.apiClient,
    this.launchConnectUrl,
    this.onConnectionsChanged,
  });

  final PostDeeApiClient? apiClient;
  final ConnectUrlLauncher? launchConnectUrl;
  final ValueChanged<int>? onConnectionsChanged;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'เชื่อมต่อช่องทาง',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: AppTheme.screenPadding,
          children: [
            ConnectedPlatformsCard(
              apiClient: apiClient,
              launchConnectUrl: launchConnectUrl,
              onConnectionsChanged: onConnectionsChanged,
            ),
          ],
        ),
      ),
    );
  }
}

class ConnectedPlatformsCard extends StatefulWidget {
  const ConnectedPlatformsCard({
    super.key,
    this.apiClient,
    this.launchConnectUrl,
    this.onConnectionsChanged,
  });

  final PostDeeApiClient? apiClient;
  final ConnectUrlLauncher? launchConnectUrl;
  final ValueChanged<int>? onConnectionsChanged;

  @override
  State<ConnectedPlatformsCard> createState() => _ConnectedPlatformsCardState();
}

class _ConnectedPlatformsCardState extends State<ConnectedPlatformsCard>
    with WidgetsBindingObserver {
  late final PostDeeApiClient _apiClient =
      widget.apiClient ?? PostDeeApiClient();
  late final ConnectUrlLauncher _launch =
      widget.launchConnectUrl ?? launchSocialConnectUrl;

  Map<String, SocialConnectionResult> _statuses = {};
  bool _loading = true;
  String? _statusError;
  String? _busyPlatform;
  bool _waitingForOAuthReturn = false;
  bool _leftAppForOAuth = false;
  bool _pendingOAuthRefresh = false;
  String? _ownerUserId;
  int _loadGeneration = 0;
  int _operationGeneration = 0;

  @override
  void initState() {
    super.initState();
    _ownerUserId = PostDeeAuthSessionStore.instance.session.stableUserId;
    PostDeeAuthSessionStore.instance.addListener(_handleOwnerChanged);
    WidgetsBinding.instance.addObserver(this);
    _loadConnections();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    PostDeeAuthSessionStore.instance.removeListener(_handleOwnerChanged);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!_waitingForOAuthReturn) return;

    switch (state) {
      case AppLifecycleState.inactive:
      case AppLifecycleState.hidden:
      case AppLifecycleState.paused:
        _leftAppForOAuth = true;
        break;
      case AppLifecycleState.resumed:
        if (!_leftAppForOAuth) return;
        _waitingForOAuthReturn = false;
        _leftAppForOAuth = false;
        _pendingOAuthRefresh = true;
        _drainOAuthRefresh();
        break;
      case AppLifecycleState.detached:
        break;
    }
  }

  void _handleOwnerChanged() {
    final owner = PostDeeAuthSessionStore.instance.session.stableUserId;
    if (!mounted || owner == _ownerUserId) return;
    _ownerUserId = owner;
    _loadGeneration += 1;
    _operationGeneration += 1;
    _waitingForOAuthReturn = false;
    _leftAppForOAuth = false;
    _pendingOAuthRefresh = false;
    setState(() {
      _statuses = {};
      _busyPlatform = null;
      _loading = false;
      _statusError = 'กรุณาเข้าสู่ระบบใหม่เพื่อตรวจสอบช่องทาง';
    });
    if (owner != null) unawaited(_loadConnections());
  }

  bool _loadIsCurrent(int generation, String? owner) =>
      mounted &&
      generation == _loadGeneration &&
      owner == PostDeeAuthSessionStore.instance.session.stableUserId;

  bool _operationIsCurrent(int generation, String? owner) =>
      mounted &&
      generation == _operationGeneration &&
      owner == PostDeeAuthSessionStore.instance.session.stableUserId;

  void _drainOAuthRefresh() {
    if (!mounted ||
        !_pendingOAuthRefresh ||
        _loading ||
        _busyPlatform != null ||
        _ownerUserId != PostDeeAuthSessionStore.instance.session.stableUserId) {
      return;
    }
    _pendingOAuthRefresh = false;
    unawaited(_refresh());
  }

  Future<void> _loadConnections() async {
    final generation = ++_loadGeneration;
    final owner = _ownerUserId;
    setState(() {
      _loading = true;
      _statusError = null;
    });
    try {
      final results = await _apiClient.listSocialConnections();
      if (!_loadIsCurrent(generation, owner)) return;
      setState(() {
        _statuses = {for (final result in results) result.platform: result};
        _loading = false;
      });
      widget.onConnectionsChanged?.call(_connectedCount);
    } catch (_) {
      if (!_loadIsCurrent(generation, owner)) return;
      _setStatusUnavailable();
    } finally {
      if (_loadIsCurrent(generation, owner)) _drainOAuthRefresh();
    }
  }

  SocialConnectionResult? _statusFor(SocialPlatform platform) =>
      _statusKnown ? _statuses[platform.apiValue] : null;

  bool get _statusKnown => !_loading && _statusError == null;

  void _setStatusUnavailable() {
    setState(() {
      _statuses = {};
      _loading = false;
      _statusError =
          'โหลดสถานะช่องทางไม่สำเร็จ กรุณาตรวจสอบอินเทอร์เน็ตแล้วลองใหม่';
    });
  }

  int get _connectedCount => connectablePlatforms
      .where((platform) => _statusFor(platform)?.connected ?? false)
      .length;

  bool get _actionsLocked => !_statusKnown || _busyPlatform != null;

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _connect(SocialPlatform platform) async {
    if (_actionsLocked) return;
    final generation = ++_operationGeneration;
    final owner = _ownerUserId;
    setState(() => _busyPlatform = platform.apiValue);
    try {
      final returnTarget = !kIsWeb && defaultTargetPlatform == TargetPlatform.android
          ? kDebugMode
              ? 'android-staging'
              : 'android'
          : null;
      final link = await _apiClient.createSocialConnectionLink(
        platform.apiValue,
        returnTarget: returnTarget,
      );
      if (!_operationIsCurrent(generation, owner)) return;
      if (!isTrustedSocialConnectUrl(link.connectUrl, platform)) {
        _showMessage('ลิงก์เชื่อมบัญชีไม่ปลอดภัย กรุณาลองใหม่อีกครั้ง');
        return;
      }
      _waitingForOAuthReturn = true;
      _leftAppForOAuth = false;
      final launched = await _launch(link.connectUri);
      if (!_operationIsCurrent(generation, owner)) return;
      if (!launched) {
        _waitingForOAuthReturn = false;
        throw StateError('Could not open the PostPeer connect URL.');
      }
      // Returning is only a hint to reconcile via the authenticated API. The
      // browser and callback never prove that an account was connected.
      _showMessage(
        'เปิดหน้าล็อกอินด้วยเบราว์เซอร์ของระบบแล้ว เมื่อเชื่อมเสร็จให้กดเปิด PostDee หากไม่กลับอัตโนมัติให้ปิดหน้าต่างหรือกลับเข้าแอป แล้วกดรีเฟรชสถานะได้',
      );
    } on ApiException catch (error) {
      if (!_operationIsCurrent(generation, owner)) return;
      _waitingForOAuthReturn = false;
      _leftAppForOAuth = false;
      _pendingOAuthRefresh = false;
      _showMessage(error.message);
    } catch (_) {
      if (!_operationIsCurrent(generation, owner)) return;
      _waitingForOAuthReturn = false;
      _leftAppForOAuth = false;
      _pendingOAuthRefresh = false;
      _showMessage('เชื่อมบัญชีไม่สำเร็จ ลองใหม่อีกครั้ง');
    } finally {
      if (_operationIsCurrent(generation, owner)) {
        setState(() => _busyPlatform = null);
        _drainOAuthRefresh();
      }
    }
  }

  Future<void> _refresh() async {
    if (_loading || _busyPlatform != null) return;
    final generation = ++_loadGeneration;
    final owner = _ownerUserId;
    setState(() {
      _loading = true;
      _statusError = null;
    });
    try {
      final results = await _apiClient.refreshSocialConnections();
      if (!_loadIsCurrent(generation, owner)) return;
      setState(() {
        _statuses = {for (final result in results) result.platform: result};
        _loading = false;
      });
      widget.onConnectionsChanged?.call(_connectedCount);
    } catch (_) {
      if (!_loadIsCurrent(generation, owner)) return;
      _setStatusUnavailable();
    } finally {
      if (_loadIsCurrent(generation, owner)) _drainOAuthRefresh();
    }
  }

  Future<void> _disconnect(SocialPlatform platform) async {
    if (_actionsLocked) return;
    final generation = ++_operationGeneration;
    final owner = _ownerUserId;
    setState(() => _busyPlatform = platform.apiValue);
    try {
      await _apiClient.disconnectSocialConnection(platform.apiValue);
      if (!_operationIsCurrent(generation, owner)) return;
      await _loadConnections();
    } catch (_) {
      if (!_operationIsCurrent(generation, owner)) return;
      _showMessage('ยกเลิกการเชื่อมไม่สำเร็จ ลองใหม่อีกครั้ง');
    } finally {
      if (_operationIsCurrent(generation, owner)) {
        setState(() => _busyPlatform = null);
        _drainOAuthRefresh();
      }
    }
  }

  ButtonStyle get _actionStyle => OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        minimumSize: Size.zero,
        side: BorderSide(color: AppTheme.border),
      );

  Widget _buildAction(SocialPlatform platform) {
    if (!connectablePlatforms.contains(platform)) {
      return OutlinedButton(
        key: ValueKey('profile-platform-soon-${platform.apiValue}'),
        onPressed: null,
        style: _actionStyle,
        child: const Text('เร็วๆ นี้'),
      );
    }

    if (_busyPlatform == platform.apiValue) {
      return const SizedBox(
        width: 18,
        height: 18,
        child: CircularProgressIndicator(strokeWidth: 2),
      );
    }

    if (!_statusKnown) {
      return OutlinedButton(
        key: ValueKey('profile-platform-status-unknown-${platform.apiValue}'),
        onPressed: null,
        style: _actionStyle,
        child: const Text('รอสถานะ'),
      );
    }

    if (_statusFor(platform)?.connected ?? false) {
      return OutlinedButton(
        key: ValueKey('profile-platform-disconnect-${platform.apiValue}'),
        onPressed: _actionsLocked ? null : () => _disconnect(platform),
        style: _actionStyle,
        child: const Text('ยกเลิก'),
      );
    }

    return FilledButton(
      key: ValueKey('profile-platform-connect-${platform.apiValue}'),
      onPressed: _actionsLocked ? null : () => _connect(platform),
      style: FilledButton.styleFrom(
        backgroundColor: AppTheme.accent,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        minimumSize: Size.zero,
        textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
      ),
      child: const Text('เชื่อม'),
    );
  }

  Widget _buildRow(BuildContext context, SocialPlatform platform) {
    final status = _statusFor(platform);
    final connected = status?.connected ?? false;
    final displayName = connected ? status?.displayName : null;

    return Container(
      padding: const EdgeInsets.all(13),
      margin: const EdgeInsets.only(bottom: 9),
      decoration: BoxDecoration(
        color: AppTheme.glass,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: AppTheme.border),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF122018).withValues(alpha: 0.04),
            blurRadius: 2,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Row(
        children: [
          SocialPlatformLogo(platform: platform, size: 30),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        platform.label,
                        style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.textPrimary,
                        ),
                      ),
                    ),
                    if (connected) ...[
                      const SizedBox(width: 6),
                      const Icon(Icons.check_circle,
                          size: 16, color: AppTheme.accent),
                    ],
                  ],
                ),
                if (displayName != null && displayName.isNotEmpty)
                  Text(
                    displayName,
                    style: TextStyle(
                      fontSize: 11.5,
                      color: AppTheme.textSecondary,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          _buildAction(platform),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Green summary banner, per the prototype's connections screen.
        Container(
          padding: const EdgeInsets.all(17),
          margin: const EdgeInsets.only(bottom: 18),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF0E9F6E), Color(0xFF0A7A55)],
            ),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF0B7A55).withValues(alpha: 0.55),
                blurRadius: 30,
                spreadRadius: -16,
                offset: const Offset(0, 14),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(13),
                ),
                child: const Icon(Icons.hub_outlined,
                    color: Colors.white, size: 26),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _loading
                          ? 'กำลังตรวจสอบช่องทาง...'
                          : _statusError != null
                              ? 'ตรวจสอบช่องทางไม่ได้'
                              : 'เชื่อมต่อแล้ว $_connectedCount/${connectablePlatforms.length} ช่องทาง',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _statusError ??
                          'เชื่อมครั้งเดียว โพสต์คลิปเดียวไปได้ทุกช่องทาง',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.white.withValues(alpha: 0.85),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        if (_statusError != null) ...[
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              key: const ValueKey('profile-platforms-retry'),
              onPressed: _loadConnections,
              icon: const Icon(Icons.refresh),
              label: const Text('ลองใหม่'),
            ),
          ),
          const SizedBox(height: 8),
        ],
        Row(
          children: [
            Expanded(
              child: Text(
                'ช่องทางโซเชียล',
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.textPrimary,
                ),
              ),
            ),
            if (_loading)
              const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            else ...[
              if (_statusKnown)
                Text(
                  '$_connectedCount/${connectablePlatforms.length}',
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textSecondary,
                  ),
                ),
              const SizedBox(width: 4),
              IconButton(
                key: const ValueKey('profile-platforms-refresh'),
                onPressed: _actionsLocked ? null : _refresh,
                icon: const Icon(Icons.refresh, size: 20),
                visualDensity: VisualDensity.compact,
                tooltip: 'รีเฟรชสถานะการเชื่อม',
              ),
            ],
          ],
        ),
        const SizedBox(height: 4),
        Text(
          'เชื่อมบัญชีโซเชียลของคุณเพื่อให้โพสต์ขึ้นบัญชีตัวเอง',
          style: TextStyle(
            fontSize: 12.5,
            height: 1.4,
            color: AppTheme.textSecondary,
          ),
        ),
        const SizedBox(height: 13),
        Container(
          key: const ValueKey('profile-social-oauth-security-note'),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppTheme.accent.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: AppTheme.accent.withValues(alpha: 0.24),
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(
                Icons.verified_user_outlined,
                size: 20,
                color: AppTheme.accent,
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'เข้าสู่ระบบอย่างปลอดภัย',
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'เปิดด้วยเบราว์เซอร์ที่ระบบเชื่อถือ PostDee ไม่ได้รับรหัสผ่านของคุณ เมื่อเสร็จให้กดเปิด PostDee หากไม่กลับให้ปิดหน้าต่างหรือกลับเข้าแอป แล้วรีเฟรชสถานะ',
                      style: TextStyle(
                        fontSize: 11.5,
                        height: 1.4,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 13),
        for (final platform in connectablePlatforms)
          _buildRow(context, platform),
      ],
    );
  }
}
