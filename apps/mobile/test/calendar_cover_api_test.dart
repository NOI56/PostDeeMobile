import 'package:flutter_test/flutter_test.dart';
import 'package:postdee_mobile/core/network/postdee_api_client.dart';

void main() {
  test('calendar retains the existing selected-cover key from post metadata',
      () {
    final post = CalendarPostResult.fromJson({
      'id': 'covered-post',
      'createdAt': '2026-10-21T05:20:00.000Z',
      'coverImageS3Key': 'uploads/owner/cover/chosen.jpg',
      'coverFrameTimeMs': 4200,
    });
    expect(post.coverImageS3Key, 'uploads/owner/cover/chosen.jpg');
    expect(post.coverFrameTimeMs, 4200);
    expect(post.coverImageUrl, isNull,
        reason: 'An object key is not a public image URL.');
  });

  test('legacy posts without a chosen cover remain valid', () {
    for (final key in [null, '', '   ', 123]) {
      final post = PostSummaryResult.fromJson({
        'id': 'legacy',
        'createdAt': '2026-10-21T00:00:00Z',
        'coverImageS3Key': key,
      });
      expect(post.coverImageS3Key, isNull);
    }
  });
}
