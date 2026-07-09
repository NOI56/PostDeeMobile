import 'package:flutter_test/flutter_test.dart';
import 'package:postdee_mobile/core/monitoring/postdee_analytics.dart';

void main() {
  test('does not log analytics events while disabled', () async {
    final events = <RecordedAnalyticsEvent>[];
    final analytics = PostDeeAnalytics(
      logEvent: (event) async => events.add(event),
    );

    await analytics.logSignInStarted('google');
    await analytics.logPublishSucceeded(
      platformCount: 2,
      isScheduled: true,
    );

    expect(events, isEmpty);
  });

  test('logs safe auth and publish funnel events when enabled', () async {
    final events = <RecordedAnalyticsEvent>[];
    final analytics = PostDeeAnalytics(
      isEnabled: true,
      logEvent: (event) async => events.add(event),
    );

    await analytics.logSignInStarted('google');
    await analytics.logSignInSucceeded('google');
    await analytics.logPublishStarted(
      platformCount: 2,
      isScheduled: false,
      watermarkEnabled: true,
    );
    await analytics.logPublishSucceeded(
      platformCount: 2,
      isScheduled: false,
    );

    expect(
      events.map((event) => event.name),
      [
        'auth_sign_in_started',
        'auth_sign_in_succeeded',
        'post_publish_started',
        'post_publish_succeeded',
      ],
    );
    expect(events.first.parameters, {'provider': 'google'});
    expect(events[2].parameters, {
      'platform_count': 2,
      'is_scheduled': false,
      'watermark_enabled': true,
    });
    expect(events[3].parameters, {
      'platform_count': 2,
      'is_scheduled': false,
    });
    for (final event in events) {
      expect(event.parameters.keys, isNot(contains('email')));
      expect(event.parameters.keys, isNot(contains('phone')));
      expect(event.parameters.keys, isNot(contains('token')));
      expect(event.parameters.keys, isNot(contains('caption')));
      expect(event.parameters.keys, isNot(contains('video_s3_key')));
    }
  });

  test('logs failures with a categorical reason only', () async {
    final events = <RecordedAnalyticsEvent>[];
    final analytics = PostDeeAnalytics(
      isEnabled: true,
      logEvent: (event) async => events.add(event),
    );

    await analytics.logPublishFailed(reason: 'network');

    expect(events.single.name, 'post_publish_failed');
    expect(events.single.parameters, {'reason': 'network'});
  });
}
