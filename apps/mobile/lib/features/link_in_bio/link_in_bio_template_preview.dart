import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../core/models/link_in_bio_appearance.dart';
import '../../core/models/profile_template_catalog.generated.dart';
import 'link_in_bio_draft_store.dart';
import 'link_in_bio_link_defaults.dart';
import 'link_in_bio_motion.dart';
import 'link_in_bio_platform_logo.dart';
import 'link_in_bio_preview_styles.dart';

class BioTemplatePreview extends StatelessWidget {
  const BioTemplatePreview(
      {super.key,
      required this.template,
      required this.storeName,
      required this.links,
      required this.appearance,
      required this.images});
  final ProfileTemplate template;
  final String storeName;
  final List<LinkInBioCustomLink> links;
  final LinkInBioAppearance appearance;
  final Map<String, Uint8List> images;

  String get _name =>
      storeName.trim().isEmpty ? 'ร้านของคุณ' : storeName.trim();
  Widget _photo(String key, double height) => Image.memory(images[key]!,
      height: height,
      width: double.infinity,
      fit: BoxFit.cover,
      errorBuilder: (_, error, stack) => SizedBox(height: height));

  Widget _avatar(double size) => Container(
      width: size,
      height: size,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
          color: bioColor(appearance.background.gradientColor),
          border: Border.all(
              color: bioColor(appearance.categoryStyle.color)
                  .withValues(alpha: .4)),
          borderRadius: BorderRadius.circular(switch (template.layout.avatar) {
            'circle' => size,
            'rounded' => size * .22,
            _ => 3,
          })),
      child: images[appearance.logoKey] != null
          ? _photo(appearance.logoKey!, size)
          : Center(
              child: Text(String.fromCharCode(_name.runes.first),
                  style: bioTextStyle(appearance.nameStyle,
                      size: size * .4, weight: FontWeight.w600))));

  Widget _copy({bool centered = false, required double headingSize}) => Column(
          crossAxisAlignment:
              centered ? CrossAxisAlignment.center : CrossAxisAlignment.start,
          children: [
            Text(_name,
                key: const ValueKey('link-in-bio-template-store-name'),
                textAlign: centered ? TextAlign.center : TextAlign.start,
                style: bioTextStyle(appearance.nameStyle,
                        size: headingSize, weight: FontWeight.w600)
                    .copyWith(height: 1.4)),
            const SizedBox(height: 8),
            Text(
                appearance.description.isEmpty
                    ? 'เลือกช่องทางที่ต้องการได้เลย'
                    : appearance.description,
                textAlign: centered ? TextAlign.center : TextAlign.start,
                style: bioTextStyle(appearance.descriptionStyle, size: 15)),
          ]);

  Widget _header(double headingSize) {
    final layout = template.layout;
    final cover = appearance.coverKey;
    Widget coverImage(double height) => images[cover] == null
        ? Container(
            height: height,
            decoration: BoxDecoration(
                gradient: LinearGradient(colors: [
              bioColor(appearance.background.gradientColor),
              bioColor(appearance.categoryStyle.color).withValues(alpha: .2)
            ])))
        : _photo(cover!, height);
    final content = switch (layout.header) {
      'left' => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _avatar(64),
          const SizedBox(height: 18),
          _copy(headingSize: headingSize),
        ]),
      'split' => Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _avatar(64),
          const SizedBox(width: 16),
          Expanded(child: _copy(headingSize: headingSize)),
        ]),
      'cover' => Column(children: [
          SizedBox(
              height: 194,
              child: Stack(children: [
                ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: coverImage(140)),
                Positioned(
                    top: 96,
                    left: 0,
                    right: 0,
                    child: Center(child: _avatar(88))),
              ])),
          _copy(centered: true, headingSize: headingSize),
        ]),
      'badge' => Container(
          padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 12),
          decoration: BoxDecoration(
              border: Border.all(
                  color: bioColor(appearance.categoryStyle.color)
                      .withValues(alpha: .6)),
              borderRadius: BorderRadius.circular(16)),
          child: Column(children: [
            _avatar(88),
            const SizedBox(height: 18),
            _copy(centered: true, headingSize: headingSize)
          ])),
      _ => Column(children: [
          _avatar(88),
          const SizedBox(height: 18),
          _copy(centered: true, headingSize: headingSize)
        ]),
    };
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (cover != null && layout.header != 'cover') ...[
        ClipRRect(
            borderRadius: BorderRadius.circular(14), child: coverImage(140)),
        const SizedBox(height: 20),
      ],
      content,
      const SizedBox(height: 28),
      if (layout.decoration == 'line') ...[
        Divider(
            height: 1,
            color:
                bioColor(appearance.categoryStyle.color).withValues(alpha: .4)),
        const SizedBox(height: 16),
      ],
    ]);
  }

  Widget _link(LinkInBioCustomLink link, int index, double phase,
      double entrance, bool reduced, bool narrow) {
    final layout = template.layout;
    final grid = layout.links == 'grid';
    final featured = appearance.featuredLinkId == link.id;
    final style = appearance.buttonStyle.copyWith(
        font: link.font ?? appearance.buttonStyle.font,
        color: link.textColor ?? appearance.buttonStyle.color);
    final color = bioColor(link.buttonColor ?? appearance.buttonColor);
    final outline = layout.button == 'outline';
    final radius = switch (appearance.buttonRadius) {
      'pill' => 999.0,
      'square' => 4.0,
      _ => 16.0
    };
    Widget label() =>
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (featured && appearance.featuredLabel.isNotEmpty)
            Text(appearance.featuredLabel,
                style: bioTextStyle(style, size: 11, weight: FontWeight.w600)),
          Text(link.title,
              style: bioTextStyle(style, size: 16, weight: FontWeight.w600)
                  .copyWith(height: 1.5)),
        ]);
    final logo = BioPlatformLogo(
        icon: link.icon == 'auto' ? bioPlatformId(link.url) : link.icon,
        fallbackColor: bioColor(style.color));
    return bioMotionLink(
        effects: reduced ? const LinkInBioEffects() : appearance.effects,
        phase: phase,
        entrance: entrance,
        featured: featured || (appearance.featuredLinkId == null && index == 0),
        child: Container(
            key: ValueKey('link-in-bio-template-link-${link.id}'),
            constraints: BoxConstraints(minHeight: grid ? 112 : 64),
            padding: grid
                ? const EdgeInsets.all(14)
                : EdgeInsets.symmetric(
                    horizontal: narrow ? 14 : 16, vertical: 12),
            decoration: BoxDecoration(
                color: outline && link.buttonColor == null
                    ? Colors.transparent
                    : color,
                borderRadius: BorderRadius.circular(radius),
                border: layout.button == 'raised'
                    ? Border.all(
                        color: bioColor(appearance.nameStyle.color), width: 2)
                    : outline || featured
                        ? Border.all(
                            color: outline
                                ? color
                                : bioColor(style.color).withValues(alpha: .9),
                            width: featured ? 2 : 1)
                        : null,
                boxShadow: layout.button == 'raised'
                    ? [
                        BoxShadow(
                            color: bioColor(appearance.nameStyle.color),
                            offset: const Offset(4, 4))
                      ]
                    : layout.button == 'soft'
                        ? [
                            BoxShadow(
                                color: bioColor(appearance.categoryStyle.color)
                                    .withValues(alpha: .10),
                                blurRadius: 16,
                                offset: const Offset(0, 3))
                          ]
                        : null),
            child: grid
                ? Stack(children: [
                    Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          logo,
                          const SizedBox(height: 10),
                          Padding(
                              padding: const EdgeInsets.only(right: 12),
                              child: label()),
                        ]),
                    Positioned(
                        right: 0,
                        bottom: 0,
                        child: Icon(Icons.north_east,
                            size: 18, color: bioColor(style.color))),
                  ])
                : Row(children: [
                    logo,
                    const SizedBox(width: 12),
                    Expanded(child: label()),
                    const SizedBox(width: 8),
                    Icon(Icons.north_east,
                        size: 18, color: bioColor(style.color))
                  ])));
  }

  Widget _linkGroups(double phase, double entrance, bool reduced, bool narrow) {
    if (links.isEmpty) {
      return Text('เพิ่มลิงก์เพื่อแสดงตัวอย่าง',
          style: bioTextStyle(appearance.descriptionStyle));
    }
    final groups = <List<(int, LinkInBioCustomLink)>>[];
    for (final (index, link) in links.indexed) {
      if (index == 0 ||
          (link.category.trim().isNotEmpty &&
              link.category.trim() != links[index - 1].category.trim())) {
        groups.add([]);
      }
      groups.last.add((index, link));
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      for (final group in groups) ...[
        if (group.first.$2.category.trim().isNotEmpty)
          Padding(
              padding: const EdgeInsets.only(top: 14, bottom: 12),
              child: Text(group.first.$2.category.trim(),
                  style: bioTextStyle(appearance.categoryStyle,
                      size: 14, weight: FontWeight.w600))),
        LayoutBuilder(
            builder: (_, size) => Wrap(spacing: 12, runSpacing: 12, children: [
                  for (final (index, link) in group)
                    SizedBox(
                        width: template.layout.links == 'grid'
                            ? (size.maxWidth - 12) / 2
                            : size.maxWidth,
                        child: _link(
                            link, index, phase, entrance, reduced, narrow))
                ])),
        const SizedBox(height: 12),
      ]
    ]);
  }

  @override
  Widget build(BuildContext context) => BioMotionSurface(
      effects: appearance.effects,
      builder: (phase, entrance, reduced) {
        final narrow = MediaQuery.sizeOf(context).width <= 400;
        final background = appearance.background;
        final drift = appearance.effects.background && !reduced
            ? math.sin(phase * math.pi * 2) * .15
            : 0.0;
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
                            child: _photo(background.imageKey!, 900),
                            effects: appearance.effects,
                            phase: phase,
                            reduced: reduced)),
                  if (background.mode == 'image')
                    Positioned.fill(
                        child: ColoredBox(
                            color: Colors.black
                                .withValues(alpha: background.overlay / 100))),
                  Positioned.fill(
                      child: IgnorePointer(
                          child: CustomPaint(
                              painter: _TemplateOrnamentPainter(
                                  template.layout.decoration,
                                  bioColor(appearance.categoryStyle.color))))),
                  Padding(
                      padding: const EdgeInsets.fromLTRB(20, 36, 20, 20),
                      child: Align(
                          alignment: Alignment.topCenter,
                          child: ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 520),
                              child: Container(
                                  key: ValueKey(
                                      'link-in-bio-template-layout-${template.layout.header}-${template.layout.links}'),
                                  decoration: BoxDecoration(
                                      color: background.mode == 'image'
                                          ? bioColor(appearance.surfaceColor)
                                              .withValues(alpha: .92)
                                          : bioColor(appearance.surfaceColor),
                                      borderRadius: BorderRadius.circular(16),
                                      border: template.layout.decoration == 'frame'
                                          ? Border.all(
                                              color:
                                                  bioColor(appearance.categoryStyle.color)
                                                      .withValues(alpha: .5))
                                          : null),
                                  padding: EdgeInsets.all(
                                      template.layout.decoration == 'frame'
                                          ? 12
                                          : 0),
                                  child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.stretch,
                                      children: [
                                        _header(narrow ? 26 : 28),
                                        _linkGroups(
                                            phase,
                                            reduced ? 1 : entrance,
                                            reduced,
                                            narrow),
                                        const SizedBox(height: 48),
                                        Text('สร้างหน้าเว็บร้านค้าด้วย PostDee',
                                            textAlign: TextAlign.center,
                                            style: bioTextStyle(
                                                appearance.brandStyle,
                                                size: 12)),
                                        const SizedBox(height: 16),
                                      ]))))),
                  if (appearance.effects.stickers != 'none')
                    Positioned.fill(
                        child: BioDecorations(
                            kind: appearance.effects.stickers,
                            phase: reduced ? 0 : phase)),
                ])));
      });
}

class _TemplateOrnamentPainter extends CustomPainter {
  _TemplateOrnamentPainter(this.kind, this.color);
  final String kind;
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color.withValues(alpha: .13);
    if (kind == 'dots') {
      for (var y = 8.0; y < size.height; y += 22) {
        canvas.drawCircle(Offset(7, y), 1.5, paint);
        canvas.drawCircle(Offset(size.width - 7, y), 1.5, paint);
      }
    } else if (kind == 'stripe') {
      paint
        ..strokeWidth = 5
        ..style = PaintingStyle.stroke;
      for (var x = -10.0; x < size.width; x += 16) {
        canvas.drawLine(Offset(x, 0), Offset(x + 18, 18), paint);
        canvas.drawLine(
            Offset(x, size.height - 18), Offset(x + 18, size.height), paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _TemplateOrnamentPainter oldDelegate) =>
      oldDelegate.kind != kind || oldDelegate.color != color;
}
