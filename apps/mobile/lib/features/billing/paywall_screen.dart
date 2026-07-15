import 'package:flutter/material.dart';

import '../../core/network/postdee_api_client.dart';
import '../../core/theme/app_theme.dart';
import 'store_subscription_service.dart';

typedef PaywallSubscriptionLoader = Future<SubscriptionStatusResult> Function();

class _PlanFeature {
  const _PlanFeature(this.text, {this.included = true});

  final String text;

  /// Limitations render with a gray dash — never a green check, per the
  /// design handoff.
  final bool included;
}

class _PlanOption {
  const _PlanOption({
    required this.id,
    required this.name,
    required this.price,
    required this.features,
    this.isCurrent = false,
    this.isRecommended = false,
  });

  final String id;
  final String name;
  final String price;
  final List<_PlanFeature> features;
  final bool isCurrent;
  final bool isRecommended;
}

class PaywallScreen extends StatefulWidget {
  const PaywallScreen({
    super.key,
    this.onSubscribed,
    this.service,
    this.loadSubscription,
  });

  /// Called with the chosen plan id after a verified purchase.
  final ValueChanged<String>? onSubscribed;

  /// Injectable for tests; defaults to the real store + backend verifier.
  final StoreSubscriptionService? service;

  /// Loads the current subscription so the right plan is marked as active.
  /// Injectable for tests; defaults to the real backend.
  final PaywallSubscriptionLoader? loadSubscription;

  @override
  State<PaywallScreen> createState() => _PaywallScreenState();
}

class _PaywallScreenState extends State<PaywallScreen> {
  late final StoreSubscriptionService _service =
      widget.service ?? StoreSubscriptionService();
  final _apiClient = PostDeeApiClient();
  SubscriptionStatusResult? _subscription;
  var _subscriptionLoadGeneration = 0;

  @override
  void initState() {
    super.initState();
    _loadSubscription();
  }

  Future<void> _loadSubscription() async {
    final loadGeneration = ++_subscriptionLoadGeneration;

    try {
      final loader =
          widget.loadSubscription ?? _apiClient.loadCurrentSubscription;
      final subscription = await loader();

      if (!mounted || loadGeneration != _subscriptionLoadGeneration) {
        return;
      }

      setState(() => _subscription = subscription);
    } catch (_) {
      // Non-fatal: without the current plan we simply highlight none. The
      // paywall stays usable so the user can still subscribe.
    }
  }

  void _applyVerifiedSubscription(SubscriptionStatusResult subscription) {
    _subscriptionLoadGeneration += 1;
    setState(() => _subscription = subscription);
  }

  // Maps a backend plan code (e.g. PRO, FREE) to a paywall card id.
  String? get _currentPlanId {
    final plan = _subscription?.plan.toUpperCase();

    return switch (plan) {
      'PRO' => 'pro',
      'STARTER' => 'starter',
      'BASIC' || 'FREE' => 'basic',
      _ => null,
    };
  }

  List<_PlanOption> get _plans {
    final currentPlanId = _currentPlanId;

    return [
      _PlanOption(
        id: 'basic',
        name: 'Basic',
        price: 'ฟรี',
        isCurrent: currentPlanId == 'basic',
        features: const [
          _PlanFeature('โพสต์ฟรี 3 หน่วย/เดือนหลังยืนยันเบอร์'),
          _PlanFeature('ต้องยืนยันเบอร์ก่อนโพสต์', included: false),
          _PlanFeature('ไม่มี AI แคปชั่นและการตั้งเวลา', included: false),
        ],
      ),
      _PlanOption(
        id: 'starter',
        name: 'Starter',
        price: '199 ฿/เดือน',
        isCurrent: currentPlanId == 'starter',
        features: const [
          _PlanFeature('โพสต์หลายช่องทาง 120 หน่วย/เดือน'),
          _PlanFeature('ตั้งเวลาโพสต์ + ปฏิทิน + เทมเพลต'),
          _PlanFeature('AI แคปชั่นจากเสียงคลิป 50 ครั้ง/เดือน'),
          _PlanFeature('ลายน้ำอัตโนมัติ'),
        ],
      ),
      _PlanOption(
        id: 'pro',
        name: 'Pro',
        price: '299 ฿/เดือน',
        isCurrent: currentPlanId == 'pro',
        isRecommended: true,
        features: const [
          _PlanFeature('โพสต์หลายช่องทาง 250 หน่วย/เดือน'),
          _PlanFeature('ทุกอย่างใน Starter + วิเคราะห์เต็มรูปแบบ'),
          _PlanFeature('AI แคปชั่นจากเสียง + ภาพ 120 ครั้ง/เดือน'),
          _PlanFeature('AI ตัดต่อ 200 นาที/เดือน'),
        ],
      ),
    ];
  }

  Future<void> _subscribe(_PlanOption plan) async {
    if (plan.id == 'basic') {
      return;
    }

    final messenger = ScaffoldMessenger.of(context);

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => PopScope(
        canPop: false,
        child: AlertDialog(
          backgroundColor: AppTheme.charcoal,
          content: const Row(
            children: [
              CircularProgressIndicator(color: AppTheme.accent),
              SizedBox(width: AppTheme.spaceLg),
              Expanded(child: Text('กำลังดำเนินการสั่งซื้อ...')),
            ],
          ),
        ),
      ),
    );

    try {
      // Real store purchase → backend receipt verification → entitlement.
      late final StoreSubscriptionVerificationResult result;
      if (plan.id == 'pro') {
        result = await _service.startProSubscription();
      } else {
        result = await _service.startStarterSubscription();
      }

      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pop();
      _applyVerifiedSubscription(result.subscription);
      widget.onSubscribed?.call(plan.id);
      _showSuccess(plan);
    } on StoreSubscriptionException catch (error) {
      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pop();
      messenger.showSnackBar(SnackBar(content: Text(error.message)));
    } catch (_) {
      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pop();
      messenger.showSnackBar(
        const SnackBar(content: Text('สมัครไม่สำเร็จ ลองใหม่อีกครั้ง')),
      );
    }
  }

  Future<void> _restorePurchase() async {
    final messenger = ScaffoldMessenger.of(context);

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => PopScope(
        canPop: false,
        child: AlertDialog(
          backgroundColor: AppTheme.charcoal,
          content: const Row(
            children: [
              CircularProgressIndicator(color: AppTheme.accent),
              SizedBox(width: AppTheme.spaceLg),
              Expanded(child: Text('กำลังกู้คืนการซื้อ...')),
            ],
          ),
        ),
      ),
    );

    try {
      final result = await _service.restoreSubscription();
      final planId = result.subscription.plan.toLowerCase();

      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pop();
      _applyVerifiedSubscription(result.subscription);
      widget.onSubscribed?.call(planId);
      _showRestoreSuccess(result.subscription.plan);
    } on StoreSubscriptionException catch (error) {
      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pop();
      messenger.showSnackBar(SnackBar(content: Text(error.message)));
    } catch (_) {
      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pop();
      messenger.showSnackBar(
        const SnackBar(content: Text('กู้คืนการซื้อไม่สำเร็จ ลองใหม่อีกครั้ง')),
      );
    }
  }

  void _showSuccess(_PlanOption plan) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.charcoal,
        title: Text('สมัคร ${plan.name} สำเร็จ'),
        content: const Text('ปลดล็อกฟีเจอร์ของแพ็กเกจเรียบร้อยแล้ว'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('ตกลง'),
          ),
        ],
      ),
    );
  }

  void _showRestoreSuccess(String plan) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.charcoal,
        title: const Text('กู้คืนการซื้อสำเร็จ'),
        content: Text('คืนสิทธิ์แพ็กเกจ ${plan.toUpperCase()} เรียบร้อยแล้ว'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('ตกลง'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'เลือกแพ็กเกจ',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
      ),
      body: SafeArea(
        child: DecoratedBox(
          decoration: AppTheme.screenBackground,
          child: ListView(
            padding: AppTheme.screenPadding,
            children: [
              Text(
                'อัปเกรดเพื่อปลดล็อกการตั้งเวลา AI แคปชั่น และวิเคราะห์เต็มรูปแบบ',
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                  height: 1.45,
                  color: AppTheme.textSecondary,
                ),
              ),
              const SizedBox(height: 16),
              for (var index = 0; index < _plans.length; index += 1) ...[
                _PlanCard(
                  plan: _plans[index],
                  onSubscribe: () => _subscribe(_plans[index]),
                ),
                if (index < _plans.length - 1) const SizedBox(height: 13),
              ],
              const SizedBox(height: 16),
              if (_service.supportsUnifiedRestore) ...[
                SizedBox(
                  height: 48,
                  child: OutlinedButton.icon(
                    onPressed: _restorePurchase,
                    icon: const Icon(Icons.restore, size: 19),
                    label: const Text('กู้คืนการซื้อ'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppTheme.accentCyanInk,
                      side: BorderSide(color: AppTheme.border),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(13),
                      ),
                      textStyle: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
              ],
              Text(
                'ราคาจริงจะแสดงตามร้านค้าของแต่ละประเทศ · ยกเลิกได้ทุกเมื่อ',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 11,
                  height: 1.5,
                  color: AppTheme.textMuted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PlanCard extends StatelessWidget {
  const _PlanCard({required this.plan, required this.onSubscribe});

  final _PlanOption plan;
  final VoidCallback onSubscribe;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(17),
      decoration: BoxDecoration(
        color: AppTheme.glass,
        borderRadius: BorderRadius.circular(18),
        border: plan.isRecommended
            ? Border.all(color: AppTheme.accent, width: 2)
            : Border.all(color: AppTheme.border),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF122018).withValues(alpha: 0.05),
            blurRadius: 2,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                plan.name,
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.textPrimary,
                ),
              ),
              if (plan.isRecommended)
                const _PlanBadge(
                  label: 'แนะนำ',
                  background: AppTheme.accent,
                  foreground: Colors.white,
                ),
              if (plan.isCurrent)
                _PlanBadge(
                  label: 'แพ็กเกจปัจจุบัน',
                  background: AppTheme.borderSoft,
                  foreground: AppTheme.textMuted,
                ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            plan.price,
            style: TextStyle(
              fontSize: 21,
              fontWeight: FontWeight.w700,
              color: plan.id == 'basic'
                  ? AppTheme.textSecondary
                  : AppTheme.accentCyanInk,
            ),
          ),
          const SizedBox(height: 13),
          for (final feature in plan.features)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 1),
                    child: Icon(
                      feature.included ? Icons.check_circle : Icons.remove,
                      color: feature.included
                          ? AppTheme.accentCyanInk
                          : AppTheme.textMuted,
                      size: 18,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      feature.text,
                      style: TextStyle(
                        fontSize: 12.5,
                        height: 1.4,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          if (!plan.isCurrent && plan.id != 'basic') ...[
            const SizedBox(height: 7),
            SizedBox(
              height: 48,
              child: FilledButton.icon(
                onPressed: onSubscribe,
                icon: const Icon(Icons.workspace_premium_outlined, size: 19),
                label: Text('สมัคร ${plan.name}'),
                style: FilledButton.styleFrom(
                  backgroundColor: AppTheme.accent,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(13),
                  ),
                  textStyle: const TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _PlanBadge extends StatelessWidget {
  const _PlanBadge({
    required this.label,
    required this.background,
    required this.foreground,
  });

  final String label;
  final Color background;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 10.5,
            fontWeight: FontWeight.w700,
            color: foreground,
          ),
        ),
      ),
    );
  }
}
