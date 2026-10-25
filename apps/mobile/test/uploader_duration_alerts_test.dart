import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postdee_mobile/core/auth/auth_session.dart';
import 'package:postdee_mobile/core/network/postdee_api_client.dart';
import 'package:postdee_mobile/features/uploader/platform_publish_preflight.dart';
import 'package:postdee_mobile/features/uploader/platform_publish_settings.dart';
import 'package:postdee_mobile/features/uploader/publish_draft.dart';
import 'package:postdee_mobile/features/uploader/uploader_screen.dart';
import 'package:postdee_mobile/features/uploader/video_picker_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/publish_preflight_fixtures.dart';
import 'support/test_publish_draft_store.dart';
import 'support/uploader_wizard_test_navigation.dart';

const _connections = [
  SocialConnectionResult(
    platform: 'TIKTOK',
    connected: true,
    externalAccountId: 'tiktok-seller',
    displayName: 'ร้าน TikTok',
  ),
  SocialConnectionResult(
    platform: 'YOUTUBE_SHORTS',
    connected: true,
    externalAccountId: 'youtube-seller',
    displayName: 'ช่อง YouTube',
  ),
  SocialConnectionResult(
    platform: 'INSTAGRAM_REELS',
    connected: true,
    externalAccountId: 'instagram-seller',
    displayName: 'ร้าน Instagram',
  ),
  SocialConnectionResult(
    platform: 'FACEBOOK_REELS',
    connected: true,
    externalAccountId: 'facebook-page',
    displayName: 'เพจ Facebook',
  ),
];

Finder _key(String key) => find.byKey(ValueKey(key));

class _Fixture {
  _Fixture({this.sourceDuration = 200, double? finalDuration})
      : finalDuration = finalDuration ?? sourceDuration ?? 10 {
    directory = Directory.systemTemp.createTempSync('uploader-duration-');
    addTearDown(() {
      if (directory.existsSync()) directory.deleteSync(recursive: true);
    });
    initialVideo = picked('initial.mp4', sourceDuration);
  }

  final double? sourceDuration;
  final double finalDuration;
  late final Directory directory;
  late final PickedVideoFile initialVideo;
  final drafts = TestPublishDraftStore();
  final picks = <PickedVideoFile>[];
  final durations = <String, double?>{};
  final metadataPaths = <String>[];
  final effects = <String>[];
  final posts = <CreatePostRequest>[];

  PickedVideoFile picked(String name, double? duration) {
    final file = File('${directory.path}${Platform.pathSeparator}$name')
      ..writeAsBytesSync([1, 2, 3]);
    durations[file.path] = duration;
    return PickedVideoFile(
      name: name,
      path: file.path,
      sizeBytes: file.lengthSync(),
      width: 720,
      height: 1280,
      durationSeconds: duration,
    );
  }

  Widget app({
    bool prefill = true,
    bool passInitialDuration = true,
    String? initialDraftId,
    VideoMetadataReader? metadataReader,
    Set<String>? connectedPlatforms,
  }) =>
      MaterialApp(
        home: Scaffold(
          body: UploaderScreen(
            draftStore: drafts,
            initialDraftId: initialDraftId,
            initialVideoPath:
                prefill && initialDraftId == null ? initialVideo.path : null,
            initialVideoName: 'initial.mp4',
            initialVideoSizeBytes: 3,
            initialVideoWidth: 720,
            initialVideoHeight: 1280,
            initialVideoDurationSeconds:
                prefill && passInitialDuration ? sourceDuration : null,
            readVideoMetadata: metadataReader ??
                (path) async {
                  metadataPaths.add(path);
                  return VideoDimensions(
                    width: 720,
                    height: 1280,
                    durationSeconds: durations[path],
                  );
                },
            pickVideo: () async => picks.isEmpty ? null : picks.removeAt(0),
            loadSocialConnections: () async => _connections
                .where((connection) =>
                    connectedPlatforms == null ||
                    connectedPlatforms.contains(connection.platform))
                .toList(),
            loadSocialPublishingReadiness: connectedPublishingReadinessForTests,
            loadSubscription: () async => const SubscriptionStatusResult(
              userId: 'test-user',
              plan: 'PRO',
              status: 'ACTIVE',
              phoneVerified: true,
              requiresPhoneVerification: false,
              canSchedule: true,
              canUseAiCaptions: true,
              canUseAnalytics: true,
            ),
            checkPublishingReadiness: () async {},
            probePublishMedia: (_) async {
              effects.add('probe');
              return PublishMediaMetadata(
                durationSeconds: finalDuration,
                width: 720,
                height: 1280,
                sizeBytes: 3,
                hasVideo: true,
                hasAudio: true,
                videoCodec: 'h264',
                audioCodec: 'aac',
                fps: 30,
                sampleRate: 48000,
                channels: 2,
                container: 'mp4',
              );
            },
            createUpload: (_) async {
              effects.add('upload');
              return const UploadResult(
                id: 'upload',
                videoS3Key: 'uploads/test-user/video.mp4',
                storageProvider: 'mock',
              );
            },
            uploadVideoFile: (_, __) async => effects.add('file'),
            createPost: (request) async {
              effects.add('post');
              posts.add(request);
              return QueuedPostResult(
                id: 'post',
                status: 'QUEUED',
                videoS3Key: request.videoS3Key,
                platforms: request.platforms,
              );
            },
          ),
        ),
      );

  void expectNoRemoteEffects() {
    expect(effects, isEmpty);
    expect(posts, isEmpty);
  }
}

Future<void> _show(WidgetTester tester, Finder target) async {
  await tester.scrollUntilVisible(target, 150, scrollable: uploaderMainScroll);
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
}

Future<void> _tap(WidgetTester tester, String key) async {
  final target = _key(key);
  await _show(tester, target);
  await tester.tap(target);
  await tester.pumpAndSettle();
}

Future<void> _pick(WidgetTester tester) async {
  await goToUploaderStep(tester, 0);
  await _tap(tester, 'uploader-video-preview-picker');
}

Future<void> _enterCaption(WidgetTester tester) async {
  await goToUploaderStep(tester, 1);
  final caption = _key('uploader-caption-field');
  await _show(tester, caption);
  await tester.enterText(caption, 'คลิปสินค้าทดสอบ');
  await tester.pumpAndSettle();
}

bool _selected(String platform) => find
    .descendant(
      of: _key('uploader-platform-$platform'),
      matching: find.byIcon(Icons.check_circle_rounded),
    )
    .evaluate()
    .isNotEmpty;

Future<void> _submit(WidgetTester tester) async {
  await goToUploaderStep(tester, 3);
  await _tap(tester, 'publish-review-confirm');
}

void main() {
  late AuthSession previous;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    previous = PostDeeAuthSessionStore.instance.session;
    PostDeeAuthSessionStore.instance
        .signIn(const AuthSession(userId: 'test-user'));
  });

  tearDown(() {
    PostDeeAuthSessionStore.instance.signIn(previous);
  });

  testWidgets(
      'picking a long clip warns for Facebook and Shorts before posting',
      (tester) async {
    final fixture = _Fixture();
    fixture.picks.add(fixture.initialVideo);
    await tester.pumpWidget(fixture.app(prefill: false));
    await tester.pumpAndSettle();
    await _pick(tester);

    for (final platform in ['YOUTUBE_SHORTS', 'FACEBOOK_REELS']) {
      await _show(tester, _key('uploader-duration-warning-$platform'));
      expect(_key('uploader-duration-warning-$platform'), findsOneWidget);
    }
    expect(_key('uploader-step-body-0'), findsOneWidget);
    expect(_key('uploader-duration-warning-INSTAGRAM_REELS'), findsNothing);
    fixture.expectNoRemoteEffects();
  });

  testWidgets('a clip over ten minutes warns for TikTok before choosing a mode',
      (tester) async {
    final fixture = _Fixture(sourceDuration: 601);
    await tester.pumpWidget(fixture.app());
    await tester.pumpAndSettle();
    await _show(tester, _key('uploader-duration-warning-TIKTOK'));
    expect(_key('uploader-duration-warning-TIKTOK'), findsOneWidget);
    await goToUploaderStep(tester, 2);
    final tiktok = _key('uploader-platform-TIKTOK');
    await _show(tester, tiktok);
    expect(tester.widget<InkWell>(tiktok).onTap, isNull);
    fixture.expectNoRemoteEffects();
  });

  testWidgets('duration-blocked destinations cannot be selected',
      (tester) async {
    final fixture = _Fixture();
    await tester.pumpWidget(fixture.app());
    await tester.pumpAndSettle();
    await goToUploaderStep(tester, 2);

    for (final platform in ['YOUTUBE_SHORTS', 'FACEBOOK_REELS']) {
      final row = _key('uploader-platform-$platform');
      await _show(tester, row);
      expect(tester.widget<InkWell>(row).onTap, isNull);
      expect(_key('uploader-platform-duration-$platform'), findsOneWidget);
      await tester.tap(row);
      await tester.pumpAndSettle();
      expect(_selected(platform), isFalse);
    }
    await _tap(tester, 'uploader-platform-INSTAGRAM_REELS');
    expect(_selected('INSTAGRAM_REELS'), isTrue);
    fixture.expectNoRemoteEffects();
  });

  testWidgets('select all adds only destinations compatible with the clip',
      (tester) async {
    final fixture = _Fixture();
    await tester.pumpWidget(fixture.app());
    await tester.pumpAndSettle();
    await goToUploaderStep(tester, 2);
    await _tap(tester, 'uploader-select-all-platforms');

    for (final platform in [
      'TIKTOK',
      'YOUTUBE_SHORTS',
      'INSTAGRAM_REELS',
      'FACEBOOK_REELS',
    ]) {
      await _show(tester, _key('uploader-platform-$platform'));
      expect(_selected(platform),
          platform == 'TIKTOK' || platform == 'INSTAGRAM_REELS');
    }
    fixture.expectNoRemoteEffects();
  });

  testWidgets(
      'a newly incompatible selection remains until the seller removes it',
      (tester) async {
    final fixture = _Fixture(sourceDuration: 60);
    fixture.picks.add(fixture.picked('longer.mp4', 200));
    await tester.pumpWidget(fixture.app());
    await tester.pumpAndSettle();
    await goToUploaderStep(tester, 2);
    await _tap(tester, 'uploader-platform-FACEBOOK_REELS');
    expect(_selected('FACEBOOK_REELS'), isTrue);

    await _pick(tester);
    await goToUploaderStep(tester, 2);
    await _tap(tester, 'uploader-select-all-platforms');
    final facebook = _key('uploader-platform-FACEBOOK_REELS');
    await _show(tester, facebook);
    expect(_selected('FACEBOOK_REELS'), isTrue);
    expect(tester.widget<InkWell>(facebook).onTap, isNotNull);
    expect(_key('uploader-platform-duration-FACEBOOK_REELS'), findsOneWidget);
    await tester.tap(facebook);
    await tester.pumpAndSettle();
    expect(_selected('FACEBOOK_REELS'), isFalse);
    expect(tester.widget<InkWell>(facebook).onTap, isNull);
    fixture.expectNoRemoteEffects();
  });

  testWidgets(
      'replacing a long clip clears warnings and enables its destinations',
      (tester) async {
    final fixture = _Fixture();
    fixture.picks.add(fixture.picked('shorter.mp4', 60));
    await tester.pumpWidget(fixture.app());
    await tester.pumpAndSettle();
    await _show(tester, _key('uploader-duration-warning-FACEBOOK_REELS'));

    await _pick(tester);
    expect(_key('uploader-duration-warning-FACEBOOK_REELS'), findsNothing);
    expect(_key('uploader-duration-warning-YOUTUBE_SHORTS'), findsNothing);
    await goToUploaderStep(tester, 2);
    for (final platform in ['YOUTUBE_SHORTS', 'FACEBOOK_REELS']) {
      final row = _key('uploader-platform-$platform');
      await _show(tester, row);
      expect(tester.widget<InkWell>(row).onTap, isNotNull);
      expect(_key('uploader-platform-duration-$platform'), findsNothing);
    }
    fixture.expectNoRemoteEffects();
  });

  testWidgets(
      'prefilled clips without a duration read metadata for the early hint',
      (tester) async {
    final fixture = _Fixture();
    await tester.pumpWidget(fixture.app(passInitialDuration: false));
    await tester.pumpAndSettle();
    await _show(tester, _key('uploader-duration-warning-FACEBOOK_REELS'));
    expect(fixture.metadataPaths, contains(fixture.initialVideo.path));
    fixture.expectNoRemoteEffects();
  });

  testWidgets('restored incompatible selections block Next and confirmation',
      (tester) async {
    final fixture = _Fixture();
    final now = DateTime(2026, 10, 25, 10);
    fixture.drafts.drafts['draft'] = PublishDraft(
      version: publishDraftManifestVersion,
      id: 'draft',
      ownerUserId: 'test-user',
      submissionRequestId: 'submit_${'a' * 64}',
      createdAt: now,
      updatedAt: now,
      videoPath: fixture.initialVideo.path,
      videoName: 'initial.mp4',
      videoSizeBytes: 3,
      videoWidth: 720,
      videoHeight: 1280,
      caption: 'คลิปสินค้า',
      aiGuidance: '',
      watermarkEnabled: false,
      platformApiValues: const {'FACEBOOK_REELS'},
      platformSettings: const PlatformPublishSettings(
        facebookPublishMode: FacebookPublishMode.publish,
        facebookIsAiGenerated: false,
      ),
    );
    await tester.pumpWidget(fixture.app(initialDraftId: 'draft'));
    await tester.pumpAndSettle();
    await goToUploaderStep(tester, 0);
    await _show(tester, _key('uploader-duration-warning-FACEBOOK_REELS'));
    expect(fixture.metadataPaths, contains(fixture.initialVideo.path));
    await goToUploaderStep(tester, 2);
    await _show(tester, _key('uploader-platform-FACEBOOK_REELS'));
    expect(_selected('FACEBOOK_REELS'), isTrue);
    await _tap(tester, 'uploader-wizard-next');
    expect(_key('uploader-step-body-2'), findsOneWidget);
    expect(_key('uploader-step-body-3'), findsNothing);
    expect(find.textContaining('1 นาที 30 วินาที'), findsWidgets);
    await goToUploaderStep(tester, 3);
    expect(_key('uploader-selected-duration-error'), findsOneWidget);
    expect(
      tester.widget<FilledButton>(_key('publish-review-confirm')).onPressed,
      isNull,
    );
    fixture.expectNoRemoteEffects();
  });

  testWidgets('unknown duration does not claim a destination is too long',
      (tester) async {
    final fixture = _Fixture(sourceDuration: null);
    await tester.pumpWidget(fixture.app());
    await tester.pumpAndSettle();
    expect(_key('uploader-duration-warning-FACEBOOK_REELS'), findsNothing);
    expect(_key('uploader-duration-warning-YOUTUBE_SHORTS'), findsNothing);
    await goToUploaderStep(tester, 2);
    final facebook = _key('uploader-platform-FACEBOOK_REELS');
    await _show(tester, facebook);
    expect(tester.widget<InkWell>(facebook).onTap, isNotNull);
    fixture.expectNoRemoteEffects();
  });

  testWidgets('a late metadata result cannot replace the newer clip duration',
      (tester) async {
    final fixture = _Fixture();
    final oldMetadata = Completer<VideoDimensions?>();
    fixture.picks.add(fixture.picked('newer-short.mp4', 60));
    await tester.pumpWidget(fixture.app(
      passInitialDuration: false,
      metadataReader: (_) => oldMetadata.future,
    ));
    await tester.pumpAndSettle();
    await _pick(tester);
    oldMetadata.complete(const VideoDimensions(
      width: 720,
      height: 1280,
      durationSeconds: 200,
    ));
    await tester.pumpAndSettle();
    await goToUploaderStep(tester, 2);
    final facebook = _key('uploader-platform-FACEBOOK_REELS');
    await _show(tester, facebook);
    expect(tester.widget<InkWell>(facebook).onTap, isNotNull);
    expect(_key('uploader-platform-duration-FACEBOOK_REELS'), findsNothing);
    fixture.expectNoRemoteEffects();
  });

  testWidgets('disposing a pending metadata read leaves no owned timeout timer',
      (tester) async {
    final fixture = _Fixture();
    final metadata = Completer<VideoDimensions?>();
    var reads = 0;
    await tester.pumpWidget(fixture.app(
      passInitialDuration: false,
      metadataReader: (_) {
        reads++;
        return metadata.future;
      },
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(reads, 1);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    expect(tester.takeException(), isNull);
    fixture.expectNoRemoteEffects();
    // Leave the reader unresolved. Flutter's end-of-test timer check must pass
    // because disposal cancels the uploader's timeout, not because time elapsed.
  });

  testWidgets('final file duration is rechecked before remote upload',
      (tester) async {
    final fixture = _Fixture(sourceDuration: 60, finalDuration: 91);
    await tester.pumpWidget(fixture.app());
    await tester.pumpAndSettle();
    await _enterCaption(tester);
    await goToUploaderStep(tester, 2);
    await _tap(tester, 'uploader-platform-FACEBOOK_REELS');
    await _tap(tester, 'uploader-platform-settings-FACEBOOK_REELS');
    await tester.ensureVisible(_key('uploader-facebook-publish'));
    await tester.tap(_key('uploader-facebook-publish'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(_key('uploader-facebook-ai-no'));
    await tester.tap(_key('uploader-facebook-ai-no'));
    await tester.pumpAndSettle();
    await tester.tap(_key('uploader-platform-settings-save'));
    await tester.pumpAndSettle();
    await _submit(tester);

    expect(fixture.effects, ['probe']);
    expect(fixture.posts, isEmpty);
    expect(find.textContaining('1 นาที 30 วินาที'), findsWidgets);
    expect(fixture.drafts.drafts, isNotEmpty);
  });

  testWidgets('a compatible selected channel can post despite other warnings',
      (tester) async {
    final fixture = _Fixture();
    await tester.pumpWidget(fixture.app());
    await tester.pumpAndSettle();
    await _enterCaption(tester);
    await goToUploaderStep(tester, 2);
    await _tap(tester, 'uploader-platform-INSTAGRAM_REELS');
    await _tap(tester, 'uploader-platform-settings-INSTAGRAM_REELS');
    await tester.ensureVisible(_key('uploader-instagram-ai-no'));
    await tester.tap(_key('uploader-instagram-ai-no'));
    await tester.pumpAndSettle();
    await tester.tap(_key('uploader-platform-settings-save'));
    await tester.pumpAndSettle();
    await _submit(tester);

    expect(fixture.effects, ['probe', 'upload', 'file', 'post']);
    expect(fixture.posts.single.platforms, ['INSTAGRAM_REELS']);
  });
}
