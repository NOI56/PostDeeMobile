import 'dart:typed_data';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/models/link_in_bio_appearance.dart';
import 'link_in_bio_draft_store.dart';
import 'link_in_bio_link_defaults.dart';
import 'link_in_bio_platform_logo.dart';
import 'link_in_bio_decorated_preview.dart';
import 'link_in_bio_motion.dart';
import 'link_in_bio_preview_styles.dart';
export 'link_in_bio_preview_styles.dart';

String bioIconId(LinkInBioCustomLink link) {
  if (link.icon != 'auto') return link.icon;
  return bioPlatformId(link.url);
}

// Bounded editor previews start at the store text, while keeping the full
// page (including its large avatar/cover) reachable by scrolling upwards.
class BioPreviewViewport extends StatefulWidget {
  const BioPreviewViewport(
      {super.key,
      required this.height,
      required this.appearance,
      required this.child});
  final double height;
  final LinkInBioAppearance appearance;
  final Widget child;
  @override
  State<BioPreviewViewport> createState() => _BioPreviewViewportState();
}

class _BioPreviewViewportState extends State<BioPreviewViewport> {
  double get _start {
    if (!const {'pink', 'garden', 'cards'}
        .contains(widget.appearance.themeId)) {
      return 0;
    }
    return (widget.appearance.themeId == 'cards' ? 188.0 : 216.0) +
        (widget.appearance.coverKey == null ? 0 : 200);
  }

  late final _controller = ScrollController(initialScrollOffset: _start);
  @override
  void didUpdateWidget(covariant BioPreviewViewport oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.appearance.themeId != widget.appearance.themeId ||
        oldWidget.appearance.coverKey != widget.appearance.coverKey) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _controller.hasClients) {
          _controller
              .jumpTo(_start.clamp(0, _controller.position.maxScrollExtent));
        }
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SizedBox(
      height: widget.height,
      child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Semantics(
              label: 'ตัวอย่างหน้าเว็บ เลื่อนเพื่อดูส่วนอื่น',
              child: Scrollbar(
                  controller: _controller,
                  thumbVisibility: true,
                  child: SingleChildScrollView(
                      controller: _controller, child: widget.child)))));
}

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
    if (const {'pink', 'garden', 'cards'}.contains(appearance.themeId)) {
      return BioDecoratedPreview(
          storeName: storeName,
          links: links,
          appearance: appearance,
          images: images);
    }
    return BioMotionSurface(
        effects: appearance.effects,
        builder: (phase, entrance, paused, togglePause, reduced) =>
            _legacyPreview(phase, entrance, paused, togglePause, reduced));
  }

  Widget _legacyPreview(double phase, double entrance, bool paused,
      VoidCallback togglePause, bool reduced) {
    final background = appearance.background;
    final drift = appearance.effects.background && !reduced
        ? math.sin(phase * math.pi * 2) * .15
        : 0.0;
    final radius = switch (appearance.buttonRadius) {
      'pill' => 999.0,
      'square' => 4.0,
      _ => 14.0
    };
    Widget button(LinkInBioCustomLink link, int index) {
      final promoted = link.id == appearance.featuredLinkId;
      final style = appearance.buttonStyle.copyWith(
          font: link.font ?? appearance.buttonStyle.font,
          color: link.textColor ?? appearance.buttonStyle.color);
      final child = Container(
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
            BioPlatformLogo(
                icon: bioIconId(link), fallbackColor: bioColor(style.color)),
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
      return bioMotionLink(
          child: child,
          effects: reduced ? const LinkInBioEffects() : appearance.effects,
          phase: phase,
          entrance: entrance,
          featured:
              promoted || (appearance.featuredLinkId == null && index == 0));
    }

    return ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: DecoratedBox(
            decoration: BoxDecoration(
                color: bioColor(background.color),
                gradient: background.mode == 'gradient'
                    ? LinearGradient(
                        begin: Alignment(-1 + drift, -1),
                        end: Alignment(1 - drift, 1),
                        colors: [
                            bioColor(background.color),
                            bioColor(background.gradientColor)
                          ])
                    : null),
            child: Stack(children: [
              if (background.mode == 'image' &&
                  images[background.imageKey] != null)
                Positioned.fill(
                    child: bioMotionBackground(
                        child: _image(background.imageKey),
                        effects: appearance.effects,
                        phase: phase,
                        reduced: reduced)),
              if (background.mode == 'image')
                Positioned.fill(
                    child: ColoredBox(
                        color: Colors.black
                            .withValues(alpha: background.overlay / 100))),
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
                                              button(link, index),
                                            ],
                                            const SizedBox(height: 28),
                                            Center(
                                                child: Text(
                                                    'สร้างหน้าเว็บร้านค้าด้วย PostDee',
                                                    textAlign: TextAlign.center,
                                                    style: bioTextStyle(
                                                        appearance.brandStyle,
                                                        size: 12))),
                                            if (appearance.effects.enabled &&
                                                !reduced)
                                              Center(
                                                  child: TextButton.icon(
                                                      key: const ValueKey(
                                                          'link-in-bio-preview-pause'),
                                                      onPressed: togglePause,
                                                      icon: Icon(
                                                          paused
                                                              ? Icons.play_arrow
                                                              : Icons.pause,
                                                          size: 14),
                                                      label: Text(
                                                          paused
                                                              ? 'เล่นการเคลื่อนไหว'
                                                              : 'หยุดการเคลื่อนไหว',
                                                          style: bioTextStyle(
                                                              appearance
                                                                  .brandStyle,
                                                              size: 12)))),
                                          ])),
                                ])),
                      ))),
              if (appearance.effects.stickers != 'none')
                Positioned.fill(
                    child: BioDecorations(
                        kind: appearance.effects.stickers,
                        phase: reduced ? 0 : phase)),
            ])));
  }
}
