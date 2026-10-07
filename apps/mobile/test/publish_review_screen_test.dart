import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postdee_mobile/features/platforms/social_platform.dart';
import 'package:postdee_mobile/features/uploader/cover_image_processor.dart';
import 'package:postdee_mobile/features/uploader/platform_publish_settings.dart';
import 'package:postdee_mobile/features/uploader/publish_review_screen.dart';

void main() {
  final previewBytes = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVQIHWP4z8DwHwAFgAI/ScLbtAAAAABJRU5ErkJggg==',
  );

  Future<void> pumpSummary(
    WidgetTester tester, {
    String? previewImagePath,
    Uint8List? previewImageBytes,
    CoverEditorResult? coverResult,
    String? videoAspectLabel = '9:16',
    List<SocialPlatform> platforms = const [SocialPlatform.tiktok],
    Map<SocialPlatform, String> connectionDisplayNames = const {
      SocialPlatform.tiktok: '@seller',
    },
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: PublishReviewSummary(
              videoName: 'seller-clip.mp4',
              caption: 'แคปชั่นขายสินค้า',
              platforms: platforms,
              connectionDisplayNames: connectionDisplayNames,
              scheduledAt: null,
              watermarkEnabled: false,
              previewImagePath: previewImagePath,
              previewImageBytes: previewImageBytes,
              videoAspectLabel: videoAspectLabel,
              coverResult: coverResult,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('summary shows a real poster without claiming a custom cover',
      (tester) async {
    await pumpSummary(tester, previewImageBytes: previewBytes);

    final image = tester.widget<Image>(
      find.byKey(const ValueKey('publish-review-preview-image')),
    );
    expect(image.image, isA<MemoryImage>());
    expect((image.image as MemoryImage).bytes, orderedEquals(previewBytes));
    expect(
        find.byKey(const ValueKey('publish-review-cover-image')), findsNothing);
    expect(
        find.byKey(const ValueKey('publish-review-cover-time')), findsNothing);
    expect(find.textContaining('หน้าปกเลือกจากวินาทีที่'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('summary accepts an existing poster file as a fallback',
      (tester) async {
    final directory = Directory.systemTemp.createTempSync('postdee-review-');
    addTearDown(() => directory.deleteSync(recursive: true));
    final poster = File('${directory.path}/poster.png')
      ..writeAsBytesSync(previewBytes);
    await pumpSummary(tester, previewImagePath: poster.path);

    final image = tester.widget<Image>(
      find.byKey(const ValueKey('publish-review-preview-image')),
    );
    expect(image.image, isA<FileImage>());
    expect((image.image as FileImage).file.path, poster.path);
    expect(
        find.byKey(const ValueKey('publish-review-cover-time')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('custom cover takes precedence over the clip poster',
      (tester) async {
    final coverBytes = Uint8List.fromList(previewBytes);
    final cover = CoverEditorResult(
      localImagePath: 'custom-cover.png',
      sizeBytes: coverBytes.length,
      design: const CoverDesign(coverFrameTimeMs: 3200),
      imageBytes: coverBytes,
    );
    await pumpSummary(
      tester,
      previewImageBytes: previewBytes,
      previewImagePath: 'poster.png',
      coverResult: cover,
    );

    final image = tester.widget<Image>(
      find.byKey(const ValueKey('publish-review-cover-image')),
    );
    expect((image.image as MemoryImage).bytes, same(coverBytes));
    expect(find.byKey(const ValueKey('publish-review-preview-image')),
        findsNothing);
    expect(find.text('หน้าปกเลือกจากวินาทีที่ 3.2'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('summary hides the aspect label when dimensions are unknown',
      (tester) async {
    await pumpSummary(tester, videoAspectLabel: null);
    expect(find.text('9:16'), findsNothing);

    await pumpSummary(tester, videoAspectLabel: '  ');
    expect(find.text('9:16'), findsNothing);

    await pumpSummary(tester, videoAspectLabel: '16:9');
    expect(find.text('16:9'), findsOneWidget);
    expect(find.text('9:16'), findsNothing);
  });

  testWidgets('empty destinations have a specific selection warning',
      (tester) async {
    await pumpSummary(tester, platforms: const []);
    expect(
      find.text('ยังไม่ได้เลือกช่องทาง กรุณากลับไปเลือกช่องทางก่อนโพสต์'),
      findsOneWidget,
    );
    expect(find.textContaining('ของบางช่องทางไม่ได้'), findsNothing);

    await pumpSummary(
      tester,
      platforms: const [SocialPlatform.shopeeVideo],
      connectionDisplayNames: const {SocialPlatform.shopeeVideo: 'seller'},
    );
    expect(
      find.text(
          'ยังยืนยันรูปแบบเผยแพร่ของบางช่องทางไม่ได้ กรุณากลับไปเลือกช่องทางใหม่'),
      findsOneWidget,
    );
    expect(find.textContaining('ยังไม่ได้เลือกช่องทาง'), findsNothing);
  });

  test('shared confirmation gate preserves destination and account checks', () {
    const settings = PlatformPublishSettings();
    expect(
      publishReviewCanConfirm(
        platforms: const [SocialPlatform.tiktok],
        platformSettings: settings,
        connectionDisplayNames: const {SocialPlatform.tiktok: '@seller'},
      ),
      isTrue,
    );
    expect(
      publishReviewCanConfirm(
        platforms: const [],
        platformSettings: settings,
        connectionDisplayNames: const {},
      ),
      isFalse,
    );
    expect(
      publishReviewCanConfirm(
        platforms: const [SocialPlatform.tiktok],
        platformSettings: settings,
        connectionDisplayNames: const {SocialPlatform.tiktok: '  '},
      ),
      isFalse,
    );
    expect(
      publishReviewCanConfirm(
        platforms: const [SocialPlatform.tiktok],
        platformSettings: const PlatformPublishSettings(
          tiktokPublishMode: TikTokPublishMode.directPost,
        ),
        connectionDisplayNames: const {SocialPlatform.tiktok: '@seller'},
      ),
      isFalse,
    );
    expect(
      publishReviewCanConfirm(
        platforms: const [SocialPlatform.youtubeShorts],
        platformSettings: settings,
        connectionDisplayNames: const {
          SocialPlatform.youtubeShorts: 'PostDee Channel',
        },
      ),
      isFalse,
    );
    expect(
      publishReviewCanConfirm(
        platforms: const [SocialPlatform.shopeeVideo],
        platformSettings: settings,
        connectionDisplayNames: const {SocialPlatform.shopeeVideo: 'seller'},
      ),
      isFalse,
    );
  });

  testWidgets('embedded summary has no route or duplicate confirmation',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: PublishReviewSummary(
              videoName: 'seller-clip.mp4',
              caption: 'แคปชั่นขายสินค้า',
              platforms: [SocialPlatform.tiktok],
              connectionDisplayNames: {SocialPlatform.tiktok: '@seller'},
              scheduledAt: null,
              watermarkEnabled: false,
            ),
          ),
        ),
      ),
    );

    expect(find.byType(Scaffold), findsOneWidget);
    expect(find.byType(AppBar), findsNothing);
    expect(find.byType(ListView), findsNothing);
    expect(find.byKey(const ValueKey('publish-review-confirm')), findsNothing);
    expect(find.text('กำหนดเวลา'), findsOneWidget);
    expect(find.text('ลายน้ำร้าน'), findsOneWidget);
    expect(find.textContaining('ส่งเป็นร่างเข้า TikTok'), findsOneWidget);
  });

  testWidgets('hiding schedule keeps provider timing and watermark truthful',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: PublishReviewSummary(
              videoName: 'seller-clip.mp4',
              caption: 'แคปชั่นขายสินค้า',
              platforms: const [SocialPlatform.tiktok],
              connectionDisplayNames: const {SocialPlatform.tiktok: '@seller'},
              scheduledAt: DateTime(2026, 8, 15, 18, 30),
              watermarkEnabled: false,
              showSchedule: false,
            ),
          ),
        ),
      ),
    );

    expect(find.text('กำหนดเวลา'), findsNothing);
    expect(find.text('ลายน้ำร้าน'), findsOneWidget);
    expect(find.text('ปิด · TikTok ไม่รับลายน้ำ PostDee'), findsOneWidget);
    expect(find.textContaining('ส่งเข้าร่างเวลา'), findsOneWidget);
    expect(find.textContaining('ส่งออกจริงและใช้โควตาโพสต์'), findsOneWidget);
  });

  testWidgets('summary edit actions return to their own form sections',
      (tester) async {
    var videoEdits = 0;
    var captionEdits = 0;
    var platformEdits = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: PublishReviewSummary(
              videoName: 'seller-clip.mp4',
              caption: 'แคปชั่นขายสินค้า',
              platforms: const [SocialPlatform.tiktok],
              connectionDisplayNames: const {SocialPlatform.tiktok: '@seller'},
              scheduledAt: null,
              watermarkEnabled: false,
              onEditVideo: () => videoEdits += 1,
              onEditCaption: () => captionEdits += 1,
              onEditPlatforms: () => platformEdits += 1,
            ),
          ),
        ),
      ),
    );

    for (final section in ['video', 'caption', 'platforms']) {
      final edit = find.byKey(ValueKey('publish-review-edit-$section'));
      await tester.ensureVisible(edit);
      await tester.tap(edit);
    }
    expect(videoEdits, 1);
    expect(captionEdits, 1);
    expect(platformEdits, 1);
    expect(find.byType(PublishReviewScreen), findsNothing);
    expect(find.byKey(const ValueKey('publish-review-confirm')), findsNothing);
  });

  testWidgets('editable embedded summary fits narrow phones with large text',
      (tester) async {
    tester.view.physicalSize = const Size(320, 740);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: MediaQueryData.fromView(tester.view).copyWith(
            textScaler: const TextScaler.linear(2),
          ),
          child: Scaffold(
            body: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: PublishReviewSummary(
                videoName: 'seller-clip-with-a-very-long-name.mp4',
                caption: 'แคปชั่นขายสินค้าที่ยาวเพื่อทดสอบหน้าจอขนาดเล็ก',
                platforms: const [SocialPlatform.tiktok],
                connectionDisplayNames: const {
                  SocialPlatform.tiktok: '@postdee-long-seller-account',
                },
                scheduledAt: DateTime(2026, 8, 15, 18, 30),
                watermarkEnabled: false,
                onEditVideo: () {},
                onEditCaption: () {},
                onEditPlatforms: () {},
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    for (final section in ['video', 'caption', 'platforms']) {
      final edit = find.byKey(ValueKey('publish-review-edit-$section'));
      await tester.ensureVisible(edit);
      await tester.tap(edit);
      await tester.pump();
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('standalone review still returns explicit confirmation',
      (tester) async {
    bool? confirmed;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                confirmed = await Navigator.of(context).push<bool>(
                  MaterialPageRoute<bool>(
                    builder: (_) => const PublishReviewScreen(
                      videoName: 'seller-clip.mp4',
                      caption: 'แคปชั่นขายสินค้า',
                      platforms: [SocialPlatform.tiktok],
                      connectionDisplayNames: {
                        SocialPlatform.tiktok: '@seller',
                      },
                      scheduledAt: null,
                      watermarkEnabled: false,
                    ),
                  ),
                );
              },
              child: const Text('เปิดตรวจทาน'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('เปิดตรวจทาน'));
    await tester.pumpAndSettle();
    expect(confirmed, isNull);
    await tester.tap(find.byKey(const ValueKey('publish-review-confirm')));
    await tester.pumpAndSettle();

    expect(confirmed, isTrue);
    expect(find.byType(PublishReviewScreen), findsNothing);
    expect(find.text('เปิดตรวจทาน'), findsOneWidget);
  });

  testWidgets('shows the current publish outcome for all four destinations',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: PublishReviewScreen(
          videoName: 'seller-clip.mp4',
          caption: 'แคปชั่นขายสินค้า',
          platforms: [
            SocialPlatform.tiktok,
            SocialPlatform.youtubeShorts,
            SocialPlatform.instagramReels,
            SocialPlatform.facebookReels,
          ],
          platformSettings: PlatformPublishSettings(
            youtubeTitle: 'คลิปขายสินค้า',
            youtubeMadeForKids: false,
            youtubeContainsSyntheticMedia: false,
            youtubeCommunityGuidelinesCertified: true,
            facebookPublishMode: FacebookPublishMode.pageDraft,
          ),
          connectionDisplayNames: {
            SocialPlatform.tiktok: '@seller',
            SocialPlatform.youtubeShorts: 'PostDee Channel',
            SocialPlatform.instagramReels: '@postdee.shop',
            SocialPlatform.facebookReels: 'PostDee Page',
          },
          scheduledAt: null,
          watermarkEnabled: false,
        ),
      ),
    );

    expect(
      find.textContaining('ส่งเป็นร่างเข้า TikTok'),
      findsOneWidget,
    );
    expect(find.textContaining('ส่งออกจริงและใช้โควตาโพสต์'), findsNWidgets(2));
    expect(find.text('ส่วนตัว (Private)'), findsOneWidget);
    expect(find.text('เผยแพร่ตามบัญชี'), findsOneWidget);
    expect(find.text('Facebook Page Video'), findsOneWidget);
    expect(find.text('@seller'), findsOneWidget);
    expect(find.text('PostDee Channel'), findsOneWidget);
    expect(find.textContaining('เก็บเป็นร่างบนเพจ'), findsOneWidget);

    final confirm = tester.widget<FilledButton>(
      find.byKey(const ValueKey('publish-review-confirm')),
    );
    expect(confirm.onPressed, isNotNull);
  });

  testWidgets('shows the exact YouTube and Facebook choices', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: PublishReviewScreen(
          videoName: 'seller-clip.mp4',
          caption: 'แคปชั่นขายสินค้า',
          platforms: [
            SocialPlatform.youtubeShorts,
            SocialPlatform.facebookReels,
          ],
          platformSettings: PlatformPublishSettings(
            youtubeTitle: 'คลิปขายสินค้า',
            youtubeVisibility: YouTubeVisibility.unlisted,
            youtubeMadeForKids: false,
            youtubeContainsSyntheticMedia: true,
            youtubeCommunityGuidelinesCertified: true,
            facebookPublishMode: FacebookPublishMode.publish,
          ),
          connectionDisplayNames: {
            SocialPlatform.youtubeShorts: 'PostDee Channel',
            SocialPlatform.facebookReels: 'PostDee Page',
          },
          scheduledAt: null,
          watermarkEnabled: false,
        ),
      ),
    );

    expect(find.text('ไม่เป็นสาธารณะ (Unlisted)'), findsOneWidget);
    expect(find.text('เผยแพร่บนเพจ'), findsOneWidget);
  });

  testWidgets('blocks unsupported TikTok direct mode', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: PublishReviewScreen(
          videoName: 'seller-clip.mp4',
          caption: 'แคปชั่นขายสินค้า',
          platforms: [SocialPlatform.tiktok],
          platformSettings: PlatformPublishSettings(
            tiktokPublishMode: TikTokPublishMode.directPost,
          ),
          connectionDisplayNames: {
            SocialPlatform.tiktok: '@seller',
          },
          scheduledAt: null,
          watermarkEnabled: false,
        ),
      ),
    );

    expect(find.text('ยังไม่พร้อมโพสต์ตรง'), findsOneWidget);
    final confirm = tester.widget<FilledButton>(
      find.byKey(const ValueKey('publish-review-confirm')),
    );
    expect(confirm.onPressed, isNull);
  });

  testWidgets('blocks incomplete YouTube compliance answers', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: PublishReviewScreen(
          videoName: 'seller-clip.mp4',
          caption: 'แคปชั่นขายสินค้า',
          platforms: [SocialPlatform.youtubeShorts],
          connectionDisplayNames: {
            SocialPlatform.youtubeShorts: 'PostDee Channel',
          },
          scheduledAt: null,
          watermarkEnabled: false,
        ),
      ),
    );

    expect(find.text('ตั้งค่า YouTube ยังไม่ครบ'), findsOneWidget);
    final confirm = tester.widget<FilledButton>(
      find.byKey(const ValueKey('publish-review-confirm')),
    );
    expect(confirm.onPressed, isNull);
  });

  testWidgets('uses send-to-draft wording for a scheduled provider draft',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: PublishReviewScreen(
          videoName: 'seller-clip.mp4',
          caption: 'แคปชั่นขายสินค้า',
          platforms: const [SocialPlatform.tiktok],
          connectionDisplayNames: const {
            SocialPlatform.tiktok: '@seller',
          },
          scheduledAt: DateTime(2026, 8, 15, 18, 30),
          watermarkEnabled: false,
        ),
      ),
    );

    expect(find.textContaining('ส่งเข้าร่างเวลา'), findsOneWidget);
    expect(find.textContaining('เผยแพร่เวลา'), findsNothing);
  });

  testWidgets('blocks confirmation when a destination has no known outcome',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: PublishReviewScreen(
          videoName: 'seller-clip.mp4',
          caption: 'แคปชั่นขายสินค้า',
          platforms: [SocialPlatform.shopeeVideo],
          connectionDisplayNames: {
            SocialPlatform.shopeeVideo: 'seller-1',
          },
          scheduledAt: null,
          watermarkEnabled: false,
        ),
      ),
    );

    expect(find.text('ยังไม่ทราบรูปแบบเผยแพร่'), findsOneWidget);
    expect(
      find.text(
        'ยังยืนยันรูปแบบเผยแพร่ของบางช่องทางไม่ได้ กรุณากลับไปเลือกช่องทางใหม่',
      ),
      findsOneWidget,
    );

    final confirm = tester.widget<FilledButton>(
      find.byKey(const ValueKey('publish-review-confirm')),
    );
    expect(confirm.onPressed, isNull);
  });

  testWidgets('blocks confirmation when target account identity is missing',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: PublishReviewScreen(
          videoName: 'seller-clip.mp4',
          caption: 'แคปชั่นขายสินค้า',
          platforms: [SocialPlatform.tiktok],
          scheduledAt: null,
          watermarkEnabled: false,
        ),
      ),
    );

    expect(find.text('ยังยืนยันบัญชีปลายทางไม่ได้'), findsOneWidget);
    expect(find.textContaining('รีเฟรชหรือเชื่อมต่อใหม่'), findsOneWidget);
    final confirm = tester.widget<FilledButton>(
      find.byKey(const ValueKey('publish-review-confirm')),
    );
    expect(confirm.onPressed, isNull);
  });

  testWidgets('summary remains readable on a narrow phone with large text',
      (tester) async {
    tester.view.physicalSize = const Size(393, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: MediaQueryData.fromView(tester.view).copyWith(
            textScaler: const TextScaler.linear(2),
          ),
          child: PublishReviewScreen(
            videoName: 'seller-clip-with-a-very-long-name.mp4',
            caption: 'แคปชั่นขายสินค้าที่ยาวเพื่อทดสอบหน้าจอขนาดเล็ก',
            platforms: const [SocialPlatform.tiktok],
            connectionDisplayNames: const {
              SocialPlatform.tiktok: '@postdee-long-seller-account',
            },
            scheduledAt: DateTime(2026, 8, 15, 18, 30),
            watermarkEnabled: false,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.fling(
      find.byType(ListView),
      const Offset(0, -1400),
      1200,
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('กำหนดเวลา'), findsOneWidget);
    expect(find.text('ลายน้ำร้าน'), findsOneWidget);
    expect(
        find.byKey(const ValueKey('publish-review-confirm')), findsOneWidget);
  });
}
