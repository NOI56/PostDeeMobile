import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../core/models/link_in_bio_appearance.dart';
import 'link_in_bio_draft_store.dart';

Color bioColor(String value) =>
    Color(int.parse('ff${value.substring(1)}', radix: 16));
String? bioFont(String value) => switch (value) {
      'anuphan' => 'Anuphan',
      'prompt' => 'Prompt',
      _ => null,
    };
TextStyle bioTextStyle(LinkInBioTextStyle value,
        {double size = 16, FontWeight weight = FontWeight.w400}) =>
    TextStyle(
        inherit: false,
        color: bioColor(value.color),
        fontFamily: bioFont(value.font),
        fontSize: size,
        fontWeight: weight,
        height: 1.6);

String bioIconId(LinkInBioCustomLink link) {
  if (link.icon != 'auto') return link.icon;
  final host = Uri.tryParse(link.url)?.host.toLowerCase() ?? '';
  const domains = {
    'shopee': ['shopee.co.th', 'shopee.com', 'shope.ee'],
    'lazada': ['lazada.co.th', 'lazada.com'],
    'line': ['line.me', 'lin.ee'],
    'tiktok': ['tiktok.com'],
    'youtube': ['youtube.com', 'youtu.be'],
    'instagram': ['instagram.com'],
    'facebook': ['facebook.com', 'fb.com', 'fb.me'],
  };
  for (final entry in domains.entries) {
    if (entry.value
        .any((domain) => host == domain || host.endsWith('.$domain'))) {
      return entry.key;
    }
  }
  return 'link';
}

IconData bioLinkIcon(LinkInBioCustomLink link) => switch (bioIconId(link)) {
      'shopee' || 'lazada' => Icons.shopping_bag_outlined,
      'line' => Icons.chat_bubble_outline,
      'tiktok' => Icons.music_note,
      'youtube' => Icons.smart_display_outlined,
      'instagram' => Icons.camera_alt_outlined,
      'facebook' => Icons.facebook,
      _ => Icons.link,
    };
String bioIconMark(LinkInBioCustomLink link) => switch (bioIconId(link)) {
      'shopee' => 'S',
      'lazada' => 'L',
      'line' => 'LINE',
      'tiktok' => '♪',
      'youtube' => '▶',
      'instagram' => '◎',
      'facebook' => 'f',
      _ => '↗',
    };

class LinkInBioPreview extends StatelessWidget {
  const LinkInBioPreview(
      {super.key,
      required this.storeName,
      required this.slug,
      required this.links,
      required this.appearance,
      this.images = const {}});
  final String storeName;
  final String slug;
  final List<LinkInBioCustomLink> links;
  final LinkInBioAppearance appearance;
  final Map<String, Uint8List> images;

  Widget _image(String? key, {double? height}) {
    final bytes = images[key];
    return bytes == null
        ? SizedBox(
            height: height ?? 88,
            child: const Center(child: Icon(Icons.image_outlined, size: 30)))
        : Image.memory(bytes,
            height: height,
            width: double.infinity,
            fit: BoxFit.cover,
            errorBuilder: (_, error, stack) => SizedBox(
                height: height ?? 88,
                child: const Icon(Icons.image_not_supported_outlined)));
  }

  @override
  Widget build(BuildContext context) {
    final background = appearance.background;
    final radius = switch (appearance.buttonRadius) {
      'pill' => 999.0,
      'square' => 4.0,
      _ => 14.0
    };
    Widget button(LinkInBioCustomLink link) {
      final promoted = link.id == appearance.featuredLinkId;
      final style = appearance.buttonStyle.copyWith(
          font: link.font ?? appearance.buttonStyle.font,
          color: link.textColor ?? appearance.buttonStyle.color);
      return Container(
          width: double.infinity,
          margin: const EdgeInsets.only(top: 12),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
              color: bioColor(link.buttonColor ?? appearance.buttonColor),
              borderRadius: BorderRadius.circular(radius),
              border: promoted
                  ? Border.all(color: bioColor(style.color), width: 2)
                  : null),
          child: Row(children: [
            Container(
                width: 36,
                height: 36,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: .14),
                    borderRadius: BorderRadius.circular(10)),
                child: Text(bioIconMark(link),
                    style: bioTextStyle(
                        LinkInBioTextStyle(font: 'system', color: style.color),
                        size: bioIconId(link) == 'line' ? 10 : 18))),
            const SizedBox(width: 12),
            Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  if (promoted && appearance.featuredLabel.isNotEmpty)
                    Text(appearance.featuredLabel,
                        style: bioTextStyle(style, size: 11).copyWith(
                            color:
                                bioColor(style.color).withValues(alpha: .86))),
                  Text(link.title,
                      style: bioTextStyle(style, weight: FontWeight.w600)),
                ])),
            const SizedBox(width: 12),
            Text('↗', style: bioTextStyle(style)),
          ]));
    }

    return ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: DecoratedBox(
            decoration: BoxDecoration(
                color: bioColor(background.color),
                gradient: background.mode == 'gradient'
                    ? LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                            bioColor(background.color),
                            bioColor(background.gradientColor)
                          ])
                    : null),
            child: Stack(children: [
              if (background.mode == 'image' &&
                  images[background.imageKey] != null)
                Positioned.fill(child: _image(background.imageKey)),
              if (background.mode == 'image')
                Positioned.fill(
                    child: ColoredBox(
                            color: Colors.black.withValues(alpha: background.overlay / 100))),
              Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
                  child: Align(
                      alignment: Alignment.topCenter,
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 520),
                        child: Container(
                            clipBehavior: Clip.antiAlias,
                            decoration: BoxDecoration(
                                color: bioColor(appearance.surfaceColor),
                                borderRadius: BorderRadius.circular(24),
                                border:
                                    Border.all(color: const Color(0x2e808080))),
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  if (appearance.coverKey != null)
                                    ConstrainedBox(
                                        constraints: const BoxConstraints(
                                            maxHeight: 220),
                                        child: _image(appearance.coverKey)),
                                  Padding(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 18, vertical: 24),
                                      child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text('PostDee',
                                                style: bioTextStyle(
                                                        appearance.brandStyle,
                                                        size: 13,
                                                        weight: FontWeight.w600)
                                                    .copyWith(
                                                        letterSpacing: 1)),
                                            if (appearance.logoKey != null) ...[
                                              const SizedBox(height: 18),
                                              SizedBox.square(
                                                  dimension: 88,
                                                  child: ClipRRect(
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                              24),
                                                      child: _image(
                                                          appearance.logoKey,
                                                          height: 88))),
                                            ],
                                            const SizedBox(height: 16),
                                            Text(
                                                storeName.trim().isEmpty
                                                    ? 'ร้านของคุณ'
                                                    : storeName,
                                                style: bioTextStyle(
                                                        appearance.nameStyle,
                                                        size: 24,
                                                        weight: FontWeight.w600)
                                                    .copyWith(height: 1.4)),
                                            const SizedBox(height: 8),
                                            Text(
                                                appearance.description.isEmpty
                                                    ? 'เลือกช่องทางที่ต้องการได้เลย'
                                                    : appearance.description,
                                                style: bioTextStyle(appearance
                                                    .descriptionStyle)),
                                            const SizedBox(height: 16),
                                            if (links.isEmpty)
                                              Text(
                                                  'เพิ่มลิงก์เพื่อแสดงตัวอย่าง',
                                                  style: bioTextStyle(appearance
                                                      .descriptionStyle)),
                                            for (final (index, link)
                                                in links.indexed) ...[
                                              if (link.category
                                                      .trim()
                                                      .isNotEmpty &&
                                                  (index == 0 ||
                                                      links[index - 1]
                                                              .category
                                                              .trim() !=
                                                          link.category.trim()))
                                                Padding(
                                                    padding:
                                                        const EdgeInsets.only(
                                                            top: 24),
                                                    child: Text(
                                                        link.category.trim(),
                                                        style: bioTextStyle(
                                                            appearance
                                                                .categoryStyle,
                                                            size: 14,
                                                            weight: FontWeight
                                                                .w600))),
                                              button(link),
                                            ],
                                            const SizedBox(height: 28),
                                            Center(
                                                child: Text(
                                                    'สร้างหน้าเว็บร้านค้าด้วย PostDee',
                                                    textAlign: TextAlign.center,
                                                    style: bioTextStyle(
                                                        appearance.brandStyle,
                                                        size: 12))),
                                          ])),
                                ])),
                      ))),
            ])));
  }
}
