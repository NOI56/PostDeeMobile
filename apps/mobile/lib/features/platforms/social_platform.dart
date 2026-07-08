import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

// Brand colors follow the design handoff: TikTok near-black, YouTube red,
// Instagram pink, Facebook blue.
enum SocialPlatform {
  tiktok(
    label: 'TikTok',
    shortLabel: 'TikTok',
    apiValue: 'TIKTOK',
    color: Color(0xFF111111),
  ),
  youtubeShorts(
    label: 'YouTube Shorts',
    shortLabel: 'Shorts',
    apiValue: 'YOUTUBE_SHORTS',
    color: Color(0xFFFF0000),
  ),
  instagramReels(
    label: 'Instagram Reels',
    shortLabel: 'Reels',
    apiValue: 'INSTAGRAM_REELS',
    color: Color(0xFFE1306C),
  ),
  facebookReels(
    label: 'Facebook Reels',
    shortLabel: 'Facebook',
    apiValue: 'FACEBOOK_REELS',
    color: Color(0xFF1877F2),
  ),
  shopeeVideo(
    label: 'Shopee Video',
    shortLabel: 'Shopee',
    apiValue: 'SHOPEE_VIDEO',
    color: Color(0xFFEE4D2D),
  ),
  lazadaVideo(
    label: 'Lazada Video',
    shortLabel: 'Lazada',
    apiValue: 'LAZADA_VIDEO',
    color: Color(0xFF0F146D),
  );

  const SocialPlatform({
    required this.label,
    required this.shortLabel,
    required this.apiValue,
    required this.color,
  });

  final String label;
  final String shortLabel;
  final String apiValue;
  final Color color;

  /// Brand color adjusted for the active theme. TikTok's near-black is
  /// invisible on dark surfaces, so it flips to a light gray there (same rule
  /// as the design prototype's brand() helper).
  Color get displayColor {
    if (this == SocialPlatform.tiktok && !AppTheme.isLightMode) {
      return const Color(0xFFE2E4E7);
    }
    return color;
  }
}
