import 'package:flutter/material.dart';

String bioColorHex(Color color) =>
    '#${color.toARGB32().toRadixString(16).padLeft(8, '0').substring(2)}';

Future<String?> selectBioColor(BuildContext context, Color initial) async {
  final color = await showDialog<Color>(
      context: context, builder: (_) => _BioColorPicker(initial: initial));
  return color == null ? null : bioColorHex(color);
}

class _BioColorPicker extends StatefulWidget {
  const _BioColorPicker({required this.initial});
  final Color initial;
  @override
  State<_BioColorPicker> createState() => _BioColorPickerState();
}

class _BioColorPickerState extends State<_BioColorPicker> {
  late HSVColor _value = HSVColor.fromColor(widget.initial);
  Widget _slider(String key, String label, double value, double maximum,
          ValueChanged<double> onChanged) =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label),
        Slider(
            key: ValueKey(key),
            min: 0,
            max: maximum,
            value: value,
            onChanged: onChanged,
            activeColor: _value.toColor())
      ]);
  @override
  Widget build(BuildContext context) => AlertDialog(
          title: const Text('เลือกสี'),
          content: SizedBox(
              width: 320,
              child: SingleChildScrollView(
                  child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    Container(
                        height: 52,
                        width: double.infinity,
                        decoration: BoxDecoration(
                            color: _value.toColor(),
                            border: Border.all(color: Colors.grey),
                            borderRadius: BorderRadius.circular(10))),
                    const SizedBox(height: 8),
                    Text(bioColorHex(_value.toColor())),
                    const SizedBox(height: 12),
                    Wrap(spacing: 8, runSpacing: 8, children: [
                      for (final hex in const [
                        'ffffff',
                        '111827',
                        '305d36',
                        'e85d24',
                        '8b5fbf',
                        '34d399',
                        'ef4444',
                        'f59e0b',
                        '3b82f6',
                        'ec4899',
                        '06b6d4',
                        '687065'
                      ])
                        Semantics(
                            label: 'สี #$hex',
                            button: true,
                            child: InkWell(
                                key: ValueKey('link-in-bio-color-swatch-$hex'),
                                borderRadius: BorderRadius.circular(8),
                                onTap: () => setState(() => _value =
                                    HSVColor.fromColor(
                                        Color(int.parse('ff$hex', radix: 16)))),
                                child: Container(
                                    width: 32,
                                    height: 32,
                                    decoration: BoxDecoration(
                                        color: Color(
                                            int.parse('ff$hex', radix: 16)),
                                        border: Border.all(color: Colors.grey),
                                        borderRadius:
                                            BorderRadius.circular(8)))))
                    ]),
                    const SizedBox(height: 18),
                    _slider(
                        'link-in-bio-color-hue',
                        'เฉดสี',
                        _value.hue,
                        360,
                        (value) =>
                            setState(() => _value = _value.withHue(value))),
                    _slider(
                        'link-in-bio-color-saturation',
                        'ความสดของสี',
                        _value.saturation,
                        1,
                        (value) => setState(
                            () => _value = _value.withSaturation(value))),
                    _slider(
                        'link-in-bio-color-brightness',
                        'ความสว่าง',
                        _value.value,
                        1,
                        (value) =>
                            setState(() => _value = _value.withValue(value))),
                  ]))),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('ยกเลิก')),
            FilledButton(
                key: const ValueKey('link-in-bio-color-confirm'),
                onPressed: () => Navigator.pop(context, _value.toColor()),
                child: const Text('ใช้สีนี้'))
          ]);
}
