import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postdee_mobile/core/auth/auth_session.dart';
import 'package:postdee_mobile/core/network/postdee_api_client.dart';
import 'package:postdee_mobile/features/platforms/social_platform.dart';
import 'package:postdee_mobile/features/uploader/platform_publish_settings.dart';
import 'package:postdee_mobile/features/uploader/publish_draft.dart';
import 'package:postdee_mobile/features/uploader/publish_flow_screen.dart';
import 'package:postdee_mobile/features/uploader/publish_review_screen.dart';
import 'package:postdee_mobile/features/uploader/tiktok_video_preparer.dart';
import 'package:postdee_mobile/features/uploader/uploader_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'uploader_channels_english_test.dart'
    show
        ChannelsEnglishFixture,
        channelEnglishConnections,
        channelEnglishRow,
        channelEnglishTap,
        channelEnglishIsSelected;
import 'uploader_video_english_test.dart'
    show
        videoEnglishOwner,
        tapVideoEnglishControl,
        revealVideoEnglishControl,
        expectVideoEnglishReadable;

const reviewEnglishSettings = PlatformPublishSettings(
    youtubeTitle: 'ชื่อวิดีโอที่ลูกค้าตั้งเอง',
    youtubeVisibility: YouTubeVisibility.private,
    youtubeMadeForKids: false,
    youtubeContainsSyntheticMedia: false,
    youtubeCommunityGuidelinesCertified: true,
    instagramShareToFeed: false,
    instagramIsAiGenerated: false,
    facebookPublishMode: FacebookPublishMode.pageDraft,
    facebookIsAiGenerated: true);

class ReviewEnglishFixture extends ChannelsEnglishFixture {
  ReviewEnglishFixture({super.locale, super.dark, super.scale}) {
    connections = [channelEnglishConnections.first];
  }

  DateTime clock = DateTime(2026, 10, 30, 9);
  DateTime? suggestedScheduleDate;
  int subscriptionReads = 0;
  int availabilityChecks = 0;
  int preparations = 0;
  Object? subscriptionError;
  Object? availabilityError;
  Future<SubscriptionStatusResult>? subscriptionGate;
  Future<void>? availabilityGate;
  bool allowFakePublish = false;
  bool viewReadOnly = false;
  bool bareMaterialApp = false;
  final uploads = <CreateUploadRequest>[];
  final uploadedPaths = <String>[];
  final posts = <CreatePostRequest>[];

  @override
  Widget app() => bareMaterialApp
      ? MaterialApp(home: Scaffold(body: screen()))
      : super.app();

  @override
  UploaderScreen screen() {
    final base = super.screen();
    return UploaderScreen(
      fullScreen: true,
      draftStore: store,
      enableRevenueCatBilling: false,
      initialDraftId: initialDraftId,
      initialVideoPath: initialDraftId == null ? base.initialVideoPath : null,
      initialVideoName: base.initialVideoName,
      initialVideoSizeBytes: base.initialVideoSizeBytes,
      initialVideoWidth: base.initialVideoWidth,
      initialVideoHeight: base.initialVideoHeight,
      initialVideoDurationSeconds: base.initialVideoDurationSeconds,
      initialScheduleDate: suggestedScheduleDate,
      now: () => clock,
      pickVideo: base.pickVideo,
      readVideoMetadata: base.readVideoMetadata,
      probePublishMedia: base.probePublishMedia,
      loadTemplates: base.loadTemplates,
      loadPostQuota: base.loadPostQuota,
      loadCaptionQuota: base.loadCaptionQuota,
      loadSocialConnections: base.loadSocialConnections,
      loadSocialPublishingReadiness: base.loadSocialPublishingReadiness,
      generateRealClipCaption: base.generateRealClipCaption,
      loadSubscription: () async {
        subscriptionReads++;
        if (subscriptionError != null) throw subscriptionError!;
        return subscriptionGate == null ? quota : await subscriptionGate!;
      },
      checkPublishingReadiness: () async {
        availabilityChecks++;
        if (availabilityError != null) throw availabilityError!;
        if (availabilityGate != null) await availabilityGate!;
      },
      prepareTikTokVideo: (request) async {
        preparations++;
        expect(allowFakePublish, isTrue, reason: 'Unexpected fake preparation');
        return TikTokPreparedVideoResult(
            file: request.inputFile,
            fileName: request.fileName,
            sizeBytes: request.inputFile.lengthSync(),
            width: 1080,
            height: 1920,
            durationSeconds: initialVideo?.durationSeconds ?? 10);
      },
      createUpload: (request) async {
        expect(allowFakePublish, isTrue, reason: 'Unexpected fake upload');
        uploads.add(request);
        return UploadResult(
            id: 'fake-upload-${uploads.length}',
            videoS3Key: 'uploads/$videoEnglishOwner/review.mp4',
            storageProvider: 'mock');
      },
      uploadVideoFile: (_, file) async {
        expect(allowFakePublish, isTrue, reason: 'Unexpected fake file upload');
        uploadedPaths.add(file.path);
      },
      createPost: (request) async {
        expect(allowFakePublish, isTrue, reason: 'Unexpected fake post');
        posts.add(request);
        return QueuedPostResult(
            id: 'fake-review-post',
            status: 'QUEUED',
            videoS3Key: request.videoS3Key,
            platforms: request.platforms);
      },
    );
  }

  Future<void> seed({
    Set<String> platforms = const {
      'TIKTOK',
      'YOUTUBE_SHORTS',
      'INSTAGRAM_REELS',
      'FACEBOOK_REELS'
    },
    PlatformPublishSettings settings = reviewEnglishSettings,
    DateTime? scheduledAt,
    String caption = 'แคปชันลูกค้าต้องคงเดิม #สินค้า',
  }) async {
    final video = initialVideo!;
    await store.saveDraft(PublishDraftSaveRequest(
      id: 'review-restored',
      createdAt: clock.toUtc(),
      updatedAt: clock.toUtc(),
      videoFile: File(video.path),
      videoName: video.name,
      videoSizeBytes: video.sizeBytes,
      videoWidth: video.width,
      videoHeight: video.height,
      caption: caption,
      aiGuidance: 'คำแนะนำลูกค้าต้องคงเดิม',
      watermarkEnabled: false,
      platformApiValues: platforms,
      platformSettings: settings,
      scheduledAt: scheduledAt,
    ));
    store.savedRequests.clear();
    initialDraftId = 'review-restored';
    connections = List.of(channelEnglishConnections);
  }

  @override
  Future<void> mount(WidgetTester tester, {bool settle = true}) async {
    if (initialDraftId == null) {
      await super.mount(tester, settle: settle);
      await channelEnglishTap(tester, channelEnglishRow('TIKTOK'));
    } else {
      await tester.pumpWidget(app());
      await tester.pumpAndSettle();
      await tapVideoEnglishControl(tester, 'uploader-progress-1');
      await tapVideoEnglishControl(tester, 'uploader-wizard-next');
      if (!viewReadOnly &&
          store.drafts[initialDraftId]!.platformApiValues
              .contains('YOUTUBE_SHORTS')) {
        await tapVideoEnglishControl(
            tester, 'uploader-platform-settings-YOUTUBE_SHORTS');
        final certification =
            find.byKey(const ValueKey('uploader-youtube-guidelines-certified'));
        expect(tester.widget<CheckboxListTile>(certification).value, isFalse);
        final checkbox =
            find.descendant(of: certification, matching: find.byType(Checkbox));
        await tester.ensureVisible(checkbox);
        await tester.pumpAndSettle();
        await tester.tap(checkbox);
        await tester.pumpAndSettle();
        await tapVideoEnglishControl(tester, 'uploader-platform-settings-save');
      }
    }
    await tapVideoEnglishControl(
        tester, viewReadOnly ? 'uploader-progress-3' : 'uploader-wizard-next');
    expect(find.byKey(const ValueKey('uploader-step-review')), findsOneWidget,
        reason: tester
            .widgetList<Text>(find.byType(Text))
            .map((text) => text.data ?? text.textSpan?.toPlainText() ?? '')
            .take(80)
            .join('\n'));
    expect(
        tester
            .widget<FilledButton>(
                find.byKey(const ValueKey('publish-review-confirm')))
            .onPressed,
        viewReadOnly ? isNull : isNotNull);
  }
}

Future<void> reviewEnglishReadable(WidgetTester tester, String value) async {
  final text = find.text(value);
  await revealVideoEnglishControl(tester, text);
  expectVideoEnglishReadable(tester, text);
}

Future<void> revealReviewEnglishSummary(WidgetTester tester) =>
    revealVideoEnglishControl(tester, find.byType(PublishReviewSummary));

void reviewEnglishNoSend(ReviewEnglishFixture fixture) {
  expect(fixture.posts, isEmpty);
  expect(fixture.uploads, isEmpty);
  expect(fixture.uploadedPaths, isEmpty);
  expect(fixture.preparations, 0);
  expect(fixture.apiWrites, 0);
}

void main() {
  late AuthSession previous;
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    previous = PostDeeAuthSessionStore.instance.session;
    PostDeeAuthSessionStore.instance
        .signIn(const AuthSession(userId: videoEnglishOwner));
  });
  tearDown(() => PostDeeAuthSessionStore.instance.signIn(previous));

  testWidgets(
      'English Review explains the final step and preserves seller data',
      (tester) async {
    final fixture = ReviewEnglishFixture();
    addTearDown(fixture.dispose);
    await fixture.mount(tester);
    expect(find.text('Review your details and choose when to post.'),
        findsOneWidget);
    await revealReviewEnglishSummary(tester);
    expect(find.text('แคปชันลูกค้าต้องคงเดิม #สินค้า'), findsOneWidget);
    expect(find.text(channelEnglishConnections.first.displayName!),
        findsOneWidget);
    expect(find.text('คลิปเลือกช่องทาง.mp4'), findsOneWidget);
    expect(fixture.store.savedRequests, isEmpty);
    expect(fixture.apiWrites, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('foreground review notice follows locale without another read',
      (tester) async {
    final fixture = ReviewEnglishFixture(locale: const Locale('th'));
    addTearDown(fixture.dispose);
    await fixture.mount(tester);
    expect(
        find.text(
            'ระหว่างเตรียมและส่งข้อมูล กรุณาเปิดแอปหน้านี้ไว้ ยังยกเลิกไม่ได้จนจบขั้นตอน'),
        findsOneWidget);
    final connections = fixture.connectionReads;
    final readiness = fixture.readinessReads;
    fixture.language.value = const Locale('en');
    await tester.pumpAndSettle();
    expect(
        find.text(
            'Keep this screen open while your post is being prepared and sent. You cannot cancel until this step finishes.'),
        findsOneWidget);
    await revealReviewEnglishSummary(tester);
    expect(find.text('แคปชันลูกค้าต้องคงเดิม #สินค้า'), findsOneWidget);
    expect(fixture.connectionReads, connections);
    expect(fixture.readinessReads, readiness);
    expect(fixture.apiWrites, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'English review summary identifies the destination before any send',
      (tester) async {
    final fixture = ReviewEnglishFixture();
    addTearDown(fixture.dispose);
    await fixture.mount(tester);
    await revealReviewEnglishSummary(tester);
    expect(
        find.descendant(
            of: find.byType(PublishReviewSummary),
            matching: find.text('Caption')),
        findsOneWidget);
    expect(find.text('Preview'), findsOneWidget);
    expect(find.text('Post to 1 channel'), findsOneWidget);
    expect(find.text('Confirm send to 1 channel'), findsOneWidget);
    expect(fixture.connectionReads, 1);
    expect(fixture.readinessReads, 1);
    expect(fixture.store.savedRequests, isEmpty);
    expect(fixture.apiWrites, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Edit destinations returns to chosen channels without sending',
      (tester) async {
    final fixture = ReviewEnglishFixture();
    addTearDown(fixture.dispose);
    await fixture.mount(tester);
    await tapVideoEnglishControl(tester, 'publish-review-edit-platforms');
    expect(
        find.byKey(const ValueKey('uploader-step-platforms')), findsOneWidget);
    expect(channelEnglishIsSelected(tester, 'TIKTOK'), isTrue);
    await tapVideoEnglishControl(tester, 'uploader-wizard-next');
    await revealReviewEnglishSummary(tester);
    expect(find.text('แคปชันลูกค้าต้องคงเดิม #สินค้า'), findsOneWidget);
    reviewEnglishNoSend(fixture);
    expect(fixture.store.savedRequests, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'restored four-channel review retains raw title and identities across locale',
      (tester) async {
    final fixture = ReviewEnglishFixture();
    addTearDown(fixture.dispose);
    await fixture.seed();
    await fixture.mount(tester);
    await revealReviewEnglishSummary(tester);
    expect(find.text('Post to 4 channels'), findsOneWidget);
    expect(find.textContaining('ชื่อวิดีโอที่ลูกค้าตั้งเอง'), findsWidgets);
    for (final connection in channelEnglishConnections) {
      expect(find.text(connection.displayName!), findsOneWidget);
    }
    final before =
        tester.widget<PublishReviewSummary>(find.byType(PublishReviewSummary));
    fixture.language.value = const Locale('th');
    await tester.pumpAndSettle();
    expect(find.text('โพสต์ไปยัง 4 ช่องทาง'), findsOneWidget);
    fixture.language.value = const Locale('en');
    await tester.pumpAndSettle();
    final after =
        tester.widget<PublishReviewSummary>(find.byType(PublishReviewSummary));
    expect(after.caption, before.caption);
    expect(after.platformSettings.youtubeTitle, 'ชื่อวิดีโอที่ลูกค้าตั้งเอง');
    expect(after.connectionDisplayNames, before.connectionDisplayNames);
    expect(after.platformSettings.facebookPublishMode,
        FacebookPublishMode.pageDraft);
    expect(after.platformSettings.instagramShareToFeed, isFalse);
    expect(fixture.connectionReads, 1);
    expect(fixture.store.savedRequests, isEmpty);
    reviewEnglishNoSend(fixture);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'restored separate captions remain customer data even when matching UI keys',
      (tester) async {
    const captions = {
      SocialPlatform.tiktok: 'พรีวิว',
      SocialPlatform.youtubeShorts: 'คำอธิบายสินค้า YouTube ของลูกค้า',
      SocialPlatform.instagramReels: 'แคปชัน Instagram ของร้าน',
      SocialPlatform.facebookReels: 'รายละเอียดเพจ Facebook ของลูกค้า',
    };
    final fixture = ReviewEnglishFixture();
    addTearDown(fixture.dispose);
    await fixture.seed(
        settings: reviewEnglishSettings.copyWith(
            usePlatformCaptions: true, platformCaptions: captions));
    await fixture.mount(tester);
    await revealReviewEnglishSummary(tester);
    for (final caption in captions.entries) {
      expect(
          find.descendant(
              of: find.byKey(
                  ValueKey('publish-review-caption-${caption.key.apiValue}')),
              matching: find.text(caption.value)),
          findsOneWidget);
    }
    fixture.language.value = const Locale('th');
    await tester.pumpAndSettle();
    for (final caption in captions.entries) {
      expect(
          find.descendant(
              of: find.byKey(
                  ValueKey('publish-review-caption-${caption.key.apiValue}')),
              matching: find.text(caption.value)),
          findsOneWidget);
    }
    final summary =
        tester.widget<PublishReviewSummary>(find.byType(PublishReviewSummary));
    expect(summary.platformSettings.platformCaptions, captions);
    expect(fixture.store.savedRequests, isEmpty);
    reviewEnglishNoSend(fixture);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'past restored schedule and stored error follow locale without changing the draft',
      (tester) async {
    final fixture = ReviewEnglishFixture(locale: const Locale('th'));
    addTearDown(fixture.dispose);
    final past = fixture.clock.subtract(const Duration(days: 1)).toUtc();
    await fixture.seed(platforms: {'TIKTOK'}, scheduledAt: past);
    await fixture.mount(tester);
    expect(
        find.text(
            'เวลาเดิมผ่านไปแล้ว เลือกเวลาใหม่หรือเลือกโพสต์เลยก่อนยืนยัน'),
        findsOneWidget);
    fixture.language.value = const Locale('en');
    await tester.pumpAndSettle();
    expect(
        find.text(
            'The previous time has passed. Choose a new time or Post now before confirming.'),
        findsOneWidget);
    await tapVideoEnglishControl(tester, 'publish-review-confirm');
    expect(
        find.text(
            'The previous time has passed. Choose a new time or Post now.'),
        findsOneWidget);
    expect(find.byType(PublishFlowScreen), findsNothing);
    await revealReviewEnglishSummary(tester);
    final summary =
        tester.widget<PublishReviewSummary>(find.byType(PublishReviewSummary));
    expect(summary.scheduledAt, past);
    expect(summary.caption, 'แคปชันลูกค้าต้องคงเดิม #สินค้า');
    expect(fixture.subscriptionReads, 0);
    expect(fixture.store.savedRequests, isEmpty);
    reviewEnglishNoSend(fixture);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'stored plan read error translates without another entitlement request',
      (tester) async {
    final fixture = ReviewEnglishFixture(locale: const Locale('th'))
      ..subscriptionError = StateError('fake offline');
    addTearDown(fixture.dispose);
    await fixture.mount(tester);
    await tapVideoEnglishControl(tester, 'uploader-schedule-later');
    expect(find.text('ตรวจสอบแพ็กเกจไม่สำเร็จ กรุณาลองใหม่ก่อนตั้งเวลา'),
        findsOneWidget);
    fixture.language.value = const Locale('en');
    await tester.pumpAndSettle();
    expect(
        find.text('Could not verify your plan. Try again before scheduling.'),
        findsOneWidget);
    await revealReviewEnglishSummary(tester);
    expect(find.text('แคปชันลูกค้าต้องคงเดิม #สินค้า'), findsOneWidget);
    expect(fixture.subscriptionReads, 1);
    expect(fixture.store.savedRequests, isEmpty);
    reviewEnglishNoSend(fixture);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'phone verification blocks fresh free-plan confirmation before any upload',
      (tester) async {
    final fixture = ReviewEnglishFixture(locale: const Locale('th'));
    addTearDown(fixture.dispose);
    await fixture.mount(tester);
    fixture.quota = const SubscriptionStatusResult(
        userId: videoEnglishOwner,
        plan: 'BASIC',
        status: 'INACTIVE',
        monthlyPostLimit: 3,
        usedPostsThisMonth: 0,
        remainingPostsThisMonth: 3,
        canSchedule: false,
        canUseAiCaptions: false,
        canUseAnalytics: false,
        requiresPhoneVerification: true);
    await tapVideoEnglishControl(tester, 'publish-review-confirm');
    expect(find.byType(PublishFlowScreen), findsNothing);
    expect(find.text('ยืนยันเบอร์โทรก่อนโพสต์ฟรี 3 ครั้งต่อเดือน'),
        findsOneWidget);
    fixture.language.value = const Locale('en');
    await tester.pumpAndSettle();
    expect(
        find.text(
            'Verify your phone number before using the 3 free post units per month.'),
        findsOneWidget);
    expect(fixture.subscriptionReads, 1);
    expect(fixture.availabilityChecks, 1);
    reviewEnglishNoSend(fixture);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'restored overlong selection stays read-only with an English correction action',
      (tester) async {
    final fixture = ReviewEnglishFixture()..viewReadOnly = true;
    fixture.initialVideo = fixture.makeVideo('คลิปยาวเกิน.mp4', duration: 700);
    addTearDown(fixture.dispose);
    await fixture.seed(platforms: {'TIKTOK'});
    await fixture.mount(tester);
    await revealVideoEnglishControl(
        tester, find.byKey(const ValueKey('uploader-selected-duration-error')));
    expect(
        find.text(
            'TikTok requires a video no longer than 10 minutes. Deselect this channel or choose another video.'),
        findsOneWidget);
    expect(find.text('Edit channels'), findsOneWidget);
    expect(find.text('Check destinations before sending'), findsOneWidget);
    reviewEnglishNoSend(fixture);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'restored blocked permissions keep Confirm disabled and show the known prefix',
      (tester) async {
    final fixture = ReviewEnglishFixture()..viewReadOnly = true;
    addTearDown(fixture.dispose);
    await fixture.seed(platforms: {'TIKTOK'});
    fixture.readiness = const [
      SocialPublishingConnectionReadiness(
          platform: 'TIKTOK', state: SocialPublishingState.reconnectRequired)
    ];
    await fixture.mount(tester);
    await revealVideoEnglishControl(
        tester, find.text('TikTok: Reconnect this account before posting'));
    expect(find.text('TikTok: Reconnect this account before posting'),
        findsOneWidget);
    expect(find.text('Check destinations before sending'), findsOneWidget);
    reviewEnglishNoSend(fixture);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'missing identity remains a blocked Review rather than an invented destination',
      (tester) async {
    final fixture = ReviewEnglishFixture()..viewReadOnly = true;
    addTearDown(fixture.dispose);
    await fixture.seed(platforms: {'TIKTOK'});
    fixture.connections = const [
      SocialConnectionResult(platform: 'TIKTOK', connected: true)
    ];
    await fixture.mount(tester);
    await revealVideoEnglishControl(
        tester, find.byKey(const ValueKey('publish-review-unknown-outcome')));
    expect(find.byKey(const ValueKey('publish-review-unknown-outcome')),
        findsOneWidget);
    expect(find.text('Check destinations before sending'), findsOneWidget);
    reviewEnglishNoSend(fixture);
    expect(tester.takeException(), isNull);
  });

  testWidgets('canceling the exit dialog keeps Review data and causes no send',
      (tester) async {
    final fixture = ReviewEnglishFixture();
    addTearDown(fixture.dispose);
    addTearDown(() => tester.pumpWidget(const SizedBox.shrink()));
    await fixture.mount(tester);
    await tapVideoEnglishControl(tester, 'uploader-close');
    expect(find.text('Keep this post?'), findsOneWidget);
    await tester.tap(find.text('Keep editing'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('uploader-step-review')), findsOneWidget);
    await revealReviewEnglishSummary(tester);
    expect(find.text('แคปชันลูกค้าต้องคงเดิม #สินค้า'), findsOneWidget);
    expect(fixture.store.savedRequests, isEmpty);
    reviewEnglishNoSend(fixture);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'confirmation sends one fake request with original channel payload values',
      (tester) async {
    final fixture = ReviewEnglishFixture()..allowFakePublish = true;
    addTearDown(fixture.dispose);
    addTearDown(() => tester.pumpWidget(const SizedBox.shrink()));
    await fixture.seed();
    await fixture.mount(tester);
    reviewEnglishNoSend(fixture);
    fixture.language.value = const Locale('th');
    await tester.pumpAndSettle();
    fixture.language.value = const Locale('en');
    await tester.pumpAndSettle();
    await tapVideoEnglishControl(tester, 'publish-review-confirm');
    expect(fixture.posts, hasLength(1));
    expect(fixture.uploads, hasLength(1));
    expect(fixture.uploadedPaths, hasLength(1));
    final request = fixture.posts.single;
    expect(request.caption, 'แคปชันลูกค้าต้องคงเดิม #สินค้า');
    expect(request.scheduledAt, isNull);
    expect(request.platforms,
        ['TIKTOK', 'YOUTUBE_SHORTS', 'INSTAGRAM_REELS', 'FACEBOOK_REELS']);
    expect(request.platformSettings, {
      'TIKTOK': {'publishMode': 'INBOX_DRAFT'},
      'YOUTUBE_SHORTS': {
        'title': 'ชื่อวิดีโอที่ลูกค้าตั้งเอง',
        'visibility': 'private',
        'madeForKids': false,
        'containsSyntheticMedia': false,
        'communityGuidelinesCertified': true
      },
      'INSTAGRAM_REELS': {'shareToFeed': false, 'isAiGenerated': false},
      'FACEBOOK_REELS': {'publishMode': 'PAGE_DRAFT', 'isAiGenerated': true},
    });
    expect(request.clientRequestId, isNotEmpty);
    expect(request.mediaContentFingerprint, isNotEmpty);
    expect(fixture.preparations, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'owner change during availability check prevents late upload and post',
      (tester) async {
    final pending = Completer<void>();
    final fixture = ReviewEnglishFixture()..availabilityGate = pending.future;
    addTearDown(fixture.dispose);
    addTearDown(() => tester.pumpWidget(const SizedBox.shrink()));
    await fixture.mount(tester);
    final confirm = find.byKey(const ValueKey('publish-review-confirm'));
    await tester.tap(confirm);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();
    expect(fixture.availabilityChecks, 1);
    PostDeeAuthSessionStore.instance
        .signIn(const AuthSession(userId: 'other-review-owner'));
    pending.complete();
    await tester.pumpAndSettle();
    reviewEnglishNoSend(fixture);
    expect(fixture.subscriptionReads, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('plain MaterialApp keeps the original Thai Review presentation',
      (tester) async {
    final fixture = ReviewEnglishFixture()..bareMaterialApp = true;
    addTearDown(fixture.dispose);
    await fixture.mount(tester);
    expect(find.text('ตรวจข้อมูลและเลือกเวลาที่ต้องการโพสต์'), findsOneWidget);
    await revealReviewEnglishSummary(tester);
    expect(find.text('พรีวิว'), findsOneWidget);
    expect(find.text('โพสต์ไปยัง 1 ช่องทาง'), findsOneWidget);
    expect(find.text('ยืนยันส่ง 1 ช่องทาง'), findsOneWidget);
    expect(find.text('แคปชันลูกค้าต้องคงเดิม #สินค้า'), findsOneWidget);
    reviewEnglishNoSend(fixture);
    expect(tester.takeException(), isNull);
  });

  for (final dark in [false, true]) {
    testWidgets(
        'narrow 2x integrated Review has readable data and usable actions ${dark ? 'dark' : 'light'}',
        (tester) async {
      tester.view.physicalSize = const Size(320, 740);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final fixture = ReviewEnglishFixture(dark: dark, scale: 2);
      addTearDown(fixture.dispose);
      addTearDown(() => tester.pumpWidget(const SizedBox.shrink()));
      await fixture.seed();
      await fixture.mount(tester);
      await reviewEnglishReadable(
          tester, 'Review your details and choose when to post.');
      await reviewEnglishReadable(tester,
          'Keep this screen open while your post is being prepared and sent. You cannot cancel until this step finishes.');
      await reviewEnglishReadable(tester, 'แคปชันลูกค้าต้องคงเดิม #สินค้า');
      await reviewEnglishReadable(tester, 'Preview');
      await reviewEnglishReadable(tester, 'Post to 4 channels');
      for (final connection in channelEnglishConnections) {
        await reviewEnglishReadable(tester, connection.displayName!);
      }
      final preview = find.byKey(const ValueKey('publish-review-preview'));
      await revealVideoEnglishControl(tester, preview);
      expect(preview.hitTestable(), findsOneWidget);
      await reviewEnglishReadable(tester, 'Confirm send to 4 channels');
      final confirm = find.byKey(const ValueKey('publish-review-confirm'));
      expect(confirm.hitTestable(), findsOneWidget);
      await tapVideoEnglishControl(tester, 'publish-review-edit-platforms');
      expect(find.byKey(const ValueKey('uploader-step-platforms')),
          findsOneWidget);
      await tapVideoEnglishControl(tester, 'uploader-wizard-next');
      expect(
          find.byKey(const ValueKey('uploader-step-review')), findsOneWidget);
      expect(fixture.store.savedRequests, isEmpty);
      reviewEnglishNoSend(fixture);
      expect(tester.takeException(), isNull);
    });
  }
}
