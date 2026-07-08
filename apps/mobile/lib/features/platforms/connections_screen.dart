import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/network/postdee_api_client.dart';
import '../../core/theme/app_theme.dart';
import 'social_platform.dart';
import 'social_platform_logo.dart';

typedef ConnectUrlLauncher = Future<bool> Function(Uri uri);

/// Platforms PostPeer can connect a user account for. Shopee/Lazada are listed
/// in the app but not yet supported by the connect API, so they stay disabled.
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
  State<ConnectedPlatformsCard> createState() =>
      _ConnectedPlatformsCardState();
}

class _ConnectedPlatformsCardState extends State<ConnectedPlatformsCard> {
  late final PostDeeApiClient _apiClient =
      widget.apiClient ?? PostDeeApiClient();
  late final ConnectUrlLauncher _launch = widget.launchConnectUrl ??
      ((uri) => launchUrl(uri, mode: LaunchMode.externalApplication));

  Map<String, SocialConnectionResult> _statuses = {};
  bool _loading = true;
  String? _busyPlatform;

  @override
  void initState() {
    super.initState();
    _loadConnections();
  }

  Future<void> _loadConnections() async {
    try {
      final results = await _apiClient.listSocialConnections();
      if (!mounted) return;
      setState(() {
        _statuses = {for (final result in results) result.platform: result};
        _loading = false;
      });
      widget.onConnectionsChanged?.call(_connectedCount);
    } catch (_) {
      // Keep platforms shown as disconnected if the status call fails.
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  SocialConnectionResult? _statusFor(SocialPlatform platform) =>
      _statuses[platform.apiValue];

  int get _connectedCount => connectablePlatforms
      .where((platform) => _statusFor(platform)?.connected ?? false)
      .length;

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _connect(SocialPlatform platform) async {
    setState(() => _busyPlatform = platform.apiValue);
    try {
      final link =
          await _apiClient.createSocialConnectionLink(platform.apiValue);
      await _launch(link.connectUrl);
      // PostPeer OAuth happens in an external browser, so prompt the user to
      // refresh once they return instead of polling immediately.
      _showMessage('เปิดหน้าเชื่อมบัญชีแล้ว — เมื่อเสร็จในเบราว์เซอร์ กดปุ่มรีเฟรช');
    } on ApiException catch (error) {
      _showMessage(error.message);
    } catch (_) {
      _showMessage('เชื่อมบัญชีไม่สำเร็จ ลองใหม่อีกครั้ง');
    } finally {
      if (mounted) setState(() => _busyPlatform = null);
    }
  }

  Future<void> _refresh() async {
    setState(() => _loading = true);
    try {
      final results = await _apiClient.refreshSocialConnections();
      if (!mounted) return;
      setState(() {
        _statuses = {for (final result in results) result.platform: result};
        _loading = false;
      });
      widget.onConnectionsChanged?.call(_connectedCount);
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() => _loading = false);
      _showMessage(error.message);
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
      _showMessage('รีเฟรชสถานะไม่สำเร็จ ลองใหม่อีกครั้ง');
    }
  }

  Future<void> _disconnect(SocialPlatform platform) async {
    setState(() => _busyPlatform = platform.apiValue);
    try {
      await _apiClient.disconnectSocialConnection(platform.apiValue);
      await _loadConnections();
    } catch (_) {
      _showMessage('ยกเลิกการเชื่อมไม่สำเร็จ ลองใหม่อีกครั้ง');
    } finally {
      if (mounted) setState(() => _busyPlatform = null);
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

    if (_statusFor(platform)?.connected ?? false) {
      return OutlinedButton(
        key: ValueKey('profile-platform-disconnect-${platform.apiValue}'),
        onPressed: () => _disconnect(platform),
        style: _actionStyle,
        child: const Text('ยกเลิก'),
      );
    }

    return FilledButton(
      key: ValueKey('profile-platform-connect-${platform.apiValue}'),
      onPressed: () => _connect(platform),
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
                      'เชื่อมต่อแล้ว $_connectedCount/${connectablePlatforms.length} ช่องทาง',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
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
                onPressed: _refresh,
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
        for (final platform in SocialPlatform.values)
          _buildRow(context, platform),
      ],
    );
  }
}
