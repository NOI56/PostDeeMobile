import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import 'auth_controller.dart';

class AuthStatusBar extends StatelessWidget {
  const AuthStatusBar({
    super.key,
    required this.controller,
    this.compact = false,
  });

  final PostDeeAuthController controller;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final colorScheme = Theme.of(context).colorScheme;
        final textTheme = Theme.of(context).textTheme;
        final session = controller.session;
        final setupMessage = controller.setupMessage ?? '';
        final signedOutMessage =
            setupMessage.toLowerCase().contains('local mock auth')
                ? 'กำลังใช้ระบบบัญชีจำลองสำหรับทดสอบ'
                : setupMessage.isNotEmpty
                    ? setupMessage
                    : 'เชื่อมต่อ Google Sign-In เมื่อพร้อมใช้งานจริง';

        if (compact) {
          return DecoratedBox(
            decoration: BoxDecoration(
              color: AppTheme.glass.withValues(alpha: 0.58),
              border: Border(
                bottom: BorderSide(
                  color: colorScheme.outlineVariant.withValues(alpha: 0.34),
                ),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Row(
                      children: [
                        DecoratedBox(
                          decoration: BoxDecoration(
                            color: AppTheme.accent.withValues(alpha: 0.14),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: AppTheme.accent.withValues(alpha: 0.34),
                            ),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 5,
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(
                                  Icons.account_circle_outlined,
                                  color: AppTheme.accent,
                                  size: 15,
                                ),
                                const SizedBox(width: 5),
                                Text(
                                  session.isSignedIn
                                      ? session.displayLabel
                                      : 'บัญชีทดลอง',
                                  overflow: TextOverflow.ellipsis,
                                  style: textTheme.labelMedium?.copyWith(
                                    color: AppTheme.textPrimary,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        if (controller.errorMessage != null) ...[
                          const SizedBox(width: AppTheme.spaceSm),
                          Expanded(
                            child: Text(
                              controller.errorMessage!,
                              overflow: TextOverflow.ellipsis,
                              style: textTheme.labelSmall?.copyWith(
                                color: colorScheme.error,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: AppTheme.spaceSm),
                  OutlinedButton(
                    onPressed: session.isSignedIn
                        ? controller.signOut
                        : controller.isSigningIn
                            ? null
                            : controller.signInWithGoogle,
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 8,
                      ),
                      minimumSize: const Size(0, 36),
                    ),
                    child: Text(
                      session.isSignedIn
                          ? 'ออก'
                          : controller.isSigningIn
                              ? '...'
                              : 'Google',
                    ),
                  ),
                ],
              ),
            ),
          );
        }

        return DecoratedBox(
          decoration: BoxDecoration(
            color: AppTheme.glass.withValues(alpha: 0.88),
            border: Border(
              bottom: BorderSide(
                color: colorScheme.outlineVariant.withValues(alpha: 0.55),
              ),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            session.isSignedIn
                                ? session.displayLabel
                                : 'บัญชีทดลอง',
                            style: textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            session.isSignedIn
                                ? session.email ?? 'Firebase session active'
                                : signedOutMessage,
                            style: textTheme.bodySmall?.copyWith(
                              color: AppTheme.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: AppTheme.spaceMd),
                    if (session.isSignedIn)
                      OutlinedButton(
                        onPressed: controller.signOut,
                        child: const Text('ออกจากระบบ'),
                      )
                    else
                      ElevatedButton(
                        onPressed: controller.isSigningIn
                            ? null
                            : controller.signInWithGoogle,
                        child: Text(
                          controller.isSigningIn
                              ? 'กำลังเข้าสู่ระบบ...'
                              : 'เข้าสู่ระบบ Google',
                        ),
                      ),
                  ],
                ),
                if (controller.errorMessage != null) ...[
                  const SizedBox(height: AppTheme.spaceSm),
                  Text(
                    controller.errorMessage!,
                    style: TextStyle(color: colorScheme.error),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}
