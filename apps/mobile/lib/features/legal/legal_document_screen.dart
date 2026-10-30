import 'package:flutter/material.dart';

import '../../core/localization/postdee_localizations.dart';
import '../../core/theme/app_theme.dart';

class LegalDocument {
  const LegalDocument({
    required this.title,
    required this.body,
    this.englishTitle,
    this.englishBody,
  });

  final String title;
  final String body;
  final String? englishTitle;
  final String? englishBody;
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
        'ฉบับร่างในเครื่อง\n'
        '- เมื่อกดบันทึกร่าง แอปคัดลอกวิดีโอ หน้าปก และข้อมูลร่างไว้ในพื้นที่ของแอป แยกตามบัญชีที่เข้าสู่ระบบ\n'
        '- การบันทึกร่างไม่อัปโหลดไป API/R2 ไม่ส่งไปแพลตฟอร์ม ไม่เข้าคิว และไม่ใช้โควตาโพสต์\n'
        '- ร่างไม่ซิงก์ข้ามอุปกรณ์ แต่อาจรวมอยู่ในข้อมูลสำรองของระบบปฏิบัติการตามการตั้งค่า\n'
        '- แอปลบร่างหลัง API รับโพสต์เข้าคิว หากขั้นตอนก่อนรับเข้าคิวล้มเหลวจะเก็บร่างไว้ และหากลบไฟล์ไม่สำเร็จแอปจะแจ้งเตือนว่าไฟล์อาจยังอยู่\n\n'
        'การใช้ข้อมูล\n'
        '- ใช้เพื่อโพสต์ ตั้งเวลา และแสดงผลวิเคราะห์ให้คุณเท่านั้น\n'
        '- ไม่ขายข้อมูลส่วนบุคคลให้บุคคลที่สาม\n\n'
        'สิทธิของคุณ\n'
        '- ขอดู แก้ไข หรือลบข้อมูลของคุณได้ทุกเมื่อ\n'
        '- ลบฉบับร่างแต่ละรายการได้จากหน้าร่าง\n'
        '- ลบบัญชีจากหน้าโปรไฟล์เพื่อลบข้อมูลฝั่งบริการ การลบนี้อาจไม่ลบไฟล์เฉพาะเครื่องหรือสำเนาในระบบสำรองข้อมูล จึงควรลบร่างหรือล้างข้อมูลแอปแยกต่างหาก\n\n'
        'ติดต่อ: postdee.support@gmail.com\n\n'
        '(เอกสารฉบับร่าง — จะอัปเดตเป็นฉบับสมบูรณ์ก่อนเผยแพร่จริง)',
    englishTitle: 'Privacy policy',
    englishBody:
        'PostDee collects only the information needed to publish and schedule videos to your social platforms.\n\n'
        'What we collect\n'
        '- The account and email address you use to sign in\n'
        '- Videos and captions you upload for publishing or scheduling\n'
        '- Social account connection tokens (stored securely and not disclosed to others)\n\n'
        'Drafts on this device\n'
        '- When you save a draft, the app copies the video, cover image and draft details into its own storage, separately for each signed-in account.\n'
        '- Saving a draft does not upload it to the API/R2, send it to a platform, add it to the queue or use any post quota.\n'
        '- Drafts do not sync across devices, but may be included in operating system backups depending on your settings.\n'
        '- The app deletes a draft after the API accepts the post into the queue. If a step fails before the post is accepted into the queue, the draft is kept. If a file cannot be deleted, the app warns you that it may still be on the device.\n\n'
        'How we use your data\n'
        '- Only to publish and schedule posts, and show you analytics\n'
        '- We do not sell personal information to third parties\n\n'
        'Your rights\n'
        '- You can request access to, correction of or deletion of your data at any time.\n'
        '- You can delete individual drafts from the drafts page.\n'
        '- Delete your account from the Account page to delete data held by the service. This may not delete files stored only on your device or copies in backups, so you should delete drafts or clear app data separately.\n\n'
        'Contact: postdee.support@gmail.com\n\n'
        '(Draft document — this will be updated to the final version before release.)',
  );

  static const termsOfService = LegalDocument(
    title: 'ข้อกำหนดการใช้งาน',
    body: 'การใช้งาน PostDee ถือว่าคุณยอมรับข้อกำหนดต่อไปนี้\n\n'
        'การใช้งานบริการ\n'
        '- ใช้แอปเพื่อโพสต์คอนเทนต์ที่คุณมีสิทธิ์เผยแพร่เท่านั้น\n'
        '- ปฏิบัติตามนโยบายของแต่ละแพลตฟอร์มโซเชียลที่เชื่อมต่อ\n'
        '- คุณต้องเลือกช่องทางเองและตรวจรูปแบบเผยแพร่ของแต่ละช่องทางก่อนยืนยัน\n'
        '- TikTok เลือกส่งเป็นร่างเพื่อแก้ต่อใน TikTok หรือโพสต์ตรงตามตัวเลือกผู้ชมล่าสุดของบัญชี โดยต้องยืนยันสิทธิ์เพลงและข้อกำหนดที่เกี่ยวข้องก่อนส่ง ผลเผยแพร่อาจต้องรอ TikTok ประมวลผล\n'
        '- YouTube Shorts เลือกการมองเห็นได้, Instagram ตามบัญชีที่เชื่อม และ Facebook Reels บนเพจเลือกเผยแพร่หรือร่างได้; หากระบุรูปแบบไม่ได้ ระบบจะไม่ให้ยืนยัน\n'
        '- การตั้งเวลาต้องเป็นเวลาในอนาคต: Starter ไม่เกิน 14 วัน และ Pro ไม่เกิน 30 วัน; การเลื่อนเวลาใช้สิทธิ์แพ็กเกจปัจจุบัน โดยคิวที่รับไว้แล้วไม่ถูกยกเลิกอัตโนมัติ\n\n'
        'ฉบับร่าง\n'
        '- ฉบับร่างโพสต์เก็บเฉพาะในพื้นที่ของแอป ไม่ใช่โพสต์บนเซิร์ฟเวอร์และไม่ซิงก์ข้ามเครื่อง\n'
        '- ระบบปฏิบัติการอาจสำรองไฟล์ร่างตามการตั้งค่า และการลบบัญชีอาจไม่ลบสำเนาเฉพาะเครื่องหรือ backup\n\n'
        'แพ็กเกจและการชำระเงิน\n'
        '- แพ็กเกจ Starter และ Pro เป็นแบบรายเดือนผ่านสโตร์ของ Apple/Google\n'
        '- จัดการหรือยกเลิกการสมัครได้จากการตั้งค่าสโตร์ของอุปกรณ์\n\n'
        'เนื้อหาและความรับผิดชอบ\n'
        '- คุณเป็นผู้รับผิดชอบเนื้อหาที่โพสต์ผ่านบัญชีของคุณ\n'
        '- ห้ามใช้แอปเพื่อสแปม หลอกลวง หรือผิดกฎหมาย\n\n'
        'การเปลี่ยนแปลง\n'
        '- เราอาจปรับปรุงบริการและข้อกำหนด โดยจะแจ้งให้ทราบล่วงหน้าตามสมควร\n\n'
        'ติดต่อ: postdee.support@gmail.com\n\n'
        '(เอกสารฉบับร่าง — จะอัปเดตเป็นฉบับสมบูรณ์ก่อนเผยแพร่จริง)',
  );
}

class LegalDocumentScreen extends StatelessWidget {
  const LegalDocumentScreen({required this.document, super.key});

  final LegalDocument document;

  @override
  Widget build(BuildContext context) {
    final usesThai =
        (Localizations.of<PostDeeLocalizations>(context, PostDeeLocalizations)
                    ?.locale
                    .languageCode ??
                'th') ==
            'th';
    final title =
        usesThai ? document.title : document.englishTitle ?? document.title;
    final body =
        usesThai ? document.body : document.englishBody ?? document.body;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          title,
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
                body,
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
