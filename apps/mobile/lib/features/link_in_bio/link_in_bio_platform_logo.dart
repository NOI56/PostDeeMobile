import 'package:flutter/material.dart';

String? bioPlatformLogoAsset(String icon) => switch (icon) {
      'youtube' ||
      'shopee' ||
      'lazada' ||
      'line' ||
      'tiktok' ||
      'instagram' ||
      'facebook' =>
        'assets/images/platforms/$icon.png',
      _ => null,
    };

class BioPlatformLogo extends StatelessWidget {
  const BioPlatformLogo({
    super.key,
    required this.icon,
    this.size = 40,
    this.fallbackColor,
  });

  final String icon;
  final double size;
  final Color? fallbackColor;

  @override
  Widget build(BuildContext context) {
    final asset = bioPlatformLogoAsset(icon);
    Widget fallback() =>
        Icon(Icons.link, size: size * .6, color: fallbackColor);
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color:
            asset == null ? Colors.white.withValues(alpha: .14) : Colors.white,
        borderRadius: BorderRadius.circular(10),
      ),
      child: asset == null
          ? fallback()
          : Image.asset(
              asset,
              width: size,
              height: size,
              fit: BoxFit.contain,
              filterQuality: FilterQuality.high,
              excludeFromSemantics: true,
              errorBuilder: (_, error, stack) => fallback(),
            ),
    );
  }
}
