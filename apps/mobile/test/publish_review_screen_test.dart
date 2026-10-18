import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
    PlatformPublishSettings platformSettings = const PlatformPublishSettings(),
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: PublishReviewSummary(
              videoName: 'seller-clip.mp4',
              caption: 'แคปชั่นขายสินค้า',
              platforms: platforms,
              platformSettings: platformSettings,
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

  testWidgets('YouTube review shows the title and every explicit answer',
      (tester) async {
    await pumpSummary(
      tester,
      platforms: const [SocialPlatform.youtubeShorts],
      connectionDisplayNames: const {
        SocialPlatform.youtubeShorts: 'Seller channel',
      },
      platformSettings: const PlatformPublishSettings(
        youtubeTitle: 'รีวิวสินค้าจากร้านเรา',
        youtubeVisibility: YouTubeVisibility.public,
        youtubeMadeForKids: true,
        youtubeContainsSyntheticMedia: false,
        youtubeCommunityGuidelinesCertified: true,
      ),
    );
    expect(find.text('ชื่อวิดีโอ: รีวิวสินค้าจากร้านเรา'), findsOneWidget);
    expect(find.text('สาธารณะ (Public)'), findsOneWidget);
    expect(find.text('สำหรับเด็ก: ใช่'), findsOneWidget);
    expect(find.text('สื่อสังเคราะห์ที่ดูเหมือนจริง: ไม่มี'), findsOneWidget);
    expect(find.text('กฎชุมชน YouTube: ยืนยันแล้ว'), findsOneWidget);
    expect(find.byKey(const ValueKey('publish-review-youtube-notice')),
        findsOneWidget);
    expect(find.textContaining('ลิขสิทธิ์หรือความเป็นส่วนตัว'), findsOneWidget);
  });

  testWidgets('YouTube review never presents unanswered choices as accepted',
      (tester) async {
    await pumpSummary(
      tester,
      platforms: const [SocialPlatform.youtubeShorts],
      connectionDisplayNames: const {
        SocialPlatform.youtubeShorts: 'Seller channel',
      },
    );
    expect(find.text('ชื่อวิดีโอ: แคปชั่นขายสินค้า'), findsOneWidget);
    expect(find.text('สำหรับเด็ก: ยังไม่ระบุ'), findsOneWidget);
    expect(
        find.text('สื่อสังเคราะห์ที่ดูเหมือนจริง: ยังไม่ระบุ'), findsOneWidget);
    expect(find.text('กฎชุมชน YouTube: ยังไม่ยืนยัน'), findsOneWidget);
    expect(find.text('ตั้งค่า YouTube ยังไม่ครบ'), findsOneWidget);
  });

  testWidgets('Instagram review distinguishes feed sharing from Reels only',
      (tester) async {
    for (final share in [true, false]) {
      await pumpSummary(
        tester,
        platforms: const [SocialPlatform.instagramReels],
        connectionDisplayNames: const {
          SocialPlatform.instagramReels: '@seller',
        },
        platformSettings: PlatformPublishSettings(instagramShareToFeed: share),
      );
      expect(
        find.text(
            '${share ? 'Reels + ฟีด' : 'Reels อย่างเดียว'} · เผยแพร่ตามบัญชี'),
        findsOneWidget,
      );
      expect(find.textContaining('Instagram ไม่มี Private รายโพสต์'),
          findsOneWidget);
      expect(find.byKey(const ValueKey('publish-review-youtube-notice')),
          findsNothing);
    }
  });

  testWidgets('Meta review shows explicit AI answers and optional omissions',
      (tester) async {
    for (final answer in <bool?>[true, false, null]) {
      await pumpSummary(
        tester,
        platforms: const [
          SocialPlatform.instagramReels,
          SocialPlatform.facebookReels,
        ],
        connectionDisplayNames: const {
          SocialPlatform.instagramReels: '@seller.instagram',
          SocialPlatform.facebookReels: 'Seller Page',
        },
        platformSettings: PlatformPublishSettings(
          instagramIsAiGenerated: answer,
          facebookIsAiGenerated: answer,
          facebookPublishMode: FacebookPublishMode.publish,
        ),
      );
      final label = answer == null
          ? 'ยังไม่ระบุ (ไม่บังคับ)'
          : answer
              ? 'ใช่'
              : 'ไม่ใช่';
      expect(find.text('สร้างโดย AI: $label'), findsNWidgets(2));
      expect(find.text('@seller.instagram'), findsOneWidget);
      expect(find.text('Seller Page'), findsOneWidget);
      expect(find.text('เผยแพร่บนเพจ'), findsOneWidget);
      expect(find.byKey(const ValueKey('publish-review-unknown-outcome')),
          findsNothing);
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('TikTok Direct review retains every publishing declaration',
      (tester) async {
    await pumpSummary(
      tester,
      platformSettings: const PlatformPublishSettings(
        tiktokPublishMode: TikTokPublishMode.directPost,
        tiktokPrivacyLevel: TikTokPrivacyLevel.publicToEveryone,
        tiktokCreatorInfoRevision:
            'aabbccddeeff00112233445566778899aabbccddeeff00112233445566778899',
        tiktokAllowComment: true,
        tiktokAllowDuet: false,
        tiktokAllowStitch: true,
        tiktokBrandContentToggle: true,
        tiktokBrandOrganicToggle: false,
        tiktokIsAigc: true,
        tiktokMusicUsageConfirmed: true,
        tiktokBrandedContentPolicyConfirmed: true,
        tiktokVideoDurationSeconds: 12,
      ),
    );
    expect(find.text('ความคิดเห็น: เปิด · Duet: ปิด · Stitch: เปิด'),
        findsOneWidget);
    expect(find.text('โปรโมตแบรนด์ตนเอง: ไม่ใช่'), findsOneWidget);
    expect(find.text('เนื้อหาที่มีผู้สนับสนุน: ใช่'), findsOneWidget);
    expect(find.text('สร้างโดย AI: ใช่'), findsOneWidget);
    expect(find.text('ข้อกำหนดการใช้เพลง TikTok: ยืนยันแล้ว'), findsOneWidget);
    expect(
        find.text('นโยบายเนื้อหาที่มีผู้สนับสนุน: ยืนยันแล้ว'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('YouTube terms opens the mobile terms URL without accepting',
      (tester) async {
    MethodCall? launched;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/url_launcher'),
      (call) async {
        launched = call;
        return true;
      },
    );
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('plugins.flutter.io/url_launcher'), null));
    await pumpSummary(
      tester,
      platforms: const [SocialPlatform.youtubeShorts],
      connectionDisplayNames: const {
        SocialPlatform.youtubeShorts: 'Seller channel',
      },
    );
    final terms = find.byKey(const ValueKey('publish-review-youtube-terms'));
    await tester.ensureVisible(terms);
    await tester.tap(terms);
    await tester.pumpAndSettle();
    expect(launched?.method, 'launch');
    expect((launched?.arguments as Map)['url'], 'https://m.youtube.com/terms');
    expect(find.text('กฎชุมชน YouTube: ยังไม่ยืนยัน'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('YouTube terms failure gives a visible recovery message',
      (tester) async {
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/url_launcher'),
      (_) async => throw PlatformException(code: 'not_available'),
    );
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('plugins.flutter.io/url_launcher'), null));
    await pumpSummary(
      tester,
      platforms: const [SocialPlatform.youtubeShorts],
      connectionDisplayNames: const {
        SocialPlatform.youtubeShorts: 'Seller channel',
      },
    );
    final terms = find.byKey(const ValueKey('publish-review-youtube-terms'));
    await tester.ensureVisible(terms);
    await tester.tap(terms);
    await tester.pumpAndSettle();
    expect(
        find.textContaining('เปิดข้อกำหนด YouTube ไม่สำเร็จ'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('complete channel details fit a narrow phone with large text',
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
                videoName: 'seller-clip.mp4',
                caption: 'แคปชั่นขายสินค้า',
                platforms: const [
                  SocialPlatform.youtubeShorts,
                  SocialPlatform.instagramReels,
                  SocialPlatform.facebookReels,
                ],
                platformSettings: PlatformPublishSettings(
                  youtubeTitle: '😀' * 100,
                  youtubeMadeForKids: false,
                  youtubeContainsSyntheticMedia: true,
                  youtubeCommunityGuidelinesCertified: true,
                  facebookPublishMode: FacebookPublishMode.pageDraft,
                ),
                connectionDisplayNames: const {
                  SocialPlatform.youtubeShorts: 'Seller channel',
                  SocialPlatform.instagramReels: '@seller',
                  SocialPlatform.facebookReels: 'Seller page',
                },
                scheduledAt: null,
                watermarkEnabled: false,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.ensureVisible(
        find.byKey(const ValueKey('publish-review-youtube-terms')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  test('scheduled Facebook drafts keep the Page destination and quota wording',
      () {
    final outcome = publishReviewOutcomeFor(
      SocialPlatform.facebookReels,
      settings: const PlatformPublishSettings(
          facebookPublishMode: FacebookPublishMode.pageDraft),
      scheduledAt: DateTime(2026, 10, 20, 15, 30),
    );
    expect(outcome, contains('ส่งเข้าร่างเวลา'));
    expect(outcome, contains('Facebook Page'));
    expect(outcome, contains('ส่งออกจริงและใช้โควตาโพสต์'));
    expect(outcome, isNot(contains('เผยแพร่เวลา')));
    expect(publishReviewPlatformLabel(SocialPlatform.facebookReels),
        'Facebook Page Video');
  });

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
    expect(find.text('Reels + ฟีด · เผยแพร่ตามบัญชี'), findsOneWidget);
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
    expect(find.text('ชื่อวิดีโอ: คลิปขายสินค้า'), findsOneWidget);
    expect(find.text('สำหรับเด็ก: ไม่ใช่'), findsOneWidget);
    expect(find.text('สื่อสังเคราะห์ที่ดูเหมือนจริง: มี'), findsOneWidget);
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
