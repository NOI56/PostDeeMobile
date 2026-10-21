import 'package:flutter_test/flutter_test.dart';
import 'package:postdee_mobile/core/network/postdee_api_client.dart';

Map<String, Object?> _subscription() => {
      'userId': 'reset-owner',
      'plan': 'PRO',
      'status': 'ACTIVE',
      'canSchedule': true,
      'canUseAiCaptions': true,
      'canUseAnalytics': true,
    };

void main() {
  test('reads the server monthly reset independently of paid-credit expiry',
      () {
    final result = SubscriptionStatusResult.fromJson({
      ..._subscription(),
      'monthlyQuotaResetsAt': '2026-11-01T00:00:00.000Z',
      'addonPostUnits': 100,
      'addonCreditsExpire': false
    });
    expect(result.monthlyQuotaResetsAt, DateTime.utc(2026, 11, 1));
    expect(result.addonExpiresAt, isNull);
    expect(result.addonCreditsExpire, isFalse);
  });
  test('old or malformed reset fields never invent a reset time', () {
    expect(
        SubscriptionStatusResult.fromJson(_subscription()).monthlyQuotaResetsAt,
        isNull);
    expect(
        SubscriptionStatusResult.fromJson(
                {..._subscription(), 'monthlyQuotaResetsAt': 'unknown'})
            .monthlyQuotaResetsAt,
        isNull);
  });
}
