import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('adaptive launcher icon keeps optical padding around the brand mark',
      () {
    final adaptiveIcon = File(
      'android/app/src/main/res/mipmap-anydpi-v26/ic_launcher.xml',
    ).readAsStringSync();
    final insetDrawable = File(
      'android/app/src/main/res/drawable/ic_launcher_foreground_inset.xml',
    );

    expect(
      adaptiveIcon,
      contains('@drawable/ic_launcher_foreground_inset'),
    );
    expect(insetDrawable.existsSync(), isTrue);

    final insetXml = insetDrawable.readAsStringSync();
    for (final side in ['Left', 'Top', 'Right', 'Bottom']) {
      expect(insetXml, contains('android:inset$side="10dp"'));
    }
  });
}
