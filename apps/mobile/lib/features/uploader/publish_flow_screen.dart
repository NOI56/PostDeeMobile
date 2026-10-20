import 'package:flutter/material.dart';

import '../../core/network/postdee_api_client.dart';
import '../../core/network/api_error_message.dart';
import '../../core/theme/app_theme.dart';
import '../platforms/social_platform.dart';
import '../platforms/social_platform_logo.dart';
import '../shared/post_delivery_outcome.dart';

enum PublishFlowAction { finish, analytics }

enum PublishFlowStage {
  preparing,
  checkingAvailability,
  checkingPlan,
  applyingWatermark,
  uploadingVideo,
  retryingUpload,
  uploadingCover,
  creatingPost,
  finalizing,
}

@immutable
class PublishFlowProgress {
  const PublishFlowProgress({
    required this.stage,
    required this.fraction,
  }) : assert(fraction >= 0 && fraction <= 1);

  final PublishFlowStage stage;

  /// Progress through known publishing stages, not bytes transferred.
  final double fraction;

  String get title => switch (stage) {
        PublishFlowStage.preparing => 'กำลังเตรียมข้อมูล',
        PublishFlowStage.checkingAvailability => 'กำลังตรวจสอบระบบโพสต์',
        PublishFlowStage.checkingPlan => 'กำลังตรวจสอบแพ็กเกจ',
        PublishFlowStage.applyingWatermark => 'กำลังใส่ลายน้ำ',
        PublishFlowStage.uploadingVideo => 'กำลังอัปโหลดวิดีโอ',
        PublishFlowStage.retryingUpload => 'กำลังเชื่อมต่ออัปโหลดใหม่',
        PublishFlowStage.uploadingCover => 'กำลังอัปโหลดหน้าปก',
        PublishFlowStage.creatingPost => 'กำลังสร้างคิวโพสต์',
        PublishFlowStage.finalizing => 'กำลังยืนยันรายการ',
      };
}

typedef PublishProgressReporter = void Function(PublishFlowProgress progress);
typedef PublishOperation = Future<QueuedPostResult?> Function(
  PublishProgressReporter reportProgress,
);

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

class _PublishFlowScreenState extends State<PublishFlowScreen>
    with WidgetsBindingObserver {
  static const _initialProgress = PublishFlowProgress(
    stage: PublishFlowStage.preparing,
    fraction: 0.05,
  );

  QueuedPostResult? _post;
  PublishFlowProgress _progress = _initialProgress;
  Object? _publishError;
  bool _isPublishing = false;
  bool _appIsResumed = true;
  int _publishAttempt = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    _appIsResumed = lifecycle == null || lifecycle == AppLifecycleState.resumed;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _publish();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final resumed = state == AppLifecycleState.resumed;
    if (mounted && _appIsResumed != resumed) {
      setState(() => _appIsResumed = resumed);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _publish() async {
    if (!mounted || _isPublishing) return;

    final attempt = ++_publishAttempt;
    setState(() {
      _isPublishing = true;
      _publishError = null;
      _progress = _initialProgress;
    });

    try {
      final post = await widget.publish((progress) {
        if (!mounted || attempt != _publishAttempt) return;
        setState(() => _progress = progress);
      });

      if (!mounted || attempt != _publishAttempt) return;

      if (post == null) {
        Navigator.of(context).pop();
        return;
      }

      setState(() {
        _isPublishing = false;
        _post = post;
      });
    } catch (error) {
      if (!mounted || attempt != _publishAttempt) return;
      setState(() {
        _isPublishing = false;
        _publishError = error;
      });
    }
  }

  String get _publishErrorMessage {
    return apiErrorMessage(_publishError!,
        fallbackMessage:
            'เกิดข้อผิดพลาดระหว่างส่งโพสต์ กรุณาตรวจการเชื่อมต่อแล้วลองใหม่');
  }

  void _handleBlockedPop(bool didPop, Object? _) {
    if (didPop || !_isPublishing) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(
          content: Text(
            'ยังยกเลิกไม่ได้ระหว่างส่งข้อมูล กรุณารอจนจบขั้นตอน',
          ),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_isPublishing,
      onPopInvokedWithResult: _handleBlockedPop,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: DecoratedBox(
          decoration: AppTheme.screenBackground,
          child: SafeArea(
            child: _PublishViewTransition(
              animate: _appIsResumed,
              child: _post != null
                  ? _PublishDoneView(
                      key: const ValueKey('publish-flow-done'),
                      platforms: widget.platforms,
                      isScheduled: widget.isScheduled,
                      post: _post!,
                    )
                  : _publishError != null
                      ? _PublishErrorView(
                          key: const ValueKey('publish-flow-error'),
                          message: _publishErrorMessage,
                          onRetry: _publish,
                          onBack: () => Navigator.of(context).pop(),
                        )
                      : _PublishingView(
                          key: const ValueKey('publish-flow-posting'),
                          platforms: widget.platforms,
                          progress: _progress,
                          animate: _appIsResumed,
                        ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PublishViewTransition extends StatefulWidget {
  const _PublishViewTransition({required this.animate, required this.child});

  final bool animate;
  final Widget child;

  @override
  State<_PublishViewTransition> createState() => _PublishViewTransitionState();
}

class _PublishViewTransitionState extends State<_PublishViewTransition>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 260), value: 1);

  bool get _motionAllowed =>
      widget.animate &&
      TickerMode.valuesOf(context).enabled &&
      !MediaQuery.disableAnimationsOf(context);

  void _finishBlockedMotion() {
    if (!_motionAllowed) {
      _controller.stop();
      _controller.value = 1;
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _finishBlockedMotion();
  }

  @override
  void didUpdateWidget(covariant _PublishViewTransition oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!Widget.canUpdate(oldWidget.child, widget.child) && _motionAllowed) {
      _controller.forward(from: 0);
    }
    _finishBlockedMotion();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      FadeTransition(opacity: _controller, child: widget.child);
}

class _PublishingView extends StatefulWidget {
  const _PublishingView({
    super.key,
    required this.platforms,
    required this.progress,
    required this.animate,
  });

  final List<SocialPlatform> platforms;
  final PublishFlowProgress progress;
  final bool animate;

  @override
  State<_PublishingView> createState() => _PublishingViewState();
}

class _PublishingViewState extends State<_PublishingView>
    with SingleTickerProviderStateMixin {
  late final AnimationController _activity = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2400),
  );

  bool get _motionAllowed =>
      widget.animate &&
      TickerMode.valuesOf(context).enabled &&
      !MediaQuery.disableAnimationsOf(context);

  void _syncMotion() {
    if (_motionAllowed) {
      if (!_activity.isAnimating) _activity.repeat();
    } else {
      _activity.stop();
      _activity.value = 0;
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncMotion();
  }

  @override
  void didUpdateWidget(covariant _PublishingView oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncMotion();
  }

  @override
  void dispose() {
    _activity.dispose();
    super.dispose();
  }

  int get _currentStep => switch (widget.progress.stage) {
        PublishFlowStage.preparing ||
        PublishFlowStage.checkingAvailability ||
        PublishFlowStage.checkingPlan ||
        PublishFlowStage.applyingWatermark =>
          0,
        PublishFlowStage.uploadingVideo ||
        PublishFlowStage.retryingUpload ||
        PublishFlowStage.uploadingCover =>
          1,
        PublishFlowStage.creatingPost || PublishFlowStage.finalizing => 2,
      };

  Widget _emblem() => ExcludeSemantics(
        child: SizedBox.square(
          dimension: 90,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: AppTheme.border),
                ),
              ),
              Container(
                width: 64,
                height: 64,
                decoration:
                    BoxDecoration(color: AppTheme.mint, shape: BoxShape.circle),
                child: Icon(Icons.file_upload_outlined,
                    size: 30, color: AppTheme.accentCyanInk),
              ),
              Positioned.fill(
                child: RotationTransition(
                  key: const ValueKey('publish-flow-orbit'),
                  turns: _activity,
                  child: Align(
                    alignment: Alignment.topCenter,
                    child: Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                          color: AppTheme.accentCyanInk,
                          shape: BoxShape.circle),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      );

  Widget _destinations() => LayoutBuilder(
        builder: (context, constraints) => Wrap(
          alignment: WrapAlignment.center,
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final platform in widget.platforms)
              ConstrainedBox(
                constraints: BoxConstraints(maxWidth: constraints.maxWidth),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
                  decoration: BoxDecoration(
                    color: AppTheme.glass,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ExcludeSemantics(
                          child:
                              SocialPlatformLogo(platform: platform, size: 16)),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(platform.label,
                            style: TextStyle(
                                fontSize: 11,
                                color: AppTheme.textPrimary,
                                fontWeight: FontWeight.w500)),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      );

  Widget _progressRail(int percent) => Semantics(
        label: 'ความคืบหน้าตามขั้นตอน',
        value: '$percent%',
        child: ExcludeSemantics(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: Stack(
              children: [
                LinearProgressIndicator(
                  key: const ValueKey('publish-flow-progress'),
                  value: widget.progress.fraction,
                  minHeight: 10,
                  backgroundColor: AppTheme.mint,
                  color: AppTheme.accentCyanInk,
                ),
                if (_motionAllowed)
                  Positioned.fill(
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: FractionallySizedBox(
                        widthFactor: widget.progress.fraction,
                        child: ClipRect(
                          child: LayoutBuilder(
                            builder: (context, constraints) {
                              final width = constraints.maxWidth;
                              final lightWidth = width * 0.36;
                              return AnimatedBuilder(
                                animation: _activity,
                                child: Container(
                                  key: const ValueKey('publish-flow-sheen'),
                                  width: lightWidth,
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(colors: [
                                      Colors.white.withValues(alpha: 0),
                                      Colors.white.withValues(alpha: 0.4),
                                      Colors.white.withValues(alpha: 0),
                                    ]),
                                  ),
                                ),
                                builder: (context, child) =>
                                    Transform.translate(
                                  offset: Offset(
                                      -lightWidth +
                                          (width + lightWidth) *
                                              _activity.value,
                                      0),
                                  child: Align(
                                      alignment: Alignment.centerLeft,
                                      child: child),
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      );

  Widget _steps() {
    const steps = [
      (id: 'prepare', label: 'เตรียมข้อมูล'),
      (id: 'upload', label: 'อัปโหลด'),
      (id: 'queue', label: 'สร้างคิว'),
    ];
    final current = _currentStep;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var index = 0; index < steps.length; index++)
          Expanded(
            child: Semantics(
              key: ValueKey('publish-flow-step-${steps[index].id}'),
              label: steps[index].label,
              value: index < current
                  ? 'เสร็จแล้ว'
                  : index == current
                      ? 'กำลังทำ'
                      : 'รอขั้นตอน',
              excludeSemantics: true,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 3),
                child: Column(
                  children: [
                    Container(
                      width: 25,
                      height: 25,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: index == current
                            ? AppTheme.accentCyanInk
                            : AppTheme.mint,
                      ),
                      child: Icon(
                        index < current
                            ? Icons.check_rounded
                            : index == current
                                ? Icons.more_horiz_rounded
                                : Icons.circle_outlined,
                        size: 14,
                        color: index == current
                            ? Theme.of(context).colorScheme.onPrimary
                            : AppTheme.accentCyanInk,
                      ),
                    ),
                    const SizedBox(height: 7),
                    Text(steps[index].label,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            fontSize: 11,
                            color: index == current
                                ? AppTheme.textPrimary
                                : AppTheme.textSecondary)),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final percent = (widget.progress.fraction * 100).round();
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 36),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _emblem(),
            const SizedBox(height: 22),
            Text(
              widget.progress.title,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: AppTheme.textPrimary,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'กำลังดำเนินการสำหรับ ${widget.platforms.length} ช่องทาง',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: AppTheme.textMuted),
            ),
            const SizedBox(height: 16),
            _destinations(),
            const SizedBox(height: 26),
            _progressRail(percent),
            const SizedBox(height: 10),
            Text(
              '$percent% · ความคืบหน้าตามขั้นตอน',
              key: const ValueKey('publish-flow-progress-label'),
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: AppTheme.textMuted,
              ),
            ),
            const SizedBox(height: 24),
            _steps(),
            const SizedBox(height: 22),
            Text(
              'เปอร์เซ็นต์นี้แสดงขั้นตอนงาน ไม่ใช่จำนวนไบต์ที่อัปโหลด',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 11.5,
                height: 1.4,
                color: AppTheme.textMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PublishErrorView extends StatelessWidget {
  const _PublishErrorView({
    super.key,
    required this.message,
    required this.onRetry,
    required this.onBack,
  });

  final String message;
  final VoidCallback onRetry;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 88,
              height: 88,
              decoration: const BoxDecoration(
                color: Color(0x1FEF4444),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.cloud_off_rounded,
                size: 48,
                color: Color(0xFFDC2626),
              ),
            ),
            const SizedBox(height: 18),
            Text(
              'ส่งโพสต์ไม่สำเร็จ',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w700,
                color: AppTheme.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13.5,
                height: 1.5,
                color: AppTheme.textMuted,
              ),
            ),
            const SizedBox(height: 28),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: FilledButton(
                key: const ValueKey('publish-flow-retry'),
                onPressed: onRetry,
                style: FilledButton.styleFrom(
                  backgroundColor: AppTheme.accent,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(15),
                  ),
                ),
                child: const Text('ลองใหม่'),
              ),
            ),
            const SizedBox(height: 4),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: TextButton(
                key: const ValueKey('publish-flow-back-after-error'),
                onPressed: onBack,
                child: const Text('กลับไปตรวจสอบ'),
              ),
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
            LayoutBuilder(
              builder: (context, constraints) => Wrap(
                alignment: WrapAlignment.center,
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final platform in platforms)
                    ConstrainedBox(
                      constraints: BoxConstraints(
                        maxWidth: constraints.maxWidth,
                      ),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 13,
                          vertical: 7,
                        ),
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
                            Flexible(
                              child: Text(
                                _platformLabel(platform),
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: AppTheme.textPrimary,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
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
