import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

class PostDeeCard extends StatelessWidget {
  const PostDeeCard({
    required this.child,
    super.key,
    this.padding = const EdgeInsets.all(AppTheme.spaceLg),
    this.glowColor,
    this.radius = AppTheme.cardRadius,
    this.borderColor,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color? glowColor;
  final double radius;
  final Color? borderColor;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        gradient: AppTheme.panelGradient,
        border: Border.all(
          color: borderColor ?? AppTheme.border.withValues(alpha: 0.45),
        ),
        // A single soft, diffuse shadow reads cleaner than a hard shadow plus a
        // colored glow; the glowColor is kept on the API but no longer painted.
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.13),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Padding(
        padding: padding,
        child: child,
      ),
    );
  }
}

class PostDeeGradientButton extends StatelessWidget {
  const PostDeeGradientButton({
    required this.label,
    required this.onPressed,
    super.key,
    this.icon,
    this.height = 44,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final double height;

  @override
  Widget build(BuildContext context) {
    final isEnabled = onPressed != null;

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppTheme.cardRadius),
        gradient: isEnabled
            ? AppTheme.brandGradient
            : const LinearGradient(
                colors: [Color(0xFF2A2D36), Color(0xFF20232B)],
              ),
        boxShadow: isEnabled
            ? [
                BoxShadow(
                  color: AppTheme.accent.withValues(alpha: 0.16),
                  blurRadius: 18,
                  offset: const Offset(0, 8),
                ),
              ]
            : const [],
      ),
      child: SizedBox(
        height: height,
        child: TextButton.icon(
          onPressed: onPressed,
          icon: icon == null
              ? const SizedBox.shrink()
              : Icon(icon, color: Colors.white, size: 18),
          label: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w800,
            ),
          ),
          style: TextButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppTheme.cardRadius),
            ),
          ),
        ),
      ),
    );
  }
}

class PostDeeSoftPill extends StatelessWidget {
  const PostDeeSoftPill({
    required this.label,
    super.key,
    this.icon,
    this.color = AppTheme.accent,
    this.isSelected = false,
  });

  final String label;
  final IconData? icon;
  final Color color;
  final bool isSelected;

  @override
  Widget build(BuildContext context) {
    // On light surfaces a faint glass fill + low-alpha border nearly disappears,
    // so an unselected pill uses a soft tint of its own accent and a stronger
    // border there. Dark mode keeps the original glass look.
    final isLight = AppTheme.isLightMode;

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppTheme.pillRadius),
        gradient: isSelected ? AppTheme.brandGradient : null,
        color: isSelected
            ? null
            : (isLight
                ? color.withValues(alpha: 0.12)
                : AppTheme.glassDeep.withValues(alpha: 0.82)),
        border: Border.all(
          color: isSelected
              ? Colors.transparent
              : color.withValues(alpha: isLight ? 0.55 : 0.28),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(
                icon,
                color: isSelected ? Colors.white : color,
                size: 15,
              ),
              const SizedBox(width: 5),
            ],
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: AppTheme.textPrimary,
                      fontWeight: FontWeight.w700,
                    ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class PostDeeSectionHeader extends StatelessWidget {
  const PostDeeSectionHeader({
    required this.title,
    super.key,
    this.trailing,
  });

  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
          ),
        ),
        if (trailing != null) trailing!,
      ],
    );
  }
}
