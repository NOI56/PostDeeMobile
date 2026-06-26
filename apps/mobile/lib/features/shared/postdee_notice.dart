import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

/// Shared inline notice for error / empty / info states: a tinted rounded box
/// with a leading icon, a message, and an optional trailing action. Replaces the
/// per-screen copies so every banner looks and behaves the same.
class PostDeeNotice extends StatelessWidget {
  const PostDeeNotice({
    required this.message,
    super.key,
    this.icon = Icons.error_outline,
    this.color,
    this.actionLabel,
    this.onAction,
  });

  final String message;
  final IconData icon;

  /// Accent used for the icon, border and tint. Defaults to the error color.
  final Color? color;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final tone = color ?? Theme.of(context).colorScheme.error;
    final hasAction = actionLabel != null && onAction != null;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: tone.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppTheme.cardRadius),
        border: Border.all(color: tone.withValues(alpha: 0.45)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppTheme.spaceMd),
        child: Row(
          children: [
            Icon(icon, color: tone, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                message,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: AppTheme.textSecondary,
                      fontWeight: FontWeight.w600,
                      height: 1.25,
                    ),
              ),
            ),
            if (hasAction) ...[
              const SizedBox(width: AppTheme.spaceSm),
              TextButton(
                onPressed: onAction,
                style: TextButton.styleFrom(foregroundColor: tone),
                child: Text(actionLabel!),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
