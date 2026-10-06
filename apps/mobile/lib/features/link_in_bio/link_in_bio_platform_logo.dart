import 'package:flutter/material.dart';

// Pixel bounds of the original bundled artwork, excluding transparent margins.
const _platformArtwork = <String, ({Size source, Rect bounds})>{
  'youtube': (
    source: Size(1255, 1075),
    bounds: Rect.fromLTWH(214, 248, 827, 579)
  ),
  'shopee': (source: Size(96, 96), bounds: Rect.fromLTWH(5, 0, 86, 96)),
  'lazada': (source: Size(128, 128), bounds: Rect.fromLTWH(0, 0, 128, 128)),
  'line': (source: Size(1001, 1000), bounds: Rect.fromLTWH(0, 0, 1001, 1000)),
  'tiktok': (source: Size(240, 240), bounds: Rect.fromLTWH(0, 0, 240, 240)),
  'instagram': (source: Size(240, 240), bounds: Rect.fromLTWH(0, 0, 240, 240)),
  'facebook': (source: Size(240, 240), bounds: Rect.fromLTWH(0, 0, 240, 240)),
};

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
    final artwork = _platformArtwork[icon];
    final extent = artwork == null
        ? size
        : artwork.bounds.width > artwork.bounds.height
            ? artwork.bounds.width
            : artwork.bounds.height;
    final scale = size / extent;
    Widget fallback() =>
        Icon(Icons.link, size: size * .6, color: fallbackColor);
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
                    left: (size - artwork!.bounds.width * scale) / 2 -
                        artwork.bounds.left * scale,
                    top: (size - artwork.bounds.height * scale) / 2 -
                        artwork.bounds.top * scale,
                    width: artwork.source.width * scale,
                    height: artwork.source.height * scale,
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
