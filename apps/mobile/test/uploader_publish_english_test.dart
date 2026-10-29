import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postdee_mobile/core/auth/auth_session.dart';
import 'package:postdee_mobile/core/network/postdee_api_client.dart';
import 'package:postdee_mobile/core/theme/app_theme.dart';
import 'package:postdee_mobile/features/shared/postdee_status_sheet.dart';
import 'package:postdee_mobile/features/shared/publishing_availability.dart';
import 'package:postdee_mobile/features/uploader/publish_submission_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'publish_flow_english_test.dart' show loadPublishEnglishFonts;
import 'uploader_review_english_test.dart' show ReviewEnglishFixture;
import 'uploader_video_english_test.dart'
    show videoEnglishOwner, tapVideoEnglishControl, expectVideoEnglishReadable;

Future<ReviewEnglishFixture> _review(WidgetTester tester,
    {bool unavailable = false,
    bool landscape = false,
    bool dark = false,
    double scale = 1}) async {
  final fixture = ReviewEnglishFixture(dark: dark, scale: scale)
    ..allowFakePublish = true;
  addTearDown(fixture.dispose);
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });
  if (landscape) {
    fixture.initialVideo =
        fixture.makeVideo('คลิปต้นฉบับ.mp4', width: 720, height: 406);
  }
  if (unavailable) {
    fixture.availabilityError = const ApiException('service unavailable',
        code: socialPublishingUnavailableCode, statusCode: 503);
  }
  await fixture.seed(platforms: {'YOUTUBE_SHORTS'});
  await fixture.mount(tester);
  return fixture;
}

void main() {
  late AuthSession previous;
  setUpAll(loadPublishEnglishFonts);
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    previous = PostDeeAuthSessionStore.instance.session;
    PostDeeAuthSessionStore.instance
        .signIn(const AuthSession(userId: videoEnglishOwner));
  });
  tearDown(() {
    PostDeeAuthSessionStore.instance.signIn(previous);
    AppTheme.applyThemeMode(ThemeMode.light);
  });

  testWidgets('English unavailable sheet and inline preserve the unsent draft',
      (tester) async {
    final fixture = await _review(tester, unavailable: true);
    await tapVideoEnglishControl(tester, 'publish-review-confirm');
    expect(find.byKey(const ValueKey('postdee-system-status-sheet')),
        findsOneWidget);
    expect(find.text('Publishing is currently unavailable'), findsOneWidget);
    expect(find.text('The video has not been uploaded. Try again later.'),
        findsOneWidget);
    expect(fixture.uploads, isEmpty);
    expect(fixture.posts, isEmpty);
    expect(fixture.availabilityChecks, 1);
    expect(fixture.store.drafts, isNotEmpty);
    final savedRequests = fixture.store.savedRequests.length;
    fixture.language.value = const Locale('th');
    await tester.pumpAndSettle();
    expect(
        find.text('ระบบรับงานโพสต์ยังไม่เปิดใช้งานในขณะนี้'), findsOneWidget);
    fixture.language.value = const Locale('en');
    await tester.pumpAndSettle();
    expect(find.text('Publishing is currently unavailable'), findsOneWidget);
    expect(fixture.store.savedRequests, hasLength(savedRequests));
    expect(fixture.availabilityChecks, 1);
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Publishing is currently unavailable'),
        findsOneWidget);
    expect(fixture.uploads, isEmpty);
    expect(fixture.posts, isEmpty);
  });

  testWidgets('English aspect warning keeps the video when Close is selected',
      (tester) async {
    final fixture = await _review(tester, landscape: true);
    await tapVideoEnglishControl(tester, 'publish-review-confirm');
    expect(find.text('Video is not 9:16'), findsOneWidget);
    expect(find.text('Use a vertical 9:16 video, such as 1080x1920.'),
        findsOneWidget);
    expect(find.text('Choose another video'), findsOneWidget);
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    expect(fixture.picks, 0);
    expect(fixture.uploads, isEmpty);
    expect(fixture.posts, isEmpty);
    expect(fixture.store.savedRequests, isEmpty);
  });

  testWidgets('English fake queued receipt preserves the original post ID',
      (tester) async {
    final fixture = await _review(tester);
    await tapVideoEnglishControl(tester, 'publish-review-confirm');
    expect(find.text('Post received'), findsOneWidget);
    expect(fixture.posts, hasLength(1));
    await tapVideoEnglishControl(tester, 'publish-flow-finish');
    expect(
        find.text('Post received for 1 channel, delivery in progress: '
            'fake-review-post'),
        findsOneWidget);
    expect(fixture.posts, hasLength(1));
    expect(fixture.posts.single.caption, 'แคปชันลูกค้าต้องคงเดิม #สินค้า');
    expect(fixture.uploads, hasLength(1));
    expect(fixture.apiWrites, 0);
  });

  testWidgets(
      'English unknown submission errors hide provider HTML in both views',
      (tester) async {
    final fixture = await _review(tester);
    fixture.availabilityError = const ApiException(
        '<html>private-provider-token /data/merchant/video.mp4</html>',
        statusCode: 400);
    await tapVideoEnglishControl(tester, 'publish-review-confirm');
    expect(find.text('Upload or publishing queue issue'), findsOneWidget);
    const fallback = 'An error occurred while sending your post. '
        'Check your connection and try again.';
    expect(find.text(fallback), findsOneWidget);
    expect(find.textContaining('private-provider-token'), findsNothing);
    expect(find.textContaining('/data/merchant/'), findsNothing);
    await tester.tap(find.text('Go back and check'));
    await tester.pumpAndSettle();
    expect(find.text(fallback), findsOneWidget);
    expect(find.textContaining('private-provider-token'), findsNothing);
    expect(fixture.uploads, isEmpty);
    expect(fixture.posts, isEmpty);
    expect(fixture.availabilityChecks, 1);
  });

  for (final dark in [false, true]) {
    testWidgets(
        'English narrow 2x after-upload warning remains usable ${dark ? 'dark' : 'light'}',
        (tester) async {
      tester.view.physicalSize = const Size(320, 740);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final fixture = await _review(tester, dark: dark, scale: 2);
      const rawData = PostDeeStatusSheetData(
          icon: Icons.cloud_off_rounded,
          iconColor: Colors.orange,
          iconTint: Color(0x24F59E0B),
          title: publishingUnavailableTitle,
          body: publishingUnavailableAfterUploadMessage,
          primaryLabel: 'รับทราบ',
          secondaryLabel: null);
      final result = showPostDeeStatusSheet(
          tester.element(find.byKey(const ValueKey('uploader-step-review'))),
          data: rawData,
          localizeData: (context, data) => PostDeeStatusSheetData(
              icon: data.icon,
              iconColor: data.iconColor,
              iconTint: data.iconTint,
              title: localizePublishSubmissionMessage(context, data.title),
              body: localizePublishSubmissionMessage(context, data.body),
              primaryLabel:
                  localizePublishSubmissionMessage(context, data.primaryLabel),
              secondaryLabel: data.secondaryLabel));
      await tester.pumpAndSettle();
      for (final label in [
        'Publishing is currently unavailable',
        'No post was created. The video may have been uploaded temporarily. '
            'Try again later.',
        'OK'
      ]) {
        final text = find.text(label);
        await tester.ensureVisible(text);
        await tester.pumpAndSettle();
        expectVideoEnglishReadable(tester, text);
      }
      expect(find.text('OK').hitTestable(), findsOneWidget);
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      expect(await result, isTrue);
      expect(rawData.body, publishingUnavailableAfterUploadMessage);
      expect(fixture.posts, isEmpty);
      expect(fixture.uploads, isEmpty);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        'English narrow 2x submission sheet is readable ${dark ? 'dark' : 'light'}',
        (tester) async {
      tester.view.physicalSize = const Size(320, 740);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final fixture =
          await _review(tester, unavailable: true, dark: dark, scale: 2);
      await tapVideoEnglishControl(tester, 'publish-review-confirm');
      for (final label in [
        'Publishing is currently unavailable',
        'The video has not been uploaded. Try again later.',
        'OK'
      ]) {
        final text = find.text(label);
        await tester.ensureVisible(text);
        await tester.pumpAndSettle();
        expectVideoEnglishReadable(tester, text);
      }
      expect(find.text('OK').hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      expect(fixture.posts, isEmpty);
      expect(fixture.uploads, isEmpty);
    });
  }
}
