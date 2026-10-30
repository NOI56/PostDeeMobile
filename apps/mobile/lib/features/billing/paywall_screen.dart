import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../core/auth/auth_session.dart';
import '../../core/localization/postdee_localizations.dart';
import '../../core/network/postdee_api_client.dart';
import '../../core/theme/app_theme.dart';
import 'store_subscription_service.dart';
import 'store_addon_service.dart';

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
    this.sessionStore,
    this.addonService,
    this.onAddonPurchased,
  });

  /// Called with the chosen plan id after a verified purchase.
  final ValueChanged<String>? onSubscribed;

  /// Injectable for tests; defaults to the real store + backend verifier.
  final StoreSubscriptionService? service;

  /// Loads the current subscription so the right plan is marked as active.
  /// Injectable for tests; defaults to the real backend.
  final PaywallSubscriptionLoader? loadSubscription;
  final StoreSubscriptionSessionCache? sessionCache;
  final PostDeeAuthSessionStore? sessionStore;
  final StoreAddonService? addonService;
  final VoidCallback? onAddonPurchased;

  @override
  State<PaywallScreen> createState() => _PaywallScreenState();
}

class _PaywallScreenState extends State<PaywallScreen> {
  late final _sessionStore =
      widget.sessionStore ?? PostDeeAuthSessionStore.instance;
  late final _screenBinding = _sessionStore.captureSession();
  late final StoreSubscriptionService _service = widget.service ??
      (widget.sessionCache ?? StoreSubscriptionSessionCache.instance).service;
  late final _apiClient = PostDeeApiClient(sessionBinding: _screenBinding);
  late final _addonService = widget.addonService ??
      (widget.sessionStore == null ? StoreAddonSessionCache.instance.service :
        StoreAddonService(sessionStore: widget.sessionStore));
  final _ownedDialogs = <DialogRoute<void>>{};
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
  AddonCatalogResult? _addonCatalog;
  StoreProductInfo? _addonProduct;
  var _addonLoading = true;
  var _addonLoadFailed = false;
  var _addonLoadGeneration = 0;

  @override
  void initState() {
    super.initState();
    _screenBinding.ensureCurrent();
    _sessionStore.addListener(_handleSessionChanged);
    _loadSubscription();
    _loadPrices();
    _loadAddon();
  }

  Future<void> _loadAddon() async {
    if (!_canUpdateScreen) return;
    final generation = ++_addonLoadGeneration;
    setState(() { _addonLoading = true; _addonLoadFailed = false; _addonProduct = null; });
    try {
      final catalog = await _addonService.loadCatalog();
      if (!_canUpdateScreen || generation != _addonLoadGeneration) return;
      final product = _addonService.supportsPlatform && catalog.enabled && catalog.eligible
          ? await _addonService.loadProduct(catalog) : null;
      if (!_canUpdateScreen || generation != _addonLoadGeneration) return;
      setState(() { _addonCatalog = catalog; _addonProduct = product; _addonLoading = false; });
    } catch (_) {
      if (!_canUpdateScreen || generation != _addonLoadGeneration) return;
      setState(() { _addonCatalog = null; _addonLoading = false; _addonLoadFailed = true; });
    }
  }

  Future<void> _buyAddon({bool retry = false}) async {
    if (!_canUpdateScreen || !_addonService.supportsPlatform || _isBillingInProgress || _service.hasPendingConfirmation ||
        (!retry && (_addonService.hasPendingPurchase || _addonProduct == null ||
          _addonCatalog?.enabled != true || _addonCatalog?.eligible != true))) {
      return;
    }
    setState(() => _isBillingInProgress = true);
    final progress = _showProgress(retry ? 'กำลังตรวจสอบการซื้อ...' : 'กำลังซื้อแพ็กเติม...');
    try {
      final result = retry ? await _addonService.retryPendingPurchase() : await _addonService.purchase();
      if (!_canUpdateScreen || !result.confirmed) return;
      await _loadSubscription();
      if (!_canUpdateScreen) return;
      widget.onAddonPurchased?.call();
      if (!_canUpdateScreen) return;
      _showOwnedDialog((context) => AlertDialog(
        title: const _PaywallText('เติมเครดิตสำเร็จ'),
        content: const _PaywallText('เพิ่มเครดิตโพสต์ 100 หน่วย และ AI แคปชั่น 50 เครดิตแล้ว เครดิตซื้อเพิ่มไม่หมดอายุ และใช้โควตารายเดือนก่อน'),
        actions: [TextButton(onPressed: () => Navigator.of(context).pop(), child: const _PaywallText('ตกลง'))],
      ));
      unawaited(_loadAddon());
    } on AuthSessionChangedException {
      _showBillingError('บัญชีเปลี่ยนแล้ว กรุณาเปิดหน้าแพ็กเกจใหม่');
    } on StoreAddonPendingException {
      if (_canUpdateScreen) setState(() {});
    } on StoreAddonException catch (error) {
      _showBillingError(error.message);
    } on StoreSubscriptionException catch (error) {
      _showBillingError(error.message);
    } catch (_) {
      _showBillingError('ซื้อแพ็กเติมไม่สำเร็จ กรุณาลองใหม่');
    } finally {
      _closeOwnedDialog(progress);
      if (_canUpdateScreen) setState(() => _isBillingInProgress = false);
    }
  }

  Future<void> _loadPrices() async {
    if (!_screenBinding.isCurrent) return;
    final generation = ++_priceLoadGeneration;
    _priceTimer?.cancel();
    setState(() { _isPriceLoading = true; _priceLoadFailed = false; });
    _priceTimer = Timer(_service.productQueryTimeout, () {
      if (!_canUpdateScreen || generation != _priceLoadGeneration) return;
      _priceLoadGeneration++;
      setState(() { _isPriceLoading = false; _priceLoadFailed = true; });
    });
    try {
      final products = await _service.loadPaidProducts();
      if (!_canUpdateScreen || generation != _priceLoadGeneration) return;
      _priceTimer?.cancel();
      setState(() {
        _products..clear()..addEntries(products.map((product) => MapEntry(product.id, product)));
        _isPriceLoading = false;
        _priceLoadFailed = products.isEmpty;
      });
    } catch (_) {
      if (!_canUpdateScreen || generation != _priceLoadGeneration) return;
      _priceTimer?.cancel();
      setState(() { _isPriceLoading = false; _priceLoadFailed = true; });
    }
  }

  @override
  void dispose() {
    _sessionStore.removeListener(_handleSessionChanged);
    _subscriptionLoadGeneration++;
    _priceLoadGeneration++;
    _addonLoadGeneration++;
    _priceTimer?.cancel();
    final ownedDialogs = _ownedDialogs.toList();
    _ownedDialogs.clear();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      for (final route in ownedDialogs) {
        _removeOwnedRoute(route);
      }
    });
    super.dispose();
  }

  String _price(String productId) {
    final price = _products[productId]?.price.trim();
    if (price != null && price.isNotEmpty) {
      return _paywallText(context, '$price/เดือน', '$price/month');
    }
    return _isPriceLoading ? 'กำลังโหลดราคา...' : 'ตรวจราคาในร้านค้า';
  }

  Future<void> _loadSubscription() async {
    if (!_screenBinding.isCurrent) return;
    final loadGeneration = ++_subscriptionLoadGeneration;

    setState(() {
      _isSubscriptionLoading = true;
      _subscriptionLoadError = null;
    });

    try {
      final loader =
          widget.loadSubscription ?? _apiClient.loadCurrentSubscription;
      final subscription = await loader();

      if (!_canUpdateScreen || loadGeneration != _subscriptionLoadGeneration) {
        return;
      }

      setState(() {
        _subscription = subscription;
        _isSubscriptionLoading = false;
        _subscriptionLoadError = null;
      });
    } catch (error) {
      if (!_canUpdateScreen || loadGeneration != _subscriptionLoadGeneration) {
        return;
      }

      setState(() {
        _isSubscriptionLoading = false;
        _subscriptionLoadError = error;
      });
    }
  }

  void _applyVerifiedSubscription(SubscriptionStatusResult subscription) {
    if (!_canUpdateScreen) return;
    _subscriptionLoadGeneration += 1;
    setState(() {
      _subscription = subscription;
      _isSubscriptionLoading = false;
      _subscriptionLoadError = null;
    });
    unawaited(_loadAddon());
  }

  bool get _canUpdateScreen => mounted && _screenBinding.isCurrent;

  void _handleSessionChanged() {
    if (_screenBinding.isCurrent || !mounted) return;
    _subscriptionLoadGeneration++;
    _priceLoadGeneration++;
    _addonLoadGeneration++;
    _priceTimer?.cancel();
    for (final route in _ownedDialogs.toList()) {
      _closeOwnedDialog(route);
    }
    setState(() {
      _subscription = null;
      _subscriptionLoadError = const AuthSessionChangedException();
      _isSubscriptionLoading = false;
      _products.clear();
      _isPriceLoading = false;
      _priceLoadFailed = false;
      _isBillingInProgress = false;
      _addonCatalog = null;
      _addonProduct = null;
      _addonLoading = false;
    });
  }

  DialogRoute<void> _showOwnedDialog(WidgetBuilder builder,
      {bool barrierDismissible = true}) {
    final route = DialogRoute<void>(
      context: context,
      barrierDismissible: barrierDismissible,
      builder: builder,
    );
    _ownedDialogs.add(route);
    unawaited(Navigator.of(context, rootNavigator: true).push(route).then<void>(
      (_) => _ownedDialogs.remove(route),
      onError: (Object _, StackTrace __) => _ownedDialogs.remove(route),
    ));
    return route;
  }

  static void _removeOwnedRoute(DialogRoute<void> route) {
    final navigator = route.navigator;
    if (navigator != null && navigator.mounted && route.isActive) {
      navigator.removeRoute(route);
    }
  }

  void _closeOwnedDialog(DialogRoute<void> route) {
    _ownedDialogs.remove(route);
    final phase = WidgetsBinding.instance.schedulerPhase;
    if (phase == SchedulerPhase.persistentCallbacks ||
        phase == SchedulerPhase.transientCallbacks) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _removeOwnedRoute(route));
    } else {
      _removeOwnedRoute(route);
    }
  }

  DialogRoute<void> _showProgress(String message) => _showOwnedDialog(
        (_) => PopScope(
          canPop: false,
          child: AlertDialog(
            backgroundColor: AppTheme.charcoal,
            content: Row(children: [
              const CircularProgressIndicator(color: AppTheme.accent),
              const SizedBox(width: AppTheme.spaceLg),
              Expanded(child: _PaywallText(message)),
            ]),
          ),
        ),
        barrierDismissible: false,
      );

  void _showBillingError(String message) {
    if (!_canUpdateScreen) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: _PaywallText(message)));
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
        price: _paywallText(context, 'ฟรี', 'Free'),
        isCurrent: currentPlanId == 'basic',
        features: const [
          _PlanFeature('โพสต์ฟรี 3 หน่วย/เดือนหลังยืนยันเบอร์'),
          _PlanFeature('ลิงก์ร้านสูงสุด 2 ลิงก์'),
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
          _PlanFeature('ลิงก์ร้านสูงสุด 7 ลิงก์'),
          _PlanFeature('ตั้งเวลาล่วงหน้า 14 วัน + ปฏิทิน + เทมเพลต'),
          _PlanFeature('AI แคปชั่นจากเสียงคลิป 50 เครดิต/เดือน'),
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
          _PlanFeature('ลิงก์ร้านสูงสุด 20 ลิงก์'),
          _PlanFeature('ทุกอย่างใน Starter + วิเคราะห์เต็มรูปแบบ'),
          _PlanFeature('ตั้งเวลาล่วงหน้า 30 วัน'),
          _PlanFeature('AI แคปชั่นจากเสียง + ภาพ 120 เครดิต/เดือน'),
        ],
      ),
    ];
  }

  Future<void> _subscribe(_PlanOption plan) async {
    if (!_canUpdateScreen ||
        plan.id == 'basic' ||
        _isBillingInProgress ||
        _isSubscriptionLoading ||
        _subscriptionLoadError != null ||
        _subscription == null ||
        _service.hasPendingConfirmation) {
      return;
    }

    setState(() => _isBillingInProgress = true);
    final progress = _showProgress('กำลังดำเนินการสั่งซื้อ...');

    try {
      // Real store purchase → backend receipt verification → entitlement.
      final result = plan.id == 'pro'
          ? await _service.startProSubscription()
          : await _service.startStarterSubscription();
      if (!_canUpdateScreen) return;
      _applyVerifiedSubscription(result.subscription);
      widget.onSubscribed?.call(plan.id);
      if (_canUpdateScreen) _showSuccess(plan);
    } on AuthSessionChangedException {
      _showBillingError('บัญชีเปลี่ยนแล้ว กรุณาเปิดหน้าแพ็กเกจใหม่');
    } on StoreSubscriptionConfirmationPendingException {
      if (_canUpdateScreen) setState(() {});
    } on StoreSubscriptionException catch (error) {
      _showBillingError(error.message);
    } catch (_) {
      _showBillingError('สมัครไม่สำเร็จ ลองใหม่อีกครั้ง');
    } finally {
      _closeOwnedDialog(progress);
      if (_canUpdateScreen) setState(() => _isBillingInProgress = false);
    }
  }

  Future<void> _recheckPurchase() async {
    if (!_canUpdateScreen ||
        _isBillingInProgress ||
        !_service.hasPendingConfirmation) {
      return;
    }
    setState(() => _isBillingInProgress = true);
    final progress = _showProgress('กำลังตรวจสอบการซื้อ...');

    try {
      final result = await _service.retryPendingConfirmation();
      if (!_canUpdateScreen) return;
      _applyVerifiedSubscription(result.subscription);
      widget.onSubscribed?.call(result.subscription.plan.toLowerCase());
      if (_canUpdateScreen) {
        _showRestoreSuccess(
          result.subscription.plan,
          title: 'ยืนยันการซื้อสำเร็จ',
        );
      }
    } on AuthSessionChangedException {
      _showBillingError('บัญชีเปลี่ยนแล้ว กรุณาเปิดหน้าแพ็กเกจใหม่');
    } on StoreSubscriptionException catch (error) {
      _showBillingError(error.message);
    } catch (_) {
      _showBillingError('ตรวจสอบการซื้อไม่สำเร็จ ลองใหม่อีกครั้ง');
    } finally {
      _closeOwnedDialog(progress);
      if (_canUpdateScreen) setState(() => _isBillingInProgress = false);
    }
  }

  Future<void> _restorePurchase() async {
    if (!_canUpdateScreen || _isBillingInProgress || _addonService.hasPendingPurchase) return;
    setState(() => _isBillingInProgress = true);
    final progress = _showProgress('กำลังกู้คืนการซื้อ...');

    try {
      final result = await _service.restoreSubscription();
      if (!_canUpdateScreen) return;
      _applyVerifiedSubscription(result.subscription);
      widget.onSubscribed?.call(result.subscription.plan.toLowerCase());
      if (_canUpdateScreen) _showRestoreSuccess(result.subscription.plan);
    } on AuthSessionChangedException {
      _showBillingError('บัญชีเปลี่ยนแล้ว กรุณาเปิดหน้าแพ็กเกจใหม่');
    } on StoreSubscriptionException catch (error) {
      _showBillingError(error.message);
    } catch (_) {
      _showBillingError('กู้คืนการซื้อไม่สำเร็จ ลองใหม่อีกครั้ง');
    } finally {
      _closeOwnedDialog(progress);
      if (_canUpdateScreen) setState(() => _isBillingInProgress = false);
    }
  }

  void _showSuccess(_PlanOption plan) {
    _showOwnedDialog(
      (context) => AlertDialog(
        backgroundColor: AppTheme.charcoal,
        title: Text(_paywallText(context, 'สมัคร ${plan.name} สำเร็จ', 'Subscribed to ${plan.name}')),
        content: const _PaywallText('ปลดล็อกฟีเจอร์ของแพ็กเกจเรียบร้อยแล้ว'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const _PaywallText('ตกลง'),
          ),
        ],
      ),
    );
  }

  void _showRestoreSuccess(String plan,
      {String title = 'กู้คืนการซื้อสำเร็จ'}) {
    _showOwnedDialog(
      (context) => AlertDialog(
        backgroundColor: AppTheme.charcoal,
        title: _PaywallText(title),
        content: Text(_paywallText(context, 'คืนสิทธิ์แพ็กเกจ ${plan.toUpperCase()} เรียบร้อยแล้ว', '${plan.toUpperCase()} plan access has been restored.')),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const _PaywallText('ตกลง'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final titleScale = MediaQuery.textScalerOf(context).scale(16) / 16;
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: kToolbarHeight * (titleScale < 1 ? 1 : titleScale),
        title: const _PaywallText(
          'เลือกแพ็กเกจ',
          maxLines: 2,
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
      ),
      body: SafeArea(
        child: DecoratedBox(
          decoration: AppTheme.screenBackground,
          child: ListView(
            padding: AppTheme.screenPadding,
            children: [
              _PaywallText(
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
                  message: _screenBinding.isCurrent
                      ? 'โหลดแพ็กเกจปัจจุบันไม่สำเร็จ กรุณาลองใหม่ก่อนสมัคร หรือกู้คืนการซื้อเดิม'
                      : 'บัญชีเปลี่ยนแล้ว กรุณาเปิดหน้าแพ็กเกจใหม่',
                  onRetry: _screenBinding.isCurrent ? _loadSubscription : null,
                ),
              if (_isSubscriptionLoading || _subscriptionLoadError != null)
                const SizedBox(height: 13),
              if (_screenBinding.isCurrent && _service.hasPendingConfirmation) ...[
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
                  onSubscribe: _screenBinding.isCurrent &&
                          !_isSubscriptionLoading &&
                          !_isBillingInProgress &&
                          !_service.hasPendingConfirmation &&
                          !_addonService.hasPendingPurchase &&
                          _subscriptionLoadError == null &&
                          _subscription != null
                      ? () => _subscribe(_plans[index])
                      : null,
                ),
                if (index < _plans.length - 1) const SizedBox(height: 13),
              ],
              const SizedBox(height: 16),
              _buildAddonCard(),
              const SizedBox(height: 16),
              if (_priceLoadFailed)
                TextButton(
                  key: const ValueKey('paywall-price-error'),
                  onPressed: !_screenBinding.isCurrent || _isBillingInProgress
                      ? null : _loadPrices,
                  child: const _PaywallText('โหลดราคาจากร้านค้าอีกครั้ง'),
                ),
              if (_service.supportsUnifiedRestore) ...[
                ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 48),
                  child: OutlinedButton.icon(
                    onPressed: !_screenBinding.isCurrent || _isBillingInProgress || _addonService.hasPendingPurchase
                        ? null : _restorePurchase,
                    icon: const Icon(Icons.restore, size: 19),
                    label: const _PaywallText('กู้คืนการซื้อ'),
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
              _PaywallText(
                'ราคาจริงจะแสดงตามร้านค้าของแต่ละประเทศ · แพ็กเกจรายเดือนยกเลิกได้ทุกเมื่อ',
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

  void _showAddonHelp() {
    if (!_canUpdateScreen) return;
    _showOwnedDialog((dialogContext) => AlertDialog(
      title: const _PaywallText('ช่วยตรวจสอบการซื้อ'),
      scrollable: true,
      content: SelectableText(_paywallMessage(dialogContext,
        'อย่าซื้อซ้ำระหว่างที่รายการเดิมยังรอยืนยัน '
        'คุณปิดหน้านี้ได้ แล้วกลับมาตรวจสอบการซื้อแพ็กเติมอีกครั้ง\n\n'
        'หากชำระเงินแล้วแต่เครดิตยังไม่เข้า ติดต่อ postdee.support@gmail.com '
        'พร้อมเลขคำสั่งซื้อหรือหลักฐานจาก Google Play / App Store '
        'และอีเมลบัญชี PostDee ที่ใช้ซื้อ ไม่ต้องส่งรหัสผ่าน',
      )),
      actions: [TextButton(onPressed: () => Navigator.of(dialogContext).pop(),
        child: const _PaywallText('รับทราบ'))],
    ));
  }

  Widget _buildAddonCard() {
    final catalog = _addonCatalog;
    final pending = _addonService.hasPendingPurchase;
    final canBuy = _addonService.supportsPlatform && _canUpdateScreen && !_addonLoading && !_isBillingInProgress &&
        !_service.hasPendingConfirmation && !pending && !_isSubscriptionLoading &&
        _subscriptionLoadError == null && _subscription != null &&
        catalog?.enabled == true && catalog?.eligible == true && _addonProduct != null;
    final message = !_addonService.supportsPlatform ? _addonService.platformUnavailableMessage
        : _addonLoading ? 'กำลังตรวจสอบแพ็กเติม...'
        : _addonLoadFailed ? 'ตรวจสอบแพ็กเติมไม่สำเร็จ กรุณาลองใหม่'
        : catalog?.enabled != true ? 'แพ็กเติมยังไม่เปิดขาย'
        : catalog?.eligible == false ? 'สำหรับสมาชิก Starter หรือ Pro · เลือกสมัครแพ็กเกจด้านบนก่อน'
        : _addonProduct == null ? 'ยังโหลดแพ็กเติมจากร้านค้าไม่ได้'
        : 'ซื้อเพิ่มได้หลายครั้ง';
    return Container(
      key: const ValueKey('paywall-addon-card'), padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: AppTheme.glass, borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.border)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const _PaywallText('แพ็กเติม ซื้อครั้งเดียว', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        const _PaywallText('โพสต์เพิ่ม 100 หน่วย + AI แคปชั่น 50 เครดิต', style: TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 6),
        _PaywallText('ราคาไทย 49 บาท · ชำระตามราคาที่ร้านค้าแสดง', style: TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
        const SizedBox(height: 8),
        _PaywallText(message, style: TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
        if (catalog != null && (catalog.addonPostUnits > 0 || catalog.addonAiCaptions > 0)) ...[
          const SizedBox(height: 6),
          Text(_paywallText(context, 'เครดิตคงเหลือ: โพสต์ ${catalog.addonPostUnits} หน่วย · AI ${catalog.addonAiCaptions} เครดิต', 'Credits remaining: ${catalog.addonPostUnits} post units · ${catalog.addonAiCaptions} AI caption credits'),
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.textSecondary)),
        ],
        const SizedBox(height: 6),
        _PaywallText('เครดิตซื้อเพิ่มไม่หมดอายุ · ใช้โควตารายเดือนก่อน · ไม่ต่ออายุอัตโนมัติ',
          style: TextStyle(fontSize: 11, color: AppTheme.textMuted)),
        const SizedBox(height: 6),
        _PaywallText('1 ช่องทางใช้ 1 หน่วย · ใช้เครดิตได้เมื่อเป็นสมาชิก Starter หรือ Pro หากสมาชิกหมดอายุ เครดิตยังคงอยู่',
          style: TextStyle(fontSize: 11, color: AppTheme.textMuted)),
        if (pending) ...[
          const SizedBox(height: 12),
          _PaywallText(const StoreAddonPendingException().message, style: TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
          TextButton(key: const ValueKey('paywall-retry-addon'),
            onPressed: _addonService.supportsPlatform && _canUpdateScreen && !_isBillingInProgress ? () => _buyAddon(retry: true) : null,
            child: const _PaywallText('ตรวจสอบการซื้อแพ็กเติมอีกครั้ง')),
          TextButton.icon(key: const ValueKey('paywall-addon-help'),
            onPressed: _canUpdateScreen ? _showAddonHelp : null,
            icon: const Icon(Icons.support_agent, size: 18),
            label: const _PaywallText('ขอความช่วยเหลือเรื่องการซื้อ')),
        ],
        const SizedBox(height: 12),
        SizedBox(width: double.infinity, child: FilledButton(
          key: const ValueKey('paywall-buy-addon'), onPressed: canBuy ? () => _buyAddon() : null,
          child: _addonProduct == null ? const _PaywallText('ซื้อแพ็กเติม') : Text(_paywallText(context, 'ซื้อครั้งเดียว ${_addonProduct!.price}', 'One-time purchase ${_addonProduct!.price}')),
        )),
        if (_addonService.supportsPlatform && !_addonLoading && (_addonLoadFailed || catalog?.enabled == true && _addonProduct == null && catalog?.eligible == true))
          TextButton(onPressed: _canUpdateScreen && !_isBillingInProgress ? _loadAddon : null, child: const _PaywallText('โหลดแพ็กเติมอีกครั้ง')),
      ]),
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
                child: _PaywallText(
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
              child: _PaywallText(retryLabel),
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
          _PaywallText(
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
                    child: _PaywallText(
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
            ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 48),
              child: FilledButton.icon(
                onPressed: onSubscribe,
                icon: const Icon(Icons.workspace_premium_outlined, size: 19),
                label: Text(_paywallText(context, 'สมัคร ${plan.name}', 'Subscribe ${plan.name}')),
                style: FilledButton.styleFrom(
                  backgroundColor: AppTheme.actionBackground,
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
        child: _PaywallText(
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

class _PaywallText extends StatelessWidget {
  const _PaywallText(this.message, {this.style, this.textAlign, this.maxLines});

  final String message;
  final TextStyle? style;
  final TextAlign? textAlign;
  final int? maxLines;

  @override
  Widget build(BuildContext context) => Text(
        _paywallMessage(context, message),
        style: style,
        textAlign: textAlign,
        maxLines: maxLines,
      );
}

bool _paywallUsesThai(BuildContext context) =>
    (Localizations.of<PostDeeLocalizations>(context, PostDeeLocalizations)
                ?.locale.languageCode ??
            'th') ==
        'th';

String _paywallText(BuildContext context, String thai, String english) =>
    _paywallUsesThai(context) ? thai : english;

String _paywallMessage(BuildContext context, String message) =>
    _paywallUsesThai(context)
        ? message
        : _englishPaywallMessages[message] ?? message;

// Translate app-owned messages at presentation time. Store prices and unknown
// provider errors retain their original values; billing services stay unchanged.
const _englishPaywallMessages = <String, String>{
  'เลือกแพ็กเกจ': 'Choose a plan',
  'อัปเกรดเพื่อปลดล็อกการตั้งเวลา AI แคปชั่น และวิเคราะห์เต็มรูปแบบ':
      'Upgrade to unlock scheduling, AI captions, and full analytics',
  'กำลังโหลดราคา...': 'Loading prices...',
  'ตรวจราคาในร้านค้า': 'Check prices in the store',
  'กำลังตรวจสอบแพ็กเกจปัจจุบัน...': 'Checking current plan...',
  'โหลดแพ็กเกจปัจจุบันไม่สำเร็จ กรุณาลองใหม่ก่อนสมัคร หรือกู้คืนการซื้อเดิม':
      'Could not load your current plan. Try again before subscribing, or restore your previous purchase.',
  'บัญชีเปลี่ยนแล้ว กรุณาเปิดหน้าแพ็กเกจใหม่':
      'Your account has changed. Please reopen the plans page.',
  'ร้านค้ายังปิดรายการซื้อไม่สำเร็จ กรุณาตรวจสอบรายการเดิมก่อนซื้อซ้ำ':
      'Your store has not finished the previous purchase. Check it before buying again.',
  'ตรวจสอบการซื้ออีกครั้ง': 'Check purchase again',
  'โหลดราคาจากร้านค้าอีกครั้ง': 'Reload store prices',
  'กู้คืนการซื้อ': 'Restore purchases',
  'ราคาจริงจะแสดงตามร้านค้าของแต่ละประเทศ · แพ็กเกจรายเดือนยกเลิกได้ทุกเมื่อ':
      'Prices vary by store and country · Cancel monthly plans at any time',
  'โพสต์ฟรี 3 หน่วย/เดือนหลังยืนยันเบอร์':
      '3 free post units/month after phone verification',
  'ลิงก์ร้านสูงสุด 2 ลิงก์': 'Up to 2 store links',
  'ต้องยืนยันเบอร์ก่อนโพสต์': 'Phone verification required to post',
  'ไม่มี AI แคปชั่นและการตั้งเวลา': 'No AI captions or scheduling',
  'โพสต์หลายช่องทาง 120 หน่วย/เดือน': '120 multi-channel post units/month',
  'ลิงก์ร้านสูงสุด 7 ลิงก์': 'Up to 7 store links',
  'ตั้งเวลาล่วงหน้า 14 วัน + ปฏิทิน + เทมเพลต':
      'Schedule up to 14 days ahead + Calendar + Templates',
  'AI แคปชั่นจากเสียงคลิป 50 เครดิต/เดือน':
      'AI captions from clip audio: 50 credits/month',
  'ลายน้ำอัตโนมัติ': 'Automatic watermark',
  'โพสต์หลายช่องทาง 250 หน่วย/เดือน': '250 multi-channel post units/month',
  'ลิงก์ร้านสูงสุด 20 ลิงก์': 'Up to 20 store links',
  'ทุกอย่างใน Starter + วิเคราะห์เต็มรูปแบบ':
      'Everything in Starter + full analytics',
  'ตั้งเวลาล่วงหน้า 30 วัน': 'Schedule up to 30 days ahead',
  'AI แคปชั่นจากเสียง + ภาพ 120 เครดิต/เดือน':
      'AI captions from audio + images: 120 credits/month',
  'แนะนำ': 'Recommended',
  'แพ็กเกจปัจจุบัน': 'Current plan',
  'ลองใหม่': 'Try again',
  'กำลังดำเนินการสั่งซื้อ...': 'Processing your purchase...',
  'กำลังตรวจสอบการซื้อ...': 'Checking your purchase...',
  'กำลังกู้คืนการซื้อ...': 'Restoring purchases...',
  'กำลังซื้อแพ็กเติม...': 'Buying credit pack...',
  'ยืนยันการซื้อสำเร็จ': 'Purchase confirmed',
  'กู้คืนการซื้อสำเร็จ': 'Purchases restored',
  'ปลดล็อกฟีเจอร์ของแพ็กเกจเรียบร้อยแล้ว':
      'Your plan features are now unlocked.',
  'ตกลง': 'OK',
  'สมัครไม่สำเร็จ ลองใหม่อีกครั้ง': 'Could not subscribe. Please try again.',
  'ตรวจสอบการซื้อไม่สำเร็จ ลองใหม่อีกครั้ง':
      'Could not check your purchase. Please try again.',
  'กู้คืนการซื้อไม่สำเร็จ ลองใหม่อีกครั้ง':
      'Could not restore purchases. Please try again.',
  'ซื้อแพ็กเติมไม่สำเร็จ กรุณาลองใหม่':
      'Could not buy the credit pack. Please try again.',
  'เติมเครดิตสำเร็จ': 'Credits added',
  'เพิ่มเครดิตโพสต์ 100 หน่วย และ AI แคปชั่น 50 เครดิตแล้ว เครดิตซื้อเพิ่มไม่หมดอายุ และใช้โควตารายเดือนก่อน':
      'Added 100 post units and 50 AI caption credits. Purchased credits do not expire. Your monthly quota is used first.',
  'แพ็กเติม ซื้อครั้งเดียว': 'One-time credit pack',
  'โพสต์เพิ่ม 100 หน่วย + AI แคปชั่น 50 เครดิต':
      '100 post units + 50 AI caption credits',
  'ราคาไทย 49 บาท · ชำระตามราคาที่ร้านค้าแสดง':
      'Thailand price: THB 49 · Pay the price shown by your store',
  'กำลังตรวจสอบแพ็กเติม...': 'Loading credit pack...',
  'ตรวจสอบแพ็กเติมไม่สำเร็จ กรุณาลองใหม่':
      'Could not load credit pack. Please try again.',
  'แพ็กเติมยังไม่เปิดขาย': 'Credit packs are not on sale yet',
  'สำหรับสมาชิก Starter หรือ Pro · เลือกสมัครแพ็กเกจด้านบนก่อน':
      'For Starter or Pro members · Subscribe to a plan above first',
  'ยังโหลดแพ็กเติมจากร้านค้าไม่ได้':
      'Could not load the credit pack from your store.',
  'ซื้อเพิ่มได้หลายครั้ง': 'Available for repeat purchases',
  'เครดิตซื้อเพิ่มไม่หมดอายุ · ใช้โควตารายเดือนก่อน · ไม่ต่ออายุอัตโนมัติ':
      'Purchased credits do not expire · Monthly quota is used first · No automatic renewal',
  '1 ช่องทางใช้ 1 หน่วย · ใช้เครดิตได้เมื่อเป็นสมาชิก Starter หรือ Pro หากสมาชิกหมดอายุ เครดิตยังคงอยู่':
      '1 channel uses 1 post unit · Credits are usable with Starter or Pro. Your credits are retained if your subscription expires.',
  'ตรวจสอบการซื้อแพ็กเติมอีกครั้ง': 'Check credit pack purchase again',
  'ขอความช่วยเหลือเรื่องการซื้อ': 'Get purchase help',
  'ซื้อแพ็กเติม': 'Buy credit pack',
  'โหลดแพ็กเติมอีกครั้ง': 'Reload credit pack',
  'ช่วยตรวจสอบการซื้อ': 'Purchase help',
  'รับทราบ': 'Got it',
  'อย่าซื้อซ้ำระหว่างที่รายการเดิมยังรอยืนยัน '
      'คุณปิดหน้านี้ได้ แล้วกลับมาตรวจสอบการซื้อแพ็กเติมอีกครั้ง\n\n'
      'หากชำระเงินแล้วแต่เครดิตยังไม่เข้า ติดต่อ postdee.support@gmail.com '
      'พร้อมเลขคำสั่งซื้อหรือหลักฐานจาก Google Play / App Store '
      'และอีเมลบัญชี PostDee ที่ใช้ซื้อ ไม่ต้องส่งรหัสผ่าน':
      'Do not buy again while your previous purchase is awaiting confirmation. You can close this page and check the credit pack purchase again later.\n\n'
          'If you have paid but your credits have not arrived, contact postdee.support@gmail.com with your order number or proof of purchase from Google Play / App Store and the PostDee account email used for the purchase. Do not send your password.',
  'รายการเดิมยังรอยืนยัน กรุณาตรวจสอบการซื้ออีกครั้งโดยไม่ต้องซื้อซ้ำ':
      'Your previous purchase is awaiting confirmation. Check it again without buying again.',
  'ยังไม่ทราบผลจากร้านค้า กรุณาตรวจสอบรายการเดิมก่อนซื้อซ้ำ':
      'The store result is not known yet. Check your previous purchase before buying again.',
  'ร้านค้าดำเนินการซื้อแล้ว แต่ PostDee ยังยืนยันแพ็กเกจไม่ได้ กรุณาตรวจสอบการซื้ออีกครั้งโดยไม่ต้องซื้อซ้ำ':
      'Your store has processed the purchase, but PostDee could not confirm your plan yet. Check the purchase again without buying again.',
  'ร้านค้ายังไม่ยืนยันผลการซื้อ กรุณาตรวจสอบรายการเดิมก่อนซื้อซ้ำ':
      'Your store has not confirmed the purchase result yet. Check your previous purchase before buying again.',
  'ยกเลิกการซื้อแพ็กเติมแล้ว': 'Credit pack purchase canceled',
  'ยังไม่เริ่มชำระเงิน กรุณาโหลดแพ็กเติมแล้วลองใหม่':
      'Payment has not started. Reload the credit pack and try again.',
  'ไม่มีรายการซื้อที่รอยืนยัน': 'There is no purchase awaiting confirmation.',
  'ระบบสมาชิกยังไม่พร้อมสำหรับแอปเวอร์ชันนี้ กรุณาลองใหม่ภายหลัง':
      'Subscriptions are unavailable for this app version. Please try again later.',
  'ระบบกู้คืนสมาชิกยังตั้งค่าไม่เสร็จ กรุณาลองใหม่ภายหลัง':
      'Subscription restore setup is incomplete. Please try again later.',
  'พบรายการสมาชิกแล้ว แต่แพ็กเกจยังเชื่อมกับระบบไม่ถูกต้อง กรุณาติดต่อทีม PostDee':
      'A subscription was found, but its plan is not linked correctly. Please contact PostDee support.',
  'เชื่อมต่อระบบสมาชิกไม่สำเร็จ กรุณาลองใหม่อีกครั้ง':
      'Could not connect to the subscription service. Please try again.',
  'ไม่พบรายการสมาชิกที่กู้คืนได้ในบัญชีนี้':
      'No restorable subscription was found for this account.',
  'ร้านค้ายังไม่รองรับแพ็กเติมในรุ่นนี้':
      'Your store does not support credit packs in this version.',
  'แพ็กเติมนี้รองรับบน Android และ iPhone เท่านั้น':
      'Credit packs are supported on Android and iPhone only.',
  'แพ็กเติมยังไม่พร้อมซื้อสำหรับบัญชีนี้ กรุณาตรวจสอบแพ็กเกจอีกครั้ง':
      'Credit packs are not available for this account. Please check your plan again.',
  'ยังโหลดแพ็กเติมจากร้านค้าไม่ได้ กรุณาลองใหม่':
      'Could not load the credit pack from your store. Please try again.',
  'ระบบซื้อเครดิตยังไม่พร้อม กรุณาโหลดแพ็กเติมใหม่':
      'Credit purchases are unavailable. Please reload the credit pack.',
  'รายการนี้ได้รับการคืนเงินหรือยกเลิกแล้ว จึงไม่เพิ่มเครดิต':
      'This purchase was refunded or canceled, so no credits were added.',
};
