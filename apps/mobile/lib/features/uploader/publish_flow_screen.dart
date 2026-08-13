import 'package:flutter/material.dart';

import '../../core/network/postdee_api_client.dart';
import '../../core/theme/app_theme.dart';
import '../platforms/social_platform.dart';
import '../platforms/social_platform_logo.dart';
import '../shared/post_delivery_outcome.dart';

enum PublishFlowAction { finish, analytics }

typedef PublishOperation = Future<QueuedPostResult?> Function();

class PublishFlowScreen extends StatefulWidget {
  const PublishFlowScreen({
    super.key,
    required this.platforms,
    required this.isScheduled,
    required this.publish,
  });

  final List<SocialPlatform> platforms;
  final bool isScheduled;
  final PublishOperation publish;

  @override
  State<PublishFlowScreen> createState() => _PublishFlowScreenState();
}

class _PublishFlowScreenState extends State<PublishFlowScreen> {
  QueuedPostResult? _post;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _publish());
  }

  Future<void> _publish() async {
    final post = await widget.publish();

    if (!mounted) return;

    if (post == null) {
      Navigator.of(context).pop();
      return;
    }

    setState(() => _post = post);
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _post != null,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: DecoratedBox(
          decoration: AppTheme.screenBackground,
          child: SafeArea(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 260),
              child: _post != null
                  ? _PublishDoneView(
                      key: const ValueKey('publish-flow-done'),
                      platforms: widget.platforms,
                      isScheduled: widget.isScheduled,
                      post: _post!,
                    )
                  : _PublishingView(
                      key: const ValueKey('publish-flow-posting'),
                      platformCount: widget.platforms.length,
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PublishingView extends StatelessWidget {
  const _PublishingView({super.key, required this.platformCount});

  final int platformCount;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 74,
              height: 74,
              child: CircularProgressIndicator(
                strokeWidth: 5,
                backgroundColor: AppTheme.mint,
                color: AppTheme.accentCyanInk,
                strokeCap: StrokeCap.round,
              ),
            ),
            const SizedBox(height: 22),
            Text(
              'กำลังส่งเข้าคิว...',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: AppTheme.textPrimary,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'กำลังเตรียมส่งสำหรับ $platformCount ช่องทาง',
              style: TextStyle(fontSize: 13, color: AppTheme.textMuted),
            ),
          ],
        ),
      ),
    );
  }
}

class _PublishDoneView extends StatelessWidget {
  const _PublishDoneView({
    super.key,
    required this.platforms,
    required this.isScheduled,
    required this.post,
  });

  final List<SocialPlatform> platforms;
  final bool isScheduled;
  final QueuedPostResult post;

  String? get _deliveryLabel =>
      aggregatePostDeliveryOutcomeLabel(post.platformResults);

  bool get _hasUnconfirmedOutcome =>
      hasUnconfirmedDeliveryOutcome(post.platformResults);

  bool get _hasPartialResults {
    final statuses = post.platformResults
        .map((result) => result.status.trim().toUpperCase())
        .toSet();
    return post.status.toUpperCase() == 'PARTIAL_PUBLISHED' ||
        (statuses.contains('PUBLISHED') && statuses.contains('FAILED'));
  }

  String get _title =>
      _deliveryLabel ??
      switch (post.status.toUpperCase()) {
        'PUBLISHING' => 'กำลังส่ง',
        'PUBLISHED' => 'ส่งสำเร็จ',
        'PARTIAL_PUBLISHED' => 'ส่งสำเร็จบางช่องทาง',
        _ => isScheduled ? 'จัดคิวส่งตามเวลาแล้ว' : 'รับรายการแล้ว',
      };

  String get _body {
    final platformCount = platforms.length;
    final deliveryLabel = _deliveryLabel;
    final isAllProviderDrafts = post.platformResults.isNotEmpty &&
        post.platformResults.every(
          (result) => isProviderDraftOutcome(result.deliveryOutcome),
        );
    final message = _hasPartialResults
        ? 'ส่งสำเร็จเพียงบางช่องทาง กรุณาเปิดรายละเอียดเพื่อตรวจช่องทางที่ไม่สำเร็จ'
        : _hasUnconfirmedOutcome
            ? 'ระบบรับผลจาก $platformCount ช่องทางแล้ว แต่ยังยืนยันรูปแบบปลายทางไม่ได้'
            : deliveryLabel != null
                ? isAllProviderDrafts
                    ? 'ส่ง $platformCount ช่องทางเป็นร่างแล้ว · ส่งออกจริงและใช้โควตาโพสต์'
                    : 'ส่ง $platformCount ช่องทางสำเร็จ · $deliveryLabel'
                : switch (post.status.toUpperCase()) {
                    'PUBLISHING' =>
                      'ระบบกำลังส่ง $platformCount ช่องทาง กรุณาตรวจผลอีกครั้งในหน้ารายการโพสต์',
                    'PUBLISHED' => 'ส่ง $platformCount ช่องทางสำเร็จแล้ว',
                    'PARTIAL_PUBLISHED' =>
                      'ส่งสำเร็จเพียงบางช่องทาง กรุณาเปิดรายละเอียดเพื่อตรวจช่องทางที่ไม่สำเร็จ',
                    _ => isScheduled
                        ? 'ระบบรับรายการตั้งเวลาสำหรับ $platformCount ช่องทางแล้ว'
                        : 'ระบบรับรายการ $platformCount ช่องทางแล้ว กำลังส่ง',
                  };
    return post.idempotentReplay ? 'พบรายการเดิม · $message' : message;
  }

  String? _outcomeFor(SocialPlatform platform) {
    for (final result in post.platformResults) {
      if (result.platform == platform.apiValue) {
        return postDeliveryOutcomeLabel(result.deliveryOutcome);
      }
    }
    return null;
  }

  String _platformLabel(SocialPlatform platform) {
    final outcome = _outcomeFor(platform);
    return outcome == null ? platform.label : '${platform.label} · $outcome';
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 96,
              height: 96,
              decoration: BoxDecoration(
                color: _hasUnconfirmedOutcome
                    ? const Color(0xFFEEF2EF)
                    : AppTheme.mint,
                shape: BoxShape.circle,
              ),
              child: Icon(
                _hasUnconfirmedOutcome
                    ? Icons.help_outline_rounded
                    : Icons.check_rounded,
                size: 54,
                color: _hasUnconfirmedOutcome
                    ? AppTheme.textMuted
                    : AppTheme.accentCyanInk,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              _title,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w700,
                color: AppTheme.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _body,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13.5,
                height: 1.5,
                color: AppTheme.textMuted,
              ),
            ),
            const SizedBox(height: 16),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final platform in platforms)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
                    decoration: BoxDecoration(
                      color: AppTheme.glass,
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: AppTheme.border),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SocialPlatformLogo(platform: platform, size: 18),
                        const SizedBox(width: 6),
                        Text(
                          _platformLabel(platform),
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: AppTheme.textPrimary,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 30),
            SizedBox(
              width: double.infinity,
              height: 54,
              child: FilledButton(
                key: const ValueKey('publish-flow-finish'),
                onPressed: () =>
                    Navigator.of(context).pop(PublishFlowAction.finish),
                style: FilledButton.styleFrom(
                  backgroundColor: AppTheme.accent,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(15),
                  ),
                  textStyle: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                child: const Text('เสร็จสิ้น'),
              ),
            ),
            const SizedBox(height: 4),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: TextButton(
                key: const ValueKey('publish-flow-analytics'),
                onPressed: () =>
                    Navigator.of(context).pop(PublishFlowAction.analytics),
                style: TextButton.styleFrom(
                  foregroundColor: AppTheme.accentCyanInk,
                  textStyle: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                child: const Text('ดูสถิติโพสต์'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
