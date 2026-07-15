import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/theme/app_theme.dart';

/// Persists whether the user finished (or skipped) first-run onboarding, so
/// the flow shows exactly once after the first sign-in.
class OnboardingSeenStore {
  const OnboardingSeenStore();

  static const _seenKey = 'postdee_onboarding_seen';

  /// When storage is unavailable (e.g. plugin missing in tests) treat the flow
  /// as already seen so onboarding never blocks the app.
  Future<bool> loadSeen() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(_seenKey) ?? false;
    } catch (_) {
      return true;
    }
  }

  Future<void> markSeen() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_seenKey, true);
    } catch (_) {
      // Non-fatal: worst case the flow shows again next launch.
    }
  }
}

class _OnboardingStep {
  const _OnboardingStep({
    required this.icon,
    required this.title,
    required this.description,
  });

  final IconData icon;
  final String title;
  final String description;
}

// Copy comes verbatim from the design handoff's OB_STEPS.
const _steps = [
  _OnboardingStep(
    icon: Icons.hub_outlined,
    title: 'เชื่อมช่องทางครั้งเดียว',
    description:
        'ต่อ TikTok, YouTube Shorts, Instagram Reels และ Facebook Video ครั้งเดียว ไม่ต้องสลับหลายแอป',
  ),
  _OnboardingStep(
    icon: Icons.movie_outlined,
    title: 'คลิปเดียว โพสต์ได้ทุกที่',
    description:
        'เลือกวิดีโอ 9:16 หนึ่งคลิป แล้วส่งขึ้นทุกช่องทางพร้อมกัน พร้อม AI ช่วยใส่แคปชั่นภาษาไทย',
  ),
  _OnboardingStep(
    icon: Icons.insights_outlined,
    title: 'ตั้งเวลา + ดูยอดที่เดียว',
    description:
        'วางแผนโพสต์ในปฏิทิน แล้วดูยอดวิว ไลก์ และเอนเกจเมนต์รวมทุกแพลตฟอร์มในหน้าเดียว',
  ),
];

/// Three-step first-run intro, per design screen #2.
class OnboardingFlow extends StatefulWidget {
  const OnboardingFlow({super.key, required this.onFinished});

  final VoidCallback onFinished;

  @override
  State<OnboardingFlow> createState() => _OnboardingFlowState();
}

class _OnboardingFlowState extends State<OnboardingFlow> {
  int _step = 0;

  bool get _isLastStep => _step == _steps.length - 1;

  void _next() {
    if (_isLastStep) {
      widget.onFinished();
      return;
    }
    setState(() => _step += 1);
  }

  void _back() {
    if (_step > 0) {
      setState(() => _step -= 1);
    }
  }

  @override
  Widget build(BuildContext context) {
    final step = _steps[_step];

    return Scaffold(
      body: DecoratedBox(
        decoration: AppTheme.screenBackground,
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 14, 24, 28),
            child: Column(
              children: [
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    key: const ValueKey('onboarding-skip'),
                    onPressed: widget.onFinished,
                    style: TextButton.styleFrom(
                      foregroundColor: AppTheme.textMuted,
                      textStyle: const TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    child: const Text('ข้าม'),
                  ),
                ),
                Expanded(
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 128,
                          height: 128,
                          decoration: BoxDecoration(
                            color: AppTheme.mint,
                            borderRadius: BorderRadius.circular(36),
                            boxShadow: [
                              BoxShadow(
                                color:
                                    AppTheme.accent.withValues(alpha: 0.45),
                                blurRadius: 44,
                                spreadRadius: -18,
                                offset: const Offset(0, 22),
                              ),
                            ],
                          ),
                          child: Icon(
                            step.icon,
                            size: 62,
                            color: AppTheme.accentCyanInk,
                          ),
                        ),
                        const SizedBox(height: 34),
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 300),
                          child: Text(
                            step.title,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 23,
                              fontWeight: FontWeight.w800,
                              height: 1.3,
                              color: AppTheme.textPrimary,
                            ),
                          ),
                        ),
                        const SizedBox(height: 14),
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 300),
                          child: Text(
                            step.description,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 14.5,
                              height: 1.6,
                              color: AppTheme.textSecondary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    for (var i = 0; i < _steps.length; i += 1) ...[
                      if (i > 0) const SizedBox(width: 7),
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 250),
                        width: i == _step ? 22 : 7,
                        height: 7,
                        decoration: BoxDecoration(
                          color: i == _step
                              ? AppTheme.accent
                              : AppTheme.border,
                          borderRadius: BorderRadius.circular(999),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 22),
                Row(
                  children: [
                    if (_step > 0) ...[
                      Semantics(
                        button: true,
                        label: 'ย้อนกลับ',
                        child: InkWell(
                          borderRadius: BorderRadius.circular(16),
                          onTap: _back,
                          child: Container(
                            width: 56,
                            height: 56,
                            decoration: BoxDecoration(
                              color: AppTheme.glass,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: AppTheme.border),
                            ),
                            child: Icon(
                              Icons.arrow_back,
                              size: 24,
                              color: AppTheme.textPrimary,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                    ],
                    Expanded(
                      child: SizedBox(
                        height: 56,
                        child: FilledButton(
                          key: const ValueKey('onboarding-next'),
                          onPressed: _next,
                          style: FilledButton.styleFrom(
                            backgroundColor: AppTheme.accent,
                            foregroundColor: Colors.white,
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                            textStyle: const TextStyle(
                              fontSize: 16.5,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(_isLastStep ? 'เริ่มใช้งาน' : 'ถัดไป'),
                              const SizedBox(width: 8),
                              const Icon(Icons.arrow_forward, size: 21),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
