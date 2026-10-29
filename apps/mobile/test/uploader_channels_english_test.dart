import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postdee_mobile/core/auth/auth_session.dart';
import 'package:postdee_mobile/core/network/postdee_api_client.dart';
import 'package:postdee_mobile/features/uploader/platform_publish_settings.dart';
import 'package:postdee_mobile/features/uploader/uploader_screen.dart';
import 'package:postdee_mobile/features/uploader/video_picker_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/publish_preflight_fixtures.dart';
import 'uploader_video_english_test.dart'
    show
        VideoEnglishFixture,
        videoEnglishOwner,
        tapVideoEnglishControl,
        revealVideoEnglishControl,
        expectVideoEnglishReadable;

const channelEnglishConnections = [
  SocialConnectionResult(
      platform: 'TIKTOK',
      connected: true,
      connectionId: 'tiktok-local',
      externalAccountId: 'tiktok-owner',
      displayName: 'ร้าน TikTok ของฉัน'),
  SocialConnectionResult(
      platform: 'YOUTUBE_SHORTS',
      connected: true,
      connectionId: 'youtube-local',
      externalAccountId: 'youtube-owner',
      displayName: 'ช่องวิดีโอภาษาไทย'),
  SocialConnectionResult(
      platform: 'INSTAGRAM_REELS',
      connected: true,
      connectionId: 'instagram-local',
      externalAccountId: 'instagram-owner',
      displayName: 'ชื่อร้าน Instagram'),
  SocialConnectionResult(
      platform: 'FACEBOOK_REELS',
      connected: true,
      connectionId: 'facebook-local',
      externalAccountId: 'facebook-page',
      displayName: 'เพจร้านค้าภาษาไทย'),
];

class ChannelsEnglishFixture extends VideoEnglishFixture {
  ChannelsEnglishFixture({super.locale, super.dark, super.scale}) {
    initialVideo = makeVideo('คลิปเลือกช่องทาง.mp4');
  }

  List<SocialConnectionResult> connections = List.of(channelEnglishConnections);
  List<SocialPublishingConnectionReadiness> readiness = [
    for (final connection in channelEnglishConnections)
      SocialPublishingConnectionReadiness(
          platform: connection.platform, state: SocialPublishingState.connected)
  ];
  Object? connectionError;
  Object? readinessError;
  Future<List<SocialConnectionResult>>? connectionGate;
  Future<List<SocialPublishingConnectionReadiness>>? readinessGate;
  Future<List<SocialConnectionResult>> Function()? respondConnections;
  int readinessReads = 0;

  @override
  UploaderScreen screen() => UploaderScreen(
      fullScreen: true,
      draftStore: store,
      enableRevenueCatBilling: false,
      initialDraftId: initialDraftId,
      initialVideoPath: initialVideo?.path,
      initialVideoName: initialVideo?.name,
      initialVideoSizeBytes: initialVideo?.sizeBytes,
      initialVideoWidth: initialVideo?.width,
      initialVideoHeight: initialVideo?.height,
      initialVideoDurationSeconds: initialVideo?.durationSeconds,
      pickVideo: () async {
        picks++;
        return picked;
      },
      readVideoMetadata: (path) async {
        metadataReads.add(path);
        return VideoDimensions(
            width: initialVideo?.width ?? 1080,
            height: initialVideo?.height ?? 1920,
            durationSeconds: initialVideo?.durationSeconds);
      },
      probePublishMedia: probeValidPublishMedia,
      loadTemplates: () async => const [],
      loadSubscription: () async => quota,
      loadPostQuota: () async {
        quotaReads++;
        return quota;
      },
      loadCaptionQuota: () async {
        captionQuotaReads++;
        return const CaptionQuotaResult(
            plan: 'PRO',
            quota: RealClipCaptionQuota(
                limit: 120, usedThisMonth: 0, remainingThisMonth: 120));
      },
      loadSocialConnections: () async {
        connectionReads++;
        if (connectionError != null) throw connectionError!;
        if (respondConnections != null) return respondConnections!();
        return connectionGate == null
            ? List.of(connections)
            : await connectionGate!;
      },
      loadSocialPublishingReadiness: () async {
        readinessReads++;
        if (readinessError != null) throw readinessError!;
        return readinessGate == null
            ? List.of(readiness)
            : await readinessGate!;
      },
      createUpload: (_) async {
        apiWrites++;
        throw StateError('Unexpected upload');
      },
      uploadVideoFile: (_, __) async {
        apiWrites++;
      },
      createPost: (_) async {
        apiWrites++;
        throw StateError('Unexpected publish');
      },
      generateRealClipCaption: (_) async {
        apiWrites++;
        throw StateError('Unexpected AI');
      });

  @override
  Future<void> mount(WidgetTester tester, {bool settle = true}) async {
    await super.mount(tester, settle: settle);
    await openChannels(tester);
  }

  Future<void> openChannels(WidgetTester tester) async {
    await tapVideoEnglishControl(tester, 'uploader-progress-1');
    final caption = find.byKey(const ValueKey('uploader-caption-field'));
    await revealVideoEnglishControl(tester, caption);
    await tester.enterText(caption, 'แคปชันลูกค้าต้องคงเดิม #สินค้า');
    tester.testTextInput.hide();
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    await tapVideoEnglishControl(tester, 'uploader-wizard-next');
    expect(
        find.byKey(const ValueKey('uploader-step-platforms')), findsOneWidget);
  }
}

Future<void> channelEnglishTap(WidgetTester tester, Finder finder) async {
  await revealVideoEnglishControl(tester, finder);
  expect(finder.hitTestable(), findsOneWidget);
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<void> channelEnglishExpectReadable(
    WidgetTester tester, String value) async {
  final text = find.text(value);
  await revealVideoEnglishControl(tester, text);
  expectVideoEnglishReadable(tester, text);
}

Finder channelEnglishRow(String apiValue) =>
    find.byKey(ValueKey('uploader-platform-$apiValue'));

bool channelEnglishIsSelected(WidgetTester tester, String apiValue) => tester
    .widget<Semantics>(find
        .ancestor(
            of: channelEnglishRow(apiValue), matching: find.byType(Semantics))
        .first)
    .properties
    .selected!;

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
      'English channels identify all connected destinations without rewriting names',
      (tester) async {
    final fixture = ChannelsEnglishFixture();
    addTearDown(fixture.dispose);
    await fixture.mount(tester);
    expect(find.text('Choose destination accounts and configure each channel.'),
        findsOneWidget);
    expect(find.text('4 channels connected'), findsOneWidget);
    expect(
        find.text('Choose only the channels for this post.'), findsOneWidget);
    expect(find.text('Recheck publishing permissions'), findsOneWidget);
    for (final connection in channelEnglishConnections) {
      expect(channelEnglishRow(connection.platform), findsOneWidget);
      expect(find.text(connection.displayName!), findsOneWidget);
    }
    expect(find.byKey(const ValueKey('uploader-platform-SHOPEE_VIDEO')),
        findsNothing);
    expect(find.byKey(const ValueKey('uploader-platform-LAZADA_VIDEO')),
        findsNothing);
    expect(fixture.connectionReads, 1);
    expect(fixture.readinessReads, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'stored channel load failure changes language without another request',
      (tester) async {
    final fixture = ChannelsEnglishFixture(locale: const Locale('th'))
      ..connectionError = StateError('local fake offline');
    addTearDown(fixture.dispose);
    await fixture.mount(tester);
    expect(find.text('ตรวจสอบช่องทางที่เชื่อมต่อไม่สำเร็จ ลองใหม่อีกครั้ง'),
        findsOneWidget);
    fixture.language.value = const Locale('en');
    await tester.pumpAndSettle();
    expect(find.text('Could not check connected channels. Please try again.'),
        findsOneWidget);
    expect(
        find.text('Account status is not confirmed. Try again before posting.'),
        findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
    expect(fixture.connectionReads, 1);
    expect(fixture.readinessReads, 0);
    expect(fixture.store.savedRequests, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'English select all and clear all change only the chosen channels',
      (tester) async {
    final fixture = ChannelsEnglishFixture();
    addTearDown(fixture.dispose);
    await fixture.mount(tester);
    expect(find.text('Select all'), findsOneWidget);
    expect(find.text('Clear all'), findsOneWidget);
    await tapVideoEnglishControl(tester, 'uploader-select-all-platforms');
    for (final connection in channelEnglishConnections) {
      expect(channelEnglishIsSelected(tester, connection.platform), isTrue);
    }
    expect(find.text('Channel settings'), findsNWidgets(4));
    await tapVideoEnglishControl(tester, 'uploader-clear-all-platforms');
    for (final connection in channelEnglishConnections) {
      expect(channelEnglishIsSelected(tester, connection.platform), isFalse);
    }
    expect(find.text('Channel settings'), findsNothing);
    expect(fixture.connectionReads, 1);
    expect(fixture.store.savedRequests, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'English loading keeps the request pending and accepts its result once',
      (tester) async {
    final pending = Completer<List<SocialConnectionResult>>();
    final fixture = ChannelsEnglishFixture()..connectionGate = pending.future;
    addTearDown(fixture.dispose);
    await fixture.mount(tester);
    expect(find.text('Checking channels...'), findsOneWidget);
    expect(find.text('Please wait while channel status is checked.'),
        findsOneWidget);
    expect(channelEnglishRow('TIKTOK'), findsNothing);
    await tapVideoEnglishControl(tester, 'uploader-wizard-next');
    expect(
        find.text('Checking connected channels. Please wait.'), findsOneWidget);
    fixture.language.value = const Locale('th');
    await tester.pumpAndSettle();
    expect(find.text('กำลังตรวจสอบช่องทาง...'), findsOneWidget);
    expect(fixture.connectionReads, 1);
    fixture.language.value = const Locale('en');
    pending.complete(channelEnglishConnections);
    await tester.pumpAndSettle();
    expect(find.text('4 channels connected'), findsOneWidget);
    expect(fixture.connectionReads, 1);
    expect(fixture.readinessReads, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'empty channels explain connection requirements without future providers',
      (tester) async {
    final fixture = ChannelsEnglishFixture()..connections = [];
    addTearDown(fixture.dispose);
    await fixture.mount(tester);
    expect(find.text('No channels connected'), findsOneWidget);
    expect(find.text('Connect your social accounts before posting.'),
        findsOneWidget);
    expect(find.byKey(const ValueKey('uploader-select-all-platforms')),
        findsNothing);
    for (final connection in channelEnglishConnections) {
      expect(channelEnglishRow(connection.platform), findsNothing);
    }
    expect(find.text('Shopee Video'), findsNothing);
    expect(find.text('Lazada Video'), findsNothing);
    expect(fixture.connectionReads, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'English retry replaces a failed read without selecting or sending',
      (tester) async {
    final fixture = ChannelsEnglishFixture()
      ..connectionError = StateError('offline');
    addTearDown(fixture.dispose);
    await fixture.mount(tester);
    fixture.connectionError = null;
    await tapVideoEnglishControl(tester, 'uploader-retry-connections');
    expect(find.text('Could not check connected channels. Please try again.'),
        findsNothing);
    expect(find.text('4 channels connected'), findsOneWidget);
    for (final connection in channelEnglishConnections) {
      expect(channelEnglishIsSelected(tester, connection.platform), isFalse);
    }
    expect(fixture.connectionReads, 2);
    expect(fixture.readinessReads, 1);
    expect(fixture.store.savedRequests, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'no selection remains on channels and stored validation follows locale',
      (tester) async {
    final fixture = ChannelsEnglishFixture(locale: const Locale('th'));
    addTearDown(fixture.dispose);
    await fixture.mount(tester);
    await tapVideoEnglishControl(tester, 'uploader-wizard-next');
    expect(find.text('เชื่อมและเลือกอย่างน้อย 1 ช่องทางก่อน'), findsOneWidget);
    fixture.language.value = const Locale('en');
    await tester.pumpAndSettle();
    expect(find.text('Connect and select at least 1 channel first.'),
        findsOneWidget);
    expect(find.byKey(const ValueKey('uploader-step-review')), findsNothing);
    expect(fixture.connectionReads, 1);
    expect(fixture.store.savedRequests, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'one connected channel uses singular copy and ignores disconnected entries',
      (tester) async {
    final fixture = ChannelsEnglishFixture()
      ..connections = [
        channelEnglishConnections.first,
        const SocialConnectionResult(
            platform: 'YOUTUBE_SHORTS', connected: false),
        const SocialConnectionResult(
            platform: 'FUTURE_PROVIDER', connected: true),
      ];
    addTearDown(fixture.dispose);
    await fixture.mount(tester);
    expect(find.text('1 channel connected'), findsOneWidget);
    expect(channelEnglishRow('TIKTOK'), findsOneWidget);
    expect(channelEnglishRow('YOUTUBE_SHORTS'), findsNothing);
    expect(find.text('4 channels connected'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('account names matching app copy and external identity stay raw',
      (tester) async {
    final fixture = ChannelsEnglishFixture()
      ..connections = const [
        SocialConnectionResult(
            platform: 'TIKTOK',
            connected: true,
            displayName: 'ยังยืนยันบัญชีไม่ได้',
            externalAccountId: 'tiktok-owner'),
        SocialConnectionResult(
            platform: 'YOUTUBE_SHORTS',
            connected: true,
            displayName: '  ',
            externalAccountId: 'บัญชี-ต้องตั้งค่า'),
      ];
    addTearDown(fixture.dispose);
    await fixture.mount(tester);
    expect(find.text('ยังยืนยันบัญชีไม่ได้'), findsOneWidget);
    expect(find.text('บัญชี-ต้องตั้งค่า'), findsOneWidget);
    expect(find.text('Account not confirmed'), findsNothing);
    fixture.language.value = const Locale('th');
    await tester.pumpAndSettle();
    expect(find.text('ยังยืนยันบัญชีไม่ได้'), findsOneWidget);
    expect(find.text('บัญชี-ต้องตั้งค่า'), findsOneWidget);
    expect(fixture.connectionReads, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'missing destination identity blocks Next with localized guidance',
      (tester) async {
    final fixture = ChannelsEnglishFixture()
      ..connections = const [
        SocialConnectionResult(platform: 'TIKTOK', connected: true)
      ];
    addTearDown(fixture.dispose);
    await fixture.mount(tester);
    expect(find.text('Account not confirmed'), findsOneWidget);
    await channelEnglishTap(tester, channelEnglishRow('TIKTOK'));
    await tapVideoEnglishControl(tester, 'uploader-wizard-next');
    expect(
        find.text(
            'The destination account or Page is not confirmed. Refresh channels or reconnect it.'),
        findsOneWidget);
    expect(find.byKey(const ValueKey('uploader-step-review')), findsNothing);
    expect(fixture.connectionReads, 1);
    expect(fixture.store.savedRequests, isEmpty);
    expect(tester.takeException(), isNull);
  });

  for (final status in const {
    SocialPublishingState.ready: 'Publishing permissions verified',
    SocialPublishingState.connected:
        'Connected · Publishing permissions not verified',
    SocialPublishingState.reconnectRequired:
        'Reconnect this account before posting',
    SocialPublishingState.permissionMissing:
        'Publishing permissions are missing. Reconnect this account.',
    SocialPublishingState.notConnected:
        'This channel is not connected. Reconnect it.',
    SocialPublishingState.unavailable:
        'Could not check publishing permissions. Try again.',
  }.entries) {
    testWidgets(
        'English ${status.key.name} readiness preserves its publishing distinction',
        (tester) async {
      final fixture = ChannelsEnglishFixture()
        ..connections = [channelEnglishConnections.first]
        ..readiness = [
          SocialPublishingConnectionReadiness(
              platform: 'TIKTOK', state: status.key)
        ];
      addTearDown(fixture.dispose);
      await fixture.mount(tester);
      expect(find.text(status.value), findsOneWidget);
      if (status.key != SocialPublishingState.ready &&
          status.key != SocialPublishingState.connected) {
        await channelEnglishTap(tester, channelEnglishRow('TIKTOK'));
        await tapVideoEnglishControl(tester, 'uploader-wizard-next');
        expect(find.text('TikTok: ${status.value}'), findsOneWidget);
        expect(
            find.byKey(const ValueKey('uploader-step-review')), findsNothing);
      }
      expect(fixture.readinessReads, 1);
      expect(fixture.store.savedRequests, isEmpty);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
      'legacy readiness route remains unverified rather than claiming permission',
      (tester) async {
    final fixture = ChannelsEnglishFixture()
      ..connections = [channelEnglishConnections.first]
      ..readinessError = const ApiException('old route', statusCode: 404);
    addTearDown(fixture.dispose);
    await fixture.mount(tester);
    expect(find.text('Connected · Publishing permissions not verified'),
        findsOneWidget);
    expect(find.text('Publishing permissions verified'), findsNothing);
    expect(fixture.connectionReads, 1);
    expect(fixture.readinessReads, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'unknown provider readiness errors remain raw across locale and block Next',
      (tester) async {
    const raw = 'ข้อมูลผู้ให้บริการจำลองที่ไม่อยู่ในแค็ตตาล็อก provider-17';
    final fixture = ChannelsEnglishFixture()
      ..connections = [channelEnglishConnections.first]
      ..readinessError = const ApiException(raw, statusCode: 400);
    addTearDown(fixture.dispose);
    await fixture.mount(tester);
    expect(find.text(raw), findsOneWidget);
    await channelEnglishTap(tester, channelEnglishRow('TIKTOK'));
    await tapVideoEnglishControl(tester, 'uploader-wizard-next');
    expect(find.text(raw), findsNWidgets(2));
    fixture.language.value = const Locale('th');
    await tester.pumpAndSettle();
    expect(find.text(raw), findsNWidgets(2));
    expect(fixture.readinessReads, 1);
    expect(find.byKey(const ValueKey('uploader-step-review')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('stored readiness fallback changes locale without checking again',
      (tester) async {
    final fixture = ChannelsEnglishFixture(locale: const Locale('th'))
      ..connections = [channelEnglishConnections.first]
      ..readinessError = StateError('fake offline');
    addTearDown(fixture.dispose);
    await fixture.mount(tester);
    expect(find.text('ตรวจสิทธิ์เผยแพร่ไม่สำเร็จ กรุณารีเฟรชช่องทางก่อนโพสต์'),
        findsOneWidget);
    fixture.language.value = const Locale('en');
    await tester.pumpAndSettle();
    expect(
        find.text(
            'Could not check publishing permissions. Refresh channels before posting.'),
        findsOneWidget);
    expect(fixture.readinessReads, 1);
    expect(fixture.connectionReads, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'provider HTML remains sanitized by the existing readiness error policy',
      (tester) async {
    const raw = '<html>ข้อมูลผู้ให้บริการที่ไม่ควรแสดง</html>';
    final fixture = ChannelsEnglishFixture()
      ..connections = [channelEnglishConnections.first]
      ..readinessError = const ApiException(raw, statusCode: 400);
    addTearDown(fixture.dispose);
    await fixture.mount(tester);
    expect(find.text(raw), findsNothing);
    expect(
        find.text(
            'Could not check publishing permissions. Refresh channels before posting.'),
        findsOneWidget);
    expect(fixture.readinessReads, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('stored timeout readiness follows locale without checking again',
      (tester) async {
    final fixture = ChannelsEnglishFixture(locale: const Locale('th'))
      ..connections = [channelEnglishConnections.first]
      ..readinessError = TimeoutException('local fake timeout');
    addTearDown(fixture.dispose);
    await fixture.mount(tester);
    expect(
        find.text('ระบบตอบกลับช้าเกินไป กรุณาลองใหม่อีกครั้ง'), findsOneWidget);
    fixture.language.value = const Locale('en');
    await tester.pumpAndSettle();
    expect(find.text('The request took too long. Please try again.'),
        findsOneWidget);
    expect(fixture.readinessReads, 1);
    expect(fixture.connectionReads, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('changed channel binding stays blocked after changing language',
      (tester) async {
    final fixture = ChannelsEnglishFixture(locale: const Locale('th'))
      ..connections = [channelEnglishConnections.first]
      ..readiness = const [
        SocialPublishingConnectionReadiness(
            platform: 'TIKTOK',
            connectionId: 'different-tiktok-account',
            state: SocialPublishingState.ready)
      ];
    addTearDown(fixture.dispose);
    await fixture.mount(tester);
    await channelEnglishTap(tester, channelEnglishRow('TIKTOK'));
    await tapVideoEnglishControl(tester, 'uploader-wizard-next');
    fixture.language.value = const Locale('en');
    await tester.pumpAndSettle();
    expect(
        find.text(
            'The TikTok account has changed. Refresh channels and review your settings again.'),
        findsNWidgets(2));
    expect(find.byKey(const ValueKey('uploader-step-review')), findsNothing);
    expect(fixture.connectionReads, 1);
    expect(fixture.readinessReads, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'duration-blocked destinations are excluded from Select all supported',
      (tester) async {
    final fixture = ChannelsEnglishFixture();
    fixture.initialVideo = fixture.makeVideo('คลิปยาว.mp4', duration: 200);
    addTearDown(fixture.dispose);
    await fixture.mount(tester);
    expect(find.text('Select all supported'), findsOneWidget);
    expect(
        find.text(
            'YouTube Shorts requires a video no longer than 3 minutes. This video cannot be posted to this channel.'),
        findsWidgets);
    expect(
        find.byKey(const ValueKey('uploader-platform-duration-FACEBOOK_REELS')),
        findsOneWidget);
    expect(tester.widget<InkWell>(channelEnglishRow('YOUTUBE_SHORTS')).onTap,
        isNull);
    expect(tester.widget<InkWell>(channelEnglishRow('FACEBOOK_REELS')).onTap,
        isNull);
    await tapVideoEnglishControl(tester, 'uploader-select-all-platforms');
    expect(channelEnglishIsSelected(tester, 'TIKTOK'), isTrue);
    expect(channelEnglishIsSelected(tester, 'INSTAGRAM_REELS'), isTrue);
    expect(channelEnglishIsSelected(tester, 'YOUTUBE_SHORTS'), isFalse);
    expect(channelEnglishIsSelected(tester, 'FACEBOOK_REELS'), isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'refresh preserves an unavailable draft selection until the user clears it',
      (tester) async {
    final fixture = ChannelsEnglishFixture();
    addTearDown(fixture.dispose);
    await fixture.mount(tester);
    await channelEnglishTap(tester, channelEnglishRow('TIKTOK'));
    fixture.connections = channelEnglishConnections.skip(1).toList();
    await tapVideoEnglishControl(
        tester, 'uploader-refresh-publishing-readiness');
    expect(find.text('Selected in this draft but not connected: TikTok'),
        findsOneWidget);
    expect(channelEnglishRow('TIKTOK'), findsNothing);
    await tapVideoEnglishControl(tester, 'uploader-wizard-next');
    expect(find.text('Connect and select at least 1 channel first.'),
        findsOneWidget);
    await tapVideoEnglishControl(tester, 'uploader-select-all-platforms');
    await tapVideoEnglishControl(tester, 'uploader-clear-all-platforms');
    expect(find.text('Selected in this draft but not connected: TikTok'),
        findsNothing);
    expect(fixture.connectionReads, 2);
    expect(fixture.store.savedRequests, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'selected API values and raw caption survive locale changes and draft saving',
      (tester) async {
    final fixture = ChannelsEnglishFixture();
    addTearDown(fixture.dispose);
    await fixture.mount(tester);
    await tapVideoEnglishControl(tester, 'uploader-select-all-platforms');
    fixture.language.value = const Locale('th');
    await tester.pumpAndSettle();
    for (final connection in channelEnglishConnections) {
      expect(channelEnglishIsSelected(tester, connection.platform), isTrue);
      expect(find.text(connection.displayName!), findsOneWidget);
    }
    fixture.language.value = const Locale('en');
    await tester.pumpAndSettle();
    await tapVideoEnglishControl(tester, 'uploader-save-draft-button');
    final saved = fixture.store.savedRequests.single;
    expect(saved.caption, 'แคปชันลูกค้าต้องคงเดิม #สินค้า');
    expect(saved.platformApiValues,
        {'TIKTOK', 'YOUTUBE_SHORTS', 'INSTAGRAM_REELS', 'FACEBOOK_REELS'});
    expect(
        saved.platformSettings.tiktokPublishMode, TikTokPublishMode.inboxDraft);
    expect(saved.platformSettings.youtubeVisibility, YouTubeVisibility.private);
    expect(saved.platformSettings.instagramShareToFeed, isTrue);
    expect(saved.platformSettings.facebookPublishMode, isNull);
    expect(fixture.connectionReads, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'late connection results cannot populate channels after an owner change',
      (tester) async {
    final pending = Completer<List<SocialConnectionResult>>();
    final fixture = ChannelsEnglishFixture()..connectionGate = pending.future;
    addTearDown(fixture.dispose);
    await fixture.mount(tester);
    PostDeeAuthSessionStore.instance
        .signIn(const AuthSession(userId: 'different-owner'));
    pending.complete(channelEnglishConnections);
    await tester.pumpAndSettle();
    for (final connection in channelEnglishConnections) {
      expect(find.text(connection.displayName!), findsNothing);
    }
    expect(fixture.connectionReads, 1);
    expect(fixture.readinessReads, 0);
    expect(fixture.store.savedRequests, isEmpty);
    await tester.pumpWidget(const SizedBox.shrink());
    expect(tester.takeException(), isNull);
  });

  testWidgets('plain MaterialApp retains the Thai channels fallback',
      (tester) async {
    final fixture = ChannelsEnglishFixture();
    addTearDown(fixture.dispose);
    await tester
        .pumpWidget(MaterialApp(home: Scaffold(body: fixture.screen())));
    await tester.pumpAndSettle();
    await fixture.openChannels(tester);
    expect(find.text('เชื่อมต่อแล้ว 4 ช่องทาง'), findsOneWidget);
    expect(find.text('เลือกทั้งหมด'), findsOneWidget);
    expect(find.text('ล้างทั้งหมด'), findsOneWidget);
    expect(find.text('Choose only the channels for this post.'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  for (final dark in [false, true]) {
    testWidgets(
        'narrow 2x channels keep destinations and validation controls readable ${dark ? 'dark' : 'light'}',
        (tester) async {
      tester.view.physicalSize = const Size(320, 740);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final fixture = ChannelsEnglishFixture(dark: dark, scale: 2);
      fixture.connections = [
        for (final connection in channelEnglishConnections)
          SocialConnectionResult(
              platform: connection.platform,
              connected: true,
              connectionId: connection.connectionId,
              externalAccountId: connection.externalAccountId,
              displayName:
                  '${connection.displayName} ชื่อบัญชีลูกค้ายาวที่ต้องอ่านได้ครบ')
      ];
      addTearDown(fixture.dispose);
      addTearDown(() => tester.pumpWidget(const SizedBox.shrink()));
      await fixture.mount(tester);
      await channelEnglishExpectReadable(tester, '4 channels connected');
      await channelEnglishExpectReadable(
          tester, 'Choose only the channels for this post.');
      await channelEnglishExpectReadable(
          tester, 'Recheck publishing permissions');
      await channelEnglishExpectReadable(tester, 'Select all');
      for (final connection in fixture.connections) {
        await channelEnglishExpectReadable(tester, connection.displayName!);
        final readiness = find.byKey(
            ValueKey('uploader-channel-readiness-${connection.platform}'));
        await revealVideoEnglishControl(tester, readiness);
        expectVideoEnglishReadable(
            tester,
            find
                    .descendant(of: readiness, matching: find.byType(Text))
                    .evaluate()
                    .isEmpty
                ? readiness
                : find.descendant(of: readiness, matching: find.byType(Text)));
      }
      await tapVideoEnglishControl(tester, 'uploader-select-all-platforms');
      for (final platform
          in channelEnglishConnections.map((value) => value.platform)) {
        final settings =
            find.byKey(ValueKey('uploader-platform-settings-$platform'));
        await revealVideoEnglishControl(tester, settings);
        expect(settings.hitTestable(), findsOneWidget);
        expectVideoEnglishReadable(
            tester,
            find.descendant(
                of: settings, matching: find.text('Channel settings')));
      }
      expect(channelEnglishIsSelected(tester, 'YOUTUBE_SHORTS'), isTrue);
      expect(channelEnglishIsSelected(tester, 'FACEBOOK_REELS'), isTrue);
      await tapVideoEnglishControl(tester, 'uploader-wizard-next');
      final validation = find
          .byKey(const ValueKey('uploader-platform-validation-YOUTUBE_SHORTS'));
      expect(
          tester.widget<Semantics>(validation).properties.liveRegion, isTrue);
      await channelEnglishExpectReadable(
          tester, 'Indicate whether this YouTube video is made for kids.');
      await channelEnglishExpectReadable(
          tester, 'Edit this channel’s settings');
      await channelEnglishTap(
          tester,
          find.byKey(const ValueKey(
              'uploader-platform-validation-edit-YOUTUBE_SHORTS')));
      expect(find.byKey(const ValueKey('uploader-platform-settings-sheet')),
          findsOneWidget);
      await channelEnglishTap(tester,
          find.byKey(const ValueKey('uploader-platform-settings-cancel')));
      expect(channelEnglishIsSelected(tester, 'YOUTUBE_SHORTS'), isTrue);
      await tapVideoEnglishControl(tester, 'uploader-clear-all-platforms');
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        'narrow 2x loading failure and retry remain readable ${dark ? 'dark' : 'light'}',
        (tester) async {
      tester.view.physicalSize = const Size(320, 740);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final pending = Completer<List<SocialConnectionResult>>();
      final fixture = ChannelsEnglishFixture(dark: dark, scale: 2)
        ..connectionGate = pending.future;
      addTearDown(fixture.dispose);
      await fixture.mount(tester);
      await channelEnglishExpectReadable(tester, 'Checking channels...');
      await channelEnglishExpectReadable(
          tester, 'Please wait while channel status is checked.');
      await tapVideoEnglishControl(tester, 'uploader-wizard-next');
      await channelEnglishExpectReadable(
          tester, 'Checking connected channels. Please wait.');
      pending.completeError(StateError('local fake offline'));
      await tester.pumpAndSettle();
      await channelEnglishExpectReadable(
          tester, 'Could not check connected channels. Please try again.');
      await channelEnglishExpectReadable(
          tester, 'Account status is not confirmed. Try again before posting.');
      await channelEnglishExpectReadable(tester, 'Try again');
      fixture.connectionGate = null;
      fixture.connections = [];
      await tapVideoEnglishControl(tester, 'uploader-retry-connections');
      await channelEnglishExpectReadable(tester, 'No channels connected');
      await channelEnglishExpectReadable(
          tester, 'Connect your social accounts before posting.');
      expect(fixture.connectionReads, 2);
      expect(tester.takeException(), isNull);
    });
  }
}
