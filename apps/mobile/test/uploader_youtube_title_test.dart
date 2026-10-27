import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postdee_mobile/core/network/postdee_api_client.dart';
import 'package:postdee_mobile/features/shared/growth_tool_settings_store.dart';
import 'package:postdee_mobile/features/uploader/publish_review_screen.dart';
import 'package:postdee_mobile/features/uploader/uploader_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _DelayedWatermarkSettings implements PostDeeGrowthToolSettingsStore {
  final loaded = Completer<GrowthToolSettings?>();

  @override
  Future<GrowthToolSettings?> loadSettings(String toolId) => loaded.future;

  @override
  Future<void> saveSettings(String toolId, GrowthToolSettings settings) async {}
}

Future<void> _show(WidgetTester tester, Finder finder) async {
  await tester.drag(find.byType(Scrollable).first, const Offset(0, 3000));
  await tester.pumpAndSettle();
  await tester.scrollUntilVisible(
    finder,
    250,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
}

Future<void> _caption(WidgetTester tester, String text) async {
  final field = find.byKey(const ValueKey('uploader-caption-field'));
  await _show(tester, field);
  await tester.enterText(field, text);
  await tester.pumpAndSettle();
}

Future<void> _editTitle(WidgetTester tester, String text) async {
  await _show(
      tester, find.byKey(const ValueKey('uploader-youtube-title-preview')));
  final edit = find.byKey(const ValueKey('uploader-youtube-title-edit'));
  if (edit.evaluate().isNotEmpty) {
    await _show(tester, edit);
    await tester.tap(edit);
    await tester.pumpAndSettle();
  }
  final field = find.byKey(const ValueKey('uploader-youtube-title-field'));
  await _show(tester, field);
  await tester.enterText(field, text);
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<void> pumpUploader(
    WidgetTester tester, {
    UploaderPostCreator? createPost,
    bool includeTikTok = false,
    PostDeeGrowthToolSettingsStore? growthToolSettingsStore,
  }) async {
    final directory = Directory.systemTemp.createTempSync('postdee-title-');
    final video = File('${directory.path}${Platform.pathSeparator}video.mp4')
      ..writeAsBytesSync([1, 2, 3]);
    addTearDown(() => directory.deleteSync(recursive: true));
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: UploaderScreen(
          initialVideoPath: video.path,
          initialVideoName: 'video.mp4',
          initialVideoSizeBytes: 3,
          loadSocialConnections: () async => [
            const SocialConnectionResult(
              platform: 'YOUTUBE_SHORTS',
              connected: true,
            ),
            if (includeTikTok)
              const SocialConnectionResult(platform: 'TIKTOK', connected: true),
          ],
          loadSubscription: () async => const SubscriptionStatusResult(
            userId: 'seller-pro',
            plan: 'PRO',
            status: 'ACTIVE',
            phoneVerified: true,
            requiresPhoneVerification: false,
            canUseFreePostQuota: false,
            canSchedule: true,
            canUseAiCaptions: true,
            canUseAnalytics: true,
          ),
          createUpload: (_) async => const UploadResult(
            id: 'upload-title',
            videoS3Key: 'uploads/title.mp4',
            storageProvider: 'mock',
          ),
          uploadVideoFile: (_, __) async {},
          createPost: createPost,
          growthToolSettingsStore: growthToolSettingsStore ??
              const SharedPreferencesGrowthToolSettingsStore(),
        ),
      ),
    ));
    await tester.pumpAndSettle();
  }

  Future<void> publish(WidgetTester tester) async {
    await tester.tap(find.byKey(const ValueKey('uploader-sticky-post-button')));
    await tester.pumpAndSettle();
    final confirm = find.byKey(const ValueKey('publish-review-confirm'));
    await tester.ensureVisible(confirm);
    await tester.tap(confirm);
    await tester.pumpAndSettle();
  }

  QueuedPostResult queued(CreatePostRequest request) => QueuedPostResult(
        id: 'post-title',
        videoS3Key: request.videoS3Key,
        platforms: request.platforms,
        status: 'QUEUED',
      );

  testWidgets('caption alone previews an automatic title and can publish',
      (tester) async {
    CreatePostRequest? sent;
    await pumpUploader(tester, createPost: (request) async {
      sent = request;
      return queued(request);
    });
    const caption = 'รีวิวของใช้วันนี้! รายละเอียดเพิ่มเติม\n#รีวิว #ของใช้';
    await _caption(tester, caption);
    final preview =
        find.byKey(const ValueKey('uploader-youtube-title-preview'));
    expect(tester.widget<Text>(preview).data, 'รีวิวของใช้วันนี้!');
    expect(find.byKey(const ValueKey('uploader-youtube-title-field')),
        findsNothing);
    await tester.tap(find.byKey(const ValueKey('uploader-sticky-post-button')));
    await tester.pumpAndSettle();
    expect(find.byType(PublishReviewScreen), findsOneWidget);
    expect(
      tester
          .widget<Text>(
              find.byKey(const ValueKey('publish-review-youtube-title')))
          .data,
      'รีวิวของใช้วันนี้!',
    );
    expect(find.text(caption), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('publish-review-confirm')));
    await tester.pumpAndSettle();
    expect(sent!.caption, caption);
    expect(sent!.youtubeTitle, isNull);
  });

  testWidgets(
      'publishes the reviewed text if background work changes the caption',
      (tester) async {
    CreatePostRequest? sent;
    await pumpUploader(tester, createPost: (request) async {
      sent = request;
      return queued(request);
    });
    await _caption(tester, 'ชื่อที่ตรวจทานแล้ว\nรายละเอียดเดิม');
    final controller = tester
        .widget<TextField>(
          find.byKey(const ValueKey('uploader-caption-field')),
        )
        .controller!;
    await tester.tap(find.byKey(const ValueKey('uploader-sticky-post-button')));
    await tester.pumpAndSettle();
    expect(find.byType(PublishReviewScreen), findsOneWidget);
    controller.text = 'แคปชันจาก AI ที่เพิ่งตอบกลับ\nรายละเอียดใหม่';
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('publish-review-confirm')));
    await tester.pumpAndSettle();
    expect(sent!.caption, 'ชื่อที่ตรวจทานแล้ว\nรายละเอียดเดิม');
    expect(sent!.youtubeTitle, isNull);
  });

  testWidgets('custom title survives caption changes and is sent separately',
      (tester) async {
    CreatePostRequest? sent;
    await pumpUploader(tester, createPost: (request) async {
      sent = request;
      return queued(request);
    });
    await _caption(tester, 'แคปชันเดิม\n#เดิม');
    final edit = find.byKey(const ValueKey('uploader-youtube-title-edit'));
    await _show(tester, edit);
    await tester.tap(edit);
    await tester.pumpAndSettle();
    final field = find.byKey(const ValueKey('uploader-youtube-title-field'));
    expect(tester.widget<TextField>(field).controller!.text, 'แคปชันเดิม');
    await _editTitle(tester, 'ชื่อสำหรับ YouTube');
    await _caption(tester, 'แคปชันใหม่\n#ใหม่');
    expect(
        tester.widget<TextField>(field).controller!.text, 'ชื่อสำหรับ YouTube');
    await publish(tester);
    expect(sent!.youtubeTitle, 'ชื่อสำหรับ YouTube');
    expect(sent!.caption, 'แคปชันใหม่\n#ใหม่');
  });

  testWidgets('reset restores a live automatic title after caption edits',
      (tester) async {
    await pumpUploader(tester);
    await _caption(tester, 'ชื่อเริ่มต้น');
    await _editTitle(tester, 'ชื่อที่กำหนดเอง');
    await _caption(tester, 'ชื่อจากแคปชันใหม่\n#แท็ก');
    final reset = find.byKey(const ValueKey('uploader-youtube-title-reset'));
    await _show(tester, reset);
    await tester.tap(reset);
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<Text>(
              find.byKey(const ValueKey('uploader-youtube-title-preview')))
          .data,
      'ชื่อจากแคปชันใหม่',
    );
    expect(find.byKey(const ValueKey('uploader-youtube-title-field')),
        findsNothing);
    await _caption(tester, 'อัปเดตตามแคปชันอีกครั้ง');
    expect(
      tester
          .widget<Text>(
              find.byKey(const ValueKey('uploader-youtube-title-preview')))
          .data,
      'อัปเดตตามแคปชันอีกครั้ง',
    );
  });

  testWidgets('YouTube-only can publish an explicit title without a caption',
      (tester) async {
    CreatePostRequest? sent;
    await pumpUploader(tester, createPost: (request) async {
      sent = request;
      return queued(request);
    });
    await _editTitle(tester, 'คลิปไม่มีคำอธิบาย');
    await publish(tester);
    expect(sent!.caption, '');
    expect(sent!.youtubeTitle, 'คลิปไม่มีคำอธิบาย');
  });

  testWidgets('a Thai caption over YouTube\'s byte limit blocks publishing',
      (tester) async {
    var posts = 0;
    await pumpUploader(tester, createPost: (request) async {
      posts++;
      return queued(request);
    });
    await _caption(tester, 'ก' * 1667);
    await tester.tap(find.byKey(const ValueKey('uploader-sticky-post-button')));
    await tester.pumpAndSettle();
    expect(find.byType(PublishReviewScreen), findsNothing);
    expect(
      find.text(
          'แคปชั่นยาวเกินที่ YouTube รับได้ (สูงสุด 5,000 ไบต์ ภาษาไทยราว 1,660 ตัวอักษร)'),
      findsOneWidget,
    );
    expect(posts, 0);
  });

  testWidgets('a caption over the platform limit blocks publishing',
      (tester) async {
    var posts = 0;
    await pumpUploader(tester, includeTikTok: true, createPost: (request) async {
      posts++;
      return queued(request);
    });
    await _caption(tester, 'ก' * 2201);
    await tester.tap(find.byKey(const ValueKey('uploader-sticky-post-button')));
    await tester.pumpAndSettle();
    expect(find.byType(PublishReviewScreen), findsNothing);
    expect(
      find.text('แคปชั่นต้องไม่เกิน 2,200 ตัวอักษร (ตอนนี้ 2,201)'),
      findsOneWidget,
    );
    expect(posts, 0);
  });

  testWidgets('blank caption still blocks a post to other platforms',
      (tester) async {
    await pumpUploader(tester, includeTikTok: true);
    await _editTitle(tester, 'ชื่อ YouTube อย่างเดียว');
    await tester.tap(find.byKey(const ValueKey('uploader-sticky-post-button')));
    await tester.pumpAndSettle();
    expect(find.byType(PublishReviewScreen), findsNothing);
    expect(find.text('เพิ่มแคปชั่นก่อนโพสต์'), findsOneWidget);
  });

  testWidgets('invalid custom title blocks publishing before upload',
      (tester) async {
    var posts = 0;
    await pumpUploader(tester, createPost: (request) async {
      posts++;
      return queued(request);
    });
    await _caption(tester, 'แคปชันที่ใช้ได้');
    await _editTitle(tester, '<ชื่อไม่ถูกต้อง>');
    await tester.tap(find.byKey(const ValueKey('uploader-sticky-post-button')));
    await tester.pumpAndSettle();
    expect(find.byType(PublishReviewScreen), findsNothing);
    expect(find.textContaining('ห้ามมีเครื่องหมาย'), findsWidgets);
    expect(posts, 0);
  });

  testWidgets('uses the current destination if it changes before review opens',
      (tester) async {
    CreatePostRequest? sent;
    final settings = _DelayedWatermarkSettings();
    await pumpUploader(
      tester,
      includeTikTok: true,
      growthToolSettingsStore: settings,
      createPost: (request) async {
        sent = request;
        return queued(request);
      },
    );
    await _caption(tester, 'แคปชันสำหรับ TikTok');
    await _editTitle(tester, 'ชื่อ YouTube');
    await tester.tap(find.byKey(const ValueKey('uploader-sticky-post-button')));
    await tester.pump();
    final youtube =
        find.byKey(const ValueKey('uploader-platform-YOUTUBE_SHORTS'));
    await _show(tester, youtube);
    await tester.tap(youtube);
    settings.loaded.complete(null);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('publish-review-youtube-title')),
        findsNothing);
    await tester.tap(find.byKey(const ValueKey('publish-review-confirm')));
    await tester.pumpAndSettle();
    expect(sent!.platforms, ['TIKTOK']);
    expect(sent!.youtubeTitle, isNull);
  });

  testWidgets('deselecting YouTube hides and omits the custom title',
      (tester) async {
    CreatePostRequest? sent;
    await pumpUploader(tester, includeTikTok: true,
        createPost: (request) async {
      sent = request;
      return queued(request);
    });
    await _caption(tester, 'แคปชัน TikTok');
    await _editTitle(tester, 'เฉพาะ YouTube');
    final youtube =
        find.byKey(const ValueKey('uploader-platform-YOUTUBE_SHORTS'));
    await _show(tester, youtube);
    await tester.tap(youtube);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('uploader-youtube-title-preview')),
        findsNothing);
    await publish(tester);
    expect(sent!.platforms, ['TIKTOK']);
    expect(sent!.youtubeTitle, isNull);
  });
}
