import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import 'social_platform.dart';

class SocialPlatformLogo extends StatelessWidget {
  const SocialPlatformLogo({
    super.key,
    required this.platform,
    this.size = 32,
  });

  final SocialPlatform platform;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '${platform.label} logo',
      image: true,
      child: ExcludeSemantics(
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(size * 0.2),
            boxShadow: [
              BoxShadow(
                color: AppTheme.pitchBlack.withValues(alpha: 0.3),
                blurRadius: size * 0.16,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(size * 0.2),
            child: Image.asset(
              _assetPath,
              width: size,
              height: size,
              fit: BoxFit.cover,
              filterQuality: FilterQuality.high,
              // Fall back to a colored monogram when the platform logo asset is
              // not bundled yet (e.g. newly added platforms), so the UI never
              // crashes on a missing asset.
              errorBuilder: (context, _, __) => _LogoFallback(
                platform: platform,
                size: size,
              ),
            ),
          ),
        ),
      ),
    );
  }

  String get _assetPath {
    switch (platform) {
      case SocialPlatform.tiktok:
        return 'assets/images/platforms/tiktok.png';
      case SocialPlatform.youtubeShorts:
        return 'assets/images/platforms/youtube_shorts.png';
      case SocialPlatform.instagramReels:
        return 'assets/images/platforms/instagram_reels.png';
      case SocialPlatform.facebookReels:
        return 'assets/images/platforms/facebook_reels.png';
      case SocialPlatform.shopeeVideo:
        return 'assets/images/platforms/shopee_video.png';
      case SocialPlatform.lazadaVideo:
        return 'assets/images/platforms/lazada_video.png';
    }
  }
}

class _LogoFallback extends StatelessWidget {
  const _LogoFallback({required this.platform, required this.size});

  final SocialPlatform platform;
  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: DecoratedBox(
        decoration: BoxDecoration(color: platform.color),
        child: Center(
          child: Text(
            platform.label.substring(0, 1),
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w900,
              fontSize: size * 0.5,
            ),
          ),
        ),
      ),
    );
  }
}
