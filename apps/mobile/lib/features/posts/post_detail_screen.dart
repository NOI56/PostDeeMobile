import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/auth/auth_session.dart';
import '../../core/network/postdee_api_client.dart';
import '../../core/theme/app_theme.dart';
import '../analytics/analytics_screen.dart';
import '../platforms/connections_screen.dart';
import '../platforms/social_platform.dart';
import '../platforms/social_platform_logo.dart';
import '../shared/publishing_availability.dart';
import '../shared/post_delivery_outcome.dart';
import '../shared/postdee_publishing_motion.dart';
import '../shared/postdee_notice.dart';
import '../uploader/post_video_preview_screen.dart';

typedef PostDetailReader = Future<PostSummaryResult?> Function(String postId);

/// Post detail (design screen #12). Shows the caption, channels, and honest
/// status-driven actions: scheduled posts can be published immediately through
/// the dedicated backend command or cancelled; published posts link to analytics.
/// Per-post stat tiles from the design are omitted until the API exposes them.
class PostDetailScreen extends StatefulWidget {
  const PostDetailScreen(
      {super.key,
      required this.post,
      this.apiClient,
      this.loadPost,
      this.refreshOnOpen = true});

  final PostSummaryResult post;
  final PostDeeApiClient? apiClient;
  final PostDetailReader? loadPost;
  final bool refreshOnOpen;

  @override
  State<PostDetailScreen> createState() => _PostDetailScreenState();
}

class _PostDetailScreenState extends State<PostDetailScreen>
    with WidgetsBindingObserver {
  late final PostDeeApiClient _apiClient =
      widget.apiClient ?? PostDeeApiClient();
  final _sessions = PostDeeAuthSessionStore.instance;
  late final String? _ownerUserId;
  bool _ownerChanged = false;
  bool _isWorking = false;
  bool _confirming = false;
  late PostSummaryResult _post;
  Uri? _previewVideoUrl;
  Uri? _previewCoverUrl;
  Timer? _refreshTimer;
  Future<bool>? _readOperation;
  int _readGeneration = 0;
  bool _foreground = true;
  bool _routeVisible = true;
  bool _hasRouteVisibility = false;
  bool _postUnavailable = false;
  String? _readError;
  DateTime? _lastChecked;

  bool get _hasPendingPost =>
      const {'QUEUED', 'PUBLISHING'}.contains(_post.status.toUpperCase());
  bool get _canReadVisible {
    if (!_ownerStillCurrent || !_foreground) return false;
    // A dialog's future can complete before didChangeDependencies rebuilds the
    // underlying route. Read the navigator's current state for reconciliation.
    // initState uses the initial value before inherited dependencies are legal.
    return _hasRouteVisibility
        ? (ModalRoute.of(context)?.isCurrent ?? true)
        : _routeVisible;
  }

  bool get _ownerStillCurrent =>
      mounted &&
      !_ownerChanged &&
      _sessions.session.stableUserId == _ownerUserId;

  @override
  void initState() {
    super.initState();
    _post = widget.post;
    _previewVideoUrl = _post.videoUrl;
    _previewCoverUrl = _post.coverImageUrl;
    _ownerUserId = _sessions.session.stableUserId;
    _sessions.addListener(_onSessionChanged);
    WidgetsBinding.instance.addObserver(this);
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    _foreground = lifecycle == null || lifecycle == AppLifecycleState.resumed;
    if (widget.refreshOnOpen) unawaited(_refresh(includeMedia: true));
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final visible = ModalRoute.of(context)?.isCurrent ?? true;
    final returned = _hasRouteVisibility && !_routeVisible && visible;
    _routeVisible = visible;
    _hasRouteVisibility = true;
    if (returned && _canReadVisible && !_confirming && !_isWorking) {
      unawaited(_refresh());
    }
    _syncRefreshTimer();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (_canReadVisible) unawaited(_refresh());
    _syncRefreshTimer();
  }

  void _syncRefreshTimer() {
    _refreshTimer?.cancel();
    _refreshTimer = null;
    if (!_canReadVisible ||
        !_hasPendingPost ||
        _postUnavailable ||
        _isWorking ||
        _confirming ||
        _readOperation != null) {
      return;
    }
    _refreshTimer = Timer(const Duration(seconds: 30), () {
      _refreshTimer = null;
      if (_canReadVisible) unawaited(_refresh());
    });
  }

  Future<bool> _refresh({bool includeMedia = false}) async {
    if (!_canReadVisible) return false;
    final pending = _readOperation;
    if (pending != null) return pending;
    // A fresh read already reconciles this route's return. Do not issue a second
    // read when the inherited route visibility update reaches the next frame.
    _routeVisible = true;
    final generation = _readGeneration;
    final operation = _performRefresh(generation, includeMedia: includeMedia);
    _readOperation = operation;
    _refreshTimer?.cancel();
    try {
      return await operation;
    } finally {
      if (identical(_readOperation, operation)) {
        _readOperation = null;
        if (_ownerStillCurrent) setState(() {});
        _syncRefreshTimer();
      }
    }
  }

  Future<bool> _performRefresh(int generation,
      {required bool includeMedia}) async {
    try {
      final latest = await (widget.loadPost?.call(_post.id) ??
          _apiClient.getPostById(_post.id, includeMedia: includeMedia));
      if (!_ownerStillCurrent || generation != _readGeneration) return false;
      if (latest != null && latest.id != _post.id) {
        throw const ApiException('Post id mismatch');
      }
      setState(() {
        if (latest != null) _post = latest;
        _postUnavailable = latest == null;
        _readError = null;
        _lastChecked = DateTime.now();
        if (includeMedia || latest == null) {
          _previewVideoUrl = latest?.videoUrl;
          _previewCoverUrl = latest?.coverImageUrl;
        }
      });
      return true;
    } catch (_) {
      if (_ownerStillCurrent && generation == _readGeneration) {
        setState(() => _readError = 'อัปเดตไม่สำเร็จ กำลังแสดงข้อมูลเดิม');
      }
      return false;
    }
  }

  void _onSessionChanged() {
    if (!_ownerChanged && _sessions.session.stableUserId != _ownerUserId) {
      _readGeneration++;
      _refreshTimer?.cancel();
      setState(() => _ownerChanged = true);
    }
  }

  @override
  void dispose() {
    _sessions.removeListener(_onSessionChanged);
    WidgetsBinding.instance.removeObserver(this);
    _refreshTimer?.cancel();
    _readGeneration++;
    super.dispose();
  }

  bool get _isScheduled =>
      _post.status.toUpperCase() == 'QUEUED' && _post.scheduledAt != null;

  bool get _isPublished => _post.status.toUpperCase() == 'PUBLISHED';

  bool get _isSending =>
      _post.status.toUpperCase() == 'PUBLISHING' && !_hasUnconfirmedOutcome;

  String? get _deliveryLabel =>
      aggregatePostDeliveryOutcomeLabel(_post.platformResults);

  bool get _hasUnconfirmedOutcome =>
      hasUnconfirmedDeliveryOutcome(_post.platformResults);

  bool get _hasPublishedChannel {
    final resultsWithOutcome = _post.platformResults
        .where((result) => result.deliveryOutcome != null)
        .toList();
    if (resultsWithOutcome.isNotEmpty) {
      return resultsWithOutcome.any(
        (result) =>
            result.status.toUpperCase() == 'PUBLISHED' &&
            isPublishedDeliveryOutcome(result.deliveryOutcome),
      );
    }
    return _isPublished ||
        _post.platformResults.any(
          (result) => result.status.toUpperCase() == 'PUBLISHED',
        );
  }

  ({String label, IconData icon, Color bg, Color ink}) get _statusMeta {
    if (_hasUnconfirmedOutcome) {
      return (
        label: 'ผลยังไม่ยืนยัน',
        icon: Icons.help_outline,
        bg: const Color(0xFFEEF2EF),
        ink: const Color(0xFF778276),
      );
    }
    return switch (_post.status.toUpperCase()) {
      'PUBLISHED' => (
          label: _deliveryLabel ?? 'เผยแพร่แล้ว',
          icon: Icons.check_circle,
          bg: const Color(0xFFE2F3EA),
          ink: const Color(0xFF0E9F6E),
        ),
      'QUEUED' when _post.scheduledAt != null => (
          label: 'รอส่งตามเวลา',
          icon: Icons.schedule,
          bg: const Color(0xFFFBEFD7),
          ink: const Color(0xFFB5740B),
        ),
      'PUBLISHING' => (
          label: 'กำลังส่ง',
          icon: Icons.sync,
          bg: const Color(0xFFE2F3EA),
          ink: const Color(0xFF0E9F6E),
        ),
      'PARTIAL_PUBLISHED' => (
          label: 'ส่งสำเร็จบางช่องทาง',
          icon: Icons.info_outline,
          bg: const Color(0xFFFBEFD7),
          ink: const Color(0xFFB5740B),
        ),
      'FAILED' => (
          label: 'ส่งไม่สำเร็จ',
          icon: Icons.error_outline,
          bg: const Color(0xFFFDE4E4),
          ink: const Color(0xFFDC2626),
        ),
      _ => (
          label: 'รอส่ง',
          icon: Icons.hourglass_top,
          bg: const Color(0xFFEEF2EF),
          ink: const Color(0xFF778276),
        ),
    };
  }

  String get _dateLabel {
    final post = _post;
    if (_isPublished && post.publishedAt != null) {
      final deliveryLabel = _deliveryLabel;
      if (deliveryLabel != null) {
        return '$deliveryLabel ${_formatThaiDateTime(post.publishedAt!)}';
      }
      return 'เผยแพร่ ${_formatThaiDateTime(post.publishedAt!)}';
    }
    if (post.status.toUpperCase() == 'PARTIAL_PUBLISHED' &&
        post.publishedAt != null) {
      return 'ส่งสำเร็จบางช่องทาง ${_formatThaiDateTime(post.publishedAt!)}';
    }
    if (post.scheduledAt != null) {
      return 'ตั้งเวลา ${_formatThaiDateTime(post.scheduledAt!)}';
    }
    return 'สร้างเมื่อ ${_formatThaiDateTime(post.createdAt)}';
  }

  List<SocialPlatform> get _platforms =>
      _post.platforms.map(_platformFor).whereType<SocialPlatform>().toList();

  PostPlatformResult? _resultFor(SocialPlatform platform) {
    for (final result in _post.platformResults) {
      if (result.platform == platform.apiValue) return result;
    }
    return null;
  }

  String _platformStatLine(SocialPlatform platform) {
    final result = _resultFor(platform);
    if (result != null) {
      if (result.status.toUpperCase() == 'PUBLISHED' &&
          result.deliveryOutcome == null) {
        return 'เผยแพร่สำเร็จ';
      }
      return postPlatformDeliveryLabel(result);
    }
    if (_isScheduled) return 'รอส่งตามเวลา';
    if (_isPublished ||
        _post.status.toUpperCase() == 'PUBLISHING' ||
        _post.status.toUpperCase() == 'PARTIAL_PUBLISHED') {
      return postPlatformDeliveryLabel(null);
    }
    if (_post.status.toUpperCase() == 'FAILED') return 'ส่งไม่สำเร็จ';
    return 'รอส่ง';
  }

  Color _platformStatusColor(SocialPlatform platform) {
    final result = _resultFor(platform);
    if (result?.status.toUpperCase() == 'FAILED') {
      return const Color(0xFFDC2626);
    }
    if (result?.status.toUpperCase() == 'PUBLISHING') {
      return const Color(0xFF0E9F6E);
    }
    if (result?.status.toUpperCase() != 'PUBLISHED') return AppTheme.textMuted;
    if (result?.deliveryOutcome != null &&
        !isKnownDeliveryOutcome(result?.deliveryOutcome)) {
      return AppTheme.textMuted;
    }
    if (postDeliveryOutcomeLabel(result?.deliveryOutcome) != null) {
      return const Color(0xFF0E9F6E);
    }
    return switch (result?.status.toUpperCase()) {
      'PUBLISHED' => const Color(0xFF0E9F6E),
      'FAILED' => const Color(0xFFDC2626),
      _ => AppTheme.textMuted,
    };
  }

  String _localizedPlatformError(String message) {
    return switch (message) {
      'Publishing to this platform failed. Please try again later.' =>
        'โพสต์ไปยังช่องทางนี้ไม่สำเร็จ กรุณาลองใหม่ภายหลัง',
      'TikTok rejected this video because its frame rate validation failed. Export the video again before retrying.' =>
        'TikTok ตรวจสอบอัตราเฟรมของคลิปนี้ไม่ผ่าน กรุณาส่งออกวิดีโอใหม่ก่อนลองอีกครั้ง',
      'TikTok publishing options changed. Review the account and publishing settings before trying again.' =>
        'สิทธิ์หรือตัวเลือกการโพสต์ TikTok เปลี่ยนไป กรุณาเปิดการตั้งค่าช่องทางและทบทวนก่อนลองอีกครั้ง',
      'TikTok publishing options could not be checked. No video was sent to TikTok. Review the settings before trying again.' =>
        'ตรวจสอบสิทธิ์การโพสต์ TikTok ไม่ได้ ยังไม่ได้ส่งคลิปไปยัง TikTok กรุณาทบทวนการตั้งค่าแล้วลองใหม่',
      'Publishing result could not be confirmed. Check the platform before trying again.' =>
        'ยังยืนยันผลการโพสต์ไม่ได้ กรุณาตรวจสอบช่องทางนี้ก่อนลองใหม่ เพื่อป้องกันโพสต์ซ้ำ',
      _ => message,
    };
  }

  bool _isWebLink(String value) {
    final uri = Uri.tryParse(value);
    return uri != null &&
        (uri.scheme == 'https' || uri.scheme == 'http') &&
        uri.host.isNotEmpty;
  }

  Future<void> _openPostLink(String value) async {
    if (!_ownerStillCurrent) return;
    final uri = Uri.tryParse(value);
    if (uri == null || !_isWebLink(value)) return;

    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!opened && mounted && _ownerStillCurrent) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('เปิดลิงก์โพสต์ไม่สำเร็จ')),
      );
    }
  }

  Widget _buildPlatformCard(SocialPlatform platform) {
    final result = _resultFor(platform);
    final statusLabel = _platformStatLine(platform);
    final sending = _isSending && statusLabel == 'กำลังส่ง';
    final errorMessage = result?.errorMessage?.trim();
    final externalReference = result?.externalPostId?.trim();
    final hasError = errorMessage != null && errorMessage.isNotEmpty;
    final canTrustReference = result?.deliveryOutcome == null ||
        isKnownDeliveryOutcome(result?.deliveryOutcome);
    final hasReference = canTrustReference &&
        externalReference != null &&
        externalReference.isNotEmpty;
    final referenceIsLink = externalReference != null &&
        externalReference.isNotEmpty &&
        (result?.deliveryOutcome == null ||
            isPublishedDeliveryOutcome(result?.deliveryOutcome)) &&
        _isWebLink(externalReference);

    return Container(
      padding: const EdgeInsets.all(12),
      margin: const EdgeInsets.only(bottom: 9),
      decoration: BoxDecoration(
        color: AppTheme.glass,
        borderRadius: BorderRadius.circular(14),
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
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SocialPlatformLogo(platform: platform, size: 40),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  platform.label,
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                if (sending)
                  PostDeePublishingBadge(
                    label: statusLabel,
                    background: const Color(0xFFE2F3EA),
                    foreground: const Color(0xFF0E9F6E),
                    sending: true,
                    fontSize: 11.5,
                  )
                else
                  Text(
                    statusLabel,
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight:
                          result == null ? FontWeight.w400 : FontWeight.w600,
                      color: _platformStatusColor(platform),
                    ),
                  ),
                if (hasError) ...[
                  const SizedBox(height: 4),
                  Text(
                    'สาเหตุ: ${_localizedPlatformError(errorMessage)}',
                    style: const TextStyle(
                      fontSize: 11.5,
                      height: 1.35,
                      color: Color(0xFFDC2626),
                    ),
                  ),
                ],
                if (result?.status.toUpperCase() == 'FAILED' ||
                    (result == null && _post.status.toUpperCase() == 'FAILED'))
                  TextButton.icon(
                    key: ValueKey('post-detail-review-${platform.apiValue}'),
                    onPressed: () => _reviewFailedChannel(platform),
                    icon: const Icon(Icons.fact_check_outlined, size: 16),
                    label: const Text('ทบทวนช่องทางนี้'),
                  ),
                if (hasReference) ...[
                  const SizedBox(height: 4),
                  InkWell(
                    onTap: referenceIsLink
                        ? () => _openPostLink(externalReference)
                        : null,
                    borderRadius: BorderRadius.circular(4),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Text(
                        referenceIsLink
                            ? 'ลิงก์โพสต์: $externalReference'
                            : 'รหัสโพสต์: $externalReference',
                        style: TextStyle(
                          fontSize: 11.5,
                          height: 1.35,
                          color: referenceIsLink
                              ? AppTheme.accent
                              : AppTheme.textMuted,
                          decoration: referenceIsLink
                              ? TextDecoration.underline
                              : TextDecoration.none,
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _publishNow() async {
    if (!_ownerStillCurrent ||
        !_isScheduled ||
        _postUnavailable ||
        _isWorking) {
      return;
    }
    final confirmed = await _confirm(
      title: 'โพสต์เลยตอนนี้?',
      body: 'โพสต์นี้จะถูกส่งไปทุกช่องทางที่เลือกทันที',
      confirmLabel: 'โพสต์เลย',
    );
    if (confirmed != true ||
        !mounted ||
        !_ownerStillCurrent ||
        !_isScheduled ||
        _postUnavailable) {
      return;
    }

    _readGeneration++;
    _refreshTimer?.cancel();
    setState(() => _isWorking = true);
    try {
      await _apiClient.publishPostNow(_post.id);
      if (!mounted || !_ownerStillCurrent) return;
      Navigator.of(context).pop(true);
    } on ApiException catch (error) {
      if (!mounted || !_ownerStillCurrent) return;
      setState(() => _isWorking = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _publishNowErrorMessage(error),
          ),
        ),
      );
    } catch (_) {
      if (!mounted || !_ownerStillCurrent) return;
      setState(() => _isWorking = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('โพสต์เลยไม่สำเร็จ ลองใหม่อีกครั้ง')),
      );
    } finally {
      _syncRefreshTimer();
    }
  }

  String _publishNowErrorMessage(ApiException error) {
    if (isPublishingUnavailable(error)) {
      return publishingUnavailableActionMessage;
    }

    return switch (error.code) {
      scheduledPostNotFoundCode =>
        'ไม่พบโพสต์ที่ตั้งเวลาไว้ กรุณากลับไปตรวจสอบรายการโพสต์',
      publishQueueUnavailableCode =>
        'ระบบคิวโพสต์ยังไม่พร้อม กรุณาลองใหม่ภายหลัง',
      _ => 'โพสต์เลยไม่สำเร็จ ลองใหม่อีกครั้ง',
    };
  }

  Future<void> _cancelPost() async {
    if (!_ownerStillCurrent ||
        !_isScheduled ||
        _postUnavailable ||
        _isWorking) {
      return;
    }
    final confirmed = await _confirm(
      title: 'ยกเลิกโพสต์นี้?',
      body: 'โพสต์ที่ตั้งเวลาไว้จะถูกนำออกจากคิว',
      confirmLabel: 'ยกเลิกโพสต์',
      destructive: true,
    );
    if (confirmed != true ||
        !mounted ||
        !_ownerStillCurrent ||
        !_isScheduled ||
        _postUnavailable) {
      return;
    }

    _readGeneration++;
    _refreshTimer?.cancel();
    setState(() => _isWorking = true);
    try {
      await _apiClient.cancelPost(_post.id);
      if (!mounted || !_ownerStillCurrent) return;
      Navigator.of(context).pop(true);
    } catch (_) {
      if (!mounted || !_ownerStillCurrent) return;
      // Drain an older read before checking the ambiguous mutation's outcome.
      // Neither reconciliation nor the next refresh can requeue or publish.
      await _readOperation;
      if (!mounted || !_ownerStillCurrent) return;
      setState(() => _isWorking = false);
      final checked = await _refresh();
      if (!mounted || !_ownerStillCurrent) return;
      final message = !checked
          ? 'ยังยืนยันผลการยกเลิกไม่ได้ กรุณาตรวจสถานะอีกครั้งเมื่อเชื่อมต่อได้'
          : _postUnavailable
              ? 'ไม่พบโพสต์นี้ในรายการแล้ว อาจถูกยกเลิกหรือถูกนำออก'
              : _post.status.toUpperCase() == 'PUBLISHING'
                  ? 'โพสต์เริ่มส่งแล้ว จึงยกเลิกคิวไม่ได้ กรุณาติดตามผลล่าสุด'
                  : !_isScheduled
                      ? 'สถานะโพสต์เปลี่ยนแล้ว กำลังแสดงผลล่าสุด'
                      : 'รายการยังรอส่งตามเวลา ยังยืนยันการยกเลิกไม่ได้';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
    } finally {
      _syncRefreshTimer();
    }
  }

  Future<bool?> _confirm({
    required String title,
    required String body,
    required String confirmLabel,
    bool destructive = false,
  }) async {
    _confirming = true;
    _syncRefreshTimer();
    try {
      return await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(title),
          content: Text(body),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('ไม่'),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              style: destructive
                  ? TextButton.styleFrom(
                      foregroundColor:
                          Theme.of(dialogContext).colorScheme.error,
                    )
                  : null,
              child: Text(confirmLabel),
            ),
          ],
        ),
      );
    } finally {
      _confirming = false;
      _syncRefreshTimer();
    }
  }

  Future<void> _reviewFailedChannel(SocialPlatform platform) async {
    if (!_ownerStillCurrent) return;
    final openConnections = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
              title: Text('ทบทวน ${platform.label}'),
              content: const SingleChildScrollView(
                  child: Text(
                'ตรวจสอบช่องทางก่อนสร้างโพสต์ใหม่\n\n'
                '1. เปิดแอปปลายทางเพื่อตรวจว่ามีคลิปนี้แล้วหรือไม่\n'
                '2. ตรวจสิทธิ์และการเชื่อมต่อของบัญชี หากมีคำเตือนเรื่องคลิป ให้ส่งออกไฟล์ใหม่ตามคำแนะนำ\n'
                '3. เมื่อตรวจแล้ว หากต้องสร้างโพสต์ใหม่ ให้เลือกเฉพาะช่องทางที่ต้องการส่งอีกครั้ง\n\n'
                'การทบทวนนี้ไม่ส่งคลิป ช่องทางที่ส่งสำเร็จแล้วจะไม่ถูกส่งซ้ำ',
              )),
              actions: [
                TextButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    child: const Text('รับทราบ')),
                TextButton(
                    onPressed: () => Navigator.of(context).pop(true),
                    child: const Text('ตรวจการเชื่อมต่อ')),
              ],
            ));
    if (!mounted || !_ownerStillCurrent) return;
    if (openConnections == true) {
      await Navigator.of(context).push<void>(
          MaterialPageRoute(builder: (_) => const ConnectionsScreen()));
    }
  }

  bool _safePreviewUrl(Uri? url) =>
      url != null &&
      (url.scheme == 'https' || url.scheme == 'http') &&
      url.host.isNotEmpty &&
      url.userInfo.isEmpty;

  Future<void> _openPreview() async {
    if (!_ownerStillCurrent || _postUnavailable) return;
    // Re-sign at the user's request rather than playing an expired cached URL.
    final pending = _readOperation;
    if (pending != null) await pending;
    if (!mounted || !_ownerStillCurrent) return;
    final checked = await _refresh(includeMedia: true);
    if (!mounted || !_ownerStillCurrent) return;
    final videoUrl = _previewVideoUrl;
    if (!checked || _postUnavailable || !_safePreviewUrl(videoUrl)) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('ตัวอย่างคลิปยังไม่พร้อม กรุณาลองตรวจสถานะอีกครั้ง')));
      return;
    }
    await Navigator.of(context).push<void>(MaterialPageRoute(
        builder: (_) => PostVideoPreviewScreen.network(
              videoUrl: videoUrl!,
              videoName:
                  _post.caption.isEmpty ? 'คลิปที่ส่งแล้ว' : _post.caption,
            )));
  }

  Widget _buildPreview() {
    final canPlay = _safePreviewUrl(_previewVideoUrl);
    final cover = _previewCoverUrl;
    final content = ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: Container(
          width: 104,
          height: 140,
          color: const Color(0xFFE7EFE9),
          child: Stack(fit: StackFit.expand, children: [
            if (_safePreviewUrl(cover))
              Image.network(cover.toString(),
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => const Icon(
                      Icons.videocam_off_outlined,
                      color: Color(0xFF8FA197))),
            if (canPlay)
              const Center(
                  child: Icon(Icons.play_circle_fill_rounded,
                      size: 38, color: Color(0xFF0E9F6E)))
            else
              Center(
                  child: Padding(
                      padding: const EdgeInsets.all(8),
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        if (!_safePreviewUrl(cover))
                          const Icon(Icons.videocam_off_outlined,
                              color: Color(0xFF8FA197)),
                        const SizedBox(height: 6),
                        const Text('ตัวอย่างยังไม่พร้อม',
                            textAlign: TextAlign.center,
                            style: TextStyle(fontSize: 11)),
                      ]))),
          ]),
        ));
    return canPlay
        ? Semantics(
            button: true,
            label: 'ดูคลิปที่ส่งแล้ว',
            child: InkWell(
              key: const ValueKey('post-detail-preview'),
              onTap: _openPreview,
              borderRadius: BorderRadius.circular(14),
              child: content,
            ))
        : KeyedSubtree(
            key: const ValueKey('post-detail-preview-unavailable'),
            child: content);
  }

  void _openAnalytics() {
    if (!_ownerStillCurrent) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => Scaffold(
          appBar: AppBar(
            title: const Text(
              'วิเคราะห์',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
          ),
          body: DecoratedBox(
            decoration: AppTheme.screenBackground,
            child: const SafeArea(
              child: AnalyticsScreen(showTitle: false),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_ownerStillCurrent) {
      return Scaffold(
        appBar: AppBar(title: const Text('รายละเอียดโพสต์')),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'บัญชีที่ใช้งานเปลี่ยนแล้ว กรุณาเปิดรายละเอียดโพสต์ใหม่',
              key: ValueKey('post-detail-owner-changed'),
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }
    if (_postUnavailable) {
      return Scaffold(
        appBar: AppBar(title: const Text('รายละเอียดโพสต์')),
        body: Padding(
            padding: const EdgeInsets.all(24),
            child: PostDeeNotice(
              key: const ValueKey('post-detail-post-unavailable'),
              icon: Icons.info_outline,
              message: 'ไม่พบโพสต์นี้ในบัญชี อาจถูกยกเลิกหรือถูกนำออกแล้ว',
              actionLabel: 'ตรวจอีกครั้ง',
              onAction: () => unawaited(_refresh(includeMedia: true)),
            )),
      );
    }
    final status = _statusMeta;
    final caption = _post.caption.trim();

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'รายละเอียดโพสต์',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
        actions: [
          IconButton(
            key: const ValueKey('post-detail-refresh'),
            tooltip: 'ตรวจสถานะล่าสุด',
            onPressed: _readOperation != null || _isWorking
                ? null
                : () => unawaited(_refresh(includeMedia: true)),
            icon: const Icon(Icons.refresh),
          )
        ],
      ),
      body: DecoratedBox(
        decoration: AppTheme.screenBackground,
        child: SafeArea(
          child: PostDeePublishingMotion(
            sending: _isSending,
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (_readError != null) ...[
                  PostDeeNotice(
                      message: _readError!,
                      icon: Icons.cloud_off,
                      actionLabel: 'ลองใหม่',
                      onAction: () => unawaited(_refresh(includeMedia: true))),
                  const SizedBox(height: 12),
                ],
                if (_lastChecked != null)
                  Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Text(
                          'ตรวจล่าสุด ${_formatThaiDateTime(_lastChecked!)}',
                          style: TextStyle(
                              fontSize: 11, color: AppTheme.textMuted))),
                Row(
                  children: [
                    PostDeePublishingBadge(
                      label: status.label,
                      background: status.bg,
                      foreground: status.ink,
                      sending: _isSending,
                      icon: status.icon,
                      fontSize: 12,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        _dateLabel,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11.5,
                          color: AppTheme.textMuted,
                        ),
                      ),
                    ),
                  ],
                ),
                if (_isSending) ...[
                  const SizedBox(height: 12),
                  const KeyedSubtree(
                    key: ValueKey('post-detail-publishing-rail'),
                    child: PostDeePublishingRail(color: Color(0xFF0E9F6E)),
                  ),
                ],
                const SizedBox(height: 14),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildPreview(),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'แคปชั่น',
                            style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w700,
                              color: AppTheme.textMuted,
                            ),
                          ),
                          const SizedBox(height: 5),
                          Text(
                            caption.isEmpty ? '(ไม่มีแคปชั่น)' : caption,
                            style: TextStyle(
                              fontSize: 13.5,
                              height: 1.55,
                              color: caption.isEmpty
                                  ? AppTheme.textMuted
                                  : AppTheme.textPrimary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                Text(
                  'ช่องทางที่โพสต์',
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textPrimary,
                  ),
                ),
                const SizedBox(height: 10),
                for (final platform in _platforms) ...[
                  _buildPlatformCard(platform),
                ],
                if (_platforms.isEmpty)
                  Text(
                    'ไม่พบข้อมูลช่องทาง',
                    style: TextStyle(fontSize: 12.5, color: AppTheme.textMuted),
                  ),
              ],
            ),
          ),
        ),
      ),
      bottomNavigationBar: _buildActionBar(context),
    );
  }

  Widget? _buildActionBar(BuildContext context) {
    if (!_isScheduled && !_hasPublishedChannel) {
      return null;
    }

    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppTheme.glass,
        border: Border(top: BorderSide(color: AppTheme.borderSoft)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          child: Row(
            children: [
              if (_isScheduled) ...[
                Semantics(
                  button: true,
                  label: 'ยกเลิกโพสต์',
                  child: InkWell(
                    borderRadius: BorderRadius.circular(14),
                    onTap: _isWorking ? null : _cancelPost,
                    child: Container(
                      width: 50,
                      height: 50,
                      decoration: BoxDecoration(
                        color: AppTheme.glass,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: AppTheme.border),
                      ),
                      child: const Icon(
                        Icons.delete_outline,
                        size: 21,
                        color: Color(0xFFEF4444),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _PrimaryActionButton(
                    key: const ValueKey('post-detail-publish-now'),
                    label: _isWorking ? 'กำลังส่ง...' : 'โพสต์เลย',
                    icon: Icons.bolt,
                    onPressed: _isWorking ? null : _publishNow,
                  ),
                ),
              ] else if (_hasPublishedChannel)
                Expanded(
                  child: _PrimaryActionButton(
                    key: const ValueKey('post-detail-open-analytics'),
                    label: 'ดูสถิติ',
                    icon: Icons.bar_chart_rounded,
                    onPressed: _openAnalytics,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PrimaryActionButton extends StatelessWidget {
  const _PrimaryActionButton({
    required this.label,
    required this.icon,
    required this.onPressed,
    super.key,
  });

  final String label;
  final IconData icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 50,
      child: FilledButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, size: 19),
        label: Text(label),
        style: FilledButton.styleFrom(
          backgroundColor: AppTheme.accent,
          foregroundColor: Colors.white,
          disabledBackgroundColor: AppTheme.accent.withValues(alpha: 0.55),
          disabledForegroundColor: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          textStyle: const TextStyle(
            fontSize: 14.5,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

SocialPlatform? _platformFor(String apiValue) {
  for (final platform in SocialPlatform.values) {
    if (platform.apiValue == apiValue) {
      return platform;
    }
  }
  return null;
}

const _thaiMonthsShort = [
  'ม.ค.',
  'ก.พ.',
  'มี.ค.',
  'เม.ย.',
  'พ.ค.',
  'มิ.ย.',
  'ก.ค.',
  'ส.ค.',
  'ก.ย.',
  'ต.ค.',
  'พ.ย.',
  'ธ.ค.',
];

String _formatThaiDateTime(DateTime value) {
  final local = value.toLocal();
  final hour = local.hour.toString().padLeft(2, '0');
  final minute = local.minute.toString().padLeft(2, '0');
  return '${local.day} ${_thaiMonthsShort[local.month - 1]} ${local.year} · $hour:$minute น.';
}
