import 'package:flutter/material.dart';
import '../../core/models/profile_platform_catalog.generated.dart';

String? bioPlatformLogoAsset(String icon) {
  final artwork = profilePlatformsById[icon]?.asset;
  return artwork == null ? null : 'assets/images/platforms/${artwork.file}';
}

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
    final artwork = profilePlatformsById[icon]?.asset;
    final extent = artwork == null
        ? size
        : artwork.width > artwork.height
            ? artwork.width
            : artwork.height;
    final scale = size / extent;
    Widget fallback() => Icon(
        switch (icon) {
          'website' => Icons.language,
          'email' => Icons.mail_outline,
          'phone' => Icons.phone_outlined,
          _ => Icons.link,
        },
        size: size * .6,
        color: fallbackColor);
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: asset == null
            ? Colors.white.withValues(alpha: .14)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
      ),
      child: asset == null
          ? fallback()
          : ClipRect(
              child: Stack(
                fit: StackFit.expand,
                clipBehavior: Clip.none,
                children: [
                  Positioned(
                    left: (size - artwork!.width * scale) / 2 -
                        artwork.left * scale,
                    top: (size - artwork.height * scale) / 2 -
                        artwork.top * scale,
                    width: artwork.sourceWidth * scale,
                    height: artwork.sourceHeight * scale,
                    child: Image.asset(
                      asset,
                      fit: BoxFit.contain,
                      filterQuality: FilterQuality.high,
                      excludeFromSemantics: true,
                      errorBuilder: (_, error, stack) =>
                          Center(child: fallback()),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
