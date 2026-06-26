import 'package:flutter/material.dart';

import '../../core/network/postdee_api_client.dart';
import '../../core/theme/app_theme.dart';
import '../shared/postdee_card.dart';
import 'store_subscription_service.dart';

typedef PaywallSubscriptionLoader = Future<SubscriptionStatusResult> Function();

class _PlanOption {
  const _PlanOption({
    required this.id,
    required this.name,
    required this.price,
    required this.color,
    required this.features,
    this.isCurrent = false,
    this.isRecommended = false,
  });

  final String id;
  final String name;
  final String price;
  final Color color;
  final List<String> features;
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

  @override
  void initState() {
    super.initState();
    _loadSubscription();
  }

  Future<void> _loadSubscription() async {
    try {
      final loader =
          widget.loadSubscription ?? _apiClient.loadCurrentSubscription;
      final subscription = await loader();

      if (!mounted) {
        return;
      }

      setState(() => _subscription = subscription);
    } catch (_) {
      // Non-fatal: without the current plan we simply highlight none. The
      // paywall stays usable so the user can still subscribe.
    }
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
        color: AppTheme.textSecondary,
        isCurrent: currentPlanId == 'basic',
        features: [
          'โพสต์ฟรี 3 ครั้ง/เดือนหลังยืนยันเบอร์',
          'ต้องยืนยันเบอร์ก่อนโพสต์',
          'ไม่มี AI แคปชั่นและการตั้งเวลา',
        ],
      ),
      _PlanOption(
        id: 'starter',
        name: 'Starter',
        price: '199 บาท/เดือน',
        color: AppTheme.accentPinkInk,
        isCurrent: currentPlanId == 'starter',
        features: [
          'โพสต์หลายช่องทาง 120 หน่วย/เดือน',
          'ตั้งเวลาโพสต์ + ปฏิทิน + เทมเพลต',
          'AI แคปชั่นจากเสียงคลิป 50 ครั้ง/เดือน',
          'ลายน้ำอัตโนมัติ + ตัดคลิปเป็น EP',
        ],
      ),
      _PlanOption(
        id: 'pro',
        name: 'Pro',
        price: '299 บาท/เดือน',
        color: AppTheme.accentCyanInk,
        isCurrent: currentPlanId == 'pro',
        isRecommended: true,
        features: [
          'โพสต์หลายช่องทาง 250 หน่วย/เดือน',
          'ทุกอย่างใน Starter + วิเคราะห์เต็มรูปแบบ',
          'AI แคปชั่นจากเสียง + ภาพ 120 ครั้ง/เดือน',
          'เรดาร์แฮชแท็ก, แจ้งเตือนไวรัล, ทีมและผู้ช่วย',
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
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.charcoal,
        content: const Row(
          children: [
            CircularProgressIndicator(color: AppTheme.accent),
            SizedBox(width: AppTheme.spaceLg),
            Expanded(child: Text('กำลังดำเนินการสั่งซื้อ...')),
          ],
        ),
      ),
    );

    try {
      // Real store purchase → backend receipt verification → entitlement.
      if (plan.id == 'pro') {
        await _service.startProSubscription();
      } else {
        await _service.startStarterSubscription();
      }

      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pop();
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'เลือกแพ็กเกจ',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      body: SafeArea(
        child: DecoratedBox(
          decoration: AppTheme.screenBackground,
          child: ListView(
            padding: AppTheme.screenPadding,
            children: [
              Text(
                'อัปเกรดเพื่อปลดล็อกการตั้งเวลา AI และวิเคราะห์',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: AppTheme.textSecondary,
                      fontWeight: FontWeight.w600,
                    ),
              ),
              const SizedBox(height: AppTheme.spaceLg),
              for (var index = 0; index < _plans.length; index += 1) ...[
                _PlanCard(
                  plan: _plans[index],
                  onSubscribe: () => _subscribe(_plans[index]),
                ),
                if (index < _plans.length - 1)
                  const SizedBox(height: AppTheme.spaceMd),
              ],
              const SizedBox(height: AppTheme.spaceMd),
              Text(
                'ราคาจริงจะแสดงตามร้านค้าของแต่ละประเทศ ยกเลิกได้ทุกเมื่อ',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
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
    final textTheme = Theme.of(context).textTheme;

    return PostDeeCard(
      glowColor: plan.color,
      borderColor: plan.isRecommended ? plan.color.withValues(alpha: 0.6) : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  plan.name,
                  style:
                      textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
                ),
              ),
              if (plan.isRecommended)
                PostDeeSoftPill(label: 'แนะนำ', color: plan.color),
              if (plan.isCurrent)
                Text(
                  'แพ็กเกจปัจจุบัน',
                  style: textTheme.labelSmall?.copyWith(
                    color: AppTheme.textSecondary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
            ],
          ),
          const SizedBox(height: AppTheme.spaceXs),
          Text(
            plan.price,
            style: textTheme.titleLarge?.copyWith(
              color: plan.color,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: AppTheme.spaceMd),
          for (final feature in plan.features)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.check_circle, color: plan.color, size: 15),
                  const SizedBox(width: 7),
                  Expanded(
                    child: Text(
                      feature,
                      style: textTheme.bodySmall?.copyWith(
                        color: AppTheme.textSecondary,
                        height: 1.25,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          if (!plan.isCurrent && plan.id != 'basic') ...[
            const SizedBox(height: AppTheme.spaceMd),
            PostDeeGradientButton(
              label: 'สมัคร ${plan.name}',
              icon: Icons.workspace_premium_outlined,
              onPressed: onSubscribe,
            ),
          ],
        ],
      ),
    );
  }
}
