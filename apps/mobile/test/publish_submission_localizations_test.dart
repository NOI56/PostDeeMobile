import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postdee_mobile/core/localization/postdee_localizations.dart';
import 'package:postdee_mobile/features/uploader/publish_submission_localizations.dart';

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
            GlobalCupertinoLocalizations.delegate,
          ],
    home: Builder(builder: (value) {
      context = value;
      return const SizedBox();
    }),
  ));
  await tester.pumpAndSettle();
  return context;
}

void main() {
  testWidgets('Thai and missing app delegate preserve submission messages',
      (tester) async {
    for (final language in <String?>[null, 'th']) {
      final context = await _context(tester, language);
      for (final raw in [
        'อัปโหลด/คิวโพสต์ขัดข้อง',
        'ใส่ลายน้ำวิดีโอไม่สำเร็จ: raw FFmpeg details',
        'ใส่ลายน้ำแล้ว · พบรายการเดิม · รับรายการ 1 ช่องทางแล้ว กำลังส่ง: raw-id',
      ]) {
        expect(localizePublishSubmissionMessage(context, raw), raw);
      }
    }
  });
  testWidgets('English submission sheet uses app-owned copy', (tester) async {
    final context = await _context(tester, 'en');
    expect(localizePublishSubmissionMessage(context, 'อัปโหลด/คิวโพสต์ขัดข้อง'),
        'Upload or publishing queue issue');
    expect(localizePublishSubmissionMessage(context, 'รับทราบ'), 'OK');
    expect(
        localizePublishSubmissionMessage(context, 'สัดส่วนวิดีโอไม่ใช่ 9:16'),
        'Video is not 9:16');
  });
  testWidgets('English queued receipt preserves the exact raw post ID',
      (tester) async {
    final context = await _context(tester, 'en');
    expect(
      localizePublishSubmissionMessage(context,
          'ใส่ลายน้ำแล้ว · พบรายการเดิม · รับรายการ 1 ช่องทางแล้ว กำลังส่ง: fake: ส่งสำเร็จ'),
      'Watermark applied · Existing post found · Post received for 1 channel, delivery in progress: fake: ส่งสำเร็จ',
    );
    const raw = 'provider message: รับรายการ 1 ช่องทางแล้ว กำลังส่ง';
    expect(localizePublishSubmissionMessage(context, raw), raw);
  });

  testWidgets(
      'known submission, preparation and cover errors are localized exactly',
      (tester) async {
    final context = await _context(tester, 'en');
    for (final entry in _knownMessages.entries) {
      expect(localizePublishSubmissionMessage(context, entry.key), entry.value,
          reason: entry.key);
      final nearMatch = '${entry.key}\n';
      expect(localizePublishSubmissionMessage(context, nearMatch), nearMatch);
    }
    const title = 'ระบบรับงานโพสต์ยังไม่เปิดใช้งานในขณะนี้';
    expect(
      localizePublishSubmissionMessage(
          context, '$title วิดีโอยังไม่ได้อัปโหลด กรุณาลองใหม่ภายหลัง'),
      'Publishing is currently unavailable The video has not been uploaded. Try again later.',
    );
    expect(
      localizePublishSubmissionMessage(context,
          '$title ยังไม่ได้สร้างโพสต์ และไฟล์วิดีโออาจถูกอัปโหลดไว้ชั่วคราว กรุณาลองใหม่ภายหลัง'),
      'Publishing is currently unavailable No post was created. The video may have been uploaded temporarily. Try again later.',
    );
  });

  testWidgets(
      'receipt status, count, prefixes and cleanup warnings preserve IDs',
      (tester) async {
    final context = await _context(tester, 'en');
    final statuses = <String, String>{
      'กำลังส่ง': 'Sending post',
      'ส่งสำเร็จ': 'Post sent',
      'ส่งสำเร็จเพียงบางช่องทาง': 'Delivered to some channels',
      for (var count = 0; count <= 6; count++)
        'รับรายการ $count ช่องทางแล้ว กำลังส่ง':
            'Post received for $count ${count == 1 ? 'channel' : 'channels'}, delivery in progress',
    };
    for (final prefix in const {
      '': '',
      'ใส่ลายน้ำแล้ว · ': 'Watermark applied · ',
      'พบรายการเดิม · ': 'Existing post found · ',
      'ใส่ลายน้ำแล้ว · พบรายการเดิม · ':
          'Watermark applied · Existing post found · ',
    }.entries) {
      for (final status in statuses.entries) {
        for (final warning in const {
          '': '',
          ' · ลบร่างแล้ว แต่รีเฟรชรายการร่างไม่สำเร็จ':
              ' · Draft deleted, but the draft list could not be refreshed.',
          ' · โพสต์เข้าคิวแล้ว แต่ลบร่างในเครื่องไม่สำเร็จ':
              ' · The post was queued, but the draft on this device could not be deleted.',
        }.entries) {
          for (final rawId in const [
            'post-123',
            'fake: ส่งสำเร็จ · provider suffix',
            ' พบรายการเดิม · ID\nunchanged ',
          ]) {
            expect(
              localizePublishSubmissionMessage(
                  context, '${prefix.key}${status.key}: $rawId${warning.key}'),
              '${prefix.value}${status.value}: $rawId${warning.value}',
            );
          }
        }
      }
    }
  });

  testWidgets('near receipts and unknown provider data remain raw',
      (tester) async {
    final context = await _context(tester, 'en');
    for (final raw in const [
      'รับรายการ 7 ช่องทางแล้ว กำลังส่ง: post',
      'รับรายการ -1 ช่องทางแล้ว กำลังส่ง: post',
      'รับรายการ 01 ช่องทางแล้ว กำลังส่ง: post',
      'รับรายการ 1.0 ช่องทางแล้ว กำลังส่ง: post',
      'รับรายการ 1 ช่องทางแล้ว กำลังส่ง\n: post',
      'ระบบรับรายการ 1 ช่องทางแล้ว กำลังส่ง: post',
      'ส่งสำเร็จบางช่องทาง: post',
      'ส่งสำเร็จ: ',
      'กำลังส่ง:post',
      'ส่งสำเร็จ:  · ลบร่างแล้ว แต่รีเฟรชรายการร่างไม่สำเร็จ',
      'ใส่ลายน้ำแล้ว · ใส่ลายน้ำแล้ว · ส่งสำเร็จ: post',
      'พบรายการเดิม · พบรายการเดิม · ส่งสำเร็จ: post',
      'พบรายการเดิม · ใส่ลายน้ำแล้ว · ส่งสำเร็จ: post',
      'ส่งสำเร็จ: post · ลบร่างแล้ว แต่รีเฟรชรายการร่างไม่สำเร็จ · โพสต์เข้าคิวแล้ว แต่ลบร่างในเครื่องไม่สำเร็จ',
      'provider: ส่งสำเร็จ: raw-id',
      'custom filename ส่งสำเร็จ.mp4',
      'raw provider message\nระบบรับงานโพสต์ยังไม่เปิดใช้งานในขณะนี้',
      'ยังไม่ได้สร้างโพสต์: provider custom reason',
    ]) {
      expect(localizePublishSubmissionMessage(context, raw), raw);
    }
    expect(
        localizePublishSubmissionMessage(context,
            'ส่งสำเร็จ: post · ลบร่างแล้ว แต่รีเฟรชรายการร่างไม่สำเร็จ!'),
        'Post sent: post · ลบร่างแล้ว แต่รีเฟรชรายการร่างไม่สำเร็จ!');
  });

  testWidgets(
      'owned watermark failure hides raw encoder details only in English',
      (tester) async {
    for (final language in ['th', 'en']) {
      final context = await _context(tester, language);
      for (final details in const [
        'FFmpeg return code: 1',
        '<encoder>\n/private/path/filename.mp4',
        'ส่งสำเร็จ',
      ]) {
        final raw = 'ใส่ลายน้ำวิดีโอไม่สำเร็จ: $details';
        expect(
            localizePublishSubmissionMessage(context, raw),
            language == 'th'
                ? raw
                : 'Could not apply the watermark. Try again.');
      }
      for (final raw in const [
        'ใส่ลายน้ำวิดีโอไม่สำเร็จ: ',
        'provider: ใส่ลายน้ำวิดีโอไม่สำเร็จ: details',
        'ใส่ลายน้ำวิดีโอไม่สำเร็จ details',
      ]) {
        expect(localizePublishSubmissionMessage(context, raw), raw);
      }
    }
  });

  testWidgets(
      'stored submission text follows live locale without changing raw data',
      (tester) async {
    final locale = ValueNotifier(const Locale('th'));
    addTearDown(locale.dispose);
    const stored = 'รับรายการ 1 ช่องทางแล้ว กำลังส่ง: raw: ส่งสำเร็จ';
    var renders = 0;
    await tester.pumpWidget(ValueListenableBuilder<Locale>(
      valueListenable: locale,
      builder: (_, value, __) => MaterialApp(
        locale: value,
        supportedLocales: PostDeeLocalizations.supportedLocales,
        localizationsDelegates: const [
          PostDeeLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: Builder(builder: (context) {
          renders++;
          return Column(children: [
            Text(localizePublishSubmissionMessage(context, stored)),
            const Text(stored, key: ValueKey('raw-merchant-data')),
          ]);
        }),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text(stored), findsNWidgets(2));
    for (final language in ['en', 'vi', 'ja']) {
      locale.value = Locale(language);
      await tester.pumpAndSettle();
      expect(
          find.text(
              'Post received for 1 channel, delivery in progress: raw: ส่งสำเร็จ'),
          findsOneWidget);
      expect(find.text(stored), findsOneWidget);
    }
    locale.value = const Locale('th');
    await tester.pumpAndSettle();
    expect(find.text(stored), findsNWidgets(2));
    expect(renders, greaterThan(1));
    expect(
        tester
            .widget<Text>(find.byKey(const ValueKey('raw-merchant-data')))
            .data,
        stored);
  });
}

const _knownMessages = <String, String>{
  'ระบบรับงานโพสต์ยังไม่เปิดใช้งานในขณะนี้':
      'Publishing is currently unavailable',
  'วิดีโอยังไม่ได้อัปโหลด กรุณาลองใหม่ภายหลัง':
      'The video has not been uploaded. Try again later.',
  'ยังไม่ได้สร้างโพสต์ และไฟล์วิดีโออาจถูกอัปโหลดไว้ชั่วคราว กรุณาลองใหม่ภายหลัง':
      'No post was created. The video may have been uploaded temporarily. Try again later.',
  'ระบบรับงานโพสต์ยังไม่เปิดใช้งาน กรุณาลองใหม่ภายหลัง':
      'Publishing is temporarily unavailable. Please try again later.',
  'อัปโหลด/คิวโพสต์ขัดข้อง': 'Upload or publishing queue issue',
  'รับทราบ': 'OK',
  'สัดส่วนวิดีโอไม่ใช่ 9:16': 'Video is not 9:16',
  'ใช้วิดีโอแนวตั้ง 9:16 เช่น 1080x1920':
      'Use a vertical 9:16 video, such as 1080x1920.',
  'เลือกวิดีโอใหม่': 'Choose another video',
  'ปิด': 'Close',
  'กลับไปตรวจสอบ': 'Go back and check',
  'เลือกวิดีโอจริงจากเครื่องก่อนโพสต์': 'Choose a local video before posting.',
  'ไม่พบไฟล์วิดีโอในเครื่อง': 'The video file was not found on this device.',
  'ไฟล์วิดีโอไม่ถูกต้อง เลือกคลิปใหม่อีกครั้ง':
      'The video file is invalid. Choose another video.',
  'เวลาตั้งโพสต์ต้องเป็นรูปแบบ ISO ที่ถูกต้อง':
      'The scheduled time must use a valid ISO format.',
  'เวลาตั้งโพสต์ต้องเป็นเวลาในอนาคต': 'The posting time must be in the future.',
  'ร่างนี้มีไฟล์อัปโหลดเดิมที่ยังไม่มีข้อมูลตรวจคลิป เก็บร่างไว้แล้ว กรุณาตรวจรายการโพสต์ก่อนเริ่มรายการใหม่':
      'This draft has an earlier upload without video check information. The draft has been kept. Check your post list before starting a new request.',
  'กำลังใส่ลายน้ำวิดีโอ...': 'Applying watermark...',
  'กำลังเตรียมวิดีโอ TikTok เป็น 30 FPS...':
      'Preparing TikTok video at 30 FPS...',
  'วิดีโอ TikTok ยังไม่ผ่านการตรวจ จึงหยุดก่อนอัปโหลด':
      'The TikTok video has not passed the checks. Upload was stopped.',
  'อ่านรายละเอียดคลิปไม่สำเร็จ ยังไม่ได้อัปโหลด กรุณาลองใหม่หรือเลือกคลิปอีกครั้ง':
      'Could not read the video details. Nothing was uploaded. Try again or choose the video again.',
  'ลิงก์อัปโหลดหมดอายุ กำลังลองใหม่...': 'The upload link expired. Retrying...',
  'กำลังอัปโหลดหน้าปก...': 'Uploading cover...',
  'บันทึกข้อมูลอัปโหลดไม่สำเร็จ กรุณาลองใหม่':
      'Could not save the upload information. Try again.',
  'รายการเดิมส่งไม่สำเร็จ เปิดรายละเอียดเพื่อตรวจสิ่งที่ต้องแก้ ร่างและข้อมูลอัปโหลดยังอยู่':
      'The original post was not sent. Open its details to see what needs fixing. The draft and upload information are still available.',
  'ระบบตอบสถานะโพสต์ที่ยังยืนยันไม่ได้ กรุณาตรวจรายการโพสต์ก่อนลองใหม่':
      'The returned post status is not confirmed. Check your post list before retrying.',
  'รายการโพสต์เดิมจบด้วยสถานะล้มเหลว ร่างยังอยู่ในเครื่อง กรุณาตรวจปลายทางก่อนเริ่มรายการโพสต์ใหม่':
      'The original post ended in failure. The draft is still on this device. Check the destinations before starting a new post request.',
  'ข้อมูลในร่างเปลี่ยนจากคำขอเดิม ร่างยังอยู่ในเครื่อง กรุณาตรวจปลายทางก่อนเริ่มรายการโพสต์ใหม่':
      'The draft has changed from the original request. The draft is still on this device. Check the destinations before starting a new post request.',
  'เชื่อมต่อ PostDee API ไม่ได้': 'Could not connect to PostDee.',
  'เกิดข้อผิดพลาดระหว่างสร้างโพสต์':
      'An error occurred while creating the post.',
  'ล้างไฟล์วิดีโอชั่วคราวไม่สำเร็จ กรุณาตรวจพื้นที่ว่างในเครื่อง':
      'Could not remove temporary video files. Check the free space on this device.',
  'ยังไม่ได้เลือกหน้าปก': 'No cover selected',
  'ยกเลิกการสร้างหน้าปกแล้ว': 'Cover creation was canceled.',
  'ไม่พบไฟล์วิดีโอสำหรับสร้างหน้าปก':
      'Video file not found. Choose your video again.',
  'ไม่พบรูปหน้าปก กรุณาเลือกรูปใหม่':
      'Cover image not found. Choose another image.',
  'สร้างภาพหน้าปกไม่สำเร็จ กรุณาลองเลือกเฟรมหรือรูปใหม่':
      'Could not create the cover image. Choose another frame or image.',
  'หยุดเตรียมวิดีโอ เพราะบัญชีหรือร่างเปลี่ยนแล้ว':
      'Video preparation stopped because the account or draft changed.',
  'หยุดเตรียมวิดีโอแล้ว': 'Video preparation stopped.',
  'อุปกรณ์นี้ยังเตรียมวิดีโอสำหรับ TikTok ไม่ได้ กรุณาใช้ไฟล์ H.264 30 FPS บนอุปกรณ์ที่รองรับ':
      'This device cannot prepare videos for TikTok. Use an H.264 30 FPS file on a supported device.',
  'ตรวจวิดีโอต้นฉบับไม่ได้ กรุณาเลือกไฟล์วิดีโอใหม่':
      'Could not check the original video. Choose another video file.',
  'วิดีโอยาวเกินระยะเวลาที่บัญชี TikTok นี้อนุญาต กรุณาเลือกคลิปที่สั้นลง':
      'This video exceeds the duration allowed by this TikTok account. Choose a shorter video.',
  'วิดีโอมีสัดส่วนกว้างหรือสูงเกินไป จึงปรับขนาดให้ TikTok รับไม่ได้ กรุณาเลือกวิดีโอใหม่':
      'This video is too wide or tall to resize for TikTok. Choose another video.',
  'เตรียมวิดีโอสำหรับ TikTok ไม่สำเร็จ ยังไม่ได้อัปโหลด กรุณาลองใหม่บนอุปกรณ์ที่รองรับ':
      'Could not prepare the video for TikTok. Nothing was uploaded. Try again on a supported device.',
  'วิดีโอที่แปลงยังไม่ผ่านการตรวจภาพ เสียง หรือ 30 FPS จึงหยุดก่อนอัปโหลด กรุณาเลือกวิดีโอใหม่หรือลองบนอุปกรณ์ที่รองรับ':
      'The converted video did not pass video, audio, or 30 FPS checks. Upload was stopped. Choose another video or try a supported device.',
  'เตรียมวิดีโอสำหรับ TikTok ไม่สำเร็จ ยังไม่ได้อัปโหลด กรุณาลองใหม่':
      'Could not prepare the video for TikTok. Nothing was uploaded. Try again.',
  'ไม่พบไฟล์วิดีโอสำหรับใส่ลายน้ำ':
      'The video file for watermarking was not found.',
  'ใส่ลายน้ำแล้วแต่ไม่พบไฟล์ผลลัพธ์':
      'The watermark was applied, but the output file was not found.',
};
