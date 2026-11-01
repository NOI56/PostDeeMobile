import 'package:flutter/material.dart';

import '../../core/models/link_in_bio_appearance.dart';
import '../../core/models/profile_template_catalog.generated.dart';
import 'link_in_bio_preview_styles.dart';

class Bio3dGeometry {
  const Bio3dGeometry(this.height, this.avatar, this.gap, this.shadows);
  final double height;
  final double avatar;
  final double gap;
  final List<BoxShadow> shadows;
}

// Keep geometry in step with the public renderer's linkInBio3dStyles.ts.
const bio3dGeometries = <String, Bio3dGeometry>{
  'dimensional-clay-mint': Bio3dGeometry(200, 96, 16, [
    BoxShadow(color: Color(0x14000000), blurRadius: 12, offset: Offset(0, 7)),
    BoxShadow(color: Color(0x12000000), blurRadius: 3, offset: Offset(0, 2)),
  ]),
  'dimensional-clay-peach': Bio3dGeometry(200, 96, 14, [
    BoxShadow(color: Color(0x0a000000), offset: Offset(0, 5)),
    BoxShadow(color: Color(0x13000000), blurRadius: 16, offset: Offset(0, 10)),
  ]),
  'dimensional-clay-cloud': Bio3dGeometry(212, 88, 18, [
    BoxShadow(color: Color(0x12000000), blurRadius: 18, offset: Offset(0, 10)),
    BoxShadow(color: Color(0x0c000000), blurRadius: 4, offset: Offset(0, 3)),
  ]),
  'dimensional-clay-sand': Bio3dGeometry(192, 96, 16, [
    BoxShadow(color: Color(0x12000000), offset: Offset(4, 5)),
    BoxShadow(color: Color(0x0d000000), blurRadius: 14, offset: Offset(0, 9)),
  ]),
  'dimensional-paper-fold': Bio3dGeometry(200, 96, 14, [
    BoxShadow(color: Color(0x14000000), offset: Offset(2, 3)),
    BoxShadow(color: Color(0x0c000000), blurRadius: 8, offset: Offset(4, 6)),
  ]),
  'dimensional-paper-stage': Bio3dGeometry(208, 96, 18, [
    BoxShadow(color: Color(0x17000000), offset: Offset(0, 4)),
    BoxShadow(color: Color(0x08000000), offset: Offset(0, 8)),
    BoxShadow(color: Color(0x0b000000), blurRadius: 14, offset: Offset(0, 11)),
  ]),
  'dimensional-paper-ribbon': Bio3dGeometry(192, 88, 14, [
    BoxShadow(color: Color(0x12000000), offset: Offset(3, 3)),
    BoxShadow(color: Color(0x0c000000), blurRadius: 12, offset: Offset(0, 7)),
  ]),
  'dimensional-glass-lavender': Bio3dGeometry(212, 96, 16, [
    BoxShadow(color: Color(0x10000000), blurRadius: 18, offset: Offset(0, 8)),
  ]),
  'dimensional-glass-mist': Bio3dGeometry(200, 88, 18, [
    BoxShadow(color: Color(0x12000000), blurRadius: 12, offset: Offset(0, 6)),
    BoxShadow(color: Color(0x08000000), blurRadius: 4, offset: Offset(0, 2)),
  ]),
  'dimensional-glass-sage': Bio3dGeometry(204, 96, 14, [
    BoxShadow(color: Color(0x12000000), blurRadius: 22, offset: Offset(0, 10)),
  ]),
};

BoxDecoration bio3dLinkDecoration({
  required ProfileTemplate template,
  required LinkInBioAppearance appearance,
  required Color color,
  required Color textColor,
  required bool customized,
  required bool featured,
}) {
  final geometry = bio3dGeometries[template.id]!;
  final glass = template.layout.composition == 'frosted';
  final paper = template.layout.composition == 'paper-stack';
  final radius = switch (appearance.buttonRadius) {
    'pill' => 999.0,
    'square' => 4.0,
    _ => 18.0,
  };
  return BoxDecoration(
      color: glass && !customized ? color.withValues(alpha: 235 / 255) : color,
      gradient: !customized && !glass && !paper
          ? LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color.lerp(color, Colors.white, .18)!, color])
          : null,
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(
          color: featured
              ? textColor.withValues(alpha: .9)
              : glass
                  ? Colors.white.withValues(alpha: .72)
                  : bioColor(appearance.categoryStyle.color)
                      .withValues(alpha: paper ? .36 : .14),
          width: featured ? 2 : 1),
      boxShadow: geometry.shadows);
}

class Bio3dHero extends StatelessWidget {
  const Bio3dHero(
      {super.key,
      required this.template,
      required this.appearance,
      required this.avatar,
      this.cover});
  final ProfileTemplate template;
  final LinkInBioAppearance appearance;
  final Widget avatar;
  final Widget? cover;

  @override
  Widget build(BuildContext context) {
    final geometry = bio3dGeometries[template.id]!;
    return SizedBox(
        height: geometry.height,
        child: LayoutBuilder(
            builder: (_, bounds) => OverflowBox(
                minWidth: bounds.maxWidth + 32,
                maxWidth: bounds.maxWidth + 32,
                minHeight: geometry.height,
                maxHeight: geometry.height,
                child: SizedBox(
                    key: ValueKey('link-in-bio-3d-hero-${template.id}'),
                    height: geometry.height,
                    width: bounds.maxWidth + 32,
                    child: Stack(alignment: Alignment.bottomCenter, children: [
                      Positioned.fill(
                          child: IgnorePointer(
                              child: appearance.coverKey != null
                                  ? KeyedSubtree(
                                      key: const ValueKey(
                                          'link-in-bio-3d-custom-cover'),
                                      child: cover ?? const SizedBox.expand())
                                  : Image.asset(
                                      'assets/images/profile_decorations/${template.id}.png',
                                      key: ValueKey(
                                          'link-in-bio-3d-art-${template.id}'),
                                      fit: BoxFit.contain,
                                      excludeFromSemantics: true,
                                      errorBuilder: (_, error, stack) =>
                                          const SizedBox.expand()))),
                      Padding(
                          padding: const EdgeInsets.only(bottom: 16),
                          child: Container(
                              width: geometry.avatar,
                              height: geometry.avatar,
                              decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: bioColor(appearance.surfaceColor),
                                  border: Border.all(
                                      color:
                                          Colors.white.withValues(alpha: .7)),
                                  boxShadow: const [
                                    BoxShadow(
                                        color: Color(0x16000000),
                                        blurRadius: 12,
                                        offset: Offset(0, 5))
                                  ]),
                              child: avatar)),
                    ])))));
  }
}
