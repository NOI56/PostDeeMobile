import 'package:flutter/material.dart';

import '../../core/network/postdee_api_client.dart';
import '../../core/theme/app_theme.dart';
import '../platforms/social_platform.dart';
import '../platforms/social_platform_logo.dart';

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
  bool _isDone = false;

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

    if (mounted) {
      setState(() => _isDone = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _isDone,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: DecoratedBox(
          decoration: AppTheme.screenBackground,
          child: SafeArea(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 260),
              child: _isDone
                  ? _PublishDoneView(
                      key: const ValueKey('publish-flow-done'),
                      platforms: widget.platforms,
                      isScheduled: widget.isScheduled,
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
              'กำลังเตรียมโพสต์สำหรับ $platformCount ช่องทาง',
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
  });

  final List<SocialPlatform> platforms;
  final bool isScheduled;

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
                color: AppTheme.mint,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.check_rounded,
                size: 54,
                color: AppTheme.accentCyanInk,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              isScheduled ? 'จัดคิวตั้งเวลาแล้ว' : 'ส่งเข้าคิวแล้ว',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w700,
                color: AppTheme.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              isScheduled
                  ? 'ระบบรับโพสต์ตั้งเวลาสำหรับ ${platforms.length} ช่องทางแล้ว'
                  : 'ระบบรับโพสต์ ${platforms.length} ช่องทางแล้ว กำลังเผยแพร่',
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
                          platform.label,
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
