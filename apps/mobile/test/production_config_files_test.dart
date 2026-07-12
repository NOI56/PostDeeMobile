import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('production dart defines point to Render and block local mock auth',
      () async {
    final file = File('production.local.example.json');

    expect(file.existsSync(), isTrue);

    final defines =
        jsonDecode(await file.readAsString()) as Map<String, Object?>;

    expect(defines['API_BASE_URL'], 'https://postdee-api.onrender.com');
    expect(defines['ENABLE_FIREBASE_AUTH'], isTrue);
    expect(defines['ALLOW_LOCAL_MOCK_AUTH'], isFalse);
    expect(defines['ENABLE_EXPERIMENTAL_BEAT_SYNC'], isFalse);
    expect(defines['ENABLE_EXPERIMENTAL_AI_HOOK'], isFalse);
    expect(defines['ENABLE_REVENUECAT_BILLING'], isTrue);
    expect(defines['GOOGLE_SERVER_CLIENT_ID'], isNot(isEmpty));
    expect(
        defines['STORE_STARTER_MONTHLY_PRODUCT_ID'], 'postdee_starter_monthly');
    expect(defines['STORE_PRO_MONTHLY_PRODUCT_ID'], 'postdee_pro_monthly');

    expect(defines.containsKey('POSTDEE_MOCK_USER_ID'), isFalse);
    expect(defines.containsKey('POSTDEE_MOCK_SUBSCRIPTION_PLAN'), isFalse);
    expect(defines.containsKey('GEMINI_API_KEY'), isFalse);
    expect(defines.containsKey('GROQ_API_KEY'), isFalse);
    expect(defines.containsKey('REVENUECAT_WEBHOOK_AUTH_TOKEN'), isFalse);
  });
  test('Android production build applies Google services plugin', () async {
    final settingsGradle = File('android/settings.gradle.kts');
    final appGradle = File('android/app/build.gradle.kts');

    expect(settingsGradle.existsSync(), isTrue);
    expect(appGradle.existsSync(), isTrue);

    expect(
      await settingsGradle.readAsString(),
      contains(
          'id("com.google.gms.google-services") version "4.5.0" apply false'),
    );
    expect(
      await appGradle.readAsString(),
      contains('id("com.google.gms.google-services")'),
    );
  });
  test('Android Firebase config includes an Android OAuth client', () async {
    final googleServicesFile = File('android/app/google-services.json');

    expect(googleServicesFile.existsSync(), isTrue);

    final config = jsonDecode(await googleServicesFile.readAsString())
        as Map<String, Object?>;
    final clients = config['client'] as List<dynamic>;
    final firstClient = clients.first as Map<String, Object?>;
    final oauthClients = firstClient['oauth_client'] as List<dynamic>;
    final androidOAuthClients = oauthClients
        .where(
          (client) =>
              client is Map<String, Object?> &&
              client['client_type'] == 1 &&
              client['android_info'] is Map<String, Object?>,
        )
        .toList();

    expect(androidOAuthClients, hasLength(greaterThanOrEqualTo(2)));
  });
  test('Android release builds use release signing properties', () async {
    final appGradle = File('android/app/build.gradle.kts');

    expect(appGradle.existsSync(), isTrue);

    final contents = await appGradle.readAsString();

    expect(contents, contains('rootProject.file("key.properties")'));
    expect(contents, contains('create("release")'));
    expect(contents, contains('signingConfigs.getByName("release")'));
    expect(contents, isNot(contains('signingConfigs.getByName("debug")')));
  });
  test('Android release builds keep FFmpegKit native methods', () async {
    final appGradle = File('android/app/build.gradle.kts');
    final proguardRules = File('android/app/proguard-rules.pro');

    expect(appGradle.existsSync(), isTrue);
    expect(proguardRules.existsSync(), isTrue);

    final gradleContents = await appGradle.readAsString();
    final rulesContents = await proguardRules.readAsString();

    expect(
      gradleContents,
      contains(
        'proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")',
      ),
    );
    expect(rulesContents,
        contains('-keep class com.antonkarpenko.ffmpegkit.** { *; }'));
    expect(rulesContents, contains('native <methods>;'));
  });
}
