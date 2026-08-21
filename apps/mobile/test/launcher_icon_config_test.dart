import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('adaptive launcher icon uses a balanced white mark on brand color',
      () {
    final adaptiveIcon = File(
      'android/app/src/main/res/mipmap-anydpi-v26/ic_launcher.xml',
    ).readAsStringSync();
    final insetDrawable = File(
      'android/app/src/main/res/drawable/ic_launcher_foreground_inset.xml',
    );
    final whiteForeground = File(
      'android/app/src/main/res/drawable/ic_launcher_foreground_white.xml',
    );
    final brandBackground = File(
      'android/app/src/main/res/drawable/ic_launcher_background_gradient.xml',
    );

    expect(
      adaptiveIcon,
      contains('@drawable/ic_launcher_foreground_inset'),
    );
    expect(
      adaptiveIcon,
      contains('@drawable/ic_launcher_background_gradient'),
    );
    expect(insetDrawable.existsSync(), isTrue);
    expect(whiteForeground.existsSync(), isTrue);
    expect(brandBackground.existsSync(), isTrue);

    final insetXml = insetDrawable.readAsStringSync();
    expect(insetXml, contains('@drawable/ic_launcher_foreground_white'));
    for (final side in ['Left', 'Top', 'Right', 'Bottom']) {
      expect(insetXml, contains('android:inset$side="10dp"'));
    }

    final whiteForegroundXml = whiteForeground.readAsStringSync();
    expect(whiteForegroundXml, contains('android:tint="#FFFFFFFF"'));

    final brandBackgroundXml = brandBackground.readAsStringSync();
    expect(brandBackgroundXml, contains('android:startColor="#0E9F6E"'));
    expect(brandBackgroundXml, contains('android:endColor="#36D6A0"'));
  });
}
