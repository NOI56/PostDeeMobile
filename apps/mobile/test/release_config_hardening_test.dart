import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// A signed-in Firebase session lives in app storage. Backup or device transfer
// would carry it to a device the backup-account owner controls.
void main() {
  final manifest =
      File('android/app/src/main/AndroidManifest.xml').readAsStringSync();

  test('Android disables backup and device transfer of app data', () {
    expect(manifest, contains('android:allowBackup="false"'));
    expect(manifest,
        contains('android:dataExtractionRules="@xml/data_extraction_rules"'));

    final rules = File('android/app/src/main/res/xml/data_extraction_rules.xml');
    expect(rules.existsSync(), isTrue);
    final xml = rules.readAsStringSync();
    expect(xml, contains('<cloud-backup>'));
    expect(xml, contains('<device-transfer>'));
    for (final domain in ['root', 'file', 'database', 'sharedpref', 'external']) {
      expect(
        RegExp('<exclude domain="$domain" path="\\."\\s*/>').allMatches(xml),
        hasLength(2),
        reason: '$domain must be excluded from cloud backup and device transfer',
      );
    }
  });

  test('Android no longer claims the unused postdee://billing deep link', () {
    expect(manifest, isNot(contains('android:host="billing"')));
  });

  // Without this define the release IPA keeps the cleartext localhost default
  // while Firebase sign-in is enabled.
  test('iOS release IPA targets the production HTTPS API', () {
    final workflow =
        File('../../.github/workflows/build_ios.yml').readAsStringSync();

    expect(workflow,
        contains('--dart-define=API_BASE_URL=https://postdee-api.onrender.com'));
  });
}
