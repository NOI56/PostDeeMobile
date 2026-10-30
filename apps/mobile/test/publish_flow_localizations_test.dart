import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postdee_mobile/core/localization/postdee_localizations.dart';
import 'package:postdee_mobile/features/uploader/publish_flow_localizations.dart';

Future<BuildContext> _context(WidgetTester tester, String? language) async {
  late BuildContext context;
  await tester.pumpWidget(MaterialApp(
      locale: language == null ? null : Locale(language),
      supportedLocales: PostDeeLocalizations.supportedLocales,
      localizationsDelegates: language == null
          ? null
          : const [
              PostDeeLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate
            ],
      home: Builder(builder: (value) {
        context = value;
        return const SizedBox();
      })));
  await tester.pumpAndSettle();
  return context;
}

void main() {
  testWidgets('Thai and missing app delegate retain exact progress and results',
      (tester) async {
    for (final language in <String?>[null, 'th']) {
      final context = await _context(tester, language);
      expect(publishFlowUsesThai(context), isTrue);
      for (final raw in [
        'กำลังเตรียมข้อมูล',
        'กำลังดำเนินการสำหรับ 2 ช่องทาง',
        '50% · ความคืบหน้าตามขั้นตอน',
        'ส่งเป็นร่างแล้ว'
      ]) {
        expect(localizePublishFlowMessage(context, raw), raw);
      }
      expect(publishFlowText(context, 'ไทย', 'English'), 'ไทย');
    }
  });
  testWidgets('English progress stages and controls use canonical labels',
      (tester) async {
    final context = await _context(tester, 'en');
    expect(localizePublishFlowMessage(context, 'กำลังเตรียมข้อมูล'),
        'Preparing post');
    expect(localizePublishFlowMessage(context, 'กำลังอัปโหลดวิดีโอ'),
        'Uploading video');
    expect(
        localizePublishFlowMessage(context, 'รับรายการแล้ว'), 'Post received');
    expect(localizePublishFlowMessage(context, 'เสร็จสิ้น'), 'Done');
  });
  testWidgets(
      'English result counts and replay translate only recognized bodies',
      (tester) async {
    final context = await _context(tester, 'en');
    expect(
        localizePublishFlowMessage(
            context, 'ระบบรับรายการ 2 ช่องทางแล้ว กำลังส่ง'),
        'Post received for 2 channels. Delivery is in progress.');
    expect(localizePublishFlowMessage(context, '50% · ความคืบหน้าตามขั้นตอน'),
        '50% · Step progress');
    expect(
        localizePublishFlowMessage(
            context, 'พบรายการเดิม · ระบบรับรายการ 1 ช่องทางแล้ว กำลังส่ง'),
        'Existing post found · Post received for 1 channel. Delivery is in progress.');
    const raw = 'พบรายการเดิม · provider data';
    expect(localizePublishFlowMessage(context, raw), raw);
  });

  testWidgets('all fixed stage, rail, action and outcome copy is exact',
      (tester) async {
    final context = await _context(tester, 'en');
    for (final entry in const {
      'กำลังตรวจสอบระบบโพสต์': 'Checking publishing service',
      'กำลังตรวจสอบแพ็กเกจ': 'Checking plan',
      'กำลังใส่ลายน้ำ': 'Applying watermark',
      'กำลังเชื่อมต่ออัปโหลดใหม่': 'Reconnecting upload',
      'กำลังอัปโหลดหน้าปก': 'Uploading cover',
      'กำลังสร้างคิวโพสต์': 'Creating post',
      'กำลังยืนยันรายการ': 'Finalizing post',
      'ความคืบหน้าตามขั้นตอน': 'Step progress',
      'เตรียมข้อมูล': 'Prepare',
      'อัปโหลด': 'Upload',
      'สร้างคิว': 'Queue',
      'เสร็จแล้ว': 'Done',
      'กำลังทำ': 'In progress',
      'รอขั้นตอน': 'Waiting',
      'เปอร์เซ็นต์นี้แสดงขั้นตอนงาน ไม่ใช่จำนวนไบต์ที่อัปโหลด':
          'This percentage shows progress through the steps, not uploaded bytes.',
      'กรุณาเปิดแอปหน้านี้ไว้ระหว่างเตรียมและส่งข้อมูล ยังยกเลิกไม่ได้จนจบขั้นตอน':
          'Keep this screen open while your post is prepared and sent. You cannot cancel until this step finishes.',
      'ยังยกเลิกไม่ได้ระหว่างส่งข้อมูล กรุณารอจนจบขั้นตอน':
          'You cannot cancel while data is being sent. Wait for this step to finish.',
      'บัญชีที่ใช้งานเปลี่ยนแล้ว กรุณาเปิดรายการโพสต์ใหม่':
          'Your account has changed. Reopen the post list.',
      'เกิดข้อผิดพลาดระหว่างส่งโพสต์ กรุณาตรวจการเชื่อมต่อแล้วลองใหม่':
          'An error occurred while sending your post. Check your connection and try again.',
      'ส่งโพสต์ไม่สำเร็จ': 'Could not send post',
      'ลองใหม่': 'Try again',
      'กลับไปตรวจสอบ': 'Go back and check',
      'ดูโพสต์นี้': 'View this post',
      'ดูสถิติโพสต์': 'View post analytics',
      'ส่งเป็นร่างแล้ว': 'Sent as draft',
      'ส่วนตัว': 'Private',
      'ไม่แสดงในรายการ': 'Unlisted',
      'เผยแพร่แล้ว': 'Published',
      'ผลยังไม่ยืนยัน': 'Delivery unconfirmed',
      'ส่งสำเร็จหลายรูปแบบ': 'Delivered with different visibility',
      'ส่งสำเร็จบางช่องทาง': 'Delivered to some channels',
      'กำลังส่ง': 'Sending post',
      'ส่งสำเร็จ': 'Post sent',
      'ส่งไม่สำเร็จ': 'Post not sent',
      'จัดคิวส่งตามเวลาแล้ว': 'Post scheduled',
      'ส่งสำเร็จเพียงบางช่องทาง กรุณาเปิดรายละเอียดเพื่อตรวจช่องทางที่ไม่สำเร็จ':
          'Only some channels succeeded. Open the post details to check the channels that failed.',
      'รายการนี้ส่งไม่สำเร็จ เปิดรายละเอียดเพื่อดูสิ่งที่ต้องแก้':
          'This post was not sent. Open the details to see what needs fixing.',
    }.entries) {
      expect(localizePublishFlowMessage(context, entry.key), entry.value);
    }
  });

  testWidgets(
      'counts zero through six retain each delivery state and replay body',
      (tester) async {
    final context = await _context(tester, 'en');
    for (var count = 0; count <= 6; count++) {
      final channels = '$count ${count == 1 ? 'channel' : 'channels'}';
      expect(
          localizePublishFlowMessage(
              context, 'กำลังดำเนินการสำหรับ $count ช่องทาง'),
          'Processing $channels');
      final messages = {
        'ระบบรับผลจาก $count ช่องทางแล้ว แต่ยังยืนยันรูปแบบปลายทางไม่ได้':
            'Results received from $channels, but the delivery outcome is not confirmed.',
        'ส่ง $count ช่องทางเป็นร่างแล้ว · ส่งออกจริงและใช้โควตาโพสต์':
            'Sent as ${count == 1 ? 'a draft' : 'drafts'} to $channels · Data was sent and post quota was used.',
        'ระบบกำลังส่ง $count ช่องทาง กรุณาตรวจผลอีกครั้งในหน้ารายการโพสต์':
            'Sending to $channels. Check the result again in your post list.',
        'ส่ง $count ช่องทางสำเร็จแล้ว': 'Sent to $channels.',
        'ระบบรับรายการตั้งเวลาสำหรับ $count ช่องทางแล้ว':
            'Scheduled post received for $channels.',
        'ระบบรับรายการ $count ช่องทางแล้ว กำลังส่ง':
            'Post received for $channels. Delivery is in progress.',
      };
      for (final outcome in const {
        'ส่งเป็นร่างแล้ว': 'Sent as draft',
        'ส่วนตัว': 'Private',
        'ไม่แสดงในรายการ': 'Unlisted',
        'เผยแพร่แล้ว': 'Published',
        'ผลยังไม่ยืนยัน': 'Delivery unconfirmed',
        'ส่งสำเร็จหลายรูปแบบ': 'Delivered with different visibility'
      }.entries) {
        messages['ส่ง $count ช่องทางสำเร็จ · ${outcome.key}'] =
            'Delivered to $channels · ${outcome.value}';
      }
      for (final message in messages.entries) {
        expect(localizePublishFlowMessage(context, message.key), message.value);
        expect(
            localizePublishFlowMessage(
                context, 'พบรายการเดิม · ${message.key}'),
            'Existing post found · ${message.value}');
      }
    }
    for (final body in const {
      'ส่งสำเร็จเพียงบางช่องทาง กรุณาเปิดรายละเอียดเพื่อตรวจช่องทางที่ไม่สำเร็จ':
          'Only some channels succeeded. Open the post details to check the channels that failed.',
      'รายการนี้ส่งไม่สำเร็จ เปิดรายละเอียดเพื่อดูสิ่งที่ต้องแก้':
          'This post was not sent. Open the details to see what needs fixing.',
    }.entries) {
      expect(localizePublishFlowMessage(context, 'พบรายการเดิม · ${body.key}'),
          'Existing post found · ${body.value}');
    }
  });

  testWidgets(
      'known platform labels accept only six recognized outcome suffixes',
      (tester) async {
    final context = await _context(tester, 'en');
    for (final platform in [
      'TikTok',
      'YouTube Shorts',
      'Instagram Reels',
      'Facebook Reels',
      'Shopee Video',
      'Lazada Video'
    ]) {
      for (final outcome in const {
        'ส่งเป็นร่างแล้ว': 'Sent as draft',
        'ส่วนตัว': 'Private',
        'ไม่แสดงในรายการ': 'Unlisted',
        'เผยแพร่แล้ว': 'Published',
        'ผลยังไม่ยืนยัน': 'Delivery unconfirmed',
        'ส่งสำเร็จหลายรูปแบบ': 'Delivered with different visibility'
      }.entries) {
        expect(
            localizePublishFlowMessage(context, '$platform · ${outcome.key}'),
            '$platform · ${outcome.value}');
      }
    }
  });

  testWidgets(
      'strict progress percentages and near matches preserve unknown data',
      (tester) async {
    final context = await _context(tester, 'en');
    for (var percent = 0; percent <= 100; percent++) {
      expect(
          localizePublishFlowMessage(
              context, '$percent% · ความคืบหน้าตามขั้นตอน'),
          '$percent% · Step progress');
    }
    for (final raw in [
      '101% · ความคืบหน้าตามขั้นตอน',
      '-1% · ความคืบหน้าตามขั้นตอน',
      '05% · ความคืบหน้าตามขั้นตอน',
      '50.0% · ความคืบหน้าตามขั้นตอน',
      '50% · ความคืบหน้าตามขั้นตอน\n',
      'กำลังดำเนินการสำหรับ 7 ช่องทาง',
      'ส่ง 09 ช่องทางสำเร็จแล้ว',
      'ส่ง 2 ช่องทางสำเร็จ · provider outcome',
      'TikTok · ส่งสำเร็จบางช่องทาง',
      'My account · ส่งเป็นร่างแล้ว',
      'TikTok · provider outcome',
      'ส่งสำเร็จ filename.mp4',
      'provider detail\nส่งไม่สำเร็จ',
      'ระบบรับรายการ 2 ช่องทางแล้ว กำลังส่ง\n',
      'พบรายการเดิม · ลองใหม่',
      'พบรายการเดิม · ส่งสำเร็จ',
      'พบรายการเดิม · พบรายการเดิม · ระบบรับรายการ 2 ช่องทางแล้ว กำลังส่ง'
    ]) {
      expect(localizePublishFlowMessage(context, raw), raw);
    }
  });

  testWidgets(
      'non-Thai locales use English while typed text and result counts stay intact',
      (tester) async {
    for (final language in ['en', 'vi', 'ja']) {
      final context = await _context(tester, language);
      expect(publishFlowUsesThai(context), isFalse);
      expect(publishFlowText(context, 'ไทย', 'English'), 'English');
      expect(localizePublishFlowMessage(context, 'รับรายการแล้ว'),
          'Post received');
      expect(
          localizePublishFlowMessage(
              context, 'ระบบรับรายการ 1 ช่องทางแล้ว กำลังส่ง'),
          'Post received for 1 channel. Delivery is in progress.');
    }
  });

  testWidgets(
      'stored Thai result follows live locale while identical raw text stays raw',
      (tester) async {
    final locale = ValueNotifier(const Locale('th'));
    addTearDown(locale.dispose);
    const stored = 'ส่งเป็นร่างแล้ว';
    await tester.pumpWidget(ValueListenableBuilder<Locale>(
        valueListenable: locale,
        builder: (_, value, __) => MaterialApp(
            locale: value,
            supportedLocales: PostDeeLocalizations.supportedLocales,
            localizationsDelegates: const [
              PostDeeLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate
            ],
            home: const Column(children: [
              PublishFlowText(stored),
              Text(stored, key: ValueKey('raw-post-data'))
            ]))));
    await tester.pumpAndSettle();
    expect(find.text(stored), findsNWidgets(2));
    locale.value = const Locale('en');
    await tester.pumpAndSettle();
    expect(find.text('Sent as draft'), findsOneWidget);
    expect(find.text(stored), findsOneWidget);
    expect(
        tester.widget<Text>(find.byKey(const ValueKey('raw-post-data'))).data,
        stored);
    locale.value = const Locale('th');
    await tester.pumpAndSettle();
    expect(find.text(stored), findsNWidgets(2));
  });
}
