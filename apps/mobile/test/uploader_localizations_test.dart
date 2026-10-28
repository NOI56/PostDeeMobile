import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postdee_mobile/core/localization/postdee_localizations.dart';
import 'package:postdee_mobile/features/uploader/uploader_localizations.dart';

Future<BuildContext> _context(WidgetTester tester, String language) async {
  late BuildContext result;
  await tester.pumpWidget(MaterialApp(
    locale: Locale(language),
    supportedLocales: PostDeeLocalizations.supportedLocales,
    localizationsDelegates: const [
      PostDeeLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate
    ],
    home: Builder(builder: (context) {
      result = context;
      return const SizedBox();
    }),
  ));
  await tester.pumpAndSettle();
  return result;
}

void main() {
  testWidgets('known step zero copy is English at presentation time',
      (tester) async {
    final context = await _context(tester, 'en');
    expect(uploaderUsesThai(context), isFalse);
    for (final entry in const {
      'สร้างโพสต์ใหม่': 'Create post',
      'เลือกวิดีโอ 9:16': 'Choose a 9:16 video',
      'แต่งหน้าปก': 'Create cover',
      'แก้หน้าปก': 'Edit cover',
      'ดูคลิป': 'Watch',
      'เลือกวิดีโอจากเครื่องก่อน': 'Choose a video from your device first.',
      'โพสต์คงเหลือ': 'Post units remaining',
    }.entries) {
      expect(localizeUploaderMessage(context, entry.key), entry.value);
    }
  });

  testWidgets('strict wizard chrome keeps indexes and recognizes completion',
      (tester) async {
    final context = await _context(tester, 'en');
    expect(localizeUploaderMessage(context, 'ขั้นตอนที่ 1 จาก 4 · เลือกคลิป'),
        'Step 1 of 4 · Choose video');
    expect(
        localizeUploaderMessage(
            context, 'ขั้นตอนที่ 4 จาก 4 · ตรวจทาน เสร็จแล้ว'),
        'Step 4 of 4 · Review · Completed');
    expect(localizeUploaderMessage(context, 'ฉบับร่าง (23)'), 'Drafts (23)');
    expect(localizeUploaderMessage(context, 'ถัดไป: เขียนแคปชัน'),
        'Next: Caption');
  });

  testWidgets(
      'picker failure translates only its prefix and preserves raw provider data',
      (tester) async {
    final context = await _context(tester, 'en');
    const details = 'provider-code-42\nเลือกคลิป · /raw/คลิปของฉัน.mp4';
    expect(localizeUploaderMessage(context, 'เลือกวิดีโอไม่ได้: $details'),
        'Could not select the video: $details');
    expect(localizeUploaderMessage(context, details), details);
  });

  testWidgets('known duration limits retain their original numeric values',
      (tester) async {
    final context = await _context(tester, 'en');
    expect(
        localizeUploaderMessage(context,
            'TikTok ต้องใช้คลิปยาวไม่เกิน 1 นาที 1 วินาที จึงโพสต์ช่องทางนี้ไม่ได้'),
        'TikTok requires a video no longer than 1 minute 1 second. This video cannot be posted to this channel.');
    expect(
        localizeUploaderMessage(
            context, 'TikTok ต้องใช้คลิปยาวไม่เกิน 37 วินาที'),
        'TikTok requires a video no longer than 37 seconds');
  });

  testWidgets(
      'recovery translates known status while preserving the original post ID',
      (tester) async {
    final context = await _context(tester, 'en');
    const id = 'post-ร่างของฉัน-007';
    expect(
        localizeUploaderMessage(context,
            'พบรายการเดิม: $id · ส่งสำเร็จ · ไม่ได้ส่งซ้ำ ร่างยังอยู่ในเครื่อง'),
        'Original submission found: $id · Delivered · Not submitted again. The draft is still on this device.');
  });

  testWidgets(
      'unknown strings remain raw and Thai fallback preserves known source copy',
      (tester) async {
    final context = await _context(tester, 'en');
    for (final raw in const [
      'customer caption แคปชันเดิม',
      'เลือกคลิป.mp4',
      'prefix เลือกวิดีโอจากเครื่องก่อน',
      'ขั้นตอนที่ 1 จาก 5 · เลือกคลิป',
      'ขั้นตอนที่ 1 จาก 4 · ตรวจทาน',
      'ฉบับร่าง (name)',
      'พบรายการเดิม: post-1 · unknown-status · ไม่ได้ส่งซ้ำ ร่างยังอยู่ในเครื่อง'
    ]) {
      expect(localizeUploaderMessage(context, raw), raw);
    }
    final thai = await _context(tester, 'th');
    expect(uploaderUsesThai(thai), isTrue);
    expect(localizeUploaderMessage(thai, 'สร้างโพสต์ใหม่'), 'สร้างโพสต์ใหม่');
  });

  testWidgets(
      'draft dialogs, storage errors and quota lifecycle use agreed copy',
      (tester) async {
    final context = await _context(tester, 'en');
    for (final entry in const {
      'เก็บโพสต์นี้ไว้ไหม?': 'Keep this post?',
      'แก้ไขต่อ': 'Keep editing',
      'ออกโดยไม่บันทึก': 'Leave without saving',
      'บันทึกแล้วออก': 'Save and exit',
      'ลบฉบับร่างนี้?': 'Delete this draft?',
      'วิดีโอและหน้าปกที่เก็บไว้กับฉบับร่างนี้จะถูกลบจากพื้นที่ของแอป':
          'The video and cover stored with this draft will be deleted from app storage.',
      'ไฟล์วิดีโอที่เลือกมีข้อมูลไม่ครบ':
          'The selected video file is missing required information.',
      'เลือกวิดีโอจริงจากเครื่องก่อนแต่งหน้าปก':
          'Choose a local video before editing the cover.',
      'บันทึกร่างไม่สำเร็จ ตรวจสอบพื้นที่ว่างในเครื่อง':
          'Could not save the draft. Check the free space on this device.',
      'บันทึกร่างในเครื่องไม่สำเร็จ':
          'Could not save the draft on this device.',
      'บัญชีที่ใช้งานเปลี่ยนแล้ว กรุณาเปิดรายการฉบับร่างใหม่':
          'Your account has changed. Please reopen Drafts.',
      'กำลังอ่านความยาวคลิป...': 'Reading video duration...',
      'ยังอ่านความยาวคลิปไม่ได้ จะตรวจซ้ำก่อนส่ง':
          'Video duration is not available yet. It will be checked again before sending.',
      'กำลังโหลดโควตาโพสต์...': 'Loading post quota...',
      'โหลดโควตาโพสต์ไม่สำเร็จ': 'Could not load post quota.',
      'โหลดโควตาโพสต์ใหม่': 'Reload post quota',
      'ยืนยันเบอร์เพื่อใช้โควตาฟรี':
          'Verify your phone number to use the free quota',
    }.entries) {
      expect(localizeUploaderMessage(context, entry.key), entry.value);
    }
  });

  testWidgets(
      'all four wizard labels retain their exact index and completion state',
      (tester) async {
    final context = await _context(tester, 'en');
    const titles = ['เลือกคลิป', 'เขียนแคปชัน', 'เลือกช่องทาง', 'ตรวจทาน'];
    const english = [
      'Choose video',
      'Write caption',
      'Choose channels',
      'Review'
    ];
    for (var index = 0; index < titles.length; index++) {
      for (final completed in [false, true]) {
        final raw =
            'ขั้นตอนที่ ${index + 1} จาก 4 · ${titles[index]}${completed ? ' เสร็จแล้ว' : ''}';
        expect(localizeUploaderMessage(context, raw),
            'Step ${index + 1} of 4 · ${english[index]}${completed ? ' · Completed' : ''}');
      }
    }
  });

  testWidgets(
      'draft counts, channel grammar and frame clocks preserve captures',
      (tester) async {
    final context = await _context(tester, 'en');
    for (final count in ['0', '1', '23', '0007']) {
      expect(localizeUploaderMessage(context, 'ฉบับร่าง ($count)'),
          'Drafts ($count)');
      expect(localizeUploaderMessage(context, '$count ช่องทาง · เก็บในเครื่อง'),
          '$count ${count == '1' ? 'channel' : 'channels'} · Stored on this device');
    }
    for (final clock in ['00:00', '12:34', '01:02:03', '123:45:59']) {
      expect(localizeUploaderMessage(context, 'เลือกเฟรมที่ $clock'),
          'Selected frame at $clock');
    }
  });

  testWidgets(
      'duration family translates only exact known bases and known suffixes',
      (tester) async {
    final context = await _context(tester, 'en');
    const limits = {
      'TikTok ต้องใช้คลิปยาวไม่เกิน 1 วินาที':
          'TikTok requires a video no longer than 1 second',
      'TikTok ต้องใช้คลิปยาวไม่เกิน 2 วินาที':
          'TikTok requires a video no longer than 2 seconds',
      'TikTok ต้องใช้คลิปยาวไม่เกิน 1 นาที':
          'TikTok requires a video no longer than 1 minute',
      'TikTok ต้องใช้คลิปยาวไม่เกิน 10 นาที':
          'TikTok requires a video no longer than 10 minutes',
      'TikTok ต้องใช้คลิปยาวไม่เกิน 3 นาที 15 วินาที':
          'TikTok requires a video no longer than 3 minutes 15 seconds',
      'YouTube Shorts ต้องใช้คลิปยาวไม่เกิน 3 นาที':
          'YouTube Shorts requires a video no longer than 3 minutes',
      'Instagram Reels ต้องใช้คลิปยาวตั้งแต่ 3 วินาทีถึง 15 นาที':
          'Instagram Reels requires a video from 3 seconds to 15 minutes long',
      'Facebook Reels ต้องใช้คลิปยาวตั้งแต่ 3 วินาทีถึง 1 นาที 30 วินาที':
          'Facebook Reels requires a video from 3 seconds to 1 minute 30 seconds long',
    };
    const suffixes = {
      '': '',
      ' จึงโพสต์ช่องทางนี้ไม่ได้':
          '. This video cannot be posted to this channel.',
      ' กรุณายกเลิกช่องทางนี้หรือเลือกคลิปใหม่':
          '. Deselect this channel or choose another video.',
      ' กรุณาตรวจรายการเดิมก่อนเริ่มรายการโพสต์ใหม่':
          '. Check the original submission before starting a new post request.',
    };
    for (final base in limits.entries) {
      for (final suffix in suffixes.entries) {
        expect(localizeUploaderMessage(context, '${base.key}${suffix.key}'),
            '${base.value}${suffix.value}');
      }
    }
  });

  testWidgets(
      'all recovery statuses preserve opaque IDs and avoid public-publish claims',
      (tester) async {
    final context = await _context(tester, 'en');
    const id = 'opaque · prefix\nโพสต์คงเหลือ-007';
    for (final entry in const {
      'รับรายการแล้ว กำลังรอส่ง': 'Accepted, waiting to send',
      'กำลังส่ง': 'Sending',
      'ส่งสำเร็จ': 'Delivered',
      'ส่งสำเร็จเพียงบางช่องทาง': 'Partially delivered',
      'ส่งไม่สำเร็จ กรุณาตรวจรายละเอียดในรายการโพสต์':
          'Failed. Check the post details',
      'กรุณาตรวจสถานะในรายการโพสต์': 'Check the status in your posts',
    }.entries) {
      final raw =
          'พบรายการเดิม: $id · ${entry.key} · ไม่ได้ส่งซ้ำ ร่างยังอยู่ในเครื่อง';
      final translated = localizeUploaderMessage(context, raw);
      expect(translated,
          'Original submission found: $id · ${entry.value} · Not submitted again. The draft is still on this device.');
      expect(translated.contains('Published'), isFalse);
    }
  });

  testWidgets(
      'strict patterns leave near matches, provider HTML and later-page bodies raw',
      (tester) async {
    final context = await _context(tester, 'en');
    for (final raw in const [
      'ฉบับร่าง (7)\n',
      'prefix ฉบับร่าง (7)',
      'ฉบับร่าง (-1)',
      '1 ช่องทาง · เก็บในเครื่อง extra',
      'เลือกเฟรมที่ 60:99',
      'เลือกเฟรมที่ 00:03.mp4',
      'ขั้นตอนที่ 2 จาก 4 · เลือกคลิป',
      'TikTok ต้องใช้คลิปยาวไม่เกิน 10 นาที extra',
      'unknown duration จึงโพสต์ช่องทางนี้ไม่ได้',
      'ตรวจทาน กรุณายกเลิกช่องทางนี้หรือเลือกคลิปใหม่',
      '<html>เลือกวิดีโอจากเครื่องก่อน</html>',
      '00:05 นาที · 512 ไบต์ · ชื่อแบบร่าง',
      'เขียนเอง หรือกดให้ AI ช่วยเมื่อพร้อม',
      'เลือกบัญชีปลายทางและตั้งค่าของแต่ละช่องทาง',
      'ตรวจข้อมูลและเลือกเวลาที่ต้องการโพสต์',
    ]) {
      expect(localizeUploaderMessage(context, raw), raw);
    }
  });

  testWidgets('Thai leaves dynamic source messages unchanged', (tester) async {
    final context = await _context(tester, 'th');
    for (final raw in const [
      'ฉบับร่าง (7)',
      '1 ช่องทาง · เก็บในเครื่อง',
      'เลือกวิดีโอไม่ได้: provider detail',
      'เลือกเฟรมที่ 00:03',
      'TikTok ต้องใช้คลิปยาวไม่เกิน 37 วินาที จึงโพสต์ช่องทางนี้ไม่ได้'
    ]) {
      expect(localizeUploaderMessage(context, raw), raw);
    }
    expect(uploaderText(context, 'ภาษาไทย', 'English'), 'ภาษาไทย');
  });

  testWidgets('non-Thai supported locales use English step-zero presentation',
      (tester) async {
    for (final language in ['en', 'vi', 'zh', 'id', 'ja']) {
      final context = await _context(tester, language);
      expect(uploaderUsesThai(context), isFalse);
      expect(localizeUploaderMessage(context, 'สร้างโพสต์ใหม่'), 'Create post');
      expect(uploaderText(context, 'ภาษาไทย', 'English'), 'English');
    }
  });

  testWidgets('plain MaterialApp safely falls back to Thai', (tester) async {
    late BuildContext context;
    await tester.pumpWidget(MaterialApp(home: Builder(builder: (value) {
      context = value;
      return const UploaderText('สร้างโพสต์ใหม่');
    })));
    expect(uploaderUsesThai(context), isTrue);
    expect(find.text('สร้างโพสต์ใหม่'), findsOneWidget);
    expect(uploaderText(context, 'ภาษาไทย', 'English'), 'ภาษาไทย');
  });

  testWidgets('shared footer covers all steps without changing channel counts',
      (tester) async {
    final context = await _context(tester, 'en');
    for (final entry in const {
      'AI กำลังคิดแคปชัน...': 'AI is writing a caption...',
      'แคปชันแก้ไขได้': 'Caption can be edited',
      'กำลังตรวจบัญชี...': 'Checking accounts...',
      'ยืนยันตั้งเวลา': 'Confirm schedule',
      'แก้แคปชันก่อนส่ง': 'Edit the caption before sending',
      'ตรวจปลายทางก่อนส่ง': 'Check destinations before sending',
    }.entries) {
      expect(localizeUploaderMessage(context, entry.key), entry.value);
    }
    for (final count in ['0', '1', '12']) {
      final channels = '$count ${count == '1' ? 'channel' : 'channels'}';
      expect(localizeUploaderMessage(context, 'เลือกแล้ว $count ช่องทาง'),
          '$channels selected');
      expect(localizeUploaderMessage(context, 'ส่ง $count ช่องทาง'),
          'Send to $channels');
      expect(localizeUploaderMessage(context, 'ตั้งเวลา $count ช่องทาง'),
          'Schedule for $channels');
      expect(localizeUploaderMessage(context, 'ยืนยันส่ง $count ช่องทาง'),
          'Confirm send to $channels');
    }
    for (final raw in [
      'เลือกแล้ว x ช่องทาง',
      'ส่ง -1 ช่องทาง',
      'ยืนยันส่ง 2 ช่องทาง extra',
      'prefix ตั้งเวลา 2 ช่องทาง'
    ]) {
      expect(localizeUploaderMessage(context, raw), raw);
    }
  });

  testWidgets('leaf widgets follow live locale while customer text remains raw',
      (tester) async {
    final locale = ValueNotifier(const Locale('en'));
    addTearDown(locale.dispose);
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
          UploaderText('เลือกคลิป',
              key: ValueKey('app-copy'),
              style: TextStyle(fontWeight: FontWeight.w700),
              textAlign: TextAlign.center,
              maxLines: 3,
              overflow: TextOverflow.fade),
          Text('เลือกคลิป', key: ValueKey('customer-draft-name')),
          Text('เลือกคลิป.mp4', key: ValueKey('raw-filename')),
        ]),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Choose video'), findsOneWidget);
    final rendered = tester.widget<Text>(find.descendant(
        of: find.byKey(const ValueKey('app-copy')),
        matching: find.byType(Text)));
    expect(rendered.style!.fontWeight, FontWeight.w700);
    expect(rendered.textAlign, TextAlign.center);
    expect(rendered.maxLines, 3);
    expect(rendered.overflow, TextOverflow.fade);
    for (final language in ['th', 'en']) {
      locale.value = Locale(language);
      await tester.pumpAndSettle();
      expect(
          tester
              .widget<Text>(find.byKey(const ValueKey('customer-draft-name')))
              .data,
          'เลือกคลิป');
      expect(find.text('เลือกคลิป.mp4'), findsOneWidget);
      expect(find.text(language == 'th' ? 'เลือกคลิป' : 'Choose video'),
          language == 'th' ? findsNWidgets(2) : findsOneWidget);
    }
  });
}
