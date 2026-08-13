import 'package:flutter_test/flutter_test.dart';
import 'package:postdee_mobile/features/legal/legal_document_screen.dart';

void main() {
  test('discloses local publish draft storage and backup behavior', () {
    expect(
      PostDeeLegalDocuments.privacyPolicy.body,
      contains('การบันทึกร่างไม่อัปโหลดไป API/R2'),
    );
    expect(
      PostDeeLegalDocuments.privacyPolicy.body,
      contains('อาจรวมอยู่ในข้อมูลสำรองของระบบปฏิบัติการ'),
    );
    expect(
      PostDeeLegalDocuments.termsOfService.body,
      contains('ฉบับร่างโพสต์เก็บเฉพาะในพื้นที่ของแอป'),
    );
  });

  test('discloses current platform modes and scheduling limit', () {
    expect(
      PostDeeLegalDocuments.termsOfService.body,
      contains('TikTok SELF_ONLY'),
    );
    expect(
      PostDeeLegalDocuments.termsOfService.body,
      contains('ไม่เกิน 30 วัน'),
    );
  });
}
