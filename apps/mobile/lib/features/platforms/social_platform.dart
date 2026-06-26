import 'package:flutter/material.dart';

enum SocialPlatform {
  tiktok(
    label: 'TikTok',
    apiValue: 'TIKTOK',
    color: Color(0xFF00F2EA),
  ),
  youtubeShorts(
    label: 'YouTube Shorts',
    apiValue: 'YOUTUBE_SHORTS',
    color: Color(0xFFFF0033),
  ),
  instagramReels(
    label: 'Instagram Reels',
    apiValue: 'INSTAGRAM_REELS',
    color: Color(0xFFE4405F),
  ),
  facebookReels(
    label: 'Facebook Reels',
    apiValue: 'FACEBOOK_REELS',
    color: Color(0xFF1877F2),
  ),
  shopeeVideo(
    label: 'Shopee Video',
    apiValue: 'SHOPEE_VIDEO',
    color: Color(0xFFEE4D2D),
  ),
  lazadaVideo(
    label: 'Lazada Video',
    apiValue: 'LAZADA_VIDEO',
    color: Color(0xFF0F146D),
  );

  const SocialPlatform({
    required this.label,
    required this.apiValue,
    required this.color,
  });

  final String label;
  final String apiValue;
  final Color color;
}
