import 'dart:typed_data';

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';

import '../../core/models/link_in_bio_appearance.dart';
import 'link_in_bio_draft_store.dart';
import 'link_in_bio_color_picker.dart';
import 'link_in_bio_localizations.dart';
import 'link_in_bio_preview.dart';
import 'link_in_bio_theme_picker.dart';
import 'link_in_bio_ui_motion.dart';
export 'link_in_bio_theme_picker.dart';

const bioFontOptions = {
  'anuphan': 'Anuphan • ตัวอย่างภาษาไทย',
  'prompt': 'Prompt • ตัวอย่างภาษาไทย',
  'system': 'ระบบ • ตัวอย่างภาษาไทย'
};
bool validBioColor(String value) =>
    RegExp(r'^#[0-9a-fA-F]{6}$').hasMatch(value);

class BioColorField extends StatefulWidget {
  const BioColorField(
      {super.key,
      required this.label,
      required this.value,
      required this.onChanged,
      this.allowEmpty = false});
  final String label;
  final String? value;
  final ValueChanged<String?> onChanged;
  final bool allowEmpty;
  @override
  State<BioColorField> createState() => _BioColorFieldState();
}

class _BioColorFieldState extends State<BioColorField> {
  late final _controller = TextEditingController(text: widget.value ?? '');
  @override
  void didUpdateWidget(covariant BioColorField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value &&
        _controller.text.toLowerCase() != widget.value) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _controller.text.toLowerCase() != widget.value) {
          _controller.text = widget.value ?? '';
          setState(() {});
        }
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _pickColor() async {
    final value = await selectBioColor(
        context,
        validBioColor(_controller.text)
            ? bioColor(_controller.text)
            : Colors.blue);
    if (!mounted || value == null) return;
    _controller.text = value;
    widget.onChanged(value);
    setState(() {});
  }

  @override
  Widget build(BuildContext context) => TextFormField(
      controller: _controller,
      maxLength: 7,
      autocorrect: false,
      decoration: InputDecoration(
          labelText: MediaQuery.textScalerOf(context).scale(14) > 18
              ? null : localizeLinkInBioMessage(context, widget.label),
          label: MediaQuery.textScalerOf(context).scale(14) > 18
              ? Text(localizeLinkInBioMessage(context, widget.label), softWrap: true) : null,
          hintText: '#123456',
          counterText: '',
          suffixIcon: BioUiPress(
              child: IconButton(
                  key: ValueKey(
                      '${(widget.key as ValueKey?)?.value ?? widget.label}-picker'),
                  tooltip: linkInBioText(context, 'เลือกสี${widget.label}',
                      'Choose ${localizeLinkInBioMessage(context, widget.label).toLowerCase()}'),
                  onPressed: _pickColor,
                  icon: const Icon(Icons.color_lens_outlined))),
          prefixIcon: Padding(
              padding: const EdgeInsets.all(13),
              child: Container(
                  width: 20,
                  height: 20,
                  decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey),
                      borderRadius: BorderRadius.circular(4),
                      color: validBioColor(_controller.text)
                          ? bioColor(_controller.text)
                          : Colors.transparent)))),
      autovalidateMode: AutovalidateMode.onUserInteraction,
      validator: (value) => (widget.allowEmpty && (value ?? '').isEmpty) ||
              validBioColor(value ?? '')
          ? null
          : linkInBioText(context, 'กรอกสีแบบ #RRGGBB', 'Enter a color as #RRGGBB'),
      onChanged: (value) {
        setState(() {});
        if (widget.allowEmpty && value.isEmpty) {
          widget.onChanged(null);
        } else if (validBioColor(value)) {
          widget.onChanged(value.toLowerCase());
        }
      });
}

class BioFontField extends StatelessWidget {
  const BioFontField(
      {super.key,
      required this.label,
      required this.value,
      required this.onChanged,
      this.allowDefault = false});
  final String label;
  final String? value;
  final ValueChanged<String?> onChanged;
  final bool allowDefault;
  @override
  Widget build(BuildContext context) => DropdownButtonFormField<String>(
      key: ValueKey('$label:$value'),
      initialValue: value ?? (allowDefault ? '' : 'anuphan'),
      isExpanded: true,
      isDense: MediaQuery.textScalerOf(context).scale(14) <= 18,
      itemHeight: MediaQuery.textScalerOf(context).scale(14) > 18 ? null : kMinInteractiveDimension,
      decoration: InputDecoration(
          labelText: MediaQuery.textScalerOf(context).scale(14) > 18
              ? null : localizeLinkInBioMessage(context, label),
          label: MediaQuery.textScalerOf(context).scale(14) > 18
              ? Text(localizeLinkInBioMessage(context, label), softWrap: true) : null),
      items: [
        if (allowDefault)
          DropdownMenuItem(value: '', child: Text(linkInBioText(context,
              'ใช้ฟอนต์ของธีม', 'Use theme font'))),
        for (final option in bioFontOptions.entries)
          DropdownMenuItem(
              value: option.key,
              child: Text(linkInBioText(context, option.value, switch (option.key) {
                'anuphan' => 'Anuphan • Sample text',
                'prompt' => 'Prompt • Sample text',
                _ => 'System • Sample text',
              }),
                  overflow: MediaQuery.textScalerOf(context).scale(14) > 18 ? TextOverflow.visible : TextOverflow.ellipsis,
                  style:
                      TextStyle(fontFamily: bioFont(option.key), fontSize: 13)))
      ],
      onChanged: (value) => onChanged(value == '' ? null : value));
}

typedef BioImageUpload = Future<String?> Function(String slot);

class LinkInBioAppearanceEditor extends StatefulWidget {
  const LinkInBioAppearanceEditor(
      {super.key,
      required this.appearance,
      required this.storeName,
      required this.slug,
      required this.links,
      required this.images,
      required this.uploadImage,
      this.imageRevision,
      this.showThemePicker = true});
  final LinkInBioAppearance appearance;
  final String storeName;
  final String slug;
  final List<LinkInBioCustomLink> links;
  final Map<String, Uint8List> images;
  final BioImageUpload uploadImage;
  final ValueListenable<int>? imageRevision;
  final bool showThemePicker;
  @override
  State<LinkInBioAppearanceEditor> createState() =>
      _LinkInBioAppearanceEditorState();
}

class _LinkInBioAppearanceEditorState extends State<LinkInBioAppearanceEditor> {
  final _form = GlobalKey<FormState>();
  final _scroll = ScrollController();
  final _disclosures = {
    for (final id in [
      'advanced',
      'images',
      'buttons',
      'styles',
      'featured',
      'style-name',
      'style-description',
      'style-category',
      'style-button',
      'style-brand',
      'effects'
    ])
      id: ExpansibleController(),
  };
  late LinkInBioAppearance _value = widget.appearance;
  late final _description = TextEditingController(text: _value.description);
  late final _featuredLabel = TextEditingController(text: _value.featuredLabel);
  bool _uploading = false;
  String? _error;
  @override
  void dispose() {
    _description.dispose();
    _featuredLabel.dispose();
    _scroll.dispose();
    for (final controller in _disclosures.values) {
      controller.dispose();
    }
    super.dispose();
  }

  void _change(LinkInBioAppearance value) => setState(() => _value = value);

  Widget _preview() {
    Widget preview() => LinkInBioPreview(
        storeName: widget.storeName,
        slug: widget.slug,
        links: widget.links,
        appearance: _value,
        images: widget.images);
    final revision = widget.imageRevision;
    final content = revision == null
        ? preview()
        : ValueListenableBuilder<int>(
            valueListenable: revision, builder: (_, value, child) => preview());
    return BioPreviewViewport(
        key: const ValueKey('link-in-bio-decoration-preview'),
        height: widget.showThemePicker ? 200 : 120,
        appearance: _value,
        child: content);
  }

  Future<void> _upload(String slot) async {
    if (_uploading) return;
    setState(() {
      _uploading = true;
      _error = null;
    });
    try {
      final key = await widget.uploadImage(slot);
      if (!mounted || key == null) return;
      _change(switch (slot) {
        'logo' => _value.copyWith(logoKey: key),
        'cover' => _value.copyWith(coverKey: key),
        _ => _value.copyWith(
            background:
                _value.background.copyWith(imageKey: key, mode: 'image')),
      });
    } catch (error) {
      if (mounted) {
        setState(() => _error = error is FormatException
            ? error.message
            : 'อัปโหลดรูปไม่สำเร็จ กรุณาลองใหม่ รูปเดิมยังอยู่');
      }
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Widget _section(String id, String title, List<Widget> children,
          {IconData? icon}) =>
      ExpansionTile(
          key: ValueKey('link-in-bio-disclosure-$id'),
          controller: _disclosures[id],
          maintainState: true,
          tilePadding: const EdgeInsets.symmetric(horizontal: 4),
          childrenPadding: const EdgeInsets.fromLTRB(4, 4, 4, 16),
          shape: const Border(),
          collapsedShape: const Border(),
          leading: icon == null ? null : Icon(icon, size: 21),
          title: Text(title,
              key: ValueKey(id.startsWith('style-')
                  ? 'link-in-bio-$id'
                  : 'link-in-bio-decoration-$id'),
              style:
                  const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
          children: [
            Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: children)
          ]);

  Widget _style(String id, String label, LinkInBioTextStyle value,
          ValueChanged<LinkInBioTextStyle> onChanged) {
    final translatedLabel = linkInBioText(context, label, switch (id) {
      'name' => 'Store name',
      'description' => 'Store description',
      'category' => 'Category heading',
      'button' => 'Button text',
      _ => 'Footer text',
    });
    return _section('style-$id', translatedLabel, [
        BioColorField(
            key: ValueKey('link-in-bio-$id-color'),
            label: linkInBioText(context, 'สี$label', '$translatedLabel color'),
            value: value.color,
            onChanged: (color) => onChanged(value.copyWith(color: color!))),
        const SizedBox(height: 8),
        BioFontField(
            key: ValueKey('link-in-bio-$id-font'),
            label: linkInBioText(context, 'ฟอนต์$label', '$translatedLabel font'),
            value: value.font,
            onChanged: (font) => onChanged(value.copyWith(font: font!))),
      ]);
  }

  Widget _media(String slot, String label, String? key, VoidCallback remove) {
    final englishLabel = switch (slot) {
      'logo' => 'logo',
      'cover' => 'cover image',
      _ => 'background image',
    };
    return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Wrap(spacing: 8, children: [
            BioUiPress(
                enabled: !_uploading,
                child: OutlinedButton.icon(
                    key: ValueKey('link-in-bio-image-$slot'),
                    onPressed: _uploading ? null : () => _upload(slot),
                    icon: const Icon(Icons.photo_library_outlined),
                    label:
                        Text(linkInBioText(context,
                            key == null ? 'เพิ่ม$label' : 'เปลี่ยน$label',
                            '${key == null ? 'Add' : 'Change'} $englishLabel')))),
            if (key != null)
              BioUiPress(
                  enabled: !_uploading,
                  child: TextButton(
                      onPressed: _uploading ? null : remove,
                      child: Text(linkInBioText(context, 'ลบ$label', 'Remove $englishLabel'))))
          ]));
  }

  Widget _effects() => _section(
      'effects',
      linkInBioText(context, 'ลูกเล่น', 'Effects'),
      [
        SwitchListTile.adaptive(
            key: const ValueKey('link-in-bio-effect-background'),
            contentPadding: EdgeInsets.zero,
            title: Text(linkInBioText(context, 'พื้นหลังเคลื่อนไหว', 'Animated background')),
            value: _value.effects.background,
            onChanged: (value) => _change(_value.copyWith(
                effects: _value.effects.copyWith(background: value)))),
        SwitchListTile.adaptive(
            key: const ValueKey('link-in-bio-effect-entrance'),
            contentPadding: EdgeInsets.zero,
            title: Text(linkInBioText(context, 'ลิงก์ค่อย ๆ ปรากฏ', 'Fade in links')),
            value: _value.effects.entrance,
            onChanged: (value) => _change(_value.copyWith(
                effects: _value.effects.copyWith(entrance: value)))),
        SwitchListTile.adaptive(
            key: const ValueKey('link-in-bio-effect-featured'),
            contentPadding: EdgeInsets.zero,
            title: Text(linkInBioText(context, 'ปุ่มเด่นขยับเบา ๆ', 'Gently animate the featured button')),
            value: _value.effects.featured,
            onChanged: (value) => _change(_value.copyWith(
                effects: _value.effects.copyWith(featured: value)))),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
            key: ValueKey(
                'link-in-bio-effect-stickers-${_value.effects.stickers}'),
            initialValue: _value.effects.stickers,
            isExpanded: true,
            decoration: InputDecoration(labelText: linkInBioText(context, 'สติกเกอร์ลอย', 'Floating stickers')),
            items: [
              DropdownMenuItem(value: 'none', child: Text(linkInBioText(context, 'ไม่มี', 'None'))),
              DropdownMenuItem(value: 'hearts', child: Text(linkInBioText(context, 'หัวใจ', 'Hearts'))),
              DropdownMenuItem(value: 'flowers', child: Text(linkInBioText(context, 'ดอกไม้', 'Flowers'))),
              DropdownMenuItem(value: 'sparkles', child: Text(linkInBioText(context, 'ประกาย', 'Sparkles'))),
            ],
            onChanged: (value) => _change(_value.copyWith(
                effects: _value.effects.copyWith(stickers: value!)))),
        const SizedBox(height: 12),
        Text(linkInBioText(context, 'ดูการเคลื่อนไหวในตัวอย่างด้านบน และเปิด–ปิดแต่ละลูกเล่นได้',
            'Preview animations above and turn each effect on or off.'),
            style: const TextStyle(fontSize: 12)),
      ],
      icon: Icons.auto_awesome_outlined);

  List<Widget> _advancedGroups() => [
        _section(
            'images',
            linkInBioText(context, 'ภาพและพื้นหลัง', 'Images and background'),
            [
              TextFormField(
                  key: const ValueKey('link-in-bio-description'),
                  controller: _description,
                  maxLength: 280,
                  minLines: 2,
                  maxLines: 4,
                  decoration: InputDecoration(labelText: linkInBioText(context, 'คำแนะนำร้าน', 'Store description')),
                  autovalidateMode: AutovalidateMode.onUserInteraction,
                  validator: (value) => (value ?? '').length > 280
                      ? linkInBioText(context, 'คำแนะนำร้านยาวเกิน 280 ตัวอักษร', 'Your store description must be no longer than 280 characters.')
                      : null,
                  onChanged: (value) {
                    if (value.length <= 280) {
                      _change(_value.copyWith(description: value));
                    }
                  }),
              const SizedBox(height: 8),
              _media('logo', 'โลโก้', _value.logoKey,
                  () => _change(_value.copyWith(logoKey: null))),
              _media('cover', 'ภาพปก', _value.coverKey,
                  () => _change(_value.copyWith(coverKey: null))),
              _media(
                  'background',
                  'ภาพพื้นหลัง',
                  _value.background.imageKey,
                  () => _change(_value.copyWith(
                      background: _value.background
                          .copyWith(imageKey: null, mode: 'solid')))),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                  key: ValueKey(
                      'link-in-bio-background-mode-${_value.background.mode}'),
                  initialValue: _value.background.mode,
                  isExpanded: true,
                  decoration:
                      InputDecoration(labelText: linkInBioText(context, 'รูปแบบพื้นหลัง', 'Background style')),
                  items: [
                    DropdownMenuItem(value: 'solid', child: Text(linkInBioText(context, 'สีเดียว', 'Solid color'))),
                    DropdownMenuItem(value: 'gradient', child: Text(linkInBioText(context, 'ไล่สี', 'Gradient'))),
                    DropdownMenuItem(
                        value: 'image', child: Text(linkInBioText(context, 'รูปภาพพร้อมปรับความมืด', 'Image with dimming')))
                  ],
                  onChanged: (mode) => _change(_value.copyWith(
                      background: _value.background.copyWith(mode: mode!)))),
              const SizedBox(height: 10),
              BioColorField(
                  key: const ValueKey('link-in-bio-background-color'),
                  label: linkInBioText(context, 'สีพื้นหลัง', 'Background color'),
                  value: _value.background.color,
                  onChanged: (color) => _change(_value.copyWith(
                      background: _value.background.copyWith(color: color!)))),
              if (_value.background.mode == 'gradient') ...[
                const SizedBox(height: 10),
                BioColorField(
                    key: const ValueKey('link-in-bio-gradient-color'),
                    label: linkInBioText(context, 'สีปลายทาง', 'Gradient end color'),
                    value: _value.background.gradientColor,
                    onChanged: (color) => _change(_value.copyWith(
                        background: _value.background
                            .copyWith(gradientColor: color!)))),
              ],
              if (_value.background.mode == 'image') ...[
                const SizedBox(height: 10),
                if (_value.background.imageKey == null)
                  Text(linkInBioText(context, 'เพิ่มภาพพื้นหลังก่อนเผยแพร่', 'Add a background image before publishing')),
                Text(linkInBioText(context, 'ความมืดของพื้นหลัง ${_value.background.overlay}%',
                    'Background dimming ${_value.background.overlay}%')),
                Slider(
                    min: 0,
                    max: 80,
                    divisions: 80,
                    value: _value.background.overlay.toDouble(),
                    onChanged: (value) => _change(_value.copyWith(
                        background: _value.background
                            .copyWith(overlay: value.round()))))
              ],
            ],
            icon: Icons.image_outlined),
        _section(
            'buttons',
            linkInBioText(context, 'สีและรูปทรงปุ่ม', 'Button colors and shape'),
            [
              BioColorField(
                  key: const ValueKey('link-in-bio-surface-color'),
                  label: linkInBioText(context, 'สีพื้นที่เนื้อหา', 'Content area color'),
                  value: _value.surfaceColor,
                  onChanged: (color) =>
                      _change(_value.copyWith(surfaceColor: color!))),
              const SizedBox(height: 10),
              BioColorField(
                  key: const ValueKey('link-in-bio-button-color'),
                  label: linkInBioText(context, 'สีพื้นปุ่ม', 'Button background color'),
                  value: _value.buttonColor,
                  onChanged: (color) =>
                      _change(_value.copyWith(buttonColor: color!))),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                  key: ValueKey('link-in-bio-radius-${_value.buttonRadius}'),
                  initialValue: _value.buttonRadius,
                  isExpanded: true,
                  decoration: InputDecoration(labelText: linkInBioText(context, 'รูปทรงปุ่ม', 'Button shape')),
                  items: [
                    DropdownMenuItem(value: 'rounded', child: Text(linkInBioText(context, 'มุมมน', 'Rounded'))),
                    DropdownMenuItem(value: 'pill', child: Text(linkInBioText(context, 'โค้งเต็ม', 'Pill'))),
                    DropdownMenuItem(
                        value: 'square', child: Text(linkInBioText(context, 'มุมเหลี่ยม', 'Square'))),
                  ],
                  onChanged: (value) =>
                      _change(_value.copyWith(buttonRadius: value!))),
            ],
            icon: Icons.palette_outlined),
        _section(
            'styles',
            linkInBioText(context, 'สีและฟอนต์รายส่วน', 'Section colors and fonts'),
            [
              _style('name', 'ชื่อร้าน', _value.nameStyle,
                  (style) => _change(_value.copyWith(nameStyle: style))),
              _style('description', 'คำแนะนำร้าน', _value.descriptionStyle,
                  (style) => _change(_value.copyWith(descriptionStyle: style))),
              _style('category', 'หัวข้อหมวดหมู่', _value.categoryStyle,
                  (style) => _change(_value.copyWith(categoryStyle: style))),
              _style('button', 'ข้อความปุ่ม', _value.buttonStyle,
                  (style) => _change(_value.copyWith(buttonStyle: style))),
              _style('brand', 'ข้อความท้ายหน้า', _value.brandStyle,
                  (style) => _change(_value.copyWith(brandStyle: style))),
            ],
            icon: Icons.text_fields),
        _section(
            'featured',
            linkInBioText(context, 'โปรโมชันเด่น', 'Featured promotion'),
            [
              TextFormField(
                  key: const ValueKey('link-in-bio-featured-label'),
                  controller: _featuredLabel,
                  maxLength: 40,
                  decoration:
                      InputDecoration(
                          labelText: MediaQuery.textScalerOf(context).scale(14) > 18
                              ? null : linkInBioText(context, 'หัวข้อโปรโมชันเด่น', 'Featured promotion heading'),
                          label: MediaQuery.textScalerOf(context).scale(14) > 18
                              ? Text(linkInBioText(context, 'หัวข้อโปรโมชันเด่น', 'Featured promotion heading'), softWrap: true) : null),
                  autovalidateMode: AutovalidateMode.onUserInteraction,
                  validator: (value) => (value ?? '').length > 40
                      ? linkInBioText(context, 'หัวข้อโปรโมชันยาวเกิน 40 ตัวอักษร', 'Your promotion heading must be no longer than 40 characters.')
                      : null,
                  onChanged: (value) {
                    if (value.length <= 40) {
                      _change(_value.copyWith(featuredLabel: value));
                    }
                  }),
              Text(linkInBioText(context, 'เลือกลิงก์เด่นได้จากเมนูของลิงก์', 'Choose a featured link from its link menu')),
            ],
            icon: Icons.star_border),
      ];

  void _apply() {
    final invalid = _form.currentState!.validateGranularly();
    if (invalid.isNotEmpty) {
      for (final field in invalid) {
        field.context.visitAncestorElements((element) {
          final ancestor = element.widget;
          if (ancestor is ExpansionTile) ancestor.controller?.expand();
          return true;
        });
      }
      return;
    }
    Navigator.pop(context, _value);
  }

  @override
  Widget build(BuildContext context) =>
      BioUiMotionScope(child: Builder(builder: _buildEditor));

  Widget _buildEditor(BuildContext context) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
          child: SizedBox(
              height: (MediaQuery.sizeOf(context).height -
                      MediaQuery.viewInsetsOf(context).bottom)
                  .clamp(0.0, MediaQuery.sizeOf(context).height * .9)
                  .toDouble(),
              child: Material(
                  color: Theme.of(context).colorScheme.surface,
                  borderRadius:
                      const BorderRadius.vertical(top: Radius.circular(22)),
                  child: Column(children: [
                    Padding(
                        padding: const EdgeInsets.fromLTRB(16, 12, 12, 4),
                        child: Row(children: [
                          Expanded(
                              child: Text(
                                  widget.showThemePicker
                                      ? linkInBioText(context, 'ตกแต่งหน้าโปรไฟล์', 'Customize profile page')
                                      : linkInBioText(context, 'ตกแต่งเพิ่มเติม', 'More customization'),
                                  style: const TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.w700))),
                          BioUiPress(
                              enabled: !_uploading,
                              child: IconButton(
                                  tooltip: linkInBioText(context, 'ปิด', 'Close'),
                                  onPressed: _uploading
                                      ? null
                                      : () => Navigator.pop(context),
                                  icon: const Icon(Icons.close)))
                        ])),
                    Expanded(
                        child: Form(
                            key: _form,
                            child: SingleChildScrollView(
                                key: const ValueKey(
                                    'link-in-bio-decoration-scroll'),
                                controller: _scroll,
                                padding: const EdgeInsets.all(16),
                                child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      _preview(),
                                      const SizedBox(height: 16),
                                      if (widget.showThemePicker) ...[
                                        Text(linkInBioText(context, 'เลือกธีมเริ่มต้น', 'Choose a starting theme'),
                                            style: const TextStyle(
                                                fontWeight: FontWeight.w700)),
                                        const SizedBox(height: 10),
                                        BioThemePicker(
                                            appearance: _value,
                                            storeName: widget.storeName,
                                            slug: widget.slug,
                                            links: widget.links,
                                            images: widget.images,
                                            imageRevision: widget.imageRevision,
                                            enabled: !_uploading,
                                            onChanged: _change),
                                        const SizedBox(height: 8),
                                        Text(linkInBioText(context,
                                            'เปลี่ยนธีมจะตั้งสีและฟอนต์ใหม่ ข้อความ รูป และลิงก์เดิมยังอยู่',
                                            'Changing the theme resets colors and fonts. Your text, images and links are kept.'),
                                            style: const TextStyle(fontSize: 12)),
                                        const SizedBox(height: 8),
                                        _effects(),
                                        _section('advanced', linkInBioText(context, 'ตกแต่งเพิ่มเติม', 'More customization'),
                                            _advancedGroups()),
                                      ] else ...[
                                        _effects(),
                                        ..._advancedGroups(),
                                      ],
                                    ])))),
                    if (_uploading)
                      const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 16),
                          child: LinearProgressIndicator()),
                    if (_error != null)
                      Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: Text(localizeLinkInBioMessage(context, _error!),
                              style: TextStyle(
                                  color: Theme.of(context).colorScheme.error))),
                    Padding(
                        padding: const EdgeInsets.all(16),
                        child: SizedBox(
                            width: double.infinity,
                            child: BioUiPress(
                                enabled: !_uploading,
                                child: FilledButton(
                                    key: const ValueKey(
                                        'link-in-bio-decoration-done'),
                                    onPressed: _uploading ? null : _apply,
                                    child:
                                        Text(linkInBioText(context, 'ใช้แบบนี้กับแบบร่าง', 'Apply to draft')))))),
                  ])))));
}
