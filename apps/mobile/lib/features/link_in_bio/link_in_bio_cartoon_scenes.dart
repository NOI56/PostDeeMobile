import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/models/link_in_bio_appearance.dart';
import '../../core/models/profile_template_catalog.generated.dart';
import 'link_in_bio_draft_store.dart';
import 'link_in_bio_preview_styles.dart';

class BioCartoonDesign {
  const BioCartoonDesign(this.height, this.avatar, this.gap, this.panelRadius);
  final double height;
  final double avatar;
  final double gap;
  final BorderRadius panelRadius;
}

// Hand-drawn corners: each corner has its own elliptical radius, matching
// the public page's `a b c d / e f g h` border-radius values.
const _wobblyPanel = BorderRadius.only(
    topLeft: Radius.elliptical(30, 40),
    topRight: Radius.elliptical(44, 30),
    bottomRight: Radius.elliptical(34, 44),
    bottomLeft: Radius.elliptical(40, 34));
const _wobblyRounded = BorderRadius.only(
    topLeft: Radius.elliptical(16, 24),
    topRight: Radius.elliptical(26, 14),
    bottomRight: Radius.elliptical(14, 26),
    bottomLeft: Radius.elliptical(24, 16));
const _wobblySquare = BorderRadius.only(
    topLeft: Radius.elliptical(6, 4),
    topRight: Radius.elliptical(3, 7),
    bottomRight: Radius.elliptical(7, 3),
    bottomLeft: Radius.elliptical(4, 6));
BorderRadius _round(double radius) => BorderRadius.all(Radius.circular(radius));

// The cartoon release: ten original drawings on five page layouts (banner,
// beside, signboard, panels and chat). Keep geometry and materials in step
// with the public renderer's linkInBioCartoonStyles.ts.
final bioCartoonDesigns = <String, BioCartoonDesign>{
  'cartoon-doodle-shop': const BioCartoonDesign(176, 84, 16, _wobblyPanel),
  'cartoon-comic-panels': BioCartoonDesign(150, 88, 16, _round(8)),
  'cartoon-tag-buddy': BioCartoonDesign(168, 72, 14, _round(28)),
  'cartoon-sticker-sheet': BioCartoonDesign(176, 84, 16, _round(26)),
  'cartoon-chalkboard': BioCartoonDesign(168, 80, 14, _round(14)),
  'cartoon-street-front': BioCartoonDesign(200, 64, 14, _round(24)),
  'cartoon-chat-bubbles': BioCartoonDesign(140, 64, 18, _round(28)),
  'cartoon-signposts': BioCartoonDesign(168, 72, 14, _round(22)),
  'cartoon-crayon-sky': const BioCartoonDesign(176, 84, 16, _wobblyPanel),
  'cartoon-rocket-night': BioCartoonDesign(176, 84, 14, _round(28)),
};

// Rotating crayon outlines; the first follows the owner's heading color.
const bioCrayonColors = [
  Color(0xff2e86de),
  Color(0xff3fa34d),
  Color(0xfff08a00)
];
const _chalkFrame = Color(0xff8b5e3c);

double bioCartoonSide(BuildContext context) =>
    MediaQuery.sizeOf(context).width <= 400 ? 16 : 20;

bool _wobbly(ProfileTemplate template) =>
    template.id == 'cartoon-doodle-shop' || template.id == 'cartoon-crayon-sky';

BorderRadius bioCartoonLinkRadius(
    ProfileTemplate template, LinkInBioAppearance appearance) {
  if (_wobbly(template)) {
    return switch (appearance.buttonRadius) {
      'pill' => _round(999),
      'square' => _wobblySquare,
      _ => _wobblyRounded,
    };
  }
  final radius = switch (appearance.buttonRadius) {
    'pill' => 999.0,
    'square' => 4.0,
    _ => 16.0,
  };
  // Arrow signs keep a straight point; only the left corners are rounded.
  return template.id == 'cartoon-signposts'
      ? BorderRadius.horizontal(left: Radius.circular(radius))
      : _round(radius);
}

// Comic, sticker and chat links take turns between a few fills, like printed
// panels, stickers or two sides of a chat, only while the owner keeps the
// design's own colors and the default text stays readable on each fill.
Color? bioCartoonLinkFill(ProfileTemplate template,
    LinkInBioAppearance appearance, LinkInBioCustomLink link, int rhythm) {
  if (link.buttonColor != null ||
      link.textColor != null ||
      appearance.buttonColor != template.palette.button ||
      appearance.buttonStyle.color != template.palette.buttonText) {
    return null;
  }
  final button = appearance.buttonColor;
  final wash = appearance.background.gradientColor;
  final colors = switch (template.id) {
    'cartoon-comic-panels' => [button, wash, '#cdeaff', '#ffd6e3'],
    'cartoon-sticker-sheet' => [button, '#c9f2d9', '#ffd6e3', '#cfe6ff'],
    'cartoon-chat-bubbles' => [button, wash, button, wash],
    _ => null,
  };
  if (colors == null) return null;
  final color = bioColor(colors[rhythm % 4]);
  final text = bioColor(appearance.buttonStyle.color).computeLuminance();
  final fill = color.computeLuminance();
  final contrast = (math.max(text, fill) + .05) / (math.min(text, fill) + .05);
  return contrast >= 4.5 ? color : bioColor(button);
}

EdgeInsets bioCartoonLinkPadding(ProfileTemplate template, bool narrow) {
  final side = narrow ? 12.0 : 16.0;
  final vertical = narrow ? 14.0 : 15.0;
  return EdgeInsets.fromLTRB(
      template.id == 'cartoon-tag-buddy' ? (narrow ? 18 : 22) : side,
      template.id == 'cartoon-street-front' ? (narrow ? 22 : 24) : vertical,
      template.id == 'cartoon-signposts' ? (narrow ? 30 : 34) : side,
      vertical);
}

BoxDecoration bioCartoonPanelDecoration(
        ProfileTemplate template, LinkInBioAppearance appearance) =>
    BoxDecoration(
        color: bioColor(appearance.surfaceColor),
        borderRadius: bioCartoonDesigns[template.id]!.panelRadius,
        boxShadow: switch (template.id) {
          'cartoon-doodle-shop' => [
              BoxShadow(
                  color: bioColor(appearance.nameStyle.color).withAlpha(0x1f),
                  offset: const Offset(5, 6))
            ],
          'cartoon-comic-panels' => [
              BoxShadow(
                  color: bioColor(appearance.nameStyle.color),
                  offset: const Offset(6, 6))
            ],
          'cartoon-chalkboard' => const [
              BoxShadow(
                  color: Color(0x38000000),
                  blurRadius: 34,
                  offset: Offset(0, 16))
            ],
          'cartoon-crayon-sky' => const <BoxShadow>[],
          'cartoon-rocket-night' => const [
              BoxShadow(
                  color: Color(0x59000000),
                  blurRadius: 40,
                  offset: Offset(0, 18))
            ],
          _ => const [
              BoxShadow(
                  color: Color(0x0f000000),
                  blurRadius: 30,
                  offset: Offset(0, 14))
            ],
        });

// Drawn on top of the panel content, as the page's border sits outside its
// clipped content.
Border bioCartoonPanelBorder(
    ProfileTemplate template, LinkInBioAppearance appearance) {
  final ink = bioColor(appearance.nameStyle.color);
  final line = bioColor(appearance.categoryStyle.color);
  return switch (template.id) {
    'cartoon-doodle-shop' => Border.all(color: ink, width: 2),
    'cartoon-comic-panels' => Border.all(color: ink, width: 3),
    'cartoon-chalkboard' => Border.all(color: _chalkFrame, width: 10),
    'cartoon-crayon-sky' => Border.all(color: line, width: 3),
    'cartoon-rocket-night' => Border.all(color: line.withAlpha(0x33)),
    _ => Border.all(color: line.withAlpha(0x24)),
  };
}

BoxDecoration bioCartoonLinkDecoration({
  required ProfileTemplate template,
  required LinkInBioAppearance appearance,
  required Color color,
  required Color textColor,
  required bool open,
  required bool featured,
  required int rhythm,
}) {
  final ink = bioColor(appearance.nameStyle.color);
  final line = bioColor(appearance.categoryStyle.color);
  final panel = bioColor(appearance.surfaceColor);
  // Flutter paints shadows in list order, so the page's first (topmost)
  // shadow is last here.
  final (Border? border, List<BoxShadow> shadows) = switch (template.id) {
    'cartoon-doodle-shop' => (
        Border.all(color: ink, width: 2),
        [
          BoxShadow(color: ink, offset: const Offset(3, 4), spreadRadius: 1),
          BoxShadow(color: panel, offset: const Offset(3, 4), spreadRadius: -1),
        ]
      ),
    'cartoon-comic-panels' => (
        Border.all(color: ink, width: 3),
        [BoxShadow(color: ink, offset: const Offset(5, 5))]
      ),
    'cartoon-tag-buddy' => (
        Border.all(color: line.withAlpha(0x24)),
        [
          const BoxShadow(
              color: Color(0x0f000000), blurRadius: 18, offset: Offset(0, 10)),
          BoxShadow(color: line.withAlpha(0x29), offset: const Offset(0, 4)),
        ]
      ),
    'cartoon-sticker-sheet' => (
        Border.all(color: Colors.white, width: 4),
        [
          const BoxShadow(
              color: Color(0x1f000000), blurRadius: 12, offset: Offset(0, 6)),
          BoxShadow(color: line.withAlpha(0x33), spreadRadius: 1),
        ]
      ),
    'cartoon-chalkboard' || 'cartoon-signposts' => (null, const <BoxShadow>[]),
    'cartoon-street-front' => (
        Border.all(color: line, width: 2),
        [BoxShadow(color: line.withAlpha(0x40), offset: const Offset(0, 4))]
      ),
    'cartoon-chat-bubbles' => (
        Border.all(color: ink, width: 2),
        [BoxShadow(color: ink.withAlpha(0x1f), offset: const Offset(0, 3))]
      ),
    'cartoon-crayon-sky' => (
        Border.all(
            color: rhythm % 4 == 0 ? line : bioCrayonColors[rhythm % 4 - 1],
            width: 3),
        const [BoxShadow(color: Color(0x12000000), offset: Offset(0, 3))]
      ),
    _ => (
        Border.all(color: line.withAlpha(0x66), width: 2),
        [
          const BoxShadow(
              color: Color(0x40000000), blurRadius: 18, offset: Offset(0, 8)),
          BoxShadow(color: line.withAlpha(0x33), spreadRadius: 5),
          BoxShadow(color: panel, spreadRadius: 4),
        ]
      ),
  };
  return BoxDecoration(
      color: open ? Colors.transparent : color,
      borderRadius: bioCartoonLinkRadius(template, appearance),
      border: featured
          ? Border.all(color: textColor.withValues(alpha: .9), width: 2)
          : border,
      boxShadow: shadows);
}

// Adds what a plain box cannot draw: chat tails, arrow signs, dashed chalk,
// sticker tilt, the tag's color stripe and the awning band.
Widget bioCartoonLink({
  required ProfileTemplate template,
  required LinkInBioAppearance appearance,
  required LinkInBioCustomLink link,
  required Color color,
  required int rhythm,
  required Widget child,
}) {
  final ink = bioColor(appearance.nameStyle.color);
  final line = bioColor(appearance.categoryStyle.color);
  final radius = bioCartoonLinkRadius(template, appearance);
  switch (template.id) {
    case 'cartoon-tag-buddy':
      return CustomPaint(
          foregroundPainter: _BioInsetBandPainter(radius, line, left: 6),
          child: child);
    case 'cartoon-street-front':
      return CustomPaint(
          foregroundPainter: _BioAwningPainter(radius, line), child: child);
    case 'cartoon-chalkboard':
      return CustomPaint(
          key: ValueKey('link-in-bio-cartoon-dashed-${link.id}'),
          foregroundPainter: _BioDashedBorderPainter(
              radius, bioColor(link.buttonColor ?? appearance.buttonColor)),
          child: child);
    case 'cartoon-sticker-sheet':
      return Transform.rotate(
          key: ValueKey('link-in-bio-cartoon-tilt-${link.id}'),
          angle: (rhythm.isEven ? -1 : 1) * math.pi / 180,
          child: child);
    case 'cartoon-signposts':
      final arrow = _BioArrowClipper(radius.topLeft.x);
      return CustomPaint(
          painter: _BioArrowShadowPainter(arrow, ink.withAlpha(0x59)),
          child: ClipPath(
              key: ValueKey('link-in-bio-cartoon-arrow-${link.id}'),
              clipper: arrow,
              child: CustomPaint(
                  foregroundPainter: const _BioGrainPainter(), child: child)));
    case 'cartoon-chat-bubbles':
      final right = rhythm.isOdd;
      return Align(
          alignment: right ? Alignment.centerRight : Alignment.centerLeft,
          child: FractionallySizedBox(
              widthFactor: .88,
              child: Stack(clipBehavior: Clip.none, children: [
                child,
                Positioned(
                    left: right ? null : 24,
                    right: right ? 24 : null,
                    bottom: -7,
                    child: BioCartoonTail(
                        key: ValueKey('link-in-bio-cartoon-tail-${link.id}'),
                        color: color,
                        ink: ink,
                        pointsLeft: false)),
              ])));
  }
  return child;
}

// A speech-bubble tail: a square turned 45 degrees with two outlined sides,
// half tucked under the bubble so it covers the bubble's own edge.
class BioCartoonTail extends StatelessWidget {
  const BioCartoonTail(
      {super.key,
      required this.color,
      required this.ink,
      required this.pointsLeft});
  final Color color;
  final Color ink;
  final bool pointsLeft;
  @override
  Widget build(BuildContext context) {
    final side = BorderSide(color: ink, width: 2);
    return Transform.rotate(
        angle: math.pi / 4,
        child: Container(
            width: 14,
            height: 14,
            decoration: BoxDecoration(
                color: color,
                border: pointsLeft
                    ? Border(left: side, bottom: side)
                    : Border(right: side, bottom: side))));
  }
}

class BioCartoonHeader extends StatelessWidget {
  const BioCartoonHeader(
      {super.key,
      required this.template,
      required this.appearance,
      required this.avatar,
      required this.copy,
      this.cover});
  final ProfileTemplate template;
  final LinkInBioAppearance appearance;
  final Widget Function(double size) avatar;
  final Widget Function(bool centered) copy;
  final Widget? cover;

  Widget _art(BoxFit fit,
      {Alignment alignment = Alignment.center, double coverRadius = 0}) {
    final custom = appearance.coverKey != null;
    return ClipRRect(
        borderRadius: BorderRadius.circular(custom ? coverRadius : 0),
        child: custom
            ? KeyedSubtree(
                key: const ValueKey('link-in-bio-cartoon-custom-cover'),
                child: cover ?? const SizedBox.expand())
            : Image.asset(
                'assets/images/profile_decorations/${template.id}.png',
                key: ValueKey('link-in-bio-cartoon-art-${template.id}'),
                fit: fit,
                alignment: alignment,
                excludeFromSemantics: true,
                errorBuilder: (_, error, stack) => const SizedBox.expand()));
  }

  // Extends a child across the panel's side padding, like the page's bleed.
  Widget _bleed(double side, double height, Widget child) => SizedBox(
      height: height,
      child: LayoutBuilder(
          builder: (_, bounds) => OverflowBox(
              minWidth: bounds.maxWidth + side * 2,
              maxWidth: bounds.maxWidth + side * 2,
              child: SizedBox(height: height, child: child))));

  List<BoxShadow> _ring(Color ink, Color line, Color panel) =>
      switch (template.id) {
        'cartoon-doodle-shop' => [
            BoxShadow(
                color: ink.withAlpha(0x33),
                offset: const Offset(4, 5),
                spreadRadius: 6),
            BoxShadow(color: ink, spreadRadius: 6),
            BoxShadow(color: panel, spreadRadius: 4),
          ],
        'cartoon-sticker-sheet' => const [
            BoxShadow(
                color: Color(0x33000000), blurRadius: 14, offset: Offset(0, 6)),
            BoxShadow(color: Colors.white, spreadRadius: 5),
          ],
        'cartoon-chalkboard' => [
            BoxShadow(color: line, spreadRadius: 6),
            BoxShadow(color: panel, spreadRadius: 4),
          ],
        'cartoon-crayon-sky' => [
            BoxShadow(color: line, spreadRadius: 7),
            BoxShadow(color: panel, spreadRadius: 4),
          ],
        'cartoon-rocket-night' => [
            BoxShadow(color: line.withAlpha(0x59), blurRadius: 18),
            BoxShadow(color: line, spreadRadius: 6),
            BoxShadow(color: panel, spreadRadius: 4),
          ],
        _ => const [
            BoxShadow(
                color: Color(0x1f000000), blurRadius: 14, offset: Offset(0, 6))
          ],
      };

  Widget _ringed(double size, List<BoxShadow> shadows) {
    final shape = template.layout.avatar;
    return DecoratedBox(
        decoration: BoxDecoration(
            shape: shape == 'circle' ? BoxShape.circle : BoxShape.rectangle,
            borderRadius: shape == 'circle'
                ? null
                : BorderRadius.circular(
                    shape == 'rounded' ? (size * .22).roundToDouble() : 3),
            boxShadow: shadows),
        child: avatar(size));
  }

  @override
  Widget build(BuildContext context) {
    final design = bioCartoonDesigns[template.id]!;
    final composition = template.layout.composition;
    final ink = bioColor(appearance.nameStyle.color);
    final line = bioColor(appearance.categoryStyle.color);
    final panel = bioColor(appearance.surfaceColor);
    final wash = bioColor(appearance.background.gradientColor);
    final side = bioCartoonSide(context);
    final narrow = MediaQuery.sizeOf(context).width <= 400;
    // Small phones give the comic caption more room for long Thai names.
    final size = composition == 'panels' && narrow ? 64.0 : design.avatar;
    final ring = _ring(ink, line, panel);
    final content = switch (composition) {
      'banner' => () {
          final centered = template.layout.header == 'centered';
          final ringed = _ringed(size, ring);
          return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Stack(clipBehavior: Clip.none, children: [
                  _bleed(side, design.height, _art(BoxFit.cover)),
                  Positioned(
                      left: 0,
                      right: centered ? 0 : null,
                      bottom: -size / 2,
                      child: centered ? Center(child: ringed) : ringed),
                ]),
                SizedBox(height: size / 2 + 14),
                copy(centered),
              ]);
        }(),
      // The owner's logo hangs on a painted board above the drawn awning.
      'signboard' =>
        Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Stack(children: [
            _bleed(side, design.height, _art(BoxFit.cover)),
            Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: Center(
                    child: Container(
                        width: 52,
                        height: 20,
                        decoration: BoxDecoration(
                            border: Border(
                                left: BorderSide(color: ink, width: 3),
                                right: BorderSide(color: ink, width: 3)))))),
            Positioned(
                top: 18,
                left: 0,
                right: 0,
                child: Center(
                    child: Container(
                        key: const ValueKey('link-in-bio-cartoon-sign'),
                        width: size + 18,
                        height: size + 18,
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                            color: panel,
                            border: Border.all(color: ink, width: 3),
                            borderRadius: BorderRadius.circular(14),
                            boxShadow: [
                              BoxShadow(color: ink, offset: const Offset(0, 4))
                            ]),
                        child: avatar(size)))),
          ]),
          const SizedBox(height: 18),
          copy(true),
        ]),
      'beside' =>
        Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const SizedBox(height: 24),
          Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Expanded(
                flex: 100,
                child: Align(
                    alignment: Alignment.bottomLeft,
                    child: _ringed(size, ring))),
            const SizedBox(width: 12),
            Expanded(
                flex: 145,
                child: SizedBox(
                    height: design.height,
                    child: _art(BoxFit.contain,
                        alignment: Alignment.bottomCenter, coverRadius: 16))),
          ]),
          const SizedBox(height: 14),
          copy(false),
        ]),
      // Comic page: a framed drawing panel, then an avatar panel and a
      // caption box.
      'panels' =>
        Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const SizedBox(height: 20),
          Container(
              height: design.height,
              decoration: BoxDecoration(
                  border: Border.all(color: ink, width: 3),
                  borderRadius: BorderRadius.circular(6)),
              child: ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: _art(BoxFit.cover))),
          const SizedBox(height: 12),
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
                width: size,
                height: size,
                decoration: BoxDecoration(
                    border: Border.all(color: ink, width: 3),
                    borderRadius: BorderRadius.circular(6)),
                child: avatar(size - 6)),
            SizedBox(width: narrow ? 10 : 12),
            Expanded(
                child: Container(
                    key: const ValueKey('link-in-bio-cartoon-caption'),
                    constraints: BoxConstraints(minHeight: size),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                        color: wash,
                        border: Border.all(color: ink, width: 3),
                        borderRadius: BorderRadius.circular(6)),
                    child: copy(false))),
          ]),
        ]),
      // Chat: a cluster of empty bubbles, then the name said in a bubble.
      _ => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const SizedBox(height: 20),
          SizedBox(
              height: design.height,
              child: _art(BoxFit.contain, coverRadius: 16)),
          const SizedBox(height: 16),
          Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            _ringed(size, ring),
            const SizedBox(width: 16),
            Expanded(
                child: Stack(clipBehavior: Clip.none, children: [
              Container(
                  key: const ValueKey('link-in-bio-cartoon-caption'),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                      color: wash,
                      border: Border.all(color: ink, width: 2),
                      borderRadius: BorderRadius.circular(20)),
                  child: copy(false)),
              Positioned(
                  left: -7,
                  bottom: 16,
                  child:
                      BioCartoonTail(color: wash, ink: ink, pointsLeft: true)),
            ])),
          ]),
        ]),
    };
    return KeyedSubtree(
        key: ValueKey('link-in-bio-cartoon-hero-${template.id}'),
        child: KeyedSubtree(
            key: ValueKey('link-in-bio-cartoon-layout-$composition'),
            child: content));
  }
}

// The design's color band inside a link's edge, like the page's inset shadow.
class _BioInsetBandPainter extends CustomPainter {
  _BioInsetBandPainter(this.radius, this.color, {required this.left});
  final BorderRadius radius;
  final Color color;
  final double left;
  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.clipRRect(radius.toRRect(Offset.zero & size).deflate(1));
    canvas.drawRect(
        Rect.fromLTWH(0, 0, left + 1, size.height), Paint()..color = color);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _BioInsetBandPainter oldDelegate) =>
      oldDelegate.radius != radius || oldDelegate.color != color;
}

// Awning stripes across the top of a link, inside its 2px edge.
class _BioAwningPainter extends CustomPainter {
  _BioAwningPainter(this.radius, this.color);
  final BorderRadius radius;
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.clipRRect(radius.toRRect(Offset.zero & size).deflate(2));
    for (var x = 2.0; x < size.width; x += 28) {
      canvas.drawRect(Rect.fromLTWH(x, 2, 14, 10), Paint()..color = color);
      canvas.drawRect(
          Rect.fromLTWH(x + 14, 2, 14, 10), Paint()..color = Colors.white);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _BioAwningPainter oldDelegate) =>
      oldDelegate.radius != radius || oldDelegate.color != color;
}

// A 2px dashed chalk outline.
class _BioDashedBorderPainter extends CustomPainter {
  _BioDashedBorderPainter(this.radius, this.color);
  final BorderRadius radius;
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    final outline = Path()
      ..addRRect(radius.toRRect(Offset.zero & size).deflate(1));
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
    for (final metric in outline.computeMetrics()) {
      for (var distance = 0.0; distance < metric.length; distance += 12) {
        canvas.drawPath(metric.extractPath(distance, distance + 6), paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _BioDashedBorderPainter oldDelegate) =>
      oldDelegate.radius != radius || oldDelegate.color != color;
}

// A wooden sign cut into a right-pointing arrow.
class _BioArrowClipper extends CustomClipper<Path> {
  const _BioArrowClipper(this.radius);
  final double radius;
  @override
  Path getClip(Size size) {
    final r = math.min(radius, size.height / 2);
    return Path()
      ..moveTo(r, 0)
      ..lineTo(size.width - 20, 0)
      ..lineTo(size.width, size.height / 2)
      ..lineTo(size.width - 20, size.height)
      ..lineTo(r, size.height)
      ..arcToPoint(Offset(0, size.height - r), radius: Radius.circular(r))
      ..lineTo(0, r)
      ..arcToPoint(Offset(r, 0), radius: Radius.circular(r))
      ..close();
  }

  @override
  bool shouldReclip(covariant _BioArrowClipper oldClipper) =>
      oldClipper.radius != radius;
}

class _BioArrowShadowPainter extends CustomPainter {
  _BioArrowShadowPainter(this.arrow, this.color);
  final _BioArrowClipper arrow;
  final Color color;
  @override
  void paint(Canvas canvas, Size size) => canvas.drawPath(
      arrow.getClip(size).shift(const Offset(0, 4)), Paint()..color = color);

  @override
  bool shouldRepaint(covariant _BioArrowShadowPainter oldDelegate) =>
      oldDelegate.arrow.radius != arrow.radius || oldDelegate.color != color;
}

// Faint wood grain: a 2px line every 10px, counted from the bottom.
class _BioGrainPainter extends CustomPainter {
  const _BioGrainPainter();
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = const Color(0x0d000000);
    for (var y = size.height; y > 0; y -= 10) {
      canvas.drawRect(Rect.fromLTWH(0, y - 2, size.width, 2), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _BioGrainPainter oldDelegate) => false;
}
