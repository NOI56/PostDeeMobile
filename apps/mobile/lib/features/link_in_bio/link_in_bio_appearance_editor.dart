import 'dart:typed_data';

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';

import '../../core/models/link_in_bio_appearance.dart';
import 'link_in_bio_draft_store.dart';
import 'link_in_bio_color_picker.dart';
import 'link_in_bio_preview.dart';
import 'link_in_bio_theme_picker.dart';
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
          labelText: widget.label,
          hintText: '#123456',
          counterText: '',
          suffixIcon: IconButton(
              key: ValueKey(
                  '${(widget.key as ValueKey?)?.value ?? widget.label}-picker'),
              tooltip: 'เลือกสี${widget.label}',
              onPressed: _pickColor,
              icon: const Icon(Icons.color_lens_outlined)),
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
          : 'กรอกสีแบบ #RRGGBB',
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
      decoration: InputDecoration(labelText: label),
      items: [
        if (allowDefault)
          const DropdownMenuItem(value: '', child: Text('ใช้ฟอนต์ของธีม')),
        for (final option in bioFontOptions.entries)
          DropdownMenuItem(
              value: option.key,
              child: Text(option.value,
                  overflow: TextOverflow.ellipsis,
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
          ValueChanged<LinkInBioTextStyle> onChanged) =>
      _section('style-$id', label, [
        BioColorField(
            key: ValueKey('link-in-bio-$id-color'),
            label: 'สี$label',
            value: value.color,
            onChanged: (color) => onChanged(value.copyWith(color: color!))),
        const SizedBox(height: 8),
        BioFontField(
            key: ValueKey('link-in-bio-$id-font'),
            label: 'ฟอนต์$label',
            value: value.font,
            onChanged: (font) => onChanged(value.copyWith(font: font!))),
      ]);

  Widget _media(String slot, String label, String? key, VoidCallback remove) =>
      Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Wrap(spacing: 8, children: [
            OutlinedButton.icon(
                key: ValueKey('link-in-bio-image-$slot'),
                onPressed: _uploading ? null : () => _upload(slot),
                icon: const Icon(Icons.photo_library_outlined),
                label: Text(key == null ? 'เพิ่ม$label' : 'เปลี่ยน$label')),
            if (key != null)
              TextButton(
                  onPressed: _uploading ? null : remove,
                  child: Text('ลบ$label'))
          ]));

  Widget _effects() => _section(
      'effects',
      'ลูกเล่น',
      [
        SwitchListTile.adaptive(
            key: const ValueKey('link-in-bio-effect-background'),
            contentPadding: EdgeInsets.zero,
            title: const Text('พื้นหลังเคลื่อนไหว'),
            value: _value.effects.background,
            onChanged: (value) => _change(_value.copyWith(
                effects: _value.effects.copyWith(background: value)))),
        SwitchListTile.adaptive(
            key: const ValueKey('link-in-bio-effect-entrance'),
            contentPadding: EdgeInsets.zero,
            title: const Text('ลิงก์ค่อย ๆ ปรากฏ'),
            value: _value.effects.entrance,
            onChanged: (value) => _change(_value.copyWith(
                effects: _value.effects.copyWith(entrance: value)))),
        SwitchListTile.adaptive(
            key: const ValueKey('link-in-bio-effect-featured'),
            contentPadding: EdgeInsets.zero,
            title: const Text('ปุ่มเด่นขยับเบา ๆ'),
            value: _value.effects.featured,
            onChanged: (value) => _change(_value.copyWith(
                effects: _value.effects.copyWith(featured: value)))),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
            key: ValueKey(
                'link-in-bio-effect-stickers-${_value.effects.stickers}'),
            initialValue: _value.effects.stickers,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'สติกเกอร์ลอย'),
            items: const [
              DropdownMenuItem(value: 'none', child: Text('ไม่มี')),
              DropdownMenuItem(value: 'hearts', child: Text('หัวใจ')),
              DropdownMenuItem(value: 'flowers', child: Text('ดอกไม้')),
              DropdownMenuItem(value: 'sparkles', child: Text('ประกาย')),
            ],
            onChanged: (value) => _change(_value.copyWith(
                effects: _value.effects.copyWith(stickers: value!)))),
        const SizedBox(height: 12),
        const Text('ดูการเคลื่อนไหวในตัวอย่างด้านบน และเปิด–ปิดแต่ละลูกเล่นได้',
            style: TextStyle(fontSize: 12)),
      ],
      icon: Icons.auto_awesome_outlined);

  List<Widget> _advancedGroups() => [
        _section(
            'images',
            'ภาพและพื้นหลัง',
            [
              TextFormField(
                  key: const ValueKey('link-in-bio-description'),
                  controller: _description,
                  maxLength: 280,
                  minLines: 2,
                  maxLines: 4,
                  decoration: const InputDecoration(labelText: 'คำแนะนำร้าน'),
                  autovalidateMode: AutovalidateMode.onUserInteraction,
                  validator: (value) => (value ?? '').length > 280
                      ? 'คำแนะนำร้านยาวเกิน 280 ตัวอักษร'
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
                      const InputDecoration(labelText: 'รูปแบบพื้นหลัง'),
                  items: const [
                    DropdownMenuItem(value: 'solid', child: Text('สีเดียว')),
                    DropdownMenuItem(value: 'gradient', child: Text('ไล่สี')),
                    DropdownMenuItem(
                        value: 'image', child: Text('รูปภาพพร้อมปรับความมืด'))
                  ],
                  onChanged: (mode) => _change(_value.copyWith(
                      background: _value.background.copyWith(mode: mode!)))),
              const SizedBox(height: 10),
              BioColorField(
                  key: const ValueKey('link-in-bio-background-color'),
                  label: 'สีพื้นหลัง',
                  value: _value.background.color,
                  onChanged: (color) => _change(_value.copyWith(
                      background: _value.background.copyWith(color: color!)))),
              if (_value.background.mode == 'gradient') ...[
                const SizedBox(height: 10),
                BioColorField(
                    key: const ValueKey('link-in-bio-gradient-color'),
                    label: 'สีปลายทาง',
                    value: _value.background.gradientColor,
                    onChanged: (color) => _change(_value.copyWith(
                        background: _value.background
                            .copyWith(gradientColor: color!)))),
              ],
              if (_value.background.mode == 'image') ...[
                const SizedBox(height: 10),
                if (_value.background.imageKey == null)
                  const Text('เพิ่มภาพพื้นหลังก่อนเผยแพร่'),
                Text('ความมืดของพื้นหลัง ${_value.background.overlay}%'),
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
            'สีและรูปทรงปุ่ม',
            [
              BioColorField(
                  key: const ValueKey('link-in-bio-surface-color'),
                  label: 'สีพื้นที่เนื้อหา',
                  value: _value.surfaceColor,
                  onChanged: (color) =>
                      _change(_value.copyWith(surfaceColor: color!))),
              const SizedBox(height: 10),
              BioColorField(
                  key: const ValueKey('link-in-bio-button-color'),
                  label: 'สีพื้นปุ่ม',
                  value: _value.buttonColor,
                  onChanged: (color) =>
                      _change(_value.copyWith(buttonColor: color!))),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                  key: ValueKey('link-in-bio-radius-${_value.buttonRadius}'),
                  initialValue: _value.buttonRadius,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'รูปทรงปุ่ม'),
                  items: const [
                    DropdownMenuItem(value: 'rounded', child: Text('มุมมน')),
                    DropdownMenuItem(value: 'pill', child: Text('โค้งเต็ม')),
                    DropdownMenuItem(
                        value: 'square', child: Text('มุมเหลี่ยม')),
                  ],
                  onChanged: (value) =>
                      _change(_value.copyWith(buttonRadius: value!))),
            ],
            icon: Icons.palette_outlined),
        _section(
            'styles',
            'สีและฟอนต์รายส่วน',
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
            'โปรโมชันเด่น',
            [
              TextFormField(
                  key: const ValueKey('link-in-bio-featured-label'),
                  controller: _featuredLabel,
                  maxLength: 40,
                  decoration:
                      const InputDecoration(labelText: 'หัวข้อโปรโมชันเด่น'),
                  autovalidateMode: AutovalidateMode.onUserInteraction,
                  validator: (value) => (value ?? '').length > 40
                      ? 'หัวข้อโปรโมชันยาวเกิน 40 ตัวอักษร'
                      : null,
                  onChanged: (value) {
                    if (value.length <= 40) {
                      _change(_value.copyWith(featuredLabel: value));
                    }
                  }),
              const Text('เลือกลิงก์เด่นได้จากเมนูของลิงก์'),
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
  Widget build(BuildContext context) => Padding(
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
                                      ? 'ตกแต่งหน้าโปรไฟล์'
                                      : 'ตกแต่งเพิ่มเติม',
                                  style: const TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.w700))),
                          IconButton(
                              tooltip: 'ปิด',
                              onPressed: _uploading
                                  ? null
                                  : () => Navigator.pop(context),
                              icon: const Icon(Icons.close))
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
                                        const Text('เลือกธีมเริ่มต้น',
                                            style: TextStyle(
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
                                        const Text(
                                            'เปลี่ยนธีมจะตั้งสีและฟอนต์ใหม่ ข้อความ รูป และลิงก์เดิมยังอยู่',
                                            style: TextStyle(fontSize: 12)),
                                        const SizedBox(height: 8),
                                        _effects(),
                                        _section('advanced', 'ตกแต่งเพิ่มเติม',
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
                          child: Text(_error!,
                              style: TextStyle(
                                  color: Theme.of(context).colorScheme.error))),
                    Padding(
                        padding: const EdgeInsets.all(16),
                        child: SizedBox(
                            width: double.infinity,
                            child: FilledButton(
                                key: const ValueKey(
                                    'link-in-bio-decoration-done'),
                                onPressed: _uploading ? null : _apply,
                                child: const Text('ใช้แบบนี้กับแบบร่าง')))),
                  ])))));
}
