import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../../core/models/link_in_bio_appearance.dart';
import 'link_in_bio_draft_store.dart';
import 'link_in_bio_link_defaults.dart';
import 'link_in_bio_motion.dart';
import 'link_in_bio_platform_logo.dart';
import 'link_in_bio_preview_styles.dart';

class BioDecoratedPreview extends StatelessWidget {
  const BioDecoratedPreview(
      {super.key,
      required this.storeName,
      required this.links,
      required this.appearance,
      required this.images});
  final String storeName;
  final List<LinkInBioCustomLink> links;
  final LinkInBioAppearance appearance;
  final Map<String, Uint8List> images;

  Widget _image(String key, double height) => images[key] == null
      ? SizedBox(
          height: height,
          child: const Center(child: Icon(Icons.image_outlined)))
      : Image.memory(images[key]!,
          width: double.infinity,
          height: height,
          fit: BoxFit.cover,
          errorBuilder: (_, error, stack) => SizedBox(
              height: height,
              child: const Center(
                  child: Icon(Icons.image_not_supported_outlined))));

  @override
  Widget build(BuildContext context) => BioMotionSurface(
      effects: appearance.effects,
      builder: (phase, entrance, reduced) {
        final cards = appearance.themeId == 'cards';
        final garden = appearance.themeId == 'garden';
        final name = storeName.trim().isEmpty ? 'ร้านของคุณ' : storeName.trim();
        final background = appearance.background;
        final drift = appearance.effects.background && !reduced
            ? math.sin(phase * math.pi * 2) * .15
            : 0.0;
        final radius = appearance.buttonRadius == 'pill'
            ? 999.0
            : appearance.buttonRadius == 'square'
                ? 4.0
                : cards
                    ? 18.0
                    : 16.0;
        Widget linkButton(LinkInBioCustomLink link, int index) {
          final promoted = link.id == appearance.featuredLinkId;
          final style = appearance.buttonStyle.copyWith(
              font: link.font ?? appearance.buttonStyle.font,
              color: link.textColor ?? appearance.buttonStyle.color);
          return Padding(
              padding: const EdgeInsets.only(top: 12),
              child: bioMotionLink(
                effects:
                    reduced ? const LinkInBioEffects() : appearance.effects,
                phase: phase,
                entrance: reduced ? 1 : entrance,
                featured: promoted ||
                    (appearance.featuredLinkId == null && index == 0),
                child: Container(
                    width: double.infinity,
                    constraints: BoxConstraints(minHeight: cards ? 100 : 68),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 14),
                    decoration: BoxDecoration(
                        color: bioColor(
                            link.buttonColor ?? appearance.buttonColor),
                        borderRadius: BorderRadius.circular(radius),
                        border: promoted
                            ? Border.all(color: bioColor(style.color))
                            : cards
                                ? Border.all(color: const Color(0x268b67b5))
                                : null,
                        boxShadow: cards
                            ? const [
                                BoxShadow(
                                    color: Color(0x148b67b5),
                                    blurRadius: 18,
                                    offset: Offset(0, 5))
                              ]
                            : null),
                    child: Row(children: [
                      BioPlatformLogo(
                          icon: link.icon == 'auto'
                              ? bioPlatformId(link.url)
                              : link.icon,
                          fallbackColor: bioColor(style.color)),
                      const SizedBox(width: 12),
                      Expanded(
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                            if (promoted && appearance.featuredLabel.isNotEmpty)
                              cards
                                  ? Container(
                                      margin: const EdgeInsets.only(bottom: 6),
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 10, vertical: 4),
                                      decoration: BoxDecoration(
                                          color: const Color(0xffeee1ff),
                                          borderRadius:
                                              BorderRadius.circular(99)),
                                      child: Text(appearance.featuredLabel,
                                          style: bioTextStyle(style, size: 11)
                                              .copyWith(
                                                  color:
                                                      const Color(0xff8053b0))))
                                  : Text(appearance.featuredLabel,
                                      style: bioTextStyle(style, size: 11)),
                            Text(link.title,
                                style: bioTextStyle(style,
                                    weight: FontWeight.w600)),
                            if (cards)
                              Text('เปิดลิงก์',
                                  style: bioTextStyle(style, size: 13).copyWith(
                                      color: const Color(0xff8b67b5))),
                          ])),
                      const SizedBox(width: 12),
                      Icon(Icons.north_east,
                          size: 20, color: bioColor(style.color)),
                    ])),
              ));
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
                            child: _image(background.imageKey!, 852),
                            effects: appearance.effects,
                            phase: phase,
                            reduced: reduced)),
                  if (background.mode == 'image')
                    Positioned.fill(
                        child: ColoredBox(
                            color: Colors.black
                                .withValues(alpha: background.overlay / 100))),
                  Padding(
                      padding: const EdgeInsets.all(16),
                      child: Align(
                          alignment: Alignment.topCenter,
                          child: ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 480),
                              child: Container(
                                  decoration: BoxDecoration(
                                      color: bioColor(appearance.surfaceColor),
                                      borderRadius: BorderRadius.circular(24)),
                                  padding: EdgeInsets.fromLTRB(
                                      8, cards ? 24 : 52, 8, 20),
                                  child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.stretch,
                                      children: [
                                        if (appearance.coverKey != null)
                                          ClipRRect(
                                              borderRadius:
                                                  BorderRadius.circular(16),
                                              child: _image(
                                                  appearance.coverKey!, 200)),
                                        const SizedBox(height: 20),
                                        Center(
                                            child: Container(
                                                width: 112,
                                                height: 112,
                                                clipBehavior: Clip.antiAlias,
                                                decoration: BoxDecoration(
                                                    shape: BoxShape.circle,
                                                    color: bioColor(background
                                                        .gradientColor),
                                                    border: Border.all(
                                                        color: bioColor(
                                                            appearance
                                                                .buttonColor),
                                                        width: 2)),
                                                child: appearance.logoKey != null
                                                    ? _image(
                                                        appearance.logoKey!,
                                                        112)
                                                    : Center(
                                                        child: Text(String.fromCharCode(name.runes.first),
                                                            style: bioTextStyle(
                                                                appearance
                                                                    .nameStyle,
                                                                size: 48,
                                                                weight: FontWeight.w600))))),
                                        const SizedBox(height: 16),
                                        Text(name,
                                            textAlign: TextAlign.center,
                                            style: bioTextStyle(
                                                    appearance.nameStyle,
                                                    size: 30,
                                                    weight: FontWeight.w600)
                                                .copyWith(height: 1.4)),
                                        const SizedBox(height: 8),
                                        Text(
                                            appearance.description.isEmpty
                                                ? 'เลือกช่องทางที่ต้องการได้เลย'
                                                : appearance.description,
                                            textAlign: TextAlign.center,
                                            style: bioTextStyle(
                                                appearance.descriptionStyle,
                                                size: 15)),
                                        const SizedBox(height: 30),
                                        if (garden)
                                          Padding(
                                              padding: const EdgeInsets.only(
                                                  bottom: 20),
                                              child: Divider(
                                                  height: 1,
                                                  color: bioColor(appearance
                                                          .buttonColor)
                                                      .withValues(alpha: .33))),
                                        if (links.isEmpty)
                                          Text('เพิ่มลิงก์เพื่อแสดงตัวอย่าง',
                                              style: bioTextStyle(
                                                  appearance.descriptionStyle)),
                                        for (final (index, link)
                                            in links.indexed) ...[
                                          if (link.category.trim().isNotEmpty &&
                                              (index == 0 ||
                                                  links[index - 1]
                                                          .category
                                                          .trim() !=
                                                      link.category.trim()))
                                            Padding(
                                                padding: const EdgeInsets.only(
                                                    top: 12),
                                                child: Text(
                                                    link.category.trim(),
                                                    style: bioTextStyle(
                                                        appearance
                                                            .categoryStyle,
                                                        size: 15,
                                                        weight:
                                                            FontWeight.w600))),
                                          linkButton(link, index),
                                        ],
                                        const SizedBox(height: 72),
                                        Text('สร้างหน้าเว็บร้านค้าด้วย PostDee',
                                            textAlign: TextAlign.center,
                                            style: bioTextStyle(
                                                appearance.brandStyle,
                                                size: 12)),
                                      ]))))),
                  if (appearance.effects.stickers != 'none')
                    Positioned.fill(
                        child: BioDecorations(
                            kind: appearance.effects.stickers,
                            phase: reduced ? 0 : phase)),
                ])));
      });
}
