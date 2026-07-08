import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

class LegalDocument {
  const LegalDocument({
    required this.title,
    required this.body,
  });

  final String title;
  final String body;
}

/// In-app legal documents. The copy below is a working draft so the required
/// Privacy Policy / Terms surfaces exist inside the app. Replace the body text
/// (or point to a hosted page) with the finalized legal content before release.
class PostDeeLegalDocuments {
  const PostDeeLegalDocuments._();

  static const privacyPolicy = LegalDocument(
    title: 'นโยบายความเป็นส่วนตัว',
    body: 'PostDee เก็บข้อมูลเท่าที่จำเป็นเพื่อให้บริการโพสต์และตั้งเวลาคลิป '
        'วิดีโอไปยังแพลตฟอร์มโซเชียลของคุณ\n\n'
        'ข้อมูลที่เราเก็บ\n'
        '- บัญชีและอีเมลที่ใช้เข้าสู่ระบบ\n'
        '- วิดีโอและแคปชั่นที่คุณอัปโหลดเพื่อโพสต์หรือตั้งเวลา\n'
        '- โทเคนการเชื่อมต่อบัญชีโซเชียล (เก็บอย่างปลอดภัย ไม่เปิดเผยต่อผู้อื่น)\n\n'
        'การใช้ข้อมูล\n'
        '- ใช้เพื่อโพสต์ ตั้งเวลา และแสดงผลวิเคราะห์ให้คุณเท่านั้น\n'
        '- ไม่ขายข้อมูลส่วนบุคคลให้บุคคลที่สาม\n\n'
        'สิทธิของคุณ\n'
        '- ขอดู แก้ไข หรือลบข้อมูลของคุณได้ทุกเมื่อ\n'
        '- ลบบัญชีเพื่อลบข้อมูลทั้งหมดออกถาวรได้จากหน้าโปรไฟล์\n\n'
        'ติดต่อ: support@postdee.app\n\n'
        '(เอกสารฉบับร่าง — จะอัปเดตเป็นฉบับสมบูรณ์ก่อนเผยแพร่จริง)',
  );

  static const termsOfService = LegalDocument(
    title: 'ข้อกำหนดการใช้งาน',
    body: 'การใช้งาน PostDee ถือว่าคุณยอมรับข้อกำหนดต่อไปนี้\n\n'
        'การใช้งานบริการ\n'
        '- ใช้แอปเพื่อโพสต์คอนเทนต์ที่คุณมีสิทธิ์เผยแพร่เท่านั้น\n'
        '- ปฏิบัติตามนโยบายของแต่ละแพลตฟอร์มโซเชียลที่เชื่อมต่อ\n\n'
        'แพ็กเกจและการชำระเงิน\n'
        '- แพ็กเกจ Starter และ Pro เป็นแบบรายเดือนผ่านสโตร์ของ Apple/Google\n'
        '- จัดการหรือยกเลิกการสมัครได้จากการตั้งค่าสโตร์ของอุปกรณ์\n\n'
        'เนื้อหาและความรับผิดชอบ\n'
        '- คุณเป็นผู้รับผิดชอบเนื้อหาที่โพสต์ผ่านบัญชีของคุณ\n'
        '- ห้ามใช้แอปเพื่อสแปม หลอกลวง หรือผิดกฎหมาย\n\n'
        'การเปลี่ยนแปลง\n'
        '- เราอาจปรับปรุงบริการและข้อกำหนด โดยจะแจ้งให้ทราบล่วงหน้าตามสมควร\n\n'
        'ติดต่อ: support@postdee.app\n\n'
        '(เอกสารฉบับร่าง — จะอัปเดตเป็นฉบับสมบูรณ์ก่อนเผยแพร่จริง)',
  );
}

class LegalDocumentScreen extends StatelessWidget {
  const LegalDocumentScreen({required this.document, super.key});

  final LegalDocument document;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          document.title,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
      ),
      body: SafeArea(
        child: DecoratedBox(
          decoration: AppTheme.screenBackground,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 24),
            children: [
              Text(
                document.body,
                style: TextStyle(
                  fontSize: 13.5,
                  height: 1.7,
                  color: AppTheme.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
