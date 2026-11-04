import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postdee_mobile/core/auth/auth_session.dart';
import 'package:postdee_mobile/core/network/postdee_api_client.dart';
import 'package:postdee_mobile/features/uploader/clip_group_draft.dart';
import 'package:postdee_mobile/features/uploader/platform_publish_settings.dart';
import 'package:postdee_mobile/features/uploader/publish_draft.dart';
import 'package:postdee_mobile/features/uploader/tiktok_video_preparer.dart';
import 'package:postdee_mobile/features/uploader/uploader_screen.dart';
import 'package:postdee_mobile/features/uploader/video_picker_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/publish_preflight_fixtures.dart';
import 'uploader_video_english_test.dart';

const _revision =
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
const _changedRevision =
    'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';
const _groupId = 'tiktok-group';
const _sourceId = 'tiktok-source';
const _partIds = ['tiktok-part-0', 'tiktok-part-1'];
const _durations = [6.25, 8.5];
final _now = DateTime(2026, 11, 5, 10);

enum _Change { none, creatorRevision, account }

class _Store extends VideoEnglishDrafts {
  final receiptsBeforeDeletion = <String, PublishDraftUploadedMedia?>{};
  final acceptedBeforeDeletion = <String, String?>{};

  @override
  Future<void> deleteDraft(String id) async {
    receiptsBeforeDeletion[id] = drafts[id]?.uploadedMedia;
    acceptedBeforeDeletion[id] = groups[_groupId]
        ?.items
        .where((item) => item.draftId == id)
        .firstOrNull
        ?.acceptedPostId;
    await super.deleteDraft(id);
  }
}

class _Fixture extends VideoEnglishFixture {
  _Fixture({this.change = _Change.none}) : super(locale: const Locale('th')) {
    initialDraftId = _sourceId;
    quota = const SubscriptionStatusResult(
        userId: videoEnglishOwner,
        plan: 'PRO',
        status: 'ACTIVE',
        remainingPostsThisMonth: 10,
        availablePostUnits: 10,
        phoneVerified: true,
        requiresPhoneVerification: false,
        canSchedule: true,
        canUseAiCaptions: true,
        canUseAnalytics: false);
  }

  final _Change change;
  final _Store _store = _Store();
  @override
  _Store get store => _store;
  final preparations = <TikTokVideoPreparationRequest>[];
  final uploads = <CreateUploadRequest>[];
  final requests = <CreatePostRequest>[];
  final events = <String>[];
  String connectionId = 'tiktok-owned-connection';
  String connectionRevision = _revision;
  String creatorRevision = _revision;
  String externalAccountId = 'owned-tiktok';
  int optionReads = 0;

  TikTokPublishingOptionsResult _options() => TikTokPublishingOptionsResult(
      connectionId: connectionId,
      creatorInfoRevision: creatorRevision,
      creatorInfo: TikTokCreatorInfo(
          creatorAvatarUrl: '',
          creatorUsername: externalAccountId,
          creatorNickname: 'บัญชี TikTok ของเจ้าของคลิป',
          privacyLevelOptions: const [TikTokPrivacyLevel.selfOnly],
          commentDisabled: false,
          duetDisabled: true,
          stitchDisabled: false,
          maxVideoPostDurationSec: 60));

  Future<void> seed() async {
    for (final id in [_sourceId, ..._partIds]) {
      final video = makeVideo('$id.mp4', duration: 10);
      await store.saveDraft(PublishDraftSaveRequest(
          id: id,
          createdAt: _now,
          updatedAt: _now,
          videoFile: File(video.path),
          videoName: video.name,
          videoSizeBytes: video.sizeBytes,
          videoWidth: video.width,
          videoHeight: video.height,
          caption: 'แคปชั่นสำหรับ $id',
          captionNeedsReview: true,
          aiGuidance: '',
          watermarkEnabled: false,
          platformApiValues: const {'TIKTOK'},
          // A stored flag must never replace consent for this runtime intent.
          platformSettings: const PlatformPublishSettings(
              tiktokPublishMode: TikTokPublishMode.directPost,
              tiktokPrivacyLevel: TikTokPrivacyLevel.selfOnly,
              tiktokCreatorInfoRevision: _revision,
              tiktokMusicUsageConfirmed: true),
          clipGroupId: _groupId,
          isClipGroupSource: id == _sourceId));
    }
    await store.saveClipGroup(
        ClipGroupDraft(
            id: _groupId,
            ownerUserId: videoEnglishOwner,
            sourceDraftId: _sourceId,
            title: 'ชุดคลิป TikTok สองตอน',
            sharedCaption: 'แคปชั่นหลักของชุด',
            deliveryMode: ClipGroupDeliveryMode.immediate,
            items: [
              for (var i = 0; i < _partIds.length; i++)
                ClipGroupItem(
                    draftId: _partIds[i],
                    index: i,
                    sourceStartSeconds: i * 10.0,
                    sourceEndSeconds: (i + 1) * 10.0,
                    platformApiValues: const {'TIKTOK'},
                    usesSharedCaption: false),
            ],
            createdAt: _now,
            updatedAt: _now),
        expectedRevision: null);
  }

  @override
  UploaderScreen screen() => UploaderScreen(
        fullScreen: true,
        initialDraftId: initialDraftId,
        draftStore: store,
        enableRevenueCatBilling: false,
        now: () => _now,
        readVideoMetadata: (_) async => const VideoDimensions(
            width: 1080, height: 1920, durationSeconds: 10),
        probePublishMedia: probeValidPublishMedia,
        loadTemplates: () async => const [],
        loadSubscription: () async => quota,
        loadPostQuota: () async => quota,
        loadCaptionQuota: () async => const CaptionQuotaResult(
            plan: 'PRO',
            quota: RealClipCaptionQuota(
                limit: 120, usedThisMonth: 0, remainingThisMonth: 120)),
        loadSocialConnections: () async => [
          SocialConnectionResult(
              platform: 'TIKTOK',
              connected: true,
              connectionId: connectionId,
              connectionRevision: connectionRevision,
              externalAccountId: externalAccountId,
              displayName: 'บัญชี TikTok ของเจ้าของคลิป'),
        ],
        loadSocialPublishingReadiness: () async => [
          SocialPublishingConnectionReadiness(
              platform: 'TIKTOK',
              state: SocialPublishingState.ready,
              connectionId: connectionId,
              connectionRevision: connectionRevision),
        ],
        loadTikTokDurationOptions: () async => _options(),
        loadTikTokPublishingOptions: () async {
          optionReads++;
          return _options();
        },
        checkPublishingReadiness: () async {},
        prepareTikTokVideo: (request) async {
          preparations.add(request);
          final i = _partIds
              .indexWhere((id) => request.inputFile.path.endsWith('$id.mp4'));
          expect(i, greaterThanOrEqualTo(0));
          expect(request.maxDurationSeconds, 60);
          events.add('prepare:${_partIds[i]}');
          final prepared =
              makeVideo('prepared-$i.mp4', duration: _durations[i]);
          return TikTokPreparedVideoResult(
              file: File(prepared.path),
              fileName: prepared.name,
              sizeBytes: prepared.sizeBytes,
              width: prepared.width!,
              height: prepared.height!,
              durationSeconds: _durations[i]);
        },
        createUpload: (request) async {
          uploads.add(request);
          events.add('upload:${request.fileName}');
          return UploadResult(
              id: 'upload-${uploads.length}',
              videoS3Key: 'uploads/${request.fileName}',
              storageProvider: 'mock');
        },
        uploadVideoFile: (_, file) async => expect(file.existsSync(), isTrue),
        createPost: (request) async {
          requests.add(request);
          final draft = store.drafts.values.singleWhere(
              (draft) => draft.submissionRequestId == request.clientRequestId);
          events.add('post:${draft.id}');
          expect(draft.uploadedMedia?.videoS3Key, request.videoS3Key);
          expect(draft.uploadedMedia?.videoDurationSeconds,
              _durations[_partIds.indexOf(draft.id)]);
          if (requests.length == 1) {
            if (change == _Change.creatorRevision) {
              creatorRevision = _changedRevision;
            } else if (change == _Change.account) {
              connectionId = 'new-tiktok-connection';
              connectionRevision = _changedRevision;
              creatorRevision = _changedRevision;
              externalAccountId = 'another-tiktok-account';
            }
          }
          return QueuedPostResult(
              id: 'accepted-${draft.id}',
              videoS3Key: request.videoS3Key,
              platforms: request.platforms,
              status: 'PUBLISHING');
        },
        recoverPostSubmission: (_) async =>
            throw StateError('Fresh group must not recover an old request'),
      );

  @override
  Future<void> mount(WidgetTester tester, {bool settle = true}) async {
    await tester.binding.setSurfaceSize(const Size(430, 1100));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await super.mount(tester, settle: settle);
    await _settle(tester);
    expect(_key('clip-group-review'), findsOneWidget);
  }
}

Finder _key(String key) => find.byKey(ValueKey(key));

Future<void> _settle(WidgetTester tester) async {
  // File fingerprints use OS futures that the widget fake clock cannot flush.
  for (var i = 0; i < 20; i++) {
    await tester
        .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
    await tester.pump(const Duration(milliseconds: 50));
  }
  // The batch progress indicator keeps animating while a consent sheet waits
  // for the seller, so settling all scheduled frames would never complete.
  await tester.pump(const Duration(milliseconds: 500));
}

Future<void> _tap(WidgetTester tester, String key) async {
  await tester.ensureVisible(_key(key));
  await tester.tap(_key(key));
  await _settle(tester);
}

Future<void> _confirmSet(WidgetTester tester, _Fixture fixture) async {
  await _tap(tester, 'clip-group-next');
  await _tap(tester, 'clip-group-next');
  expect(_key('uploader-platform-settings-sheet'), findsNothing);
  expect(fixture.preparations, isEmpty);
  expect(fixture.uploads, isEmpty);
  expect(fixture.requests, isEmpty);
  await _tap(tester, 'clip-group-confirm');
}

Future<void> _consentToOnePart(WidgetTester tester) async {
  expect(_key('uploader-platform-settings-sheet'), findsOneWidget);
  final music = _key('uploader-tiktok-music-consent');
  expect(tester.widget<CheckboxListTile>(music).value, isFalse,
      reason: 'Every part needs its own fresh explicit music consent');
  expect(
      tester
          .widget<FilledButton>(_key('uploader-platform-settings-save'))
          .onPressed,
      isNull);
  await _tap(tester, 'uploader-tiktok-music-consent');
  expect(tester.widget<CheckboxListTile>(music).value, isTrue);
  expect(
      tester
          .widget<FilledButton>(_key('uploader-platform-settings-save'))
          .onPressed,
      isNotNull);
  await _tap(tester, 'uploader-platform-settings-save');
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    final sessions = PostDeeAuthSessionStore.instance;
    final previous = sessions.session;
    sessions.signIn(AuthSession.authenticated(
        userId: videoEnglishOwner, idToken: 'clip-group-tiktok-test'));
    addTearDown(() =>
        previous.isSignedIn ? sessions.signIn(previous) : sessions.clear());
  });

  testWidgets(
      'two Direct parts require two fresh consent sheets before posting '
      'with independent IDs and verified duration receipts', (tester) async {
    final fixture = _Fixture();
    addTearDown(fixture.dispose);
    await fixture.seed();
    final expectedIds = [
      for (final id in _partIds) fixture.store.drafts[id]!.submissionRequestId,
    ];
    await fixture.mount(tester);
    await _confirmSet(tester, fixture);
    await _consentToOnePart(tester);
    expect(fixture.preparations, isEmpty);
    expect(fixture.uploads, isEmpty);
    expect(fixture.requests, isEmpty,
        reason: 'The entire set is reviewed before the first remote write');
    await _consentToOnePart(tester);
    expect(fixture.requests, hasLength(2), reason: fixture.events.join(' | '));
    expect(fixture.requests.map((request) => request.clientRequestId),
        expectedIds);
    expect(expectedIds.toSet(), hasLength(2));
    expect(fixture.preparations, hasLength(2));
    expect(fixture.uploads, hasLength(2));
    expect(fixture.optionReads, greaterThan(2),
        reason:
            'Posting revalidates creator options beyond the consent sheets');
    for (var i = 0; i < _partIds.length; i++) {
      final settings = fixture.requests[i].platformSettings['TIKTOK']!
          as Map<String, Object?>;
      expect(settings['publishMode'], 'DIRECT_POST');
      expect(settings['musicUsageConfirmed'], isTrue);
      expect(settings['creatorInfoRevision'], _revision);
      expect(settings['videoDurationSeconds'], _durations[i]);
      expect(
          fixture
              .store.receiptsBeforeDeletion[_partIds[i]]?.videoDurationSeconds,
          _durations[i]);
      expect(fixture.store.acceptedBeforeDeletion[_partIds[i]],
          'accepted-${_partIds[i]}');
    }
    expect(fixture.store.groups[_groupId]!.isComplete, isTrue);
    expect(fixture.store.drafts.keys, [_sourceId]);
    expect(_key('clip-group-result'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final change in [_Change.creatorRevision, _Change.account]) {
    testWidgets(
        '${change.name} change after the first accepted Direct part '
        'stops the second part without reusing its old approval',
        (tester) async {
      final fixture = _Fixture(change: change);
      addTearDown(fixture.dispose);
      await fixture.seed();
      await fixture.mount(tester);
      await _confirmSet(tester, fixture);
      await _consentToOnePart(tester);
      expect(fixture.requests, isEmpty);
      await _consentToOnePart(tester);
      expect(fixture.requests, hasLength(1),
          reason: fixture.events.join(' | '));
      expect(fixture.preparations, hasLength(1));
      expect(fixture.uploads, hasLength(1));
      final group = fixture.store.groups[_groupId]!;
      expect(group.items.first.acceptedPostId, 'accepted-${_partIds.first}');
      expect(group.items.last.isAccepted, isFalse);
      expect(fixture.store.drafts.containsKey(_partIds.first), isFalse);
      expect(fixture.store.drafts[_partIds.last]!.uploadedMedia, isNull);
      expect(fixture.store.drafts.containsKey(_sourceId), isTrue);
      expect(_key('clip-group-result'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
