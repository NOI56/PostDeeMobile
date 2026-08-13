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
}
