import 'package:flutter_test/flutter_test.dart';
import 'package:postdee_mobile/features/uploader/clip_split_localizations.dart';

void main() {
  test('split clocks show minutes and seconds without long fractions', () {
    expect(formatClipSplitTime(55.153966), '0:55');
    expect(formatClipSplitTime(155.067414), '2:35');
    expect(formatClipSplitTime(59.999999), '0:59');
    expect(formatClipSplitTime(60.000001), '1:00');
    expect(formatClipSplitTime(180.0000005), '3:00');
    expect(formatClipSplitTime(3600.125), '60:00');
  });
}
