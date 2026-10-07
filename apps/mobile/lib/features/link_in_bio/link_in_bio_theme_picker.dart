import 'dart:typed_data';

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';

import '../../core/models/link_in_bio_appearance.dart';
import '../../core/models/profile_template_catalog.generated.dart';
import 'link_in_bio_draft_store.dart';
import 'link_in_bio_preview.dart';

const _categoryChipNames = {
  'minimal': 'เรียบง่าย',
  'cute': 'น่ารัก',
  'nature': 'ธรรมชาติ',
  'luxury': 'หรูหรา',
  'creative': 'ครีเอทีฟ'
};

LinkInBioAppearance _keepContent(
        LinkInBioAppearance original, LinkInBioAppearance preset) =>
    preset.copyWith(
        description: original.description,
        logoKey: original.logoKey,
        coverKey: original.coverKey,
        background:
            preset.background.copyWith(imageKey: original.background.imageKey),
        featuredLinkId: original.featuredLinkId,
        featuredLabel: original.featuredLabel);

LinkInBioAppearance bioApplyTheme(
        LinkInBioAppearance appearance, String themeId) =>
    _keepContent(appearance, LinkInBioAppearance.forTheme(themeId));

LinkInBioAppearance bioApplyTemplate(
        LinkInBioAppearance appearance, String templateId) =>
    _keepContent(appearance, LinkInBioAppearance.forTemplate(templateId));

class BioThemePicker extends StatefulWidget {
  const BioThemePicker(
      {super.key,
      required this.appearance,
      required this.onChanged,
      this.enabled = true,
      this.storeName = '',
      this.slug = '',
      this.links = const [],
      this.images = const {},
      this.imageRevision});
  final LinkInBioAppearance appearance;
  final ValueChanged<LinkInBioAppearance> onChanged;
  final bool enabled;
  final String storeName;
  final String slug;
  final List<LinkInBioCustomLink> links;
  final Map<String, Uint8List> images;
  final ValueListenable<int>? imageRevision;
  @override
  State<BioThemePicker> createState() => _BioThemePickerState();
}

class _BioThemePickerState extends State<BioThemePicker> {
  late String _category =
      getProfileTemplate(widget.appearance.templateId)?.category ?? 'minimal';
  @override
  void didUpdateWidget(covariant BioThemePicker oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.appearance.templateId != widget.appearance.templateId) {
      _category = getProfileTemplate(widget.appearance.templateId)?.category ??
          _category;
    }
  }

  Future<void> _preview(ProfileTemplate template) async {
    final candidate = bioApplyTemplate(widget.appearance, template.id);
    final result = await showModalBottomSheet<LinkInBioAppearance>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        builder: (context) => FractionallySizedBox(
            heightFactor: .9,
            child: Column(children: [
              Padding(
                  padding: const EdgeInsets.fromLTRB(20, 14, 12, 8),
                  child: Row(children: [
                    Expanded(
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                          Text(template.name,
                              style: const TextStyle(
                                  fontSize: 18, fontWeight: FontWeight.w700)),
                          Text(profileTemplateCategories[template.category]!,
                              style: const TextStyle(fontSize: 13)),
                        ])),
                    IconButton(
                        key: const ValueKey(
                            'link-in-bio-template-preview-close'),
                        tooltip: 'ปิดตัวอย่าง',
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.close)),
                  ])),
              Expanded(
                  child: SingleChildScrollView(
                      key: const ValueKey('link-in-bio-template-preview'),
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: widget.imageRevision == null
                          ? _page(candidate)
                          : ValueListenableBuilder<int>(
                              valueListenable: widget.imageRevision!,
                              builder: (_, value, child) => _page(candidate)))),
              SafeArea(
                  top: false,
                  child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: SizedBox(
                          width: double.infinity,
                          child: FilledButton(
                              key: const ValueKey('link-in-bio-template-use'),
                              onPressed: () =>
                                  Navigator.pop(context, candidate),
                              child: const Text('ใช้แบบนี้'))))),
            ])));
    if (!mounted || result == null || !widget.enabled) return;
    widget.onChanged(result);
  }

  Widget _page(LinkInBioAppearance candidate) => LinkInBioPreview(
      storeName: widget.storeName,
      slug: widget.slug,
      links: widget.links,
      appearance: candidate,
      images: widget.images);

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final templates =
        profileTemplates.where((item) => item.category == _category).toList();
    final current = getProfileTemplate(widget.appearance.templateId);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(children: [
            for (final category in profileTemplateCategories.entries)
              Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                      key: ValueKey('link-in-bio-category-${category.key}'),
                      label: Text(_categoryChipNames[category.key]!),
                      selected: _category == category.key,
                      showCheckmark: false,
                      selectedColor: colors.primary,
                      labelStyle: TextStyle(
                          color: _category == category.key
                              ? colors.onPrimary
                              : colors.onSurface),
                      onSelected: widget.enabled
                          ? (_) => setState(() => _category = category.key)
                          : null)),
          ])),
      const SizedBox(height: 14),
      Text('${profileTemplateCategories[_category]} · 20 แบบ',
          style: const TextStyle(fontWeight: FontWeight.w700)),
      const SizedBox(height: 4),
      const Text('แตะแบบที่ชอบเพื่อดูตัวอย่างก่อนเลือก',
          style: TextStyle(fontSize: 12)),
      if (current != null)
        Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text('กำลังใช้ ${current.name}',
                style: TextStyle(fontSize: 12, color: colors.primary))),
      const SizedBox(height: 12),
      LayoutBuilder(
          builder: (_, size) => Wrap(
                  key: const ValueKey('link-in-bio-template-grid'),
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    for (final template in templates)
                      SizedBox(
                          width: (size.maxWidth - 12) / 2,
                          child: Material(
                              color: colors.surface,
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                  side: BorderSide(
                                      color: widget.appearance.templateId ==
                                              template.id
                                          ? colors.primary
                                          : colors.outlineVariant,
                                      width: widget.appearance.templateId ==
                                              template.id
                                          ? 2
                                          : 1)),
                              clipBehavior: Clip.antiAlias,
                              child: InkWell(
                                  key: ValueKey(
                                      'link-in-bio-template-${template.id}'),
                                  onTap: widget.enabled
                                      ? () => _preview(template)
                                      : null,
                                  child: Padding(
                                      padding: const EdgeInsets.all(8),
                                      child: Column(children: [
                                        BioTemplateSample(template: template),
                                        const SizedBox(height: 8),
                                        Row(children: [
                                          Expanded(
                                              child: Text(template.name,
                                                  style: const TextStyle(
                                                      fontSize: 12,
                                                      fontWeight:
                                                          FontWeight.w600),
                                                  maxLines: 2,
                                                  overflow:
                                                      TextOverflow.ellipsis)),
                                          if (widget.appearance.templateId ==
                                              template.id)
                                            Icon(Icons.check_circle,
                                                color: colors.primary,
                                                size: 17),
                                        ]),
                                      ])))))
                  ])),
      const SizedBox(height: 12),
      ExpansionTile(
          key: const ValueKey('link-in-bio-legacy-themes'),
          initiallyExpanded: widget.appearance.templateId == null &&
              widget.appearance.themeId != 'minimal',
          tilePadding: EdgeInsets.zero,
          childrenPadding: const EdgeInsets.only(bottom: 12),
          title: const Text('ธีมเดิม 7 แบบ', style: TextStyle(fontSize: 13)),
          subtitle: widget.appearance.templateId == null
              ? Text(
                  'กำลังใช้ ${linkInBioThemeNames[widget.appearance.themeId]}',
                  style: const TextStyle(fontSize: 12))
              : null,
          children: [
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final theme in linkInBioThemeNames.entries)
                ChoiceChip(
                    key: ValueKey('link-in-bio-theme-${theme.key}'),
                    selected: widget.appearance.templateId == null &&
                        widget.appearance.themeId == theme.key,
                    label: Text(theme.value),
                    onSelected: widget.enabled
                        ? (_) => widget.onChanged(
                            bioApplyTheme(widget.appearance, theme.key))
                        : null),
            ])
          ]),
    ]);
  }
}

// A lightweight schematic of the actual header, link columns and treatment.
// It avoids fetching artwork or playing 20 animations in the picker at once.
class BioTemplateSample extends StatelessWidget {
  const BioTemplateSample({super.key, required this.template});
  final ProfileTemplate template;
  @override
  Widget build(BuildContext context) => CustomPaint(
      painter: _TemplateSamplePainter(template),
      child: const SizedBox(height: 136, width: double.infinity));
}

class _TemplateSamplePainter extends CustomPainter {
  _TemplateSamplePainter(this.template);
  final ProfileTemplate template;
  @override
  void paint(Canvas canvas, Size size) {
    final palette = template.palette;
    final layout = template.layout;
    final paint = Paint();
    void rect(Rect rect, String color,
        {double radius = 3, bool outline = false}) {
      paint
        ..color = bioColor(color)
        ..style = outline ? PaintingStyle.stroke : PaintingStyle.fill
        ..strokeWidth = 1;
      canvas.drawRRect(
          RRect.fromRectAndRadius(rect, Radius.circular(radius)), paint);
    }

    rect(Offset.zero & size, palette.background, radius: 7);
    if (layout.decoration == 'frame') {
      rect(Rect.fromLTWH(5, 5, size.width - 10, size.height - 10),
          palette.category,
          radius: 5, outline: true);
    }
    if (layout.decoration == 'stripe') {
      for (var x = 0.0; x < size.width; x += 12) {
        paint
          ..color = bioColor(palette.category).withValues(alpha: .13)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 4;
        canvas.drawLine(Offset(x, 0), Offset(x + 12, 12), paint);
      }
    }
    if (layout.decoration == 'dots') {
      paint
        ..color = bioColor(palette.category).withValues(alpha: .2)
        ..style = PaintingStyle.fill;
      for (var x = 8.0; x < size.width; x += 16) {
        canvas.drawCircle(Offset(x, 6), 1.5, paint);
      }
    }
    double y = 18;
    if (layout.header == 'cover') {
      rect(Rect.fromLTWH(8, 8, size.width - 16, 30), palette.gradient);
      y = 34;
    }
    final left = layout.header == 'left' || layout.header == 'split';
    final avatar = Rect.fromLTWH(left ? 12 : size.width / 2 - 10, y, 20, 20);
    rect(avatar, palette.category,
        radius: layout.avatar == 'circle'
            ? 20
            : layout.avatar == 'rounded'
                ? 5
                : 1);
    if (layout.header == 'badge') {
      rect(avatar.inflate(3), palette.category, radius: 24, outline: true);
    }
    final textX = layout.header == 'split'
        ? 38.0
        : left
            ? 12.0
            : size.width / 2 - 21;
    final textY = layout.header == 'split' ? y + 5 : y + 27;
    rect(Rect.fromLTWH(textX, textY, 42, 3), palette.name, radius: 1);
    rect(Rect.fromLTWH(textX, textY + 7, 35, 2), palette.description,
        radius: 1);
    var linkY = layout.header == 'split' ? y + 32 : textY + 20;
    if (layout.decoration == 'line') {
      rect(Rect.fromLTWH(12, linkY - 6, size.width - 24, 1), palette.category);
    }
    final grid = layout.links == 'grid';
    final width = grid ? (size.width - 29) / 2 : size.width - 24;
    for (var index = 0; index < (grid ? 4 : 3); index++) {
      final x = grid ? 12 + (index % 2) * (width + 5) : 12.0;
      final row = grid ? index ~/ 2 : index;
      final height = grid ? 20.0 : 11.0;
      final box = Rect.fromLTWH(x, linkY + row * (height + 5), width, height);
      if (layout.button == 'raised') {
        rect(box.translate(2, 2), palette.name, radius: 3);
      }
      rect(box, palette.button,
          radius: template.buttonRadius == 'pill'
              ? 20
              : template.buttonRadius == 'square'
                  ? 1
                  : 3,
          outline: layout.button == 'outline');
      rect(Rect.fromLTWH(box.left + 6, box.top + height / 2 - 1, width - 15, 2),
          palette.buttonText,
          radius: 1);
    }
  }

  @override
  bool shouldRepaint(covariant _TemplateSamplePainter oldDelegate) =>
      oldDelegate.template.id != template.id;
}
