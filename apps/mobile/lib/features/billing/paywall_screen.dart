import 'dart:async';

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
    this.sessionCache,
  });

  /// Called with the chosen plan id after a verified purchase.
  final ValueChanged<String>? onSubscribed;

  /// Injectable for tests; defaults to the real store + backend verifier.
  final StoreSubscriptionService? service;

  /// Loads the current subscription so the right plan is marked as active.
  /// Injectable for tests; defaults to the real backend.
  final PaywallSubscriptionLoader? loadSubscription;
  final StoreSubscriptionSessionCache? sessionCache;

  @override
  State<PaywallScreen> createState() => _PaywallScreenState();
}

class _PaywallScreenState extends State<PaywallScreen> {
  late final StoreSubscriptionService _service = widget.service ??
      (widget.sessionCache ?? StoreSubscriptionSessionCache.instance).service;
  final _apiClient = PostDeeApiClient();
  SubscriptionStatusResult? _subscription;
  var _isSubscriptionLoading = true;
  Object? _subscriptionLoadError;
  var _subscriptionLoadGeneration = 0;
  var _isBillingInProgress = false;
  final Map<String, StoreProductInfo> _products = {};
  var _isPriceLoading = true;
  var _priceLoadFailed = false;
  var _priceLoadGeneration = 0;
  Timer? _priceTimer;

  @override
  void initState() {
    super.initState();
    _loadSubscription();
    _loadPrices();
  }

  Future<void> _loadPrices() async {
    final generation = ++_priceLoadGeneration;
    _priceTimer?.cancel();
    setState(() { _isPriceLoading = true; _priceLoadFailed = false; });
    _priceTimer = Timer(_service.productQueryTimeout, () {
      if (!mounted || generation != _priceLoadGeneration) return;
      _priceLoadGeneration++;
      setState(() { _isPriceLoading = false; _priceLoadFailed = true; });
    });
    try {
      final products = await _service.loadPaidProducts();
      if (!mounted || generation != _priceLoadGeneration) return;
      _priceTimer?.cancel();
      setState(() {
        _products..clear()..addEntries(products.map((product) => MapEntry(product.id, product)));
        _isPriceLoading = false;
        _priceLoadFailed = products.isEmpty;
      });
    } catch (_) {
      if (!mounted || generation != _priceLoadGeneration) return;
      _priceTimer?.cancel();
      setState(() { _isPriceLoading = false; _priceLoadFailed = true; });
    }
  }

  @override
  void dispose() {
    _priceLoadGeneration++;
    _priceTimer?.cancel();
    super.dispose();
  }

  String _price(String productId) {
    final price = _products[productId]?.price.trim();
    if (price != null && price.isNotEmpty) return '$price/เดือน';
    return _isPriceLoading ? 'กำลังโหลดราคา...' : 'ตรวจราคาในร้านค้า';
  }

  Future<void> _loadSubscription() async {
    final loadGeneration = ++_subscriptionLoadGeneration;

    setState(() {
      _isSubscriptionLoading = true;
      _subscriptionLoadError = null;
    });

    try {
      final loader =
          widget.loadSubscription ?? _apiClient.loadCurrentSubscription;
      final subscription = await loader();

      if (!mounted || loadGeneration != _subscriptionLoadGeneration) {
        return;
      }

      setState(() {
        _subscription = subscription;
        _isSubscriptionLoading = false;
        _subscriptionLoadError = null;
      });
    } catch (error) {
      if (!mounted || loadGeneration != _subscriptionLoadGeneration) {
        return;
      }

      setState(() {
        _isSubscriptionLoading = false;
        _subscriptionLoadError = error;
      });
    }
  }

  void _applyVerifiedSubscription(SubscriptionStatusResult subscription) {
    _subscriptionLoadGeneration += 1;
    setState(() {
      _subscription = subscription;
      _isSubscriptionLoading = false;
      _subscriptionLoadError = null;
    });
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
        price: _price(_service.starterProductId),
        isCurrent: currentPlanId == 'starter',
        features: const [
          _PlanFeature('โพสต์หลายช่องทาง 120 หน่วย/เดือน'),
          _PlanFeature('ตั้งเวลาล่วงหน้า 14 วัน + ปฏิทิน + เทมเพลต'),
          _PlanFeature('AI แคปชั่นจากเสียงคลิป 50 ครั้ง/เดือน'),
          _PlanFeature('ลายน้ำอัตโนมัติ'),
        ],
      ),
      _PlanOption(
        id: 'pro',
        name: 'Pro',
        price: _price(_service.productId),
        isCurrent: currentPlanId == 'pro',
        isRecommended: true,
        features: const [
          _PlanFeature('โพสต์หลายช่องทาง 250 หน่วย/เดือน'),
          _PlanFeature('ทุกอย่างใน Starter + วิเคราะห์เต็มรูปแบบ'),
          _PlanFeature('ตั้งเวลาล่วงหน้า 30 วัน'),
          _PlanFeature('AI แคปชั่นจากเสียง + ภาพ 120 ครั้ง/เดือน'),
        ],
      ),
    ];
  }

  Future<void> _subscribe(_PlanOption plan) async {
    if (plan.id == 'basic' ||
        _isBillingInProgress ||
        _isSubscriptionLoading ||
        _subscriptionLoadError != null ||
        _subscription == null ||
        _service.hasPendingConfirmation) {
      return;
    }

    setState(() => _isBillingInProgress = true);
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
    } on StoreSubscriptionConfirmationPendingException {
      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pop();
      setState(() {});
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
    } finally {
      if (mounted) setState(() => _isBillingInProgress = false);
    }
  }

  Future<void> _recheckPurchase() async {
    if (_isBillingInProgress || !_service.hasPendingConfirmation) return;
    setState(() => _isBillingInProgress = true);
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
              Expanded(child: Text('กำลังตรวจสอบการซื้อ...')),
            ],
          ),
        ),
      ),
    );

    try {
      final result = await _service.retryPendingConfirmation();
      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pop();
      _applyVerifiedSubscription(result.subscription);
      widget.onSubscribed?.call(result.subscription.plan.toLowerCase());
      _showRestoreSuccess(
        result.subscription.plan,
        title: 'ยืนยันการซื้อสำเร็จ',
      );
    } on StoreSubscriptionConfirmationPendingException catch (error) {
      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.message)),
      );
    } on StoreSubscriptionException catch (error) {
      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.message)),
      );
    } finally {
      if (mounted) setState(() => _isBillingInProgress = false);
    }
  }

  Future<void> _restorePurchase() async {
    if (_isBillingInProgress) return;
    setState(() => _isBillingInProgress = true);
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
    } finally {
      if (mounted) setState(() => _isBillingInProgress = false);
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

  void _showRestoreSuccess(String plan,
      {String title = 'กู้คืนการซื้อสำเร็จ'}) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.charcoal,
        title: Text(title),
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
              if (_isSubscriptionLoading)
                const _PaywallSubscriptionStatus(
                  key: ValueKey('paywall-subscription-loading'),
                  message: 'กำลังตรวจสอบแพ็กเกจปัจจุบัน...',
                  isLoading: true,
                )
              else if (_subscriptionLoadError != null)
                _PaywallSubscriptionStatus(
                  key: const ValueKey('paywall-subscription-error'),
                  message:
                      'โหลดแพ็กเกจปัจจุบันไม่สำเร็จ กรุณาลองใหม่ก่อนสมัคร หรือกู้คืนการซื้อเดิม',
                  onRetry: _loadSubscription,
                ),
              if (_isSubscriptionLoading || _subscriptionLoadError != null)
                const SizedBox(height: 13),
              if (_service.hasPendingConfirmation) ...[
                _PaywallSubscriptionStatus(
                  key: const ValueKey('paywall-purchase-awaiting-confirmation'),
                  message: _service.hasPendingStoreAcknowledgement
                      ? 'ร้านค้ายังปิดรายการซื้อไม่สำเร็จ กรุณาตรวจสอบรายการเดิมก่อนซื้อซ้ำ'
                      : _service.hasPendingStoreOperation
                          ? const StoreSubscriptionStorePendingException().message
                          : const StoreSubscriptionConfirmationPendingException().message,
                  onRetry: _isBillingInProgress ? null : _recheckPurchase,
                  retryKey: const ValueKey('paywall-retry-purchase'),
                  retryLabel: 'ตรวจสอบการซื้ออีกครั้ง',
                ),
                const SizedBox(height: 13),
              ],
              for (var index = 0; index < _plans.length; index += 1) ...[
                _PlanCard(
                  plan: _plans[index],
                  onSubscribe: !_isSubscriptionLoading &&
                          !_isBillingInProgress &&
                          !_service.hasPendingConfirmation &&
                          _subscriptionLoadError == null &&
                          _subscription != null
                      ? () => _subscribe(_plans[index])
                      : null,
                ),
                if (index < _plans.length - 1) const SizedBox(height: 13),
              ],
              const SizedBox(height: 16),
              if (_priceLoadFailed)
                TextButton(
                  key: const ValueKey('paywall-price-error'),
                  onPressed: _isBillingInProgress ? null : _loadPrices,
                  child: const Text('โหลดราคาจากร้านค้าอีกครั้ง'),
                ),
              if (_service.supportsUnifiedRestore) ...[
                SizedBox(
                  height: 48,
                  child: OutlinedButton.icon(
                    onPressed: _isBillingInProgress ? null : _restorePurchase,
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

class _PaywallSubscriptionStatus extends StatelessWidget {
  const _PaywallSubscriptionStatus({
    super.key,
    required this.message,
    this.isLoading = false,
    this.onRetry,
    this.retryKey = const ValueKey('paywall-retry-subscription'),
    this.retryLabel = 'ลองใหม่',
  });

  final String message;
  final bool isLoading;
  final VoidCallback? onRetry;
  final Key retryKey;
  final String retryLabel;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppTheme.glass,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              if (isLoading)
                const SizedBox.square(
                  dimension: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else
                Icon(
                  Icons.cloud_off_outlined,
                  size: 20,
                  color: AppTheme.textSecondary,
                ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  message,
                  style: TextStyle(
                    fontSize: 12.5,
                    height: 1.35,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textSecondary,
                  ),
                ),
              ),
            ],
          ),
          if (onRetry != null)
            TextButton(
              key: retryKey,
              onPressed: onRetry,
              child: Text(retryLabel),
            ),
        ],
      ),
    );
  }
}

class _PlanCard extends StatelessWidget {
  const _PlanCard({required this.plan, required this.onSubscribe});

  final _PlanOption plan;
  final VoidCallback? onSubscribe;

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
