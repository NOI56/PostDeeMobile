import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('production dart defines point to Render and block local mock auth',
      () async {
    final file = File('production.local.example.json');

    expect(file.existsSync(), isTrue);

    final defines = jsonDecode(await file.readAsString())
        as Map<String, Object?>;

    expect(defines['API_BASE_URL'], 'https://postdee-api.onrender.com');
    expect(defines['ENABLE_FIREBASE_AUTH'], isTrue);
    expect(defines['ALLOW_LOCAL_MOCK_AUTH'], isFalse);
    expect(defines['ENABLE_REVENUECAT_BILLING'], isTrue);
    expect(defines['GOOGLE_SERVER_CLIENT_ID'], isNot(isEmpty));
    expect(defines['STORE_STARTER_MONTHLY_PRODUCT_ID'],
        'postdee_starter_monthly');
    expect(defines['STORE_PRO_MONTHLY_PRODUCT_ID'], 'postdee_pro_monthly');

    expect(defines.containsKey('POSTDEE_MOCK_USER_ID'), isFalse);
    expect(defines.containsKey('POSTDEE_MOCK_SUBSCRIPTION_PLAN'), isFalse);
    expect(defines.containsKey('GEMINI_API_KEY'), isFalse);
    expect(defines.containsKey('GROQ_API_KEY'), isFalse);
    expect(defines.containsKey('REVENUECAT_WEBHOOK_AUTH_TOKEN'), isFalse);
  });
}
