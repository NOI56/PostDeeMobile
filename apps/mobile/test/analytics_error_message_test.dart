import 'package:flutter_test/flutter_test.dart';
import 'package:postdee_mobile/core/network/postdee_api_client.dart';
import 'package:postdee_mobile/features/analytics/analytics_error_message.dart';

void main() {
  test('recognizes the backend PRO_REQUIRED analytics contract', () {
    const error = ApiException(
      'Unified Analytics requires the Pro plan',
      statusCode: 402,
      code: 'PRO_REQUIRED',
    );

    expect(isAnalyticsPlanRequired(error), isTrue);
  });

  test('does not treat an unrelated payment error as an analytics Pro lock', () {
    const error = ApiException(
      'Payment is required',
      statusCode: 402,
      code: 'PAYMENT_REQUIRED',
    );

    expect(isAnalyticsPlanRequired(error), isFalse);
  });
}
