import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import 'style_options.dart';

/// Opens the post-style fine-tuning sheet and returns the chosen options (null
/// if dismissed without applying).
Future<EditStyleOptions?> showStyleOptionsSheet(
  BuildContext context,
  EditStyleOptions current,
) {
  return showModalBottomSheet<EditStyleOptions>(
    context: context,
    backgroundColor: AppTheme.charcoal,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius:
          BorderRadius.vertical(top: Radius.circular(AppTheme.cardRadius)),
    ),
    builder: (context) => _StyleOptionsSheet(current: current),
  );
}

class _StyleOptionsSheet extends StatefulWidget {
  const _StyleOptionsSheet({required this.current});

  final EditStyleOptions current;

  @override
  State<_StyleOptionsSheet> createState() => _StyleOptionsSheetState();
}

class _StyleOptionsSheetState extends State<_StyleOptionsSheet> {
  late int? _targetSeconds = widget.current.targetSeconds;
  late int? _subtitleMaxChars = widget.current.subtitleMaxChars;
  late double? _silenceMinGapSec = widget.current.silenceMinGapSec;
  late double _speed = widget.current.speed ?? 1.0;
  late int _filterIndex = widget.current.filterIndex ?? 0;
  late bool _subtitleAtBottom = widget.current.subtitleAtBottom ?? true;
  late double _subtitleFontSize = widget.current.subtitleFontSize ?? 18;
  late double _brightness = widget.current.brightness ?? 0;
  late double _contrast = widget.current.contrast ?? 0;

  static const _filterLabels = [
    'ปกติ',
    'สดใส',
    'วินเทจ',
    'ขาวดำ',
    'อบอุ่น',
    'เย็น',
  ];

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return SafeArea(
      top: false,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.9,
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(AppTheme.spaceLg, AppTheme.spaceSm,
              AppTheme.spaceLg, AppTheme.spaceLg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppTheme.borderSoft,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: AppTheme.spaceMd),
            Text('ปรับแต่งสไตล์',
                style:
                    textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: AppTheme.spaceLg),
            _section('ความยาวคลิป'),
            _chips<int?>(
              value: _targetSeconds,
              options: const [
                ('ตามต้นฉบับ', null),
                ('15 วิ', 15),
                ('30 วิ', 30),
                ('60 วิ', 60),
              ],
              onSelected: (v) => setState(() => _targetSeconds = v),
            ),
            const SizedBox(height: AppTheme.spaceMd),
            _section('ความยาวซับต่อบรรทัด'),
            Text('นับเป็นตัวอักษร (ภาษาไทยไม่มีเว้นวรรคต่อคำ) · มีผลเมื่อเปิดซับ',
                style:
                    textTheme.bodySmall?.copyWith(color: AppTheme.textMuted)),
            const SizedBox(height: AppTheme.spaceSm),
            _chips<int?>(
              value: _subtitleMaxChars,
              options: const [
                ('ปกติ', null),
                ('สั้น', 16),
                ('กลาง', 24),
                ('ยาว', 36),
              ],
              onSelected: (v) => setState(() => _subtitleMaxChars = v),
            ),
            const SizedBox(height: AppTheme.spaceMd),
            _section('จังหวะตัดเงียบ'),
            _chips<double?>(
              value: _silenceMinGapSec,
              options: const [
                ('ตามสไตล์', null),
                ('เก็บจังหวะ', 1.0),
                ('กลาง', 0.6),
                ('กระชับ', 0.4),
              ],
              onSelected: (v) => setState(() => _silenceMinGapSec = v),
            ),
            const SizedBox(height: AppTheme.spaceMd),
            _section('ความเร็ว'),
            _chips<double>(
              value: _speed,
              options: const [
                ('0.5x', 0.5),
                ('1x', 1.0),
                ('1.5x', 1.5),
                ('2x', 2.0),
              ],
              onSelected: (v) => setState(() => _speed = v),
            ),
            const SizedBox(height: AppTheme.spaceMd),
            _section('โทนสี / ฟิลเตอร์'),
            _chips<int>(
              value: _filterIndex,
              options: [
                for (var i = 0; i < _filterLabels.length; i += 1)
                  (_filterLabels[i], i),
              ],
              onSelected: (v) => setState(() => _filterIndex = v),
            ),
            const SizedBox(height: AppTheme.spaceMd),
            _section('ตำแหน่งซับ'),
            _chips<bool>(
              value: _subtitleAtBottom,
              options: const [('ล่าง', true), ('บน', false)],
              onSelected: (v) => setState(() => _subtitleAtBottom = v),
            ),
            const SizedBox(height: AppTheme.spaceMd),
            _section('ขนาดซับ'),
            _chips<double>(
              value: _subtitleFontSize,
              options: const [('เล็ก', 14.0), ('กลาง', 18.0), ('ใหญ่', 24.0)],
              onSelected: (v) => setState(() => _subtitleFontSize = v),
            ),
            const SizedBox(height: AppTheme.spaceMd),
            _section('ความสว่าง'),
            _chips<double>(
              value: _brightness,
              options: const [('ปกติ', 0.0), ('สว่างขึ้น', 0.3), ('ลดแสง', -0.3)],
              onSelected: (v) => setState(() => _brightness = v),
            ),
            const SizedBox(height: AppTheme.spaceMd),
            _section('คอนทราสต์'),
            _chips<double>(
              value: _contrast,
              options: const [('ปกติ', 0.0), ('เพิ่ม', 0.3), ('ลด', -0.3)],
              onSelected: (v) => setState(() => _contrast = v),
            ),
            const SizedBox(height: AppTheme.spaceLg),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () => Navigator.of(context).pop(
                  EditStyleOptions(
                    targetSeconds: _targetSeconds,
                    subtitleMaxChars: _subtitleMaxChars,
                    silenceMinGapSec: _silenceMinGapSec,
                    speed: _speed,
                    filterIndex: _filterIndex,
                    subtitleFontSize: _subtitleFontSize,
                    subtitleAtBottom: _subtitleAtBottom,
                    brightness: _brightness,
                    contrast: _contrast,
                  ),
                ),
                icon: const Icon(Icons.check, size: 18),
                label: const Text('ใช้ตัวเลือก'),
              ),
            ),
          ],
          ),
        ),
      ),
    );
  }

  Widget _section(String title) => Padding(
        padding: const EdgeInsets.only(bottom: AppTheme.spaceSm),
        child: Text(title,
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
      );

  Widget _chips<T>({
    required T value,
    required List<(String, T)> options,
    required ValueChanged<T> onSelected,
  }) {
    return Wrap(
      spacing: AppTheme.spaceSm,
      runSpacing: AppTheme.spaceSm,
      children: [
        for (final (label, optionValue) in options)
          ChoiceChip(
            label: Text(label),
            selected: value == optionValue,
            onSelected: (_) => onSelected(optionValue),
          ),
      ],
    );
  }
}
