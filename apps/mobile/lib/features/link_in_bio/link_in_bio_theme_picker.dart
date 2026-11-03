import 'dart:typed_data';

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'link_in_bio_color_picker.dart' show BioOwnedModalScope;

import '../../core/models/link_in_bio_appearance.dart';
import '../../core/models/profile_template_catalog.generated.dart';
import 'link_in_bio_draft_store.dart';
import 'link_in_bio_localizations.dart';
import 'link_in_bio_preview.dart';
import 'link_in_bio_template_preview.dart';
import 'link_in_bio_ui_motion.dart';
import 'link_in_bio_theme_access.dart';

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
      this.hasPremiumThemeAccess = false,
      this.premiumThemeAccess,
      this.beforeApply,
      this.onMembershipRequested,
      this.onMembershipRetry,
      this.storeName = '',
      this.slug = '',
      this.links = const [],
      this.images = const {},
      this.imageRevision});
  final LinkInBioAppearance appearance;
  final ValueChanged<LinkInBioAppearance> onChanged;
  final bool enabled;
  final bool hasPremiumThemeAccess;
  final ValueListenable<bool>? premiumThemeAccess;
  final Future<bool> Function(LinkInBioAppearance)? beforeApply;
  final Future<void> Function()? onMembershipRequested;
  final Future<void> Function()? onMembershipRetry;
  final String storeName;
  final String slug;
  final List<LinkInBioCustomLink> links;
  final Map<String, Uint8List> images;
  final ValueListenable<int>? imageRevision;
  @override
  State<BioThemePicker> createState() => _BioThemePickerState();
}

class _BioThemePickerState extends State<BioThemePicker> {
  late String _category;
  bool _applying = false;
  bool get _hasAccess => widget.premiumThemeAccess?.value ?? widget.hasPremiumThemeAccess;

  Widget _watchAccess(WidgetBuilder builder) => widget.premiumThemeAccess == null
      ? Builder(builder: builder)
      : ValueListenableBuilder<bool>(valueListenable: widget.premiumThemeAccess!,
          builder: (context, value, child) => builder(context));

  static const _categories = ['minimal', 'dimensional', 'cartoon', 'premium'];

  String _savedCategory() {
    final saved = getProfileTemplate(widget.appearance.templateId)?.category;
    return _categories.contains(saved) ? saved! : 'minimal';
  }

  @override
  void initState() {
    super.initState();
    _category = _savedCategory();
  }

  @override
  void didUpdateWidget(covariant BioThemePicker oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.appearance.templateId != widget.appearance.templateId ||
        oldWidget.appearance.themeId != widget.appearance.themeId) {
      _category = _savedCategory();
    }
  }

  Future<void> _preview(ProfileTemplate template) async {
    final ownership = BioOwnedModalScope.maybeOf(context);
    final candidate = bioApplyTemplate(widget.appearance, template.id);
    final result = await showModalBottomSheet<LinkInBioAppearance>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        builder: (context) {
          final route = ModalRoute.of(context);
          if (route != null) ownership?.onOpened(route);
          return _watchAccess((context) => StatefulBuilder(builder: (context, update) {
            final locked = bioRequiresThemeMembership(candidate) && !_hasAccess;
            return BioUiMotionScope(
              child: FractionallySizedBox(
                  heightFactor: .9,
                  child: Column(children: [
                    Padding(
                        padding: const EdgeInsets.fromLTRB(20, 14, 12, 8),
                        child: Row(children: [
                          Expanded(
                              child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                Text(
                                    localizeLinkInBioMessage(
                                        context, template.name),
                                    style: const TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.w700)),
                                Text(
                                    localizeLinkInBioMessage(
                                        context,
                                        profileTemplateCategories[
                                            template.category]!),
                                    style: const TextStyle(fontSize: 13)),
                              ])),
                          BioUiPress(
                              child: IconButton(
                                  key: const ValueKey(
                                      'link-in-bio-template-preview-close'),
                                  tooltip: linkInBioText(
                                      context, 'ปิดตัวอย่าง', 'Close preview'),
                                  onPressed: () => Navigator.pop(context),
                                  icon: const Icon(Icons.close))),
                        ])),
                    Expanded(
                        child: SingleChildScrollView(
                            key: const ValueKey('link-in-bio-template-preview'),
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    if (locked)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                          Text(linkInBioText(context, 'ธีมสำหรับสมาชิก', 'Member theme'),
                              key: const ValueKey('link-in-bio-template-membership-required'),
                              style: const TextStyle(fontWeight: FontWeight.w700)),
                          Text(linkInBioText(context,
                              'ดูตัวอย่างได้ สมัคร Starter, Pro หรือ Business เพื่อนำไปใช้',
                              'Preview this theme. Subscribe to Starter, Pro or Business to apply it.')),
                          if (widget.onMembershipRetry != null)
                            TextButton(key: const ValueKey('link-in-bio-template-membership-retry'),
                                onPressed: _applying ? null : () async {
                                  update(() => _applying = true);
                                  try { await widget.onMembershipRetry!(); }
                                  finally {
                                    _applying = false;
                                    if (context.mounted) update(() {});
                                  }
                                },
                                child: Text(linkInBioText(context, 'ตรวจสอบสมาชิกอีกครั้ง', 'Check membership again'))),
                          if (widget.onMembershipRequested != null)
                            TextButton(key: const ValueKey('link-in-bio-template-membership-plans'),
                                onPressed: _applying ? null : widget.onMembershipRequested,
                                child: Text(linkInBioText(context, 'ดูแพ็กเกจสมาชิก', 'View membership plans'))),
                        ])),
                            widget.imageRevision == null
                                ? _page(candidate)
                                : ValueListenableBuilder<int>(
                                    valueListenable: widget.imageRevision!,
                                    builder: (_, value, child) =>
                                        _page(candidate)),
                            ]))),
                    SafeArea(
                        top: false,
                        child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: SizedBox(
                                width: double.infinity,
                                child: BioUiPress(
                                    child: FilledButton(
                                        key: const ValueKey(
                                            'link-in-bio-template-use'),
                                        onPressed: locked || _applying || !widget.enabled ? null : () async {
                                          update(() => _applying = true);
                                          try {
                                            final allowed = await widget.beforeApply?.call(candidate) ?? true;
                                            if (!mounted || !context.mounted || !widget.enabled || !allowed) return;
                                            if (bioRequiresThemeMembership(candidate) && !_hasAccess) return;
                                            Navigator.pop(context, candidate);
                                          } finally {
                                            _applying = false;
                                            if (context.mounted) update(() {});
                                          }
                                        },
                                        child: Text(linkInBioText(
                                            context,
                                            'ใช้กับแบบร่าง',
                                            'Apply to draft'))))))),
                  ])));
          }));
        });
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
  Widget build(BuildContext context) =>
      BioUiMotionScope(child: _watchAccess(_buildPicker));

  Widget _buildPicker(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final templates =
        profileTemplates.where((item) => item.category == _category).toList();
    final current = getProfileTemplate(widget.appearance.templateId);
    final savedOnly = !_hasAccess && bioRequiresThemeMembership(widget.appearance);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Wrap(spacing: 8, runSpacing: 8, children: [
        for (final category in _categories)
          ChoiceChip(
              key: ValueKey('link-in-bio-category-$category'),
              avatar: category != 'minimal' && !_hasAccess
                  ? const Icon(Icons.lock_outline, size: 16) : null,
              label: Text(localizeLinkInBioMessage(
                  context, profileTemplateCategories[category]!)),
              selected: _category == category,
              onSelected: (_) => setState(() => _category = category)),
      ]),
      const SizedBox(height: 12),
      Text(
          linkInBioText(
              context,
              '${profileTemplateCategories[_category]} · ${templates.length} แบบ',
              '${localizeLinkInBioMessage(context, profileTemplateCategories[_category]!)} · ${templates.length} templates'),
          key: const ValueKey('link-in-bio-category-heading'),
          style: const TextStyle(fontWeight: FontWeight.w700)),
      const SizedBox(height: 4),
      Text(
          linkInBioText(
              context,
              'ภาพย่อเป็นตัวอย่าง แตะเพื่อดูร้านของคุณก่อนเลือก',
              'Thumbnails are examples. Tap to preview your store before choosing.'),
          style: const TextStyle(fontSize: 12)),
      if (current != null || widget.appearance.themeId != 'minimal')
        Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
                savedOnly ? linkInBioText(context,
                    'เก็บธีม ${current?.name ?? linkInBioThemeNames[widget.appearance.themeId]} ไว้แล้ว · ขณะนี้ใช้ธีมเรียบง่ายชั่วคราว',
                    'Saved ${localizeLinkInBioMessage(context, current?.name ?? linkInBioThemeNames[widget.appearance.themeId] ?? '')} · Using Minimal temporarily.') : linkInBioText(
                    context,
                    'กำลังใช้ ${current?.name ?? linkInBioThemeNames[widget.appearance.themeId]}',
                    'Currently using ${localizeLinkInBioMessage(context, current?.name ?? linkInBioThemeNames[widget.appearance.themeId] ?? '')}'),
                key: savedOnly ? const ValueKey('link-in-bio-saved-theme-membership') : null,
                style: TextStyle(fontSize: 12, color: colors.primary))),
      const SizedBox(height: 12),
      LayoutBuilder(
          builder: (_, size) => BioUiEntrance(
              key: ValueKey('link-in-bio-category-motion-$_category'),
              child: Wrap(
                  key: const ValueKey('link-in-bio-template-grid'),
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    for (final template in templates)
                      SizedBox(
                          width:
                              MediaQuery.textScalerOf(context).scale(12) > 18 &&
                                      size.maxWidth < 560
                                  ? size.maxWidth
                                  : (size.maxWidth - 12) / 2,
                          child: BioUiPress(
                              enabled: widget.enabled,
                              child: Material(
                                  animationDuration: bioUiMotionAllowed(context)
                                      ? const Duration(milliseconds: 160)
                                      : Duration.zero,
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
                                  child: Semantics(
                                      key: ValueKey(
                                          'link-in-bio-template-state-${template.id}'),
                                      button: true,
                                      enabled: widget.enabled,
                                      selected: widget.appearance.templateId ==
                                          template.id,
                                      label: localizeLinkInBioMessage(context, template.name),
                                      hint: linkInBioText(context, 'ดูตัวอย่างก่อนใช้', 'Preview before applying'),
                                      excludeSemantics: true,
                                      onTap: widget.enabled ? () => _preview(template) : null,
                                      child: InkWell(
                                          key: ValueKey('link-in-bio-template-${template.id}'),
                                          onTap: widget.enabled ? () => _preview(template) : null,
                                          child: Padding(
                                              padding: const EdgeInsets.all(8),
                                              child: Column(children: [
                                                BioTemplateSample(
                                                    template: template),
                                                const SizedBox(height: 8),
                                                Row(children: [
                                                  Expanded(
                                                      child: Text(
                                                          localizeLinkInBioMessage(
                                                              context,
                                                              template.name),
                                                          style: const TextStyle(
                                                              fontSize: 12,
                                                              fontWeight:
                                                                  FontWeight
                                                                      .w600),
                                                          maxLines: MediaQuery.textScalerOf(
                                                                          context)
                                                                      .scale(
                                                                          12) >
                                                                  18
                                                              ? null
                                                              : 2,
                                                          overflow: MediaQuery.textScalerOf(
                                                                          context)
                                                                      .scale(
                                                                          12) >
                                                                  18
                                                              ? TextOverflow
                                                                  .visible
                                                              : TextOverflow
                                                                  .ellipsis)),
                                                  if (widget.appearance
                                                          .templateId ==
                                                      template.id)
                                                    Icon(Icons.check_circle,
                                                        color: colors.primary,
                                                        size: 17),
                                                ]),
                                              ])))))))
                  ]))),
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
                storeName: const {'dimensional', 'cartoon', 'premium'}
                        .contains(template.category)
                    ? ''
                    : 'noikub',
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
                        height: constraints.maxWidth * 1.45,
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
