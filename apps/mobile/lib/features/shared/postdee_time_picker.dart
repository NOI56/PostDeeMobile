import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

Future<TimeOfDay?> showPostDeeTimePicker({
  required BuildContext context,
  required TimeOfDay initialTime,
  DateTime? date,
}) {
  FocusManager.instance.primaryFocus?.unfocus();
  return showModalBottomSheet<TimeOfDay>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    requestFocus: true,
    backgroundColor: Theme.of(context).colorScheme.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
    ),
    clipBehavior: Clip.antiAlias,
    sheetAnimationStyle: MediaQuery.disableAnimationsOf(context)
        ? AnimationStyle.noAnimation
        : null,
    builder: (sheetContext) => Padding(
      padding:
          EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(sheetContext).bottom),
      child: PostDeeTimePicker(initialTime: initialTime, date: date),
    ),
  );
}

/// Selects a local wall-clock time. The supplied local date is informational;
/// callers retain ownership of date, scheduling rules and UTC conversion.
class PostDeeTimePicker extends StatefulWidget {
  const PostDeeTimePicker({
    super.key,
    required this.initialTime,
    this.date,
  });

  final TimeOfDay initialTime;
  final DateTime? date;

  @override
  State<PostDeeTimePicker> createState() => _PostDeeTimePickerState();
}

class _PostDeeTimePickerState extends State<PostDeeTimePicker> {
  late final _hourController =
      FixedExtentScrollController(initialItem: widget.initialTime.hour);
  late final _minuteController =
      FixedExtentScrollController(initialItem: widget.initialTime.minute);
  late int _hour = widget.initialTime.hour;
  late int _minute = widget.initialTime.minute;

  String get _formattedTime => '${_two(_hour)}:${_two(_minute)}';
  String _two(int value) => value.toString().padLeft(2, '0');

  @override
  void dispose() {
    _hourController.dispose();
    _minuteController.dispose();
    super.dispose();
  }

  void _confirm() {
    final hourIndex =
        _hourController.hasClients ? _hourController.selectedItem : _hour;
    final minuteIndex =
        _minuteController.hasClients ? _minuteController.selectedItem : _minute;
    // Stop momentum at the visible center before returning the exact value.
    _hourController.jumpToItem(hourIndex);
    _minuteController.jumpToItem(minuteIndex);
    Navigator.of(context)
        .pop(TimeOfDay(hour: hourIndex % 24, minute: minuteIndex % 60));
  }

  String _dateLabel(DateTime date) {
    const months = [
      'ม.ค.',
      'ก.พ.',
      'มี.ค.',
      'เม.ย.',
      'พ.ค.',
      'มิ.ย.',
      'ก.ค.',
      'ส.ค.',
      'ก.ย.',
      'ต.ค.',
      'พ.ย.',
      'ธ.ค.',
    ];
    return '${date.day} ${months[date.month - 1]} ${date.year}';
  }

  Widget _wheel({
    required Key key,
    required String label,
    required int count,
    required int selected,
    required FixedExtentScrollController controller,
    required ValueChanged<int> onChanged,
    required double itemExtent,
  }) {
    final colors = Theme.of(context).colorScheme;
    final reducedMotion = MediaQuery.disableAnimationsOf(context);
    return MergeSemantics(
        child: Semantics(
      label: label,
      child: CupertinoPicker(
        key: key,
        scrollController: controller,
        looping: true,
        itemExtent: itemExtent,
        squeeze: 1,
        diameterRatio: 2,
        selectionOverlay: null,
        backgroundColor: Colors.transparent,
        onSelectedItemChanged: onChanged,
        children: [
          for (var number = 0; number < count; number++)
            Center(
              child: GestureDetector(
                onTap: reducedMotion
                    ? () {
                        final currentIndex = controller.selectedItem;
                        var delta = (number - currentIndex % count) % count;
                        if (delta > count ~/ 2) delta -= count;
                        controller.jumpToItem(currentIndex + delta);
                      }
                    : null,
                child: Text(
                  _two(number),
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        color: selected == number
                            ? colors.primary
                            : colors.onSurfaceVariant,
                        fontSize: selected == number ? 28 : 23,
                        height: 1.2,
                        fontWeight: selected == number
                            ? FontWeight.w600
                            : FontWeight.w400,
                      ),
                ),
              ),
            ),
        ],
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final itemExtent =
        math.max(46.0, MediaQuery.textScalerOf(context).scale(28) * 1.35);
    return ConstrainedBox(
      key: const ValueKey('postdee-time-picker'),
      constraints:
          BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * .92),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: colors.outlineVariant,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Row(children: [
                Icon(Icons.schedule, color: colors.primary, size: 24),
                const SizedBox(width: 10),
                Expanded(
                  child: Text('เลือกเวลาโพสต์',
                      style: Theme.of(context)
                          .textTheme
                          .titleLarge
                          ?.copyWith(fontWeight: FontWeight.w600)),
                ),
              ]),
              const SizedBox(height: 8),
              Text(
                widget.date == null
                    ? 'รูปแบบ 24 ชั่วโมง · เวลาตามเครื่อง'
                    : '${_dateLabel(widget.date!)} · เวลาตามเครื่อง',
                key: const ValueKey('postdee-time-date'),
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: colors.onSurfaceVariant),
              ),
              const SizedBox(height: 20),
              const Row(children: [
                Expanded(child: Center(child: Text('ชั่วโมง'))),
                SizedBox(width: 18),
                Expanded(child: Center(child: Text('นาที'))),
              ]),
              const SizedBox(height: 8),
              SizedBox(
                height: itemExtent * 5,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    IgnorePointer(
                      child: Container(
                        height: itemExtent,
                        decoration: BoxDecoration(
                          color: colors.primary.withValues(alpha: .10),
                          borderRadius: BorderRadius.circular(13),
                        ),
                      ),
                    ),
                    Row(children: [
                      Expanded(
                        child: _wheel(
                          key: const ValueKey('postdee-time-hour-picker'),
                          label: 'ชั่วโมง',
                          count: 24,
                          selected: _hour,
                          controller: _hourController,
                          itemExtent: itemExtent,
                          onChanged: (value) => setState(() => _hour = value),
                        ),
                      ),
                      SizedBox(
                        width: 18,
                        child: ExcludeSemantics(
                          child: Text(':',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                  fontSize: 28,
                                  color: colors.primary,
                                  fontWeight: FontWeight.w600)),
                        ),
                      ),
                      Expanded(
                        child: _wheel(
                          key: const ValueKey('postdee-time-minute-picker'),
                          label: 'นาที',
                          count: 60,
                          selected: _minute,
                          controller: _minuteController,
                          itemExtent: itemExtent,
                          onChanged: (value) => setState(() => _minute = value),
                        ),
                      ),
                    ]),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              DecoratedBox(
                key: const ValueKey('postdee-time-summary'),
                decoration: BoxDecoration(
                  color: colors.surfaceContainerHighest.withValues(alpha: .45),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Wrap(
                    alignment: WrapAlignment.spaceBetween,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 12,
                    runSpacing: 4,
                    children: [
                      Text('เวลาที่เลือก',
                          style: TextStyle(color: colors.onSurfaceVariant)),
                      Text('$_formattedTime น.',
                          style: Theme.of(context)
                              .textTheme
                              .titleLarge
                              ?.copyWith(fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),
              LayoutBuilder(builder: (context, constraints) {
                final cancel = OutlinedButton(
                  key: const ValueKey('postdee-time-cancel'),
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('ยกเลิก', textAlign: TextAlign.center),
                );
                final confirm = FilledButton(
                  key: const ValueKey('postdee-time-confirm'),
                  onPressed: _confirm,
                  style: FilledButton.styleFrom(
                      minimumSize: const Size(0, 48),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 12)),
                  child: Text('ใช้เวลา $_formattedTime',
                      textAlign: TextAlign.center),
                );
                final stack = constraints.maxWidth < 300 &&
                    MediaQuery.textScalerOf(context).scale(14) > 18;
                if (stack) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [cancel, const SizedBox(height: 9), confirm],
                  );
                }
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: cancel),
                    const SizedBox(width: 9),
                    Expanded(flex: 2, child: confirm),
                  ],
                );
              }),
            ],
          ),
        ),
      ),
    );
  }
}
