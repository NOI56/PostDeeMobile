import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postdee_mobile/core/auth/auth_session.dart';
import 'package:postdee_mobile/core/network/postdee_api_client.dart';
import 'package:postdee_mobile/core/theme/app_theme.dart';
import 'package:postdee_mobile/features/platforms/social_platform.dart';
import 'package:postdee_mobile/features/uploader/platform_publish_defaults_store.dart';
import 'package:postdee_mobile/features/uploader/uploader_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/publish_preflight_fixtures.dart';
import 'support/uploader_wizard_test_navigation.dart';
import 'uploader_video_english_test.dart'
    show VideoEnglishFixture, videoEnglishOwner, expectVideoEnglishReadable;

const _save = 'uploader-platform-settings-save';
const _cancel = 'uploader-platform-settings-cancel';
const _connections = [
  SocialConnectionResult(
      platform: 'YOUTUBE_SHORTS',
      connected: true,
      connectionId: 'youtube-connection',
      externalAccountId: 'youtube-account',
      displayName: 'ข้อมูลวิดีโอ'),
  SocialConnectionResult(
      platform: 'INSTAGRAM_REELS',
      connected: true,
      connectionId: 'instagram-connection',
      externalAccountId: 'instagram-account',
      displayName: 'ภาพปก'),
  SocialConnectionResult(
      platform: 'FACEBOOK_REELS',
      connected: true,
      connectionId: 'facebook-connection',
      externalAccountId: 'facebook-page',
      displayName: 'เพจลูกค้า · ภาพปก'),
];

class _Defaults implements PlatformPublishDefaultsStore {
  final saved = <PlatformPublishDefaults>[];
  final values = <String, PlatformPublishDefaults>{};

  @override
  Future<PlatformPublishDefaults?> load(
          PlatformPublishDefaultsScope scope) async =>
      values[scope.storageKey];

  @override
  Future<void> save(
      PlatformPublishDefaultsScope scope, PlatformPublishDefaults defaults,
      {bool Function()? isCurrent}) async {
    if (isCurrent?.call() == false) return;
    saved.add(defaults);
    values[scope.storageKey] = defaults;
  }

  @override
  Future<void> clearForDeletedAccount(String ownerUserId) async {}
}

class _Fixture extends VideoEnglishFixture {
  _Fixture({super.locale, super.scale, super.dark}) {
    initialVideo = makeVideo('คลิปของลูกค้า.mp4');
  }

  final defaults = _Defaults();
  final posts = <CreatePostRequest>[];
  int uploads = 0;

  @override
  UploaderScreen screen() => UploaderScreen(
      fullScreen: true,
      draftStore: store,
      platformPublishDefaultsStore: defaults,
      enableRevenueCatBilling: false,
      initialVideoPath: initialVideo!.path,
      initialVideoName: initialVideo!.name,
      initialVideoSizeBytes: initialVideo!.sizeBytes,
      initialVideoWidth: initialVideo!.width,
      initialVideoHeight: initialVideo!.height,
      initialVideoDurationSeconds: initialVideo!.durationSeconds,
      probePublishMedia: probeValidPublishMedia,
      loadTemplates: () async => const [],
      loadSubscription: () async => const SubscriptionStatusResult(
          userId: videoEnglishOwner,
          plan: 'PRO',
          status: 'ACTIVE',
          phoneVerified: true,
          requiresPhoneVerification: false,
          canSchedule: true,
          canUseAiCaptions: true,
          canUseAnalytics: true),
      loadPostQuota: () async => quota,
      loadCaptionQuota: () async => const CaptionQuotaResult(
          plan: 'PRO',
          quota: RealClipCaptionQuota(
              limit: 120, usedThisMonth: 0, remainingThisMonth: 120)),
      loadSocialConnections: () async {
        connectionReads++;
        return _connections;
      },
      loadSocialPublishingReadiness: () async => [
            for (final connection in _connections)
              SocialPublishingConnectionReadiness(
                  platform: connection.platform,
                  state: SocialPublishingState.connected,
                  connectionId: connection.connectionId)
          ],
      checkPublishingReadiness: () async {},
      createUpload: (_) async {
        uploads++;
        return const UploadResult(
            id: 'upload',
            videoS3Key: 'uploads/english-settings/video.mp4',
            storageProvider: 'mock');
      },
      uploadVideoFile: (_, __) async {},
      createPost: (request) async {
        posts.add(request);
        return QueuedPostResult(
            id: 'post',
            videoS3Key: request.videoS3Key,
            platforms: request.platforms,
            status: 'QUEUED');
      });
}

Future<void> _tap(WidgetTester tester, String key) async {
  final finder = find.byKey(ValueKey(key));
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  final checkbox = find.descendant(of: finder, matching: find.byType(Checkbox));
  final control = checkbox.evaluate().isEmpty ? finder : checkbox;
  await tester.ensureVisible(control);
  await tester.pumpAndSettle();
  await tester.tap(control);
  await tester.pumpAndSettle();
}

Future<void> _mount(WidgetTester tester, _Fixture fixture, String platform,
    {String caption = 'ภาพปก'}) async {
  addTearDown(fixture.dispose);
  tester.view.physicalSize = const Size(393, 852);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetViewInsets);
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });
  await fixture.mount(tester);
  await goToUploaderStep(tester, 1);
  await tester.enterText(
      find.byKey(const ValueKey('uploader-caption-field')), caption);
  await goToUploaderStep(tester, 2);
  await _tap(tester, 'uploader-platform-$platform');
  await _tap(tester, 'uploader-platform-settings-$platform');
}

bool _selected(String key) => find
    .descendant(
        of: find.byKey(ValueKey(key)),
        matching: find.byIcon(Icons.radio_button_checked_rounded))
    .evaluate()
    .isNotEmpty;

Future<void> _youtubeAnswers(WidgetTester tester) async {
  await _tap(tester, 'uploader-youtube-made-for-kids-yes');
  await _tap(tester, 'uploader-youtube-synthetic-no');
  await _tap(tester, 'uploader-youtube-guidelines-certified');
}

Future<void> _title(WidgetTester tester, String text) async {
  if (find
      .byKey(const ValueKey('uploader-youtube-title-edit'))
      .evaluate()
      .isNotEmpty) {
    await _tap(tester, 'uploader-youtube-title-edit');
  }
  final field = find.byKey(const ValueKey('uploader-youtube-title'));
  await tester.ensureVisible(field);
  await tester.enterText(field, text);
  FocusManager.instance.primaryFocus?.unfocus();
  await tester.pumpAndSettle();
}

Future<void> _submit(WidgetTester tester) async {
  await _tap(tester, _save);
  await goToUploaderStep(tester, 3);
  await _tap(tester, 'publish-review-confirm');
}

void main() {
  setUpAll(() async {
    final fonts = FontLoader('Anuphan');
    for (final weight in ['Regular', 'Medium', 'SemiBold', 'Bold']) {
      fonts
          .addFont(rootBundle.load('assets/fonts/anuphan/Anuphan-$weight.ttf'));
    }
    await fonts.load();
  });
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    PostDeeAuthSessionStore.instance.signIn(
        const AuthSession(userId: videoEnglishOwner, idToken: 'fake-token'));
  });
  tearDown(() {
    PostDeeAuthSessionStore.instance.clear();
    AppTheme.applyThemeMode(ThemeMode.light);
  });

  testWidgets('YouTube settings use English while account and title stay raw',
      (tester) async {
    final fixture = _Fixture();
    await _mount(tester, fixture, 'YOUTUBE_SHORTS');
    for (final text in [
      'Video details',
      'Title shown on YouTube Shorts',
      'Customize YouTube title',
      'Visibility',
      'Audience and content',
      'Is this video made for kids?',
      'Yes',
      'No'
    ]) {
      expect(find.text(text), findsWidgets);
    }
    expect(
        find.descendant(
            of: find.byKey(const ValueKey('uploader-platform-settings-sheet')),
            matching: find.text('ข้อมูลวิดีโอ')),
        findsOneWidget);
    expect(
        tester
            .widget<Text>(
                find.byKey(const ValueKey('uploader-youtube-title-preview')))
            .data,
        'ภาพปก');
    expect(find.text('Indicate whether this YouTube video is made for kids.'),
        findsOneWidget);
    expect(fixture.defaults.saved, isEmpty);
    expect(fixture.posts, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'Instagram settings explain feed cover and optional AI in English',
      (tester) async {
    final fixture = _Fixture();
    await _mount(tester, fixture, 'INSTAGRAM_REELS');
    for (final text in [
      'Reels publishing',
      'Share Reels to feed',
      'Turn off to show only in Reels.',
      'Cover',
      'Change the cover in the video step.',
      'AI content disclosure',
      'Not specified (optional)'
    ]) {
      expect(find.text(text), findsOneWidget);
    }
    expect(
        find.descendant(
            of: find.byKey(const ValueKey('uploader-platform-settings-sheet')),
            matching: find.text('ภาพปก')),
        findsOneWidget);
    expect(fixture.posts, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Facebook settings distinguish Page publishing and Page draft',
      (tester) async {
    final fixture = _Fixture();
    await _mount(tester, fixture, 'FACEBOOK_REELS');
    for (final text in [
      'Page publishing',
      'Publish to Page',
      'Save as Page draft',
      'Send as Facebook Reels to the Page shown above.',
      'This sends the post and uses your post quota. Open Facebook to publish it. This is different from saving a draft in PostDee.',
      'Choose Publish to Page or Save as Page draft before saving.'
    ]) {
      expect(find.text(text), findsOneWidget);
    }
    expect(
        find.descendant(
            of: find.byKey(const ValueKey('uploader-platform-settings-sheet')),
            matching: find.text('เพจลูกค้า · ภาพปก')),
        findsOneWidget);
    expect(
        tester
            .widget<FilledButton>(find.byKey(const ValueKey(_save)))
            .onPressed,
        isNull);
    expect(fixture.posts, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'YouTube title and answers survive locale changes and reach API once',
      (tester) async {
    final fixture = _Fixture();
    await _mount(tester, fixture, 'YOUTUBE_SHORTS');
    await _title(tester, 'ข้อมูลวิดีโอ');
    await _youtubeAnswers(tester);
    await _tap(tester, 'uploader-youtube-visibility');
    await tester.tap(find.text('Unlisted').last);
    await tester.pumpAndSettle();
    final reads = fixture.connectionReads;
    fixture.language.value = const Locale('th');
    await tester.pumpAndSettle();
    expect(find.text('ผู้ชมและเนื้อหา'), findsOneWidget);
    fixture.language.value = const Locale('en');
    await tester.pumpAndSettle();
    expect(find.text('Audience and content'), findsOneWidget);
    expect(fixture.connectionReads, reads);
    expect(fixture.defaults.saved, isEmpty);
    expect(_selected('uploader-youtube-made-for-kids-yes'), isTrue);
    expect(_selected('uploader-youtube-synthetic-no'), isTrue);
    expect(
        tester
            .widget<TextField>(
                find.byKey(const ValueKey('uploader-youtube-title')))
            .controller!
            .text,
        'ข้อมูลวิดีโอ');
    await _submit(tester);
    expect(fixture.posts, hasLength(1));
    expect(fixture.posts.single.platformSettings['YOUTUBE_SHORTS'], {
      'title': 'ข้อมูลวิดีโอ',
      'visibility': 'unlisted',
      'madeForKids': true,
      'containsSyntheticMedia': false,
      'communityGuidelinesCertified': true,
    });
    expect(fixture.uploads, 1);
    expect(fixture.defaults.saved.single.toJson()['values'], {
      'visibility': 'unlisted',
      'madeForKids': true,
    });
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'YouTube validation follows current language without losing input',
      (tester) async {
    final fixture = _Fixture();
    await _mount(tester, fixture, 'YOUTUBE_SHORTS');
    await _title(tester, '<ชื่อลูกค้า>');
    const error =
        'YouTube titles must be 100 characters or fewer and cannot contain < or >.';
    expect(find.text(error), findsWidgets);
    fixture.language.value = const Locale('th');
    await tester.pumpAndSettle();
    expect(
        find.text('ชื่อ YouTube ต้องไม่เกิน 100 ตัวอักษร และห้ามมี < หรือ >'),
        findsWidgets);
    fixture.language.value = const Locale('en');
    await tester.pumpAndSettle();
    expect(find.text(error), findsWidgets);
    expect(
        tester
            .widget<TextField>(
                find.byKey(const ValueKey('uploader-youtube-title')))
            .controller!
            .text,
        '<ชื่อลูกค้า>');
    await _title(tester, '');
    await _tap(tester, 'uploader-youtube-title-reset');
    expect(
        tester
            .widget<Text>(
                find.byKey(const ValueKey('uploader-youtube-title-preview')))
            .data,
        'ภาพปก');
    expect(fixture.defaults.saved, isEmpty);
    expect(fixture.posts, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('YouTube required answers keep Save disabled until certified',
      (tester) async {
    final fixture = _Fixture();
    await _mount(tester, fixture, 'YOUTUBE_SHORTS');
    await _tap(tester, 'uploader-youtube-made-for-kids-no');
    expect(
        find.text(
            'Indicate whether this video contains realistic synthetic media.'),
        findsOneWidget);
    await _tap(tester, 'uploader-youtube-synthetic-yes');
    expect(find.text("Confirm YouTube's Community Guidelines before posting."),
        findsOneWidget);
    expect(
        tester
            .widget<FilledButton>(find.byKey(const ValueKey(_save)))
            .onPressed,
        isNull);
    await _tap(tester, 'uploader-youtube-guidelines-certified');
    expect(
        tester
            .widget<FilledButton>(find.byKey(const ValueKey(_save)))
            .onPressed,
        isNotNull);
    await _tap(tester, _cancel);
    expect(fixture.defaults.saved, isEmpty);
    expect(fixture.posts, isEmpty);
  });

  for (final language in ['en', 'th']) {
    testWidgets(
        'YouTube $language title stays readable at 320dp 2x with keyboard',
        (tester) async {
      final fixture = _Fixture(locale: Locale(language), scale: 2);
      await _mount(tester, fixture, 'YOUTUBE_SHORTS');
      await _title(tester, 'ชื่อคลิปของลูกค้า');
      tester.view.physicalSize = const Size(320, 640);
      final field = find.byKey(const ValueKey('uploader-youtube-title'));
      await tester.showKeyboard(field);
      tester.view.viewInsets = const FakeViewPadding(bottom: 180);
      await tester.pumpAndSettle();
      final editable =
          find.descendant(of: field, matching: find.byType(EditableText));
      await Scrollable.ensureVisible(tester.element(editable), alignment: .5);
      final state = tester.state<EditableTextState>(editable);
      final position = TextPosition(
          offset: tester.widget<TextField>(field).controller!.text.length);
      state.bringIntoView(position);
      await tester.pumpAndSettle();
      final caret = state.renderEditable
          .getLocalRectForCaret(position)
          .shift(state.renderEditable.localToGlobal(Offset.zero));
      final scroll = tester
          .getRect(find.byKey(const ValueKey('platform-settings-scroll')));
      expect(caret.top, greaterThanOrEqualTo(scroll.top));
      expect(caret.bottom, lessThanOrEqualTo(scroll.bottom));
      expectVideoEnglishReadable(
          tester,
          find.text(language == 'en'
              ? 'Leave blank to use a title from your caption.'
              : 'เว้นว่างเพื่อใช้ชื่อจากแคปชัน'));
      await tester.enterText(field, '<ชื่อคลิปของลูกค้า>');
      await tester.pumpAndSettle();
      expectVideoEnglishReadable(
          tester,
          find.descendant(
              of: field,
              matching: find.text(language == 'en'
                  ? 'YouTube titles must be 100 characters or fewer and cannot contain < or >.'
                  : 'ชื่อ YouTube ต้องไม่เกิน 100 ตัวอักษร และห้ามมี < หรือ >')));
      expect(tester.widget<TextField>(field).controller!.text,
          '<ชื่อคลิปของลูกค้า>');
      expect(tester.takeException(), isNull);
      expect(fixture.posts, isEmpty);
      expect(fixture.defaults.saved, isEmpty);
    });
  }

  for (final ai in [true, false]) {
    testWidgets('English Instagram sends feed=false with explicit AI=$ai',
        (tester) async {
      final fixture = _Fixture();
      await _mount(tester, fixture, 'INSTAGRAM_REELS');
      await _tap(tester, 'uploader-instagram-share-to-feed');
      await _tap(tester, 'uploader-instagram-ai-${ai ? 'yes' : 'no'}');
      expect(find.text('Clear answer'), findsOneWidget);
      await _submit(tester);
      expect(fixture.posts.single.platformSettings['INSTAGRAM_REELS'],
          {'shareToFeed': false, 'isAiGenerated': ai});
      expect(fixture.defaults.saved.single.toJson()['values'],
          {'shareToFeed': false});
      expect(tester.takeException(), isNull);
    });
  }

  for (final mode in ['PUBLISH', 'PAGE_DRAFT']) {
    testWidgets('English Facebook sends Reels $mode and optional declaration',
        (tester) async {
      final fixture = _Fixture();
      await _mount(tester, fixture, 'FACEBOOK_REELS');
      await _tap(
          tester,
          mode == 'PUBLISH'
              ? 'uploader-facebook-publish'
              : 'uploader-facebook-page-draft');
      await _tap(tester, 'uploader-facebook-ai-no');
      await _submit(tester);
      expect(fixture.posts.single.platforms, ['FACEBOOK_REELS']);
      expect(fixture.posts.single.platformSettings['FACEBOOK_REELS'],
          {'publishMode': mode, 'isAiGenerated': false});
      expect(
          fixture.defaults.saved.single.platform, SocialPlatform.facebookReels);
      expect(tester.takeException(), isNull);
    });
  }

  for (final platform in ['INSTAGRAM_REELS', 'FACEBOOK_REELS']) {
    final prefix = platform == 'INSTAGRAM_REELS' ? 'instagram' : 'facebook';
    testWidgets('English $platform can clear optional AI and cancel edits',
        (tester) async {
      final fixture = _Fixture();
      await _mount(tester, fixture, platform);
      await _tap(tester, 'uploader-$prefix-ai-yes');
      await _tap(tester, 'uploader-$prefix-ai-clear');
      expect(find.text('Not specified (optional)'), findsOneWidget);
      await _tap(tester, _cancel);
      expect(fixture.defaults.saved, isEmpty);
      await _tap(tester, 'uploader-platform-settings-$platform');
      expect(_selected('uploader-$prefix-ai-yes'), isFalse);
      expect(_selected('uploader-$prefix-ai-no'), isFalse);
      if (platform == 'FACEBOOK_REELS') {
        await _tap(tester, 'uploader-facebook-page-draft');
      }
      await _submit(tester);
      expect(
          (fixture.posts.single.platformSettings[platform] as Map)
              .containsKey('isAiGenerated'),
          isFalse);
      expect(tester.takeException(), isNull);
    });
  }

  for (final platform in [
    'YOUTUBE_SHORTS',
    'INSTAGRAM_REELS',
    'FACEBOOK_REELS'
  ]) {
    for (final scale in [1.0, 2.0]) {
      for (final dark in [false, true]) {
        testWidgets(
            'English $platform fits 320dp at ${scale}x above keyboard dark=$dark',
            (tester) async {
          final fixture = _Fixture(scale: scale, dark: dark);
          await _mount(tester, fixture, platform);
          tester.view.physicalSize = const Size(320, 640);
          tester.view.viewInsets = const FakeViewPadding(bottom: 180);
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          final save = find.byKey(const ValueKey(_save));
          final cancel = find.byKey(const ValueKey(_cancel));
          expect(save.hitTestable(), findsOneWidget);
          expect(cancel.hitTestable(), findsOneWidget);
          expect(tester.getRect(save).bottom, lessThanOrEqualTo(460));
          final last = platform == 'YOUTUBE_SHORTS'
              ? 'uploader-youtube-guidelines-certified'
              : 'uploader-${platform == 'INSTAGRAM_REELS' ? 'instagram' : 'facebook'}-ai-no';
          await _tap(tester, last);
          expect(save.hitTestable(), findsOneWidget);
          expect(tester.takeException(), isNull);
          await _tap(tester, _cancel);
        });
      }
    }
  }
}
