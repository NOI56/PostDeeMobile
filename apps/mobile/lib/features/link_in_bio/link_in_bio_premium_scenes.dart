import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/models/link_in_bio_appearance.dart';
import '../../core/models/profile_template_catalog.generated.dart';
import 'link_in_bio_draft_store.dart';
import 'link_in_bio_preview_styles.dart';

// How a premium link is finished: a polished plate with a sheen, a gilded
// double rule, cut Art Deco corners, an open row over a fine rule, a stitched
// inner line, or a soft pearl glow.
enum BioPremiumMaterial { plate, gilded, notched, hairline, stitched, pearl }

class BioPremiumDesign {
  const BioPremiumDesign(
      this.height, this.avatar, this.gap, this.panelRadius, this.material,
      {this.frame = false, this.fade = true});
  final double height;
  final double avatar;
  final double gap;
  final double panelRadius;
  final BioPremiumMaterial material;

  /// A fine inner frame around the whole page.
  final bool frame;

  /// Full-width art fades into the page; a light page under dark art keeps a
  /// clean edge instead.
  final bool fade;
}

const _plate = BioPremiumMaterial.plate;
const _gilded = BioPremiumMaterial.gilded;
const _notched = BioPremiumMaterial.notched;
const _hairline = BioPremiumMaterial.hairline;
const _stitched = BioPremiumMaterial.stitched;
const _pearl = BioPremiumMaterial.pearl;

// The premium release: twenty original pictures on five page layouts (crest,
// cameo, portal, atelier and vitrine). Keep geometry and materials in step
// with the public renderer's linkInBioPremiumStyles.ts.
const bioPremiumDesigns = <String, BioPremiumDesign>{
  'premium-gold-leaf': BioPremiumDesign(188, 92, 14, 6, _plate, frame: true),
  'premium-white-marble':
      BioPremiumDesign(250, 84, 14, 6, _gilded, frame: true),
  'premium-thai-gold': BioPremiumDesign(188, 92, 14, 6, _gilded, frame: true),
  'premium-art-deco': BioPremiumDesign(210, 96, 14, 4, _notched, frame: true),
  'premium-emerald-facet': BioPremiumDesign(176, 72, 14, 6, _gilded),
  'premium-pearl-strand': BioPremiumDesign(250, 84, 14, 28, _pearl),
  'premium-velvet-wine': BioPremiumDesign(176, 80, 14, 16, _stitched),
  'premium-champagne': BioPremiumDesign(210, 96, 14, 28, _plate),
  'premium-guilloche': BioPremiumDesign(210, 96, 14, 6, _gilded, frame: true),
  'premium-rose-gold': BioPremiumDesign(176, 72, 14, 24, _plate),
  'premium-midnight-stars':
      BioPremiumDesign(210, 96, 0, 6, _hairline, frame: true),
  'premium-black-onyx': BioPremiumDesign(176, 80, 0, 4, _hairline),
  'premium-silk-ribbon': BioPremiumDesign(250, 84, 14, 28, _plate),
  'premium-crystal': BioPremiumDesign(176, 72, 14, 20, _pearl),
  'premium-damask': BioPremiumDesign(188, 92, 14, 6, _plate, frame: true),
  'premium-golden-palms': BioPremiumDesign(176, 80, 14, 16, _gilded),
  'premium-spotlight': BioPremiumDesign(210, 96, 14, 8, _gilded),
  'premium-colonnade': BioPremiumDesign(250, 84, 0, 6, _hairline, frame: true),
  'premium-leather-stitch':
      BioPremiumDesign(176, 80, 14, 14, _stitched, fade: false),
  'premium-sapphire-wave':
      BioPremiumDesign(176, 72, 14, 4, _notched, frame: true),
};

// Cut corners for Art Deco plates, as on the public page.
const bioPremiumNotch = 10.0;

double bioPremiumSide(BuildContext context) =>
    MediaQuery.sizeOf(context).width <= 400 ? 18 : 24;

bool _dark(Color color) {
  final value = color.computeLuminance();
  return (1.05 / (value + .05)) > ((value + .05) / .05);
}

BoxDecoration bioPremiumPanelDecoration(
    ProfileTemplate template, LinkInBioAppearance appearance) {
  final panel = bioColor(appearance.surfaceColor);
  return BoxDecoration(
      color: panel,
      borderRadius: BorderRadius.circular(
          bioPremiumDesigns[template.id]!.panelRadius),
      border:
          Border.all(color: bioColor(appearance.categoryStyle.color).withAlpha(0x33)),
      boxShadow: _dark(panel)
          ? const [
              BoxShadow(
                  color: Color(0x59000000), blurRadius: 60, offset: Offset(0, 24))
            ]
          : const [
              BoxShadow(
                  color: Color(0x1a000000), blurRadius: 44, offset: Offset(0, 18))
            ]);
}

/// The fine inner frame drawn over the whole page, 10 points inside its edge.
Widget? bioPremiumFrame(
    ProfileTemplate template, LinkInBioAppearance appearance) {
  final design = bioPremiumDesigns[template.id]!;
  if (!design.frame) return null;
  return Positioned.fill(
      child: IgnorePointer(
          child: Padding(
              padding: const EdgeInsets.all(10),
              child: DecoratedBox(
                  key: const ValueKey('link-in-bio-premium-frame'),
                  decoration: BoxDecoration(
                      border: Border.all(
                          color: bioColor(appearance.categoryStyle.color)
                              .withAlpha(0x59)),
                      borderRadius: BorderRadius.circular(
                          math.max(0, design.panelRadius - 6)))))));
}

BorderRadius bioPremiumLinkRadius(
    ProfileTemplate template, LinkInBioAppearance appearance) {
  final material = bioPremiumDesigns[template.id]!.material;
  if (material == _notched || material == _hairline) return BorderRadius.zero;
  return BorderRadius.circular(switch (appearance.buttonRadius) {
    'pill' => 999.0,
    'square' => 4.0,
    _ => 16.0,
  });
}

double bioPremiumLinkMinHeight(ProfileTemplate template) =>
    bioPremiumDesigns[template.id]!.material == _hairline ? 68 : 64;

EdgeInsets bioPremiumLinkPadding(ProfileTemplate template, bool narrow,
    {bool custom = false}) {
  if (bioPremiumDesigns[template.id]!.material == _hairline) {
    final side = custom ? 14.0 : (narrow ? 2.0 : 4.0);
    return EdgeInsets.symmetric(horizontal: side, vertical: narrow ? 14 : 16);
  }
  return EdgeInsets.symmetric(
      horizontal: narrow ? 14 : 18, vertical: narrow ? 13 : 14);
}

// A polished sheen across a filled link: light at the top, a touch darker at
// the bottom, like the public page's gradient over the link color.
LinearGradient _sheen(Color color, int light, int dark) => LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        stops: const [0, .52, 1],
        colors: [
          Color.alphaBlend(Colors.white.withAlpha(light), color),
          color,
          Color.alphaBlend(Colors.black.withAlpha(dark), color),
        ]);

BoxDecoration bioPremiumLinkDecoration({
  required ProfileTemplate template,
  required LinkInBioAppearance appearance,
  required Color color,
  required Color textColor,
  required bool open,
  required bool featured,
}) {
  final line = bioColor(appearance.categoryStyle.color);
  final material = bioPremiumDesigns[template.id]!.material;
  final fill = open ? Colors.transparent : color;
  final radius = bioPremiumLinkRadius(template, appearance);
  final focus = Border.all(color: textColor.withValues(alpha: .9), width: 2);
  return switch (material) {
    BioPremiumMaterial.plate => BoxDecoration(
        gradient: open ? null : _sheen(color, 0x38, 0x14),
        color: open ? fill : null,
        borderRadius: radius,
        border: featured ? focus : Border.all(color: line.withAlpha(0x66)),
        boxShadow: const [
          BoxShadow(
              color: Color(0x26000000), blurRadius: 18, offset: Offset(0, 8))
        ]),
    BioPremiumMaterial.gilded => BoxDecoration(
        color: fill,
        borderRadius: radius,
        border: featured ? focus : Border.all(color: line),
        boxShadow: const [
          BoxShadow(
              color: Color(0x26000000), blurRadius: 24, offset: Offset(0, 10))
        ]),
    // The notch clip hides an outer edge; the shadow is painted around it.
    BioPremiumMaterial.notched => BoxDecoration(
        gradient: open ? null : _sheen(color, 0x33, 0x14),
        color: open ? fill : null,
        border: featured ? focus : null),
    BioPremiumMaterial.hairline => BoxDecoration(
        color: fill,
        borderRadius: radius,
        border: featured
            ? focus
            : Border(bottom: BorderSide(color: line.withAlpha(0x80)))),
    BioPremiumMaterial.stitched => BoxDecoration(
        color: fill,
        borderRadius: radius,
        border: featured ? focus : Border.all(color: const Color(0x33000000)),
        boxShadow: const [
          BoxShadow(
              color: Color(0x33000000), blurRadius: 18, offset: Offset(0, 8))
        ]),
    BioPremiumMaterial.pearl => BoxDecoration(
        color: fill,
        borderRadius: radius,
        border: featured ? focus : Border.all(color: line.withAlpha(0x40)),
        boxShadow: [
          const BoxShadow(
              color: Color(0x0f000000), blurRadius: 6, offset: Offset(0, 2)),
          BoxShadow(
              color: line.withAlpha(0x26),
              blurRadius: 24,
              offset: const Offset(0, 10)),
        ]),
  };
}

// Adds what a plain box cannot draw: the gilded inner rule, the stitched
// thread and the cut Art Deco corners with their shadow.
Widget bioPremiumLink({
  required ProfileTemplate template,
  required LinkInBioAppearance appearance,
  required LinkInBioCustomLink link,
  required Color textColor,
  required Widget child,
}) {
  final line = bioColor(appearance.categoryStyle.color);
  final radius = bioPremiumLinkRadius(template, appearance);
  switch (bioPremiumDesigns[template.id]!.material) {
    case BioPremiumMaterial.gilded:
      return CustomPaint(
          key: ValueKey('link-in-bio-premium-gilded-${link.id}'),
          foregroundPainter:
              _BioInsetRulePainter(radius, line.withAlpha(0x73), inset: 4),
          child: child);
    case BioPremiumMaterial.stitched:
      return CustomPaint(
          key: ValueKey('link-in-bio-premium-stitch-${link.id}'),
          foregroundPainter: _BioInsetRulePainter(
              radius, textColor.withValues(alpha: .65),
              inset: 5, width: 1.5, dashed: true),
          child: child);
    case BioPremiumMaterial.notched:
      return CustomPaint(
          painter: const _BioNotchShadowPainter(),
          child: ClipPath(
              key: ValueKey('link-in-bio-premium-notch-${link.id}'),
              clipper: const BioPremiumNotchClipper(),
              child: child));
    case BioPremiumMaterial.plate ||
          BioPremiumMaterial.hairline ||
          BioPremiumMaterial.pearl:
      return child;
  }
}

/// Wraps the link list: open rows start under one fine rule.
Widget bioPremiumLinkList(ProfileTemplate template,
    LinkInBioAppearance appearance, Widget child) {
  if (bioPremiumDesigns[template.id]!.material != _hairline) return child;
  return DecoratedBox(
      key: const ValueKey('link-in-bio-premium-rule'),
      decoration: BoxDecoration(
          border: Border(
              top: BorderSide(
                  color: bioColor(appearance.categoryStyle.color)
                      .withAlpha(0x80)))),
      child: child);
}

class BioPremiumNotchClipper extends CustomClipper<Path> {
  const BioPremiumNotchClipper();
  @override
  Path getClip(Size size) => _notchPath(size);
  @override
  bool shouldReclip(covariant CustomClipper<Path> oldClipper) => false;
}

Path _notchPath(Size size) {
  const cut = bioPremiumNotch;
  return Path()
    ..moveTo(cut, 0)
    ..lineTo(size.width - cut, 0)
    ..lineTo(size.width, cut)
    ..lineTo(size.width, size.height - cut)
    ..lineTo(size.width - cut, size.height)
    ..lineTo(cut, size.height)
    ..lineTo(0, size.height - cut)
    ..lineTo(0, cut)
    ..close();
}

class _BioNotchShadowPainter extends CustomPainter {
  const _BioNotchShadowPainter();
  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawPath(
        _notchPath(size).shift(const Offset(0, 8)),
        Paint()
          ..color = const Color(0x40000000)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6));
  }

  @override
  bool shouldRepaint(covariant _BioNotchShadowPainter oldDelegate) => false;
}

// A second, finer outline inside the link's edge: solid for gilded links,
// dashed thread for stitched ones.
class _BioInsetRulePainter extends CustomPainter {
  _BioInsetRulePainter(this.radius, this.color,
      {required this.inset, this.width = 1, this.dashed = false});
  final BorderRadius radius;
  final Color color;
  final double inset;
  final double width;
  final bool dashed;
  @override
  void paint(Canvas canvas, Size size) {
    final outer = radius.toRRect(Offset.zero & size);
    final rect = outer.deflate(inset + width / 2);
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = width;
    final path = Path()..addRRect(rect);
    if (!dashed) {
      canvas.drawPath(path, paint);
      return;
    }
    for (final metric in path.computeMetrics()) {
      for (var distance = 0.0; distance < metric.length; distance += 9) {
        canvas.drawPath(metric.extractPath(distance, distance + 5), paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _BioInsetRulePainter oldDelegate) =>
      oldDelegate.color != color ||
      oldDelegate.radius != radius ||
      oldDelegate.inset != inset;
}

// A fine rule, a small diamond and a fine rule under centred names, the same
// polygon as the public page's ornament.
class BioPremiumOrnament extends StatelessWidget {
  const BioPremiumOrnament({super.key, required this.color});
  final Color color;
  @override
  Widget build(BuildContext context) => CustomPaint(
      key: const ValueKey('link-in-bio-premium-ornament'),
      size: const Size(132, 9),
      painter: _BioOrnamentPainter(color));
}

class _BioOrnamentPainter extends CustomPainter {
  _BioOrnamentPainter(this.color);
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(0, 4)
      ..lineTo(56, 4)
      ..lineTo(66, 0)
      ..lineTo(76, 4)
      ..lineTo(132, 4)
      ..lineTo(132, 5)
      ..lineTo(76, 5)
      ..lineTo(66, 9)
      ..lineTo(56, 5)
      ..lineTo(0, 5)
      ..close();
    canvas.drawPath(path, Paint()..color = color);
  }

  @override
  bool shouldRepaint(covariant _BioOrnamentPainter oldDelegate) =>
      oldDelegate.color != color;
}

class BioPremiumHeader extends StatelessWidget {
  const BioPremiumHeader(
      {super.key,
      required this.template,
      required this.appearance,
      required this.avatar,
      required this.copy,
      this.cover});
  final ProfileTemplate template;
  final LinkInBioAppearance appearance;
  final Widget Function(double size) avatar;
  final Widget Function(bool centered, double headingSize) copy;
  final Widget? cover;

  Widget _art() => appearance.coverKey != null
      ? KeyedSubtree(
          key: const ValueKey('link-in-bio-premium-custom-cover'),
          child: cover ?? const SizedBox.expand())
      : Image.asset('assets/images/profile_decorations/${template.id}.png',
          key: ValueKey('link-in-bio-premium-art-${template.id}'),
          fit: BoxFit.cover,
          width: double.infinity,
          height: double.infinity,
          excludeFromSemantics: true,
          errorBuilder: (_, error, stack) => const SizedBox.expand());

  // Extends a child across the panel's side padding, like the page's bleed.
  Widget _bleed(double side, double height, Widget child) => SizedBox(
      height: height,
      child: LayoutBuilder(
          builder: (_, bounds) => OverflowBox(
              minWidth: bounds.maxWidth + side * 2,
              maxWidth: bounds.maxWidth + side * 2,
              child: SizedBox(height: height, child: child))));

  // Full-width art fades into the page so the avatar can sit on its edge.
  Widget _fadingArt(double height, double fade, Color panel) =>
      Stack(fit: StackFit.expand, children: [
        _art(),
        if (bioPremiumDesigns[template.id]!.fade)
          Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              height: height * fade,
              child: IgnorePointer(
                  child: DecoratedBox(
                      decoration: BoxDecoration(
                          gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [panel.withAlpha(0), panel]))))),
      ]);

  Widget _ringed(double size, Color line, Color panel, bool single) {
    final shape = template.layout.avatar;
    // Flutter paints shadows in list order, so the page's first (topmost)
    // shadow is last here.
    final shadows = single
        ? [
            const BoxShadow(
                color: Color(0x33000000), blurRadius: 18, offset: Offset(0, 8)),
            BoxShadow(color: line, spreadRadius: 4),
            BoxShadow(color: panel, spreadRadius: 3),
          ]
        : [
            const BoxShadow(
                color: Color(0x4d000000),
                blurRadius: 28,
                offset: Offset(0, 12)),
            BoxShadow(color: line.withAlpha(0x80), spreadRadius: 8),
            BoxShadow(color: panel, spreadRadius: 7),
            BoxShadow(color: line, spreadRadius: 4),
            BoxShadow(color: panel, spreadRadius: 3),
          ];
    return DecoratedBox(
        key: const ValueKey('link-in-bio-premium-avatar-ring'),
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
    final design = bioPremiumDesigns[template.id]!;
    final composition = template.layout.composition;
    final line = bioColor(appearance.categoryStyle.color);
    final panel = bioColor(appearance.surfaceColor);
    final side = bioPremiumSide(context);
    final narrow = MediaQuery.sizeOf(context).width <= 400;
    final heading = composition == 'vitrine'
        ? (narrow ? 24.0 : 26.0)
        : (narrow ? 26.0 : 30.0);
    final size = design.avatar;
    final ringed = _ringed(size, line, panel, composition == 'vitrine');
    final ornament = Padding(
        padding: const EdgeInsets.only(top: 18),
        child: Center(child: BioPremiumOrnament(color: line)));
    final content = switch (composition) {
      'crest' => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Stack(clipBehavior: Clip.none, children: [
            _bleed(side, design.height, _fadingArt(design.height, .42, panel)),
            Positioned(
                left: 0,
                right: 0,
                bottom: -size / 2,
                child: Center(child: ringed)),
          ]),
          SizedBox(height: size / 2 + 18),
          copy(true, heading),
          ornament,
        ]),
      // The avatar sits in the middle of the picture, like a cameo.
      'cameo' => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Stack(children: [
            _bleed(side, design.height, _fadingArt(design.height, .3, panel)),
            Positioned.fill(child: Center(child: ringed)),
          ]),
          const SizedBox(height: 20),
          copy(true, heading),
          ornament,
        ]),
      'atelier' => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Stack(clipBehavior: Clip.none, children: [
            _bleed(side, design.height, _fadingArt(design.height, .42, panel)),
            Positioned(left: 0, bottom: -size / 2, child: ringed),
          ]),
          SizedBox(height: size / 2 + 16),
          copy(false, heading),
          Align(
              alignment: AlignmentDirectional.centerStart,
              child: Container(
                  key: const ValueKey('link-in-bio-premium-rule-short'),
                  width: 48,
                  height: 1,
                  margin: const EdgeInsets.only(top: 16),
                  color: line)),
        ]),
      // The picture is seen through an arched window; the avatar sits on its sill.
      'portal' => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const SizedBox(height: 34),
          LayoutBuilder(builder: (_, bounds) {
            final width = math.min(bounds.maxWidth * .7, 300.0);
            final arch = BorderRadius.vertical(
                top: Radius.circular(width / 2),
                bottom: const Radius.circular(6));
            return Center(
                child: SizedBox(
                    width: width,
                    height: design.height,
                    child: Stack(clipBehavior: Clip.none, children: [
                      Positioned.fill(
                          child: DecoratedBox(
                              key: const ValueKey('link-in-bio-premium-arch'),
                              decoration: BoxDecoration(
                                  color: bioColor(
                                      appearance.background.gradientColor),
                                  borderRadius: arch,
                                  boxShadow: [
                                    const BoxShadow(
                                        color: Color(0x2e000000),
                                        blurRadius: 40,
                                        offset: Offset(0, 18)),
                                    BoxShadow(color: line, spreadRadius: 7),
                                    BoxShadow(color: panel, spreadRadius: 6),
                                  ]),
                              child: ClipRRect(
                                  borderRadius: arch, child: _art()))),
                      Positioned(
                          left: 0,
                          right: 0,
                          bottom: -size / 2,
                          child: Center(child: ringed)),
                    ])));
          }),
          SizedBox(height: size / 2 + 18),
          copy(true, heading),
          ornament,
        ]),
      // A framed picture above, then the avatar beside the name like a label.
      _ => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const SizedBox(height: 30),
          Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Container(
                  key: const ValueKey('link-in-bio-premium-vitrine'),
                  height: design.height,
                  decoration: BoxDecoration(
                      color: bioColor(appearance.background.gradientColor),
                      borderRadius: BorderRadius.circular(3),
                      boxShadow: [
                        const BoxShadow(
                            color: Color(0x40000000),
                            blurRadius: 34,
                            offset: Offset(0, 16)),
                        BoxShadow(color: line.withAlpha(0x99), spreadRadius: 6),
                        BoxShadow(color: panel, spreadRadius: 5),
                      ]),
                  clipBehavior: Clip.antiAlias,
                  child: _art())),
          const SizedBox(height: 26),
          Row(children: [
            ringed,
            const SizedBox(width: 16),
            Expanded(child: copy(false, heading)),
          ]),
        ]),
    };
    return KeyedSubtree(
        key: ValueKey('link-in-bio-premium-hero-${template.id}'),
        child: KeyedSubtree(
            key: ValueKey('link-in-bio-premium-layout-$composition'),
            child: content));
  }
}
