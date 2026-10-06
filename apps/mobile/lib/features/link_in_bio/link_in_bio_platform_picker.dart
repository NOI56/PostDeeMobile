import 'package:flutter/material.dart';

import '../../core/models/profile_platform_catalog.generated.dart';
import 'link_in_bio_platform_logo.dart';

const _genericNames = {
  'auto': 'เลือกจากลิงก์อัตโนมัติ',
  'link': 'ลิงก์',
  'website': 'เว็บไซต์',
  'email': 'อีเมล',
  'phone': 'โทรศัพท์',
};

String bioPlatformLabel(String id) =>
    profilePlatformNames[id] ?? _genericNames[id] ?? _genericNames['auto']!;

Future<String?> showBioPlatformPicker(BuildContext context, String selected) =>
    showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) {
        final media = MediaQuery.of(context);
        return Padding(
          padding: EdgeInsets.only(bottom: media.viewInsets.bottom),
          child: SizedBox(
            height: (media.size.height * .8)
                .clamp(
                    0.0,
                    (media.size.height - media.viewInsets.bottom - 48)
                        .clamp(0.0, media.size.height))
                .toDouble(),
            child: BioPlatformPicker(
                selected: selected,
                onSelected: (id) => Navigator.pop(context, id)),
          ),
        );
      },
    );

class BioPlatformPicker extends StatefulWidget {
  const BioPlatformPicker({
    super.key,
    required this.selected,
    required this.onSelected,
  });

  final String selected;
  final ValueChanged<String> onSelected;

  @override
  State<BioPlatformPicker> createState() => _BioPlatformPickerState();
}

class _BioPlatformPickerState extends State<BioPlatformPicker> {
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final words = _search.text.trim().toLowerCase().split(RegExp(r'\s+'));
    bool matches(String value) =>
        words.every((word) => value.toLowerCase().contains(word));
    final generic = _genericNames.entries
        .where((entry) => matches('${entry.key} ${entry.value}'))
        .toList();
    final brands = profilePlatformCatalog
        .where((platform) => matches([
              platform.name,
              platform.id,
              ...platform.aliases,
              ...platform.regions,
              ...platform.domains,
            ].join(' ')))
        .toList();
    Widget option(String id, String name, {String? subtitle}) => ListTile(
          key: ValueKey('bio-platform-option-$id'),
          leading: BioPlatformLogo(
              icon: id, fallbackColor: Theme.of(context).hintColor),
          title: Text(name),
          subtitle: subtitle == null ? null : Text(subtitle),
          trailing: widget.selected == id
              ? Icon(Icons.check, color: Theme.of(context).colorScheme.primary)
              : null,
          selected: widget.selected == id,
          onTap: () => widget.onSelected(id),
        );
    return Material(
      color: Theme.of(context).colorScheme.surface,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
      child: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 6, 0),
          child: Row(children: [
            const Expanded(
                child: Text('เลือกโลโก้',
                    style:
                        TextStyle(fontSize: 18, fontWeight: FontWeight.w700))),
            IconButton(
                tooltip: 'ปิด',
                onPressed: () => Navigator.maybePop(context),
                icon: const Icon(Icons.close)),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: TextField(
            key: const ValueKey('bio-platform-search'),
            controller: _search,
            onChanged: (_) => setState(() {}),
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              hintText: 'ค้นหาชื่อแอปหรือประเทศ',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _search.text.isEmpty
                  ? null
                  : IconButton(
                      key: const ValueKey('bio-platform-search-clear'),
                      tooltip: 'ล้างคำค้น',
                      onPressed: () => setState(_search.clear),
                      icon: const Icon(Icons.close)),
            ),
          ),
        ),
        Expanded(
          child: generic.isEmpty && brands.isEmpty
              ? const Center(child: Text('ไม่พบโลโก้ที่ตรงกับคำค้น'))
              : ListView.builder(
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  itemCount: generic.length + brands.length,
                  itemBuilder: (context, index) {
                    if (index < generic.length) {
                      final item = generic[index];
                      return option(item.key, item.value);
                    }
                    final item = brands[index - generic.length];
                    return option(item.id, item.name);
                  }),
        ),
      ]),
    );
  }
}
