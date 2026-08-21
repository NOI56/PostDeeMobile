import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postdee_mobile/features/platforms/social_platform.dart';
import 'package:postdee_mobile/features/uploader/platform_publish_settings.dart';
import 'package:postdee_mobile/features/uploader/publish_review_screen.dart';

void main() {
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
