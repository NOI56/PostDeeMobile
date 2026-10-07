import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../core/models/link_in_bio_appearance.dart';
import '../../core/models/profile_template_catalog.generated.dart';
import 'link_in_bio_composition_art.dart';
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
      required this.images,
      this.staticPreview = false});
  final ProfileTemplate template;
  final String storeName;
  final List<LinkInBioCustomLink> links;
  final LinkInBioAppearance appearance;
  final Map<String, Uint8List> images;
  final bool staticPreview;
  String get _composition => template.layout.composition;
  bool get _presetBackground =>
      appearance.background.imageKey == null &&
      appearance.background.mode ==
          (template.effects['background'] == true ? 'gradient' : 'solid') &&
      appearance.background.color == template.palette.background &&
      appearance.background.gradientColor == template.palette.gradient;

  String get _name =>
      storeName.trim().isEmpty ? 'ร้านของคุณ' : storeName.trim();
  Color get _avatarColor => const {'seal', 'tag'}.contains(_composition)
      ? Colors.transparent
      : _composition == 'portrait' ||
              (_presetBackground &&
                  const {'gallery', 'glass'}.contains(_composition))
          ? bioColor(appearance.buttonColor)
          : bioColor(appearance.background.gradientColor);
  Widget _photo(String key, double height, {Widget? fallback}) => Image.memory(
      images[key]!,
      height: height,
      width: double.infinity,
      fit: BoxFit.cover,
      errorBuilder: (_, error, stack) => fallback ?? SizedBox(height: height));

  Widget _initial(double size) {
    final selected = bioColor(_composition == 'portrait'
        ? appearance.buttonStyle.color
        : appearance.nameStyle.color);
    final a = selected.computeLuminance();
    final b = (_avatarColor == Colors.transparent
            ? bioColor(appearance.surfaceColor)
            : _avatarColor)
        .computeLuminance();
    final readable = (math.max(a, b) + .05) / (math.min(a, b) + .05) >= 4.5;
    return Center(
        child: Text(String.fromCharCode(_name.runes.first),
            style: bioTextStyle(appearance.nameStyle,
                    size: const <String, double>{
                          'editorial': 24,
                          'bicolor': 36,
                          'portrait': 36,
                          'scallop': 32,
                          'collage': 32,
                          'window': 24,
                          'botanical': 36,
                          'glass': 18,
                          'torn': 36,
                          'seal': 26,
                          'tag': 22,
                          'gallery': 26,
                          'poster': 16,
                          'window-grid': 22,
                          'ticket': 18,
                          'rail': 26,
                          'ribbon': 28,
                          'notebook': 24,
                          'arch': 32,
                          'staircase': 22,
                        }[_composition] ??
                        size * .4,
                    weight: FontWeight.w600)
                .copyWith(
                    height: 1,
                    color: readable
                        ? selected
                        : b > .18
                            ? Colors.black
                            : Colors.white)));
  }

  Widget _avatar(double size, {double? height, bool arch = false}) {
    final plain = const {'seal', 'tag'}.contains(_composition);
    final circle = const {'bicolor', 'seal'}.contains(_composition);
    final avatar = Container(
        key: const ValueKey('link-in-bio-composition-avatar'),
        width: size,
        height: height ?? size,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
            color: _avatarColor,
            border: plain
                ? null
                : Border.all(
                    color: bioColor(appearance.categoryStyle.color)
                        .withValues(alpha: .4)),
            borderRadius: arch || _composition == 'portrait'
                ? BorderRadius.vertical(top: Radius.circular(size / 2))
                : circle
                    ? BorderRadius.circular(size)
                    : BorderRadius.circular(switch (template.layout.avatar) {
                        'circle' => size,
                        'rounded' => size * .22,
                        _ => 3,
                      })),
        child: images[appearance.logoKey] != null
            ? _photo(appearance.logoKey!, height ?? size,
                fallback: _initial(size))
            : _initial(size));
    if (_composition != 'bicolor') return avatar;
    return Container(
        key: const ValueKey('link-in-bio-avatar-double-outline'),
        padding: const EdgeInsets.all(5),
        decoration: BoxDecoration(
            shape: BoxShape.circle,
            border:
                Border.all(color: bioColor(appearance.categoryStyle.color))),
        child: avatar);
  }

  Widget _copy(
          {bool centered = false,
          required double headingSize,
          bool heavy = false,
          bool framed = false,
          bool nameDivider = false}) =>
      Column(
          crossAxisAlignment:
              centered ? CrossAxisAlignment.center : CrossAxisAlignment.start,
          children: [
            Container(
                padding: framed
                    ? const EdgeInsets.symmetric(horizontal: 16, vertical: 8)
                    : EdgeInsets.zero,
                decoration: framed
                    ? BoxDecoration(
                        border: Border.all(
                            color: bioColor(appearance.nameStyle.color)))
                    : null,
                child: Text(_name,
                    key: const ValueKey('link-in-bio-template-store-name'),
                    textAlign: centered ? TextAlign.center : TextAlign.start,
                    style: bioTextStyle(appearance.nameStyle,
                            size: headingSize,
                            weight: heavy ? FontWeight.w800 : FontWeight.w600)
                        .copyWith(
                            height: 1.2, letterSpacing: framed ? 4 : null))),
            const SizedBox(height: 8),
            if (nameDivider) ...[
              Divider(
                  height: 24,
                  color: bioColor(appearance.categoryStyle.color)
                      .withValues(alpha: .45)),
              const SizedBox(height: 8),
            ],
            Text(
                appearance.description.isEmpty
                    ? 'เลือกช่องทางที่ต้องการได้เลย'
                    : appearance.description,
                textAlign: centered ? TextAlign.center : TextAlign.start,
                style: bioTextStyle(appearance.descriptionStyle,
                    size: _composition == 'poster' ? 16 : 15,
                    weight: _composition == 'poster'
                        ? FontWeight.w600
                        : FontWeight.w400)),
          ]);

  Widget _header(double headingSize, double editorialSize) {
    final cover = appearance.coverKey;
    Widget coverImage(double height, {String? fallback}) =>
        images[cover] == null
            ? Container(
                height: height,
                decoration: BoxDecoration(
                    gradient: LinearGradient(colors: [
                  bioColor(appearance.background.gradientColor),
                  bioColor(appearance.categoryStyle.color).withValues(alpha: .2)
                ])),
                child: fallback != null && _presetBackground
                    ? bioCompositionArt(fallback, height: height)
                    : null)
            : _photo(cover!, height);
    Widget centered({double avatar = 80, double? title, bool framed = false}) =>
        Column(children: [
          _avatar(avatar),
          const SizedBox(height: 18),
          _copy(
              centered: true, headingSize: title ?? headingSize, framed: framed)
        ]);
    Widget portrait({bool gallery = false}) =>
        Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
          _avatar(gallery ? 48 : 78, height: gallery ? 104 : 130),
          const SizedBox(width: 18),
          Expanded(child: _copy(headingSize: gallery ? 34 : 28))
        ]);
    final content = switch (_composition) {
      'editorial' =>
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (appearance.logoKey != null) ...[
            _avatar(48),
            const SizedBox(height: 16)
          ],
          _copy(headingSize: editorialSize, heavy: true, nameDivider: true),
        ]),
      'poster' => Stack(children: [
          Padding(
              padding: const EdgeInsets.only(top: 32),
              child: _copy(headingSize: 48, heavy: true)),
          Align(alignment: Alignment.topRight, child: _avatar(28)),
        ]),
      'bicolor' => Container(
          padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 12),
          color: bioColor(appearance.background.gradientColor),
          child: centered(avatar: 88, title: 24, framed: true)),
      'portrait' => portrait(),
      'gallery' => portrait(gallery: true),
      'scallop' => Padding(
          padding: const EdgeInsets.only(top: 30), child: centered(avatar: 88)),
      'collage' => Column(children: [
          Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
            Transform.rotate(
                angle: -.10,
                child: Container(
                    padding: const EdgeInsets.fromLTRB(7, 7, 7, 22),
                    decoration: BoxDecoration(
                        color: bioColor(appearance.surfaceColor),
                        boxShadow: const [
                          BoxShadow(
                              color: Color(0x22000000),
                              blurRadius: 8,
                              offset: Offset(2, 4))
                        ]),
                    child: SizedBox(
                        width: 76,
                        height: 92,
                        child: Stack(children: [
                          _avatar(76, height: 92),
                          Positioned(
                              top: -2,
                              left: 0,
                              right: 0,
                              child: bioCompositionArt('collage-tape',
                                  height: 26, fit: BoxFit.contain)),
                        ])))),
            const SizedBox(width: 16),
            Expanded(child: _copy(headingSize: 32)),
          ]),
          const SizedBox(height: 12),
        ]),
      'window' ||
      'window-grid' =>
        Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
          _avatar(_composition == 'window-grid' ? 44 : 48),
          const SizedBox(width: 14),
          Expanded(
              child:
                  _copy(headingSize: 30, heavy: _composition == 'window-grid'))
        ]),
      'botanical' => Padding(
          padding: const EdgeInsets.only(top: 24), child: centered(avatar: 88)),
      'glass' => Padding(
          padding: const EdgeInsets.only(top: 76),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _avatar(36),
            const SizedBox(width: 12),
            Expanded(child: _copy(headingSize: 30))
          ])),
      'torn' => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(
              height: 180,
              child: Stack(children: [
                ClipPath(
                    clipper: const BioCompositionClipper('torn'),
                    child: coverImage(160, fallback: 'meadow')),
                Positioned(
                    top: 44,
                    left: 0,
                    right: 0,
                    child: Center(child: _avatar(84, height: 118, arch: true))),
              ])),
          _copy(headingSize: 34),
        ]),
      'seal' => Column(children: [
          SizedBox(
              width: 100,
              height: 100,
              child: Stack(alignment: Alignment.center, children: [
                bioCompositionArt('gold-seal',
                    height: 100, fit: BoxFit.contain),
                _avatar(52),
              ])),
          const SizedBox(height: 18),
          _copy(centered: true, headingSize: 40)
        ]),
      'tag' => Column(children: [
          bioCompositionArt('tag-cord', height: 70, fit: BoxFit.contain),
          const SizedBox(height: 8),
          _avatar(40),
          const SizedBox(height: 14),
          _copy(centered: true, headingSize: 38)
        ]),
      'ticket' => Column(children: [
          _copy(centered: true, headingSize: 42, heavy: true),
          const SizedBox(height: 12),
          _avatar(32)
        ]),
      'rail' => Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _avatar(52),
          const SizedBox(width: 16),
          Expanded(child: _copy(headingSize: 30))
        ]),
      'ribbon' => Column(children: [
          _avatar(60),
          const SizedBox(height: 16),
          Container(
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 18),
              color: bioColor(appearance.categoryStyle.color)
                  .withValues(alpha: .12),
              child: _copy(centered: true, headingSize: 32)),
        ]),
      'notebook' => Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: _copy(headingSize: 32)),
              const SizedBox(width: 12),
              _avatar(48)
            ]),
      'arch' => Column(children: [
          ClipPath(
              clipper: const BioCompositionClipper('arch'),
              child: SizedBox(
                  width: 156,
                  height: 172,
                  child: Stack(alignment: Alignment.bottomCenter, children: [
                    coverImage(172),
                    Padding(
                        padding: const EdgeInsets.only(bottom: 16),
                        child: _avatar(76))
                  ]))),
          const SizedBox(height: 18),
          _copy(centered: true, headingSize: 30)
        ]),
      'staircase' => Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Expanded(child: _copy(headingSize: 34)),
          const SizedBox(width: 12),
          _avatar(44)
        ]),
      _ => centered(),
    };
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (cover != null && !const {'torn', 'arch'}.contains(_composition)) ...[
        ClipRRect(
            borderRadius: BorderRadius.circular(14), child: coverImage(140)),
        const SizedBox(height: 20),
      ],
      if (_composition == 'window-grid')
        Container(
            padding: const EdgeInsets.fromLTRB(8, 20, 8, 24),
            decoration: BoxDecoration(
                color: bioColor(appearance.background.color),
                border: Border.all(
                    color: bioColor(appearance.nameStyle.color), width: 2),
                borderRadius: BorderRadius.circular(4)),
            child: content)
      else
        content,
      SizedBox(height: _composition == 'torn' ? 20 : 28),
      if (const {'botanical', 'gallery', 'ticket', 'rail', 'notebook'}
          .contains(_composition)) ...[
        Divider(
            height: 1,
            color:
                bioColor(appearance.categoryStyle.color).withValues(alpha: .4)),
        const SizedBox(height: 16),
      ],
    ]);
  }

  Widget _link(LinkInBioCustomLink link, int index, double phase,
      double entrance, bool reduced, bool narrow,
      {bool tile = false, int rhythm = 0}) {
    final layout = template.layout;
    final grid = tile;
    final featured = appearance.featuredLinkId == link.id;
    var style = appearance.buttonStyle.copyWith(
        font: link.font ?? appearance.buttonStyle.font,
        color: link.textColor ?? appearance.buttonStyle.color);
    var color = bioColor(link.buttonColor ?? appearance.buttonColor);
    if (_composition == 'portrait' &&
        index > 0 &&
        link.buttonColor == null &&
        link.textColor == null &&
        appearance.buttonColor == template.palette.button &&
        appearance.buttonStyle.color == template.palette.buttonText) {
      color = bioColor(appearance.surfaceColor);
      style = style.copyWith(color: appearance.nameStyle.color);
    }
    final outline = layout.button == 'outline';
    final hairline = const {
      'editorial',
      'scallop',
      'botanical',
      'seal',
      'rail',
      'notebook'
    }.contains(_composition);
    final raised =
        const {'poster', 'window-grid', 'staircase'}.contains(_composition);
    final textColor = bioColor(style.color);
    bool readable(Color foreground, Color background) {
      final a = foreground.computeLuminance();
      final b = background.computeLuminance();
      return (math.max(a, b) + .05) / (math.min(a, b) + .05) >= 4.5;
    }

    if (const {'poster', 'window', 'window-grid', 'collage'}
            .contains(_composition) &&
        link.buttonColor == null &&
        link.textColor == null &&
        appearance.buttonColor == template.palette.button &&
        appearance.buttonStyle.color == template.palette.buttonText) {
      final colors = switch (_composition) {
        'window' => [
            color,
            const Color(0xfffff9e6),
            const Color(0xffd2bfff),
            const Color(0xffbcf0bd)
          ],
        'window-grid' => [
            color,
            bioColor(appearance.background.color),
            bioColor(appearance.surfaceColor),
            const Color(0xfff8d4e1)
          ],
        _ => [
            color,
            const Color(0xffbcf0bd),
            const Color(0xffd2bfff),
            const Color(0xfffff9e6)
          ],
      };
      final candidate = colors[rhythm % 4];
      if (readable(textColor, candidate)) color = candidate;
    }
    final transparent = (outline || hairline) &&
        link.buttonColor == null &&
        readable(textColor, bioColor(appearance.surfaceColor)) &&
        readable(textColor, bioColor(appearance.background.color));
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
    final numbered = const {'editorial', 'ticket', 'rail', 'notebook'}
        .contains(_composition);
    final button = Container(
        key: ValueKey('link-in-bio-template-link-${link.id}'),
        constraints: BoxConstraints(minHeight: grid ? 112 : 64),
        padding: grid
            ? const EdgeInsets.all(14)
            : EdgeInsets.symmetric(horizontal: narrow ? 12 : 16, vertical: 12),
        decoration: BoxDecoration(
            color: transparent
                ? Colors.transparent
                : _composition == 'glass' &&
                        link.buttonColor == null &&
                        link.textColor == null &&
                        appearance.buttonColor == template.palette.button &&
                        appearance.buttonStyle.color ==
                            template.palette.buttonText
                    ? color.withValues(alpha: 235 / 255)
                    : color,
            borderRadius:
                hairline && transparent ? null : BorderRadius.circular(radius),
            border: hairline && transparent
                ? Border(
                    bottom: BorderSide(
                        color: bioColor(appearance.categoryStyle.color)
                            .withValues(alpha: .45)))
                : raised
                    ? Border.all(
                        color: bioColor(appearance.nameStyle.color), width: 2)
                    : outline || featured
                        ? Border.all(
                            color: outline
                                ? color
                                : textColor.withValues(alpha: .9),
                            width: featured ? 2 : 1)
                        : _composition == 'collage'
                            ? Border.all(
                                color: bioColor(appearance.categoryStyle.color)
                                    .withValues(alpha: .4))
                            : _composition == 'glass'
                                ? Border.all(
                                    color: Colors.white.withValues(alpha: .6))
                                : null,
            boxShadow: raised
                ? [
                    BoxShadow(
                        color: bioColor(appearance.nameStyle.color),
                        offset: const Offset(4, 4))
                  ]
                : _composition == 'collage'
                    ? [
                        BoxShadow(
                            color: bioColor(appearance.categoryStyle.color)
                                .withValues(alpha: 53 / 255),
                            offset: const Offset(3, 4))
                      ]
                    : const {'torn', 'glass'}.contains(_composition)
                        ? [
                            const BoxShadow(
                                color: Color(0x19000000),
                                blurRadius: 7,
                                offset: Offset(0, 3))
                          ]
                        : null),
        child: grid
            ? Stack(children: [
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  logo,
                  const SizedBox(height: 10),
                  Padding(
                      padding: const EdgeInsets.only(right: 12),
                      child: label()),
                  const SizedBox(height: 24),
                ]),
                Positioned(
                    right: 0,
                    bottom: 0,
                    child: Icon(Icons.north_east, size: 18, color: textColor)),
              ])
            : Row(children: [
                if (numbered) ...[
                  Container(
                      width: 26,
                      margin: const EdgeInsets.only(right: 10),
                      padding: const EdgeInsets.only(right: 8),
                      decoration: const {'editorial', 'ticket'}
                              .contains(_composition)
                          ? BoxDecoration(
                              border: Border(
                                  right: BorderSide(
                                      color: textColor.withValues(alpha: .3))))
                          : null,
                      child: Text('${index + 1}'.padLeft(2, '0'),
                          key: ValueKey('link-in-bio-link-number-${link.id}'),
                          style: bioTextStyle(style, size: 12))),
                ],
                logo,
                const SizedBox(width: 12),
                Expanded(child: label()),
                const SizedBox(width: 8),
                Icon(Icons.north_east, size: 18, color: textColor)
              ]));
    Widget decorated = button;
    if (_composition == 'torn') {
      decorated = ClipPath(
          clipper: BioCompositionClipper(_composition), child: decorated);
    }
    if (_composition == 'ribbon' || _composition == 'staircase') {
      decorated = Padding(
          padding: EdgeInsets.only(
              left: rhythm.isOdd ? 18 : 0, right: rhythm.isEven ? 18 : 0),
          child: decorated);
    }
    if (_composition == 'rail') {
      decorated = Container(
          padding: const EdgeInsets.only(left: 12),
          decoration: BoxDecoration(
              border: Border(
                  left: BorderSide(
                      color: bioColor(appearance.categoryStyle.color)
                          .withValues(alpha: .5)))),
          child: decorated);
    }
    return bioMotionLink(
        effects: reduced ? const LinkInBioEffects() : appearance.effects,
        phase: phase,
        entrance: entrance,
        featured: featured || (appearance.featuredLinkId == null && index == 0),
        child: decorated);
  }

  Widget _linkGroups(double phase, double entrance, bool reduced, bool narrow) {
    if (links.isEmpty) {
      return Text('เพิ่มลิงก์เพื่อแสดงตัวอย่าง',
          style: bioTextStyle(appearance.descriptionStyle));
    }
    final groups = <List<(int, LinkInBioCustomLink)>>[];
    var currentCategory = '';
    for (final (index, link) in links.indexed) {
      if (index == 0 ||
          (link.category.trim().isNotEmpty &&
              link.category.trim() != currentCategory)) {
        groups.add([]);
        currentCategory = link.category.trim();
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
                  for (final (rhythm, record) in group.indexed)
                    SizedBox(
                        width: _tileAt(rhythm)
                            ? (size.maxWidth - 12) / 2
                            : size.maxWidth,
                        child: _link(record.$2, record.$1, phase, entrance,
                            reduced, narrow,
                            tile: _tileAt(rhythm), rhythm: rhythm))
                ])),
        const SizedBox(height: 12),
      ]
    ]);
  }

  bool _tileAt(int rhythm) =>
      const {'bicolor', 'gallery', 'window-grid'}.contains(_composition) ||
      (const {'collage', 'glass'}.contains(_composition) &&
          (rhythm % 4 == 1 || rhythm % 4 == 2));

  Widget _chrome() => Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
          color: bioColor(appearance.background.gradientColor),
          border: Border(
              bottom: BorderSide(
                  color: bioColor(appearance.categoryStyle.color),
                  width: _composition == 'window-grid' ? 2 : 1))),
      child: Row(children: [
        for (final color in [
          const Color(0xfff997ac),
          const Color(0xfff8d779),
          const Color(0xff96c6a0)
        ])
          Container(
              width: 12,
              height: 12,
              margin: const EdgeInsets.only(right: 7),
              decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                  border: _composition == 'window-grid'
                      ? Border.all(
                          color: bioColor(appearance.nameStyle.color),
                          width: 1.5)
                      : null))
      ]));

  Widget _panel(Widget child) {
    final window = _composition == 'window' || _composition == 'window-grid';
    final clipped = const {'tag', 'scallop', 'ticket'}.contains(_composition);
    final open = const {
      'editorial',
      'botanical',
      'glass',
      'gallery',
      'poster',
      'rail',
      'ribbon',
      'staircase',
      'collage'
    }.contains(_composition);
    final surface = bioColor(appearance.surfaceColor);
    Widget panel = Container(
        key: ValueKey(
            'link-in-bio-template-layout-${template.layout.header}-${template.layout.links}'),
        decoration: BoxDecoration(
            color: open &&
                    appearance.surfaceColor == template.palette.surface &&
                    appearance.background.mode != 'image' &&
                    (_composition != 'glass' || _presetBackground)
                ? Colors.transparent
                : surface,
            borderRadius:
                clipped ? null : BorderRadius.circular(window ? 12 : 0),
            border:
                const {'seal', 'window', 'window-grid'}.contains(_composition)
                    ? Border.all(
                        color: bioColor(_composition == 'window-grid'
                            ? appearance.nameStyle.color
                            : appearance.categoryStyle.color),
                        width: _composition == 'window-grid' ? 3 : 1)
                    : null),
        clipBehavior: window ? Clip.antiAlias : Clip.none,
        child: Stack(children: [
          if (_presetBackground &&
              appearance.surfaceColor == template.palette.surface &&
              const {'collage', 'torn', 'tag', 'notebook'}
                  .contains(_composition))
            Positioned.fill(
                child: IgnorePointer(child: bioCompositionArt('paper'))),
          if (_composition == 'scallop')
            Positioned.fill(
                child: IgnorePointer(
                    child:
                        bioCompositionArt('letter-frame', fit: BoxFit.fill))),
          if (_composition == 'notebook')
            Positioned.fill(
                child: IgnorePointer(
                    child: CustomPaint(
                        painter: BioCompositionPattern('notebook',
                            bioColor(appearance.categoryStyle.color))))),
          if (_composition == 'tag' || _composition == 'ticket')
            Positioned.fill(
                child: IgnorePointer(
                    child: CustomPaint(
                        painter: _CompositionBorderPainter(_composition,
                            bioColor(appearance.categoryStyle.color))))),
          Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            if (window) _chrome(),
            if (_composition == 'window-grid')
              ColoredBox(
                  color: bioColor(appearance.background.gradientColor),
                  child: Padding(
                      padding: const EdgeInsets.all(8),
                      child: ColoredBox(
                          color: surface,
                          child: Padding(
                              padding: const EdgeInsets.all(10),
                              child: KeyedSubtree(
                                  key: ValueKey(
                                      'link-in-bio-composition-$_composition'),
                                  child: child)))))
            else
              Padding(
                  padding:
                      EdgeInsets.all(window || clipped || _composition == 'seal'
                          ? 18
                          : _composition == 'notebook'
                              ? 24
                              : 0),
                  child: KeyedSubtree(
                      key: ValueKey('link-in-bio-composition-$_composition'),
                      child: child)),
          ])
        ]));
    if (clipped) {
      panel =
          ClipPath(clipper: BioCompositionClipper(_composition), child: panel);
    }
    return panel;
  }

  Widget _surface(
      BuildContext context, double phase, double entrance, bool reduced) {
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
              if (_presetBackground && _composition == 'glass')
                Positioned.fill(
                    child: IgnorePointer(child: bioCompositionArt('forest'))),
              if (_presetBackground &&
                  const {'collage', 'torn', 'tag', 'notebook'}
                      .contains(_composition))
                Positioned.fill(
                    child: IgnorePointer(child: bioCompositionArt('paper'))),
              if (_composition == 'botanical')
                Positioned.fill(
                    child: IgnorePointer(
                        child: bioCompositionArt('botanical-frame',
                            fit: BoxFit.fill))),
              if (_presetBackground && _composition == 'window')
                Positioned.fill(
                    child: IgnorePointer(
                        child: CustomPaint(
                            painter: BioCompositionPattern(
                                'window', Colors.white)))),
              Padding(
                  padding: const EdgeInsets.fromLTRB(20, 36, 20, 20),
                  child: Align(
                      alignment: Alignment.topCenter,
                      child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 520),
                          child: _panel(Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                _header(
                                    narrow ? 26 : 28,
                                    (MediaQuery.sizeOf(context).width * .14)
                                        .clamp(48, 56)),
                                _linkGroups(phase, reduced ? 1 : entrance,
                                    reduced, narrow),
                                SizedBox(
                                    height: _composition == 'torn' ? 28 : 48),
                                Text('PostDee',
                                    textAlign: TextAlign.center,
                                    style: bioTextStyle(appearance.brandStyle,
                                        size: 12)),
                                const SizedBox(height: 16),
                              ]))))),
              if (appearance.effects.stickers != 'none')
                Positioned.fill(
                    child: BioDecorations(
                        kind: appearance.effects.stickers,
                        phase: reduced ? 0 : phase)),
            ])));
  }

  @override
  Widget build(BuildContext context) => staticPreview
      ? _surface(context, 0, 1, true)
      : BioMotionSurface(
          effects: appearance.effects,
          builder: (phase, entrance, reduced) =>
              _surface(context, phase, entrance, reduced));
}

class _CompositionBorderPainter extends CustomPainter {
  _CompositionBorderPainter(this.kind, this.color);
  final String kind;
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = (kind == 'ticket' ? 3 : 1.5)
      ..style = PaintingStyle.stroke;
    canvas.drawPath(BioCompositionClipper(kind).getClip(size), paint);
  }

  @override
  bool shouldRepaint(covariant _CompositionBorderPainter oldDelegate) =>
      oldDelegate.kind != kind || oldDelegate.color != color;
}
