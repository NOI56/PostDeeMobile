import 'package:flutter/material.dart';

import '../../core/models/link_in_bio_appearance.dart';
import '../../core/models/profile_template_catalog.generated.dart';
import 'link_in_bio_preview_styles.dart';

class Bio3dScene {
  const Bio3dScene(this.height, this.avatar, this.gap, this.panelRadius);
  final double height;
  final double avatar;
  final double gap;
  final double panelRadius;
}

// Second 3D release: ten scenes on five page layouts (showcase, neon,
// split-art, tile-grid and slab). Keep geometry and materials in step with
// the public renderer's linkInBio3dSceneStyles.ts.
const bio3dScenes = <String, Bio3dScene>{
  'dimensional-chrome-night': Bio3dScene(184, 84, 14, 24),
  'dimensional-lowpoly-dawn': Bio3dScene(184, 84, 14, 24),
  'dimensional-zen-garden': Bio3dScene(176, 80, 12, 20),
  'dimensional-wood-blocks': Bio3dScene(160, 64, 18, 26),
  'dimensional-parcel-stack': Bio3dScene(160, 64, 14, 18),
  'dimensional-ceramic-tiles': Bio3dScene(150, 60, 14, 24),
  'dimensional-pop-shapes': Bio3dScene(150, 60, 14, 28),
  'dimensional-neon-sign': Bio3dScene(168, 76, 16, 28),
  'dimensional-concrete-slab': Bio3dScene(150, 64, 18, 4),
  'dimensional-terrazzo-steps': Bio3dScene(150, 64, 18, 22),
};

const bio3dSceneSide = 20.0;

BoxDecoration bio3dScenePanelDecoration(
    ProfileTemplate template, LinkInBioAppearance appearance) {
  final scene = bio3dScenes[template.id]!;
  final ink = bioColor(appearance.nameStyle.color);
  final line = bioColor(appearance.categoryStyle.color);
  final concrete = template.id == 'dimensional-concrete-slab';
  final (border, shadows) = switch (template.layout.composition) {
    'neon' => (
        Border.all(color: line.withAlpha(0x59)),
        [
          BoxShadow(color: line.withAlpha(0x1f), spreadRadius: 1),
          BoxShadow(color: line.withAlpha(0x2e), blurRadius: 36),
        ]
      ),
    'split-art' => (
        Border.all(color: line.withAlpha(0x24)),
        const [
          BoxShadow(
              color: Color(0x0d000000), blurRadius: 32, offset: Offset(0, 14))
        ]
      ),
    'tile-grid' => (
        Border.all(color: line.withAlpha(0x1f)),
        const [
          BoxShadow(
              color: Color(0x0d000000), blurRadius: 30, offset: Offset(0, 14))
        ]
      ),
    'slab' when concrete => (
        Border.all(color: ink, width: 2),
        [BoxShadow(color: ink, offset: const Offset(8, 8))]
      ),
    'slab' => (
        Border.all(color: line.withAlpha(0x33)),
        const [
          BoxShadow(
              color: Color(0x1f000000), blurRadius: 34, offset: Offset(0, 16))
        ]
      ),
    _ => (
        Border.all(color: line.withAlpha(0x1f)),
        const [
          BoxShadow(
              color: Color(0x0f000000), blurRadius: 36, offset: Offset(0, 16))
        ]
      ),
  };
  return BoxDecoration(
      color: bioColor(appearance.surfaceColor),
      borderRadius: BorderRadius.circular(scene.panelRadius),
      border: border,
      boxShadow: shadows);
}

BoxDecoration bio3dSceneLinkDecoration({
  required ProfileTemplate template,
  required LinkInBioAppearance appearance,
  required Color color,
  required Color textColor,
  required bool open,
  required bool featured,
}) {
  final ink = bioColor(appearance.nameStyle.color);
  final line = bioColor(appearance.categoryStyle.color);
  final button = bioColor(appearance.buttonColor);
  final radius = switch (appearance.buttonRadius) {
    'pill' => 999.0,
    'square' => 4.0,
    _ => 18.0,
  };
  final (border, shadows) = switch (template.id) {
    'dimensional-chrome-night' => (
        Border.all(color: line.withAlpha(0x38)),
        [
          const BoxShadow(
              color: Color(0x52000000), blurRadius: 22, offset: Offset(0, 10)),
          BoxShadow(color: line.withAlpha(0x40), offset: const Offset(0, 1)),
        ]
      ),
    'dimensional-lowpoly-dawn' => (
        Border.all(color: line.withAlpha(0x1f)),
        [
          BoxShadow(
              color: ink.withAlpha(0x1a),
              blurRadius: 18,
              offset: const Offset(0, 8)),
          BoxShadow(
              color: ink.withAlpha(0x0f),
              blurRadius: 4,
              offset: const Offset(0, 2)),
        ]
      ),
    'dimensional-zen-garden' => (
        Border.all(color: color, width: 1.5),
        [BoxShadow(color: line.withAlpha(0x29), offset: const Offset(0, 2))]
      ),
    'dimensional-wood-blocks' => (
        Border.all(color: ink, width: 2),
        [BoxShadow(color: ink, offset: const Offset(0, 5))]
      ),
    'dimensional-parcel-stack' => (
        Border.all(color: line.withAlpha(0x47)),
        [
          BoxShadow(color: line.withAlpha(0x2e), offset: const Offset(0, 3)),
          const BoxShadow(
              color: Color(0x0f000000), blurRadius: 18, offset: Offset(0, 10)),
        ]
      ),
    'dimensional-ceramic-tiles' => (
        Border.all(color: ink.withAlpha(0x26)),
        [
          BoxShadow(color: ink.withAlpha(0xcc), offset: const Offset(0, 5)),
          BoxShadow(
              color: ink.withAlpha(0x26),
              blurRadius: 20,
              offset: const Offset(0, 12)),
        ]
      ),
    'dimensional-pop-shapes' => (
        Border.all(color: ink, width: 2),
        [BoxShadow(color: line, offset: const Offset(3, 4))]
      ),
    'dimensional-neon-sign' => (
        Border.all(color: color, width: 1.5),
        [
          BoxShadow(color: button.withAlpha(0x73), blurRadius: 14),
          BoxShadow(color: button, blurRadius: 2),
        ]
      ),
    'dimensional-concrete-slab' => (
        Border.all(color: ink, width: 2),
        [BoxShadow(color: ink, offset: const Offset(0, 6))]
      ),
    _ => (
        Border.all(color: line.withAlpha(0x99), width: 1.5),
        [
          BoxShadow(color: line.withAlpha(0x59), offset: const Offset(0, 5)),
          const BoxShadow(
              color: Color(0x0f000000), blurRadius: 16, offset: Offset(0, 10)),
        ]
      ),
  };
  // An open outline link shows the solid panel, as on the public page, and
  // keeps Flutter from painting its shadow through the transparent fill.
  final fill = open ? bioColor(appearance.surfaceColor) : color;
  return BoxDecoration(
      color: fill,
      gradient: template.id == 'dimensional-ceramic-tiles'
          ? LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              stops: const [
                  0,
                  .6
                ],
              colors: [
                  Color.alphaBlend(Colors.white.withAlpha(0x33), fill),
                  fill
                ])
          : null,
      borderRadius: BorderRadius.circular(radius),
      border: featured
          ? Border.all(color: textColor.withValues(alpha: .9), width: 2)
          : border,
      boxShadow: shadows);
}

class Bio3dSceneHeader extends StatelessWidget {
  const Bio3dSceneHeader(
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
      {Alignment alignment = Alignment.center, double radius = 0}) {
    final custom = appearance.coverKey != null;
    return ClipRRect(
        borderRadius: BorderRadius.circular(custom &&
                radius == 0 &&
                const {'split-art', 'tile-grid', 'slab'}
                    .contains(template.layout.composition)
            ? 16
            : radius),
        child: custom
            ? KeyedSubtree(
                key: const ValueKey('link-in-bio-3d-custom-cover'),
                child: cover ?? const SizedBox.expand())
            : Image.asset(
                'assets/images/profile_decorations/${template.id}.png',
                key: ValueKey('link-in-bio-3d-art-${template.id}'),
                fit: fit,
                alignment: alignment,
                excludeFromSemantics: true,
                errorBuilder: (_, error, stack) => const SizedBox.expand()));
  }

  // Extends a child across the panel's side padding, like the page's bleed.
  Widget _bleed(double height, Widget child) => SizedBox(
      height: height,
      child: LayoutBuilder(
          builder: (_, bounds) => OverflowBox(
              minWidth: bounds.maxWidth + bio3dSceneSide * 2,
              maxWidth: bounds.maxWidth + bio3dSceneSide * 2,
              child: SizedBox(height: height, child: child))));

  Widget _avatar(double size, List<BoxShadow> shadows) {
    final shape = template.layout.avatar;
    return DecoratedBox(
        decoration: BoxDecoration(
            shape: shape == 'circle' ? BoxShape.circle : BoxShape.rectangle,
            borderRadius: shape == 'circle'
                ? null
                : BorderRadius.circular(
                    shape == 'rounded' ? (size * .22).roundToDouble() : 6),
            boxShadow: shadows),
        child: avatar(size));
  }

  @override
  Widget build(BuildContext context) {
    final scene = bio3dScenes[template.id]!;
    final composition = template.layout.composition;
    final panel = bioColor(appearance.surfaceColor);
    final button = bioColor(appearance.buttonColor);
    final size = scene.avatar;
    const lift = [
      BoxShadow(color: Color(0x1f000000), blurRadius: 14, offset: Offset(0, 6))
    ];
    final content = switch (composition) {
      'showcase' || 'neon' => () {
          final neon = composition == 'neon';
          final centered = neon || template.layout.header == 'centered';
          final ring = neon
              ? [
                  BoxShadow(color: panel, spreadRadius: 3),
                  BoxShadow(color: button, spreadRadius: 5),
                  BoxShadow(color: button.withAlpha(0x73), blurRadius: 18),
                ]
              : [
                  BoxShadow(color: panel, spreadRadius: 4),
                  const BoxShadow(
                      color: Color(0x29000000),
                      blurRadius: 18,
                      offset: Offset(0, 8)),
                ];
          final banner = neon
              ? Container(
                  height: scene.height,
                  decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(18),
                      boxShadow: [
                        BoxShadow(color: button.withAlpha(0x40), blurRadius: 26)
                      ]),
                  child: _art(BoxFit.cover, radius: 18))
              : _bleed(scene.height, _art(BoxFit.cover));
          return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (neon) const SizedBox(height: 16),
                Stack(clipBehavior: Clip.none, children: [
                  banner,
                  Positioned(
                      left: 0,
                      right: centered ? 0 : null,
                      bottom: -size / 2,
                      child: centered
                          ? Center(child: _avatar(size, ring))
                          : _avatar(size, ring)),
                ]),
                SizedBox(height: size / 2 + (neon ? 16 : 14)),
                copy(centered),
              ]);
        }(),
      'split-art' =>
        Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const SizedBox(height: 24),
          Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Expanded(
                flex: 100,
                child: Align(
                    alignment: Alignment.bottomLeft,
                    child: _avatar(size, lift))),
            const SizedBox(width: 12),
            Expanded(
                flex: 145,
                child: SizedBox(
                    height: scene.height,
                    child: _art(BoxFit.contain,
                        alignment: Alignment.bottomCenter))),
          ]),
          const SizedBox(height: 14),
          copy(false),
        ]),
      'tile-grid' =>
        Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const SizedBox(height: 20),
          SizedBox(height: scene.height, child: _art(BoxFit.contain)),
          const SizedBox(height: 16),
          Row(children: [
            _avatar(size, lift),
            const SizedBox(width: 14),
            Expanded(child: copy(false)),
          ]),
        ]),
      _ => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const SizedBox(height: 28),
          _avatar(size, lift),
          const SizedBox(height: 16),
          SizedBox(width: double.infinity, child: copy(false)),
          const SizedBox(height: 18),
          appearance.coverKey != null
              ? SizedBox(
                  height: scene.height,
                  width: double.infinity,
                  child: _art(BoxFit.cover,
                      radius:
                          template.id == 'dimensional-concrete-slab' ? 4 : 16))
              : _bleed(scene.height, _art(BoxFit.contain)),
        ]),
    };
    return KeyedSubtree(
        key: ValueKey('link-in-bio-3d-hero-${template.id}'),
        child: KeyedSubtree(
            key: ValueKey('link-in-bio-3d-scene-$composition'),
            child: content));
  }
}
