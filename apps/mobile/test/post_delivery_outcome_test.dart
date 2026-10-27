import 'package:flutter_test/flutter_test.dart';
import 'package:postdee_mobile/core/network/postdee_api_client.dart';
import 'package:postdee_mobile/features/shared/post_delivery_outcome.dart';

void main() {
  PostPlatformResult result({
    required String platform,
    required String status,
    String? deliveryOutcome,
  }) {
    return PostPlatformResult(
      postId: 'post-1',
      platform: platform,
      status: status,
      deliveryOutcome: deliveryOutcome,
    );
  }

  test('uses a delivery outcome only after every platform succeeded', () {
    expect(
      aggregatePostDeliveryOutcomeLabel([
        result(
          platform: 'TIKTOK',
          status: 'PUBLISHED',
          deliveryOutcome: 'DRAFT',
        ),
        result(
          platform: 'YOUTUBE_SHORTS',
          status: 'PUBLISHED',
          deliveryOutcome: 'DRAFT',
        ),
      ]),
      'ส่งเป็นร่างแล้ว',
    );
  });

  test('reports partial success instead of a full delivery outcome', () {
    final results = [
      result(
        platform: 'TIKTOK',
        status: 'PUBLISHED',
        deliveryOutcome: 'DRAFT',
      ),
      result(platform: 'YOUTUBE_SHORTS', status: 'FAILED'),
    ];

    expect(aggregatePostDeliveryOutcomeLabel(results), 'ส่งสำเร็จบางช่องทาง');
    expect(
      aggregatePostDeliveryOutcomeLabel(results, compact: true),
      'ส่งบางส่วน',
    );
  });

  test('falls back to the aggregate status while any platform is working', () {
    expect(
      aggregatePostDeliveryOutcomeLabel([
        result(
          platform: 'TIKTOK',
          status: 'PUBLISHED',
          deliveryOutcome: 'DRAFT',
        ),
        result(platform: 'YOUTUBE_SHORTS', status: 'PUBLISHING'),
      ]),
      isNull,
    );
  });

  test('never treats an unknown non-null outcome as a live result', () {
    final unknown = result(
      platform: 'TIKTOK',
      status: 'PUBLISHED',
      deliveryOutcome: 'SOMETHING_NEW',
    );

    expect(postDeliveryOutcomeLabel(unknown.deliveryOutcome), 'ผลยังไม่ยืนยัน');
    expect(aggregatePostDeliveryOutcomeLabel([unknown]), 'ผลยังไม่ยืนยัน');
    expect(isKnownDeliveryOutcome(unknown.deliveryOutcome), isFalse);
    expect(isPublishedDeliveryOutcome(unknown.deliveryOutcome), isFalse);
  });

  test('English preserves each delivery visibility and unknown outcome', () {
    const labels = {
      'DRAFT': 'Sent as draft',
      'PRIVATE': 'Private',
      'UNLISTED': 'Unlisted',
      'LIVE': 'Published',
      'SOMETHING_NEW': 'Delivery unconfirmed',
    };
    for (final entry in labels.entries) {
      expect(
        postDeliveryOutcomeLabel(entry.key, languageCode: 'en'),
        entry.value,
      );
      expect(
        postDeliveryOutcomeLabel(entry.key, compact: true, languageCode: 'en'),
        entry.value,
      );
      expect(
        aggregatePostDeliveryOutcomeLabel([
          result(
            platform: 'TIKTOK',
            status: 'PUBLISHED',
            deliveryOutcome: entry.key,
          ),
        ], languageCode: 'en'),
        entry.value,
      );
    }
    expect(postDeliveryOutcomeLabel(null, languageCode: 'en'), isNull);
  });

  test('English distinguishes partial delivery from mixed visibility', () {
    final partial = [
      result(
        platform: 'TIKTOK',
        status: 'PUBLISHED',
        deliveryOutcome: 'DRAFT',
      ),
      result(platform: 'YOUTUBE_SHORTS', status: 'FAILED'),
    ];
    expect(
      aggregatePostDeliveryOutcomeLabel(partial,
          compact: true, languageCode: 'en'),
      'Partially delivered',
    );
    expect(
      aggregatePostDeliveryOutcomeLabel(partial, languageCode: 'en'),
      'Delivered to some channels',
    );

    final mixed = [
      result(
        platform: 'TIKTOK',
        status: 'PUBLISHED',
        deliveryOutcome: 'DRAFT',
      ),
      result(
        platform: 'YOUTUBE_SHORTS',
        status: 'PUBLISHED',
        deliveryOutcome: 'PRIVATE',
      ),
    ];
    expect(
      aggregatePostDeliveryOutcomeLabel(mixed,
          compact: true, languageCode: 'en'),
      'Delivered',
    );
    expect(
      aggregatePostDeliveryOutcomeLabel(mixed, languageCode: 'en'),
      'Delivered with different visibility',
    );
  });

  test('English keeps pending and legacy missing outcomes unconfirmed', () {
    expect(
      aggregatePostDeliveryOutcomeLabel([
        result(
          platform: 'TIKTOK',
          status: 'PUBLISHED',
          deliveryOutcome: 'DRAFT',
        ),
        result(platform: 'YOUTUBE_SHORTS', status: 'PUBLISHING'),
      ], languageCode: 'en'),
      isNull,
    );
    expect(
      aggregatePostDeliveryOutcomeLabel([
        result(platform: 'TIKTOK', status: 'PUBLISHED'),
      ], languageCode: 'en'),
      isNull,
    );
    expect(aggregatePostDeliveryOutcomeLabel([], languageCode: 'en'), isNull);
  });
}
