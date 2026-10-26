import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:postdee_mobile/features/legal/legal_document_screen.dart';

void main() {
  test('legal documents point to the monitored support address', () {
    expect(
      PostDeeLegalDocuments.privacyPolicy.body,
      contains('ติดต่อ: postdee.support@gmail.com'),
    );
    expect(
      PostDeeLegalDocuments.termsOfService.body,
      contains('ติดต่อ: postdee.support@gmail.com'),
    );
  });

  test('no screen shows the unregistered postdee.app support address', () {
    final offenders = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'))
        .where((file) => file.readAsStringSync().contains('support@postdee.app'))
        .map((file) => file.path)
        .toList();

    expect(offenders, isEmpty);
  });

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
      contains(
          'TikTok เลือกส่งเป็นร่างเพื่อแก้ต่อใน TikTok หรือโพสต์ตรงตามตัวเลือกผู้ชมล่าสุดของบัญชี'),
    );
    expect(
      PostDeeLegalDocuments.termsOfService.body,
      contains('ต้องยืนยันสิทธิ์เพลงและข้อกำหนดที่เกี่ยวข้องก่อนส่ง'),
    );
    expect(
      PostDeeLegalDocuments.termsOfService.body,
      contains('Starter ไม่เกิน 14 วัน และ Pro ไม่เกิน 30 วัน'),
    );
  });
}
