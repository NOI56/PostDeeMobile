import 'package:flutter_test/flutter_test.dart';
import 'package:postdee_mobile/features/uploader/post_caption.dart';

void main() {
  group('validatePostCaption', () {
    test('accepts 2,200 Unicode code points', () {
      expect(validatePostCaption('😀' * 2200), isNull);
    });

    test('rejects a caption over 2,200 Unicode code points', () {
      expect(
        validatePostCaption('😀' * 2201),
        'แคปชั่นต้องไม่เกิน 2,200 ตัวอักษร (ตอนนี้ 2,201)',
      );
    });

    test('ignores surrounding whitespace like the API does', () {
      expect(validatePostCaption('  ${'ก' * 2200}\n'), isNull);
    });
  });

  group('validatePostCaption for YouTube', () {
    const youtubeTooLong =
        'แคปชั่นยาวเกินที่ YouTube รับได้ (สูงสุด 5,000 ไบต์ ภาษาไทยราว 1,660 ตัวอักษร)';

    test('lets a YouTube-only caption pass 2,200 characters up to 5,000 bytes',
        () {
      expect(
        validatePostCaption('a' * 5000,
            includesYoutube: true, includesOtherPlatforms: false),
        isNull,
      );
      expect(
        validatePostCaption('ก' * 1666,
            includesYoutube: true, includesOtherPlatforms: false),
        isNull,
      );
    });

    test('rejects a YouTube caption over 5,000 UTF-8 bytes', () {
      expect(
        validatePostCaption('ก' * 1667,
            includesYoutube: true, includesOtherPlatforms: false),
        youtubeTooLong,
      );
    });

    test('keeps the 2,200 character limit when other platforms are included',
        () {
      expect(
        validatePostCaption('a' * 3000,
            includesYoutube: true, includesOtherPlatforms: true),
        'แคปชั่นต้องไม่เกิน 2,200 ตัวอักษร (ตอนนี้ 3,000)',
      );
    });

    test('rejects angle brackets only for YouTube', () {
      expect(
        validatePostCaption('ชอบมาก <3',
            includesYoutube: true, includesOtherPlatforms: true),
        'YouTube ไม่รับเครื่องหมาย < หรือ > ในแคปชั่น',
      );
      expect(validatePostCaption('ชอบมาก <3'), isNull);
    });
  });
}
