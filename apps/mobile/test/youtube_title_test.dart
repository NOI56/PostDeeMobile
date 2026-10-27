import 'package:flutter_test/flutter_test.dart';
import 'package:postdee_mobile/features/uploader/youtube_title.dart';

void main() {
  group('deriveYoutubeTitle', () {
    test('uses the first nonempty Thai caption line', () {
      expect(
        deriveYoutubeTitle('\r\n  มาแต่งบ้านกัน   วันนี้\r\n#แต่งบ้าน #ของใช้'),
        'มาแต่งบ้านกัน วันนี้',
      );
    });

    test('uses the first sentence and keeps its punctuation', () {
      expect(
        deriveYoutubeTitle('ดูวิธีตั้งค่านี้!   ใช้งานง่ายมาก #สอนใช้งาน'),
        'ดูวิธีตั้งค่านี้!',
      );
      expect(deriveYoutubeTitle('เริ่มเลย。 ข้อความเพิ่มเติม'), 'เริ่มเลย。');
      expect(deriveYoutubeTitle('พร้อมไหม？ ลองทำตาม'), 'พร้อมไหม？');
      expect(deriveYoutubeTitle('Try this. More details.'), 'Try this.');
    });

    test('keeps punctuation within URLs and decimal numbers', () {
      expect(
        deriveYoutubeTitle('ดู https://postdee.app ราคา 19.99 บาท! ซื้อเลย'),
        'ดู https://postdee.app ราคา 19.99 บาท!',
      );
    });

    test('normalizes spaces and tabs before choosing a sentence', () {
      expect(
        deriveYoutubeTitle('  สินค้า\tใหม่\t\tมาแล้ว!\tดูรายละเอียด  '),
        'สินค้า ใหม่ มาแล้ว!',
      );
    });

    test('truncates at 100 Unicode code points without splitting emoji', () {
      final emoji = List.filled(youtubeTitleMaxLength, '😀').join();
      expect(deriveYoutubeTitle('$emojiเพิ่ม'), emoji);
      expect(deriveYoutubeTitle('$emojiเพิ่ม').runes.length, 100);
    });

    test('counts combining marks as individual code points', () {
      final thai = List.filled(50, 'กิ').join();
      expect(deriveYoutubeTitle('$thaiเพิ่ม'), thai);
    });

    test('trims whitespace left at the truncation boundary', () {
      final prefix = List.filled(99, 'a').join();
      expect(deriveYoutubeTitle('$prefix more'), prefix);
    });

    test('removes forbidden angle brackets from automatic titles', () {
      expect(deriveYoutubeTitle('  <สินค้า> ใหม่! รายละเอียด'), 'สินค้า ใหม่!');
      expect(deriveYoutubeTitle('<>\n  ชื่อคลิปถัดไป'), 'ชื่อคลิปถัดไป');
    });

    test('returns empty when no usable caption remains', () {
      for (final caption in ['', ' \t\r\n ', ' < > \n <> ']) {
        expect(deriveYoutubeTitle(caption), isEmpty);
      }
    });
  });

  group('validateYoutubeTitle', () {
    test('allows blank input so the uploader can use the automatic title', () {
      expect(validateYoutubeTitle(''), isNull);
      expect(validateYoutubeTitle(' \n\t '), isNull);
    });

    test('allows 100 code points and rejects 101', () {
      final emoji = List.filled(youtubeTitleMaxLength, '😀').join();
      expect(validateYoutubeTitle(emoji), isNull);
      expect(
        validateYoutubeTitle('$emoji😀'),
        'ชื่อวิดีโอ YouTube ต้องไม่เกิน 100 ตัวอักษร',
      );
    });

    test('rejects angle brackets in a custom title', () {
      for (final title in ['ชื่อ <สินค้า', 'ชื่อสินค้า>', '<>']) {
        expect(
          validateYoutubeTitle(title),
          'ชื่อวิดีโอ YouTube ห้ามมีเครื่องหมาย < หรือ >',
        );
      }
    });

    test('allows other punctuation in a custom title', () {
      expect(
          validateYoutubeTitle('สินค้าใหม่! ราคา 19.99 บาท #รีวิว 😀'), isNull);
    });
  });
}
