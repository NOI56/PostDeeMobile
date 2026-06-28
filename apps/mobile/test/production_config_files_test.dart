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

    expect(
      oauthClients.any(
        (client) =>
            client is Map<String, Object?> &&
            client['client_type'] == 1 &&
            client['android_info'] is Map<String, Object?>,
      ),
      isTrue,
    );
  });
}
