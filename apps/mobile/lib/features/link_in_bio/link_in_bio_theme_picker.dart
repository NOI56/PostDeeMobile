import 'dart:typed_data';

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';

import '../../core/models/link_in_bio_appearance.dart';
import '../../core/models/profile_template_catalog.generated.dart';
import 'link_in_bio_draft_store.dart';
import 'link_in_bio_preview.dart';
import 'link_in_bio_template_preview.dart';

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

// The chooser shows the actual native composition with deterministic sample
// content. Tickers are disabled; decoded artwork is shared by Flutter's cache.
class BioTemplateSample extends StatelessWidget {
  const BioTemplateSample({super.key, required this.template});
  final ProfileTemplate template;
  @override
  Widget build(BuildContext context) {
    final page = TickerMode(
        enabled: false,
        child: MediaQuery(
            data: const MediaQueryData(
                size: Size(320, 900), disableAnimations: true),
            child: BioTemplatePreview(
                template: template,
                storeName: 'noikub',
                links: const [
                  LinkInBioCustomLink(
                      id: 'sample-youtube',
                      title: 'YouTube',
                      url: 'https://youtube.com'),
                  LinkInBioCustomLink(
                      id: 'sample-shopee',
                      title: 'Shopee',
                      url: 'https://shopee.co.th'),
                  LinkInBioCustomLink(
                      id: 'sample-tiktok',
                      title: 'TikTok',
                      url: 'https://tiktok.com'),
                  LinkInBioCustomLink(
                      id: 'sample-line', title: 'LINE', url: 'https://line.me'),
                ],
                appearance: LinkInBioAppearance.forTemplate(template.id),
                images: const {},
                staticPreview: true)));
    return ExcludeSemantics(
        child: IgnorePointer(
            child: RepaintBoundary(
                child: LayoutBuilder(
                    builder: (_, constraints) => SizedBox(
                        height: constraints.maxWidth * 2,
                        width: double.infinity,
                        child: ClipRect(
                            child: OverflowBox(
                                alignment: Alignment.topLeft,
                                minWidth: 320,
                                maxWidth: 320,
                                minHeight: 0,
                                maxHeight: double.infinity,
                                child: Transform.scale(
                                    scale: constraints.maxWidth / 320,
                                    alignment: Alignment.topLeft,
                                    child: SizedBox(
                                        width: 320, child: page)))))))));
  }
}
