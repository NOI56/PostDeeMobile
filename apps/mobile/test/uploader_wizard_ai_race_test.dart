import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postdee_mobile/core/auth/auth_session.dart';
import 'package:postdee_mobile/core/network/postdee_api_client.dart';
import 'package:postdee_mobile/core/theme/app_theme.dart';
import 'package:postdee_mobile/features/shared/postdee_card.dart';
import 'package:postdee_mobile/features/uploader/clip_frame_extractor.dart';
import 'package:postdee_mobile/features/uploader/uploader_screen.dart';
import 'package:postdee_mobile/features/uploader/video_picker_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/test_publish_draft_store.dart';
import 'support/uploader_wizard_test_navigation.dart';

const _captionKey = ValueKey('uploader-caption-field');

PickedVideoFile _video(String name) {
  final directory = Directory.systemTemp.createTempSync('postdee-wizard-ai-');
  addTearDown(() {
    if (directory.existsSync()) directory.deleteSync(recursive: true);
  });
  final file = File('${directory.path}${Platform.pathSeparator}$name')
    ..writeAsBytesSync(List<int>.filled(512, 1));
  return PickedVideoFile(
    path: file.path,
    name: name,
    sizeBytes: file.lengthSync(),
    width: 1080,
    height: 1920,
  );
}

RealClipCaptionResult _aiResult(
        {String caption = 'แคปชันจาก AI ของคลิปเดิม',
        List<String> hashtags = const [],
        List<String> seoKeywords = const [],
        bool isFallback = false}) =>
    RealClipCaptionResult(
      caption: caption,
      isFallback: isFallback,
      captionOptions: [caption],
      hooks: const [],
      hashtags: hashtags,
      seoKeywords: seoKeywords,
      searchTitle: 'คลิปเดิม',
      source: const RealClipCaptionSource(
        videoS3Key: 'uploads/old-clip.mp4',
        mode: 'AUDIO_ONLY',
        selectedFrameCount: 0,
      ),
      quota: RealClipCaptionQuota(
        limit: 50,
        usedThisMonth: 1,
        remainingThisMonth: 49,
        charged: !isFallback,
      ),
    );

class _AiFixture {
  _AiFixture({
    this.captionGate,
    this.captionGates,
    this.isPro = false,
    this.extractFrames,
    this.firstUploadCreationGate,
    this.gatedUploadNumber = 1,
    this.expireFirstUpload = false,
  }) : firstVideo = _video('old-clip.mp4');

  final PickedVideoFile firstVideo;
  final Completer<RealClipCaptionResult>? captionGate;
  final List<Completer<RealClipCaptionResult>>? captionGates;
  final bool isPro;
  final UploaderClipFrameExtractor? extractFrames;
  final Completer<UploadResult>? firstUploadCreationGate;
  final int gatedUploadNumber;
  final bool expireFirstUpload;
  final List<CreateUploadRequest> uploadRequests = [];
  final List<String> uploadedPaths = [];
  final draftStore = TestPublishDraftStore();
  PickedVideoFile? replacementVideo;
  bool cancelPick = false;
  int uploadsCreated = 0;
  int filesUploaded = 0;
  int captionsGenerated = 0;
  int postsCreated = 0;

  Widget app({bool prefill = true}) => MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: UploaderScreen(
            draftStore: draftStore,
            loadSocialConnections: () async => const [],
            loadSubscription: () async => SubscriptionStatusResult(
              userId: 'seller-starter',
              plan: isPro ? 'PRO' : 'STARTER',
              status: 'ACTIVE',
              phoneVerified: true,
              requiresPhoneVerification: false,
              canUseFreePostQuota: false,
              canSchedule: false,
              canUseAiCaptions: true,
              canUseAnalytics: false,
            ),
            pickVideo: () async =>
                cancelPick ? null : replacementVideo ?? firstVideo,
            extractFrames: extractFrames,
            createUpload: (request) async {
              uploadsCreated++;
              uploadRequests.add(request);
              if (uploadsCreated == gatedUploadNumber &&
                  firstUploadCreationGate != null) {
                return firstUploadCreationGate!.future;
              }
              return UploadResult(
                id: 'ai-upload-$uploadsCreated',
                videoS3Key: 'uploads/${request.fileName}',
                storageProvider: 's3',
              );
            },
            uploadVideoFile: (_, file) async {
              filesUploaded++;
              uploadedPaths.add(file.path);
              if (expireFirstUpload && filesUploaded == 1) {
                throw const ApiException('Expired upload URL',
                    code: 'UPLOAD_URL_EXPIRED');
              }
            },
            generateRealClipCaption: (_) async {
              captionsGenerated++;
              if (captionGates != null) {
                return captionGates![captionsGenerated - 1].future;
              }
              return captionGate?.future ?? _aiResult();
            },
            createPost: (_) async {
              postsCreated++;
              throw StateError('These tests must never submit a post');
            },
            initialVideoPath: prefill ? firstVideo.path : null,
            initialVideoName: prefill ? firstVideo.name : null,
            initialVideoSizeBytes: prefill ? firstVideo.sizeBytes : null,
            initialVideoWidth: prefill ? firstVideo.width : null,
            initialVideoHeight: prefill ? firstVideo.height : null,
          ),
        ),
      );

  void expectNoApiWrites() {
    expect(uploadsCreated, 0);
    expect(filesUploaded, 0);
    expect(captionsGenerated, 0);
    expect(postsCreated, 0);
  }
}

Future<void> _show(WidgetTester tester, Finder finder) async {
  await tester.scrollUntilVisible(
    finder,
    250,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
}

Future<void> _openAi(WidgetTester tester) async {
  await goToUploaderStep(tester, 1);
  final panel = find.byKey(const ValueKey('uploader-ai-open-panel'));
  await _show(tester, panel);
  await tester.tap(panel);
  await tester.pumpAndSettle();
}

Future<void> _generate(WidgetTester tester) async {
  await _openAi(tester);
  final button = find.byKey(const ValueKey('uploader-ai-generate-button'));
  await _show(tester, button);
  await tester.tap(button);
  await tester.pumpAndSettle();
}

Future<void> _enterCaption(WidgetTester tester, String caption) async {
  await _show(tester, find.byKey(_captionKey));
  await tester.enterText(find.byKey(_captionKey), caption);
  await tester.pump();
}

String _caption(WidgetTester tester) =>
    tester.widget<TextField>(find.byKey(_captionKey)).controller!.text;

Future<void> _pickAgain(WidgetTester tester) async {
  await goToUploaderStep(tester, 0);
  final picker = find.byKey(const ValueKey('uploader-video-preview-picker'));
  await _show(tester, picker);
  await tester.tap(picker);
  await tester.pumpAndSettle();
  await goToUploaderStep(tester, 1);
  await _show(tester, find.byKey(_captionKey));
}

Future<void> _saveAndRestore(WidgetTester tester, _AiFixture fixture) async {
  final save = find.byKey(const ValueKey('uploader-save-draft-button'));
  await _show(tester, save);
  await tester.tap(save);
  await tester.pumpAndSettle();
  final draftId = fixture.draftStore.drafts.keys.single;
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pumpAndSettle();
  await tester.pumpWidget(fixture.app(prefill: false));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const ValueKey('uploader-open-drafts')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(ValueKey('publish-draft-$draftId')));
  await tester.pumpAndSettle();
  await goToUploaderStep(tester, 1);
  await _show(tester, find.byKey(_captionKey));
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AppTheme.applyThemeMode(ThemeMode.light);
  });

  testWidgets(
      'AI publish text omits SEO and appends unique normalized hashtags',
      (tester) async {
    final gate = Completer<RealClipCaptionResult>();
    final fixture = _AiFixture(captionGate: gate);
    await tester.pumpWidget(fixture.app());
    await tester.pumpAndSettle();
    await _generate(tester);
    gate.complete(_aiResult(
      caption: 'เรื่องจากคลิป #Sale #ขายดี',
      hashtags: [' sale ', '#SALE', 'ขายดี', '#ใหม่', ' ใหม่ ', '##PostDee'],
      seoKeywords: ['คำค้นหนึ่ง', 'คำค้นสอง'],
    ));
    await tester.pumpAndSettle();
    await _show(tester, find.byKey(_captionKey));
    expect(_caption(tester), 'เรื่องจากคลิป #Sale #ขายดี\n\n#ใหม่ #PostDee');
    final seo = find.byKey(const ValueKey('uploader-ai-seo-keywords'));
    await _show(tester, seo);
    expect(find.text('คำค้นหนึ่ง, คำค้นสอง'), findsNothing);
    await tester.tap(seo);
    await tester.pumpAndSettle();
    expect(find.text('คำค้นหนึ่ง, คำค้นสอง'), findsOneWidget);
    expect(_caption(tester), isNot(contains('SEO:')));

    fixture.replacementVideo = _video('different-seo-source.mp4');
    await _pickAgain(tester);
    expect(
        find.byKey(const ValueKey('uploader-ai-seo-keywords')), findsNothing);
  });

  for (final generated in [false, true]) {
    testWidgets(
        '${generated ? 'generated' : 'manual'} caption survives replacement and requires explicit review',
        (tester) async {
      final fixture = _AiFixture();
      await tester.pumpWidget(fixture.app());
      await tester.pumpAndSettle();
      if (generated) {
        await _generate(tester);
      } else {
        await goToUploaderStep(tester, 1);
        await _enterCaption(tester, 'ข้อความที่เขียนเองทั้งหมด #ร้านฉัน');
      }
      await _show(tester, find.byKey(_captionKey));
      final originalCaption = _caption(tester);
      fixture.replacementVideo = _video('replacement-review.mp4');
      await _pickAgain(tester);
      expect(_caption(tester), originalCaption);
      final notice =
          find.byKey(const ValueKey('uploader-caption-review-notice'));
      await _show(tester, notice);
      expect(notice, findsOneWidget);
      await _enterCaption(tester, '$originalCaption ');
      expect(notice, findsOneWidget);
      final acknowledge =
          find.byKey(const ValueKey('uploader-caption-reviewed'));
      await _show(tester, acknowledge);
      await tester.tap(acknowledge);
      await tester.pumpAndSettle();
      expect(notice, findsNothing);
      expect(_caption(tester), '$originalCaption ');
      await _saveAndRestore(tester, fixture);
      expect(_caption(tester), '$originalCaption ');
      expect(notice, findsNothing);
    });
  }

  testWidgets('cancelled and same-path picks do not require caption review',
      (tester) async {
    final fixture = _AiFixture();
    await tester.pumpWidget(fixture.app());
    await tester.pumpAndSettle();
    await goToUploaderStep(tester, 1);
    await _enterCaption(tester, 'ข้อความเดิม');
    fixture.cancelPick = true;
    await _pickAgain(tester);
    fixture.cancelPick = false;
    await _pickAgain(tester);
    expect(_caption(tester), 'ข้อความเดิม');
    expect(find.byKey(const ValueKey('uploader-caption-review-notice')),
        findsNothing);
    await _saveAndRestore(tester, fixture);
    expect(find.byKey(const ValueKey('uploader-caption-review-notice')),
        findsNothing);
    fixture.expectNoApiWrites();
  });

  testWidgets('replacement review survives saving and reopening a draft',
      (tester) async {
    final fixture = _AiFixture();
    await tester.pumpWidget(fixture.app());
    await tester.pumpAndSettle();
    await goToUploaderStep(tester, 1);
    await _enterCaption(tester, 'แคปชั่นที่เก็บไว้');
    fixture.replacementVideo = _video('saved-review.mp4');
    await _pickAgain(tester);
    await _saveAndRestore(tester, fixture);
    expect(_caption(tester), 'แคปชั่นที่เก็บไว้');
    expect(find.byKey(const ValueKey('uploader-caption-review-notice')),
        findsOneWidget);
    fixture.expectNoApiWrites();
  });

  testWidgets('fresh non-fallback AI result clears replacement review',
      (tester) async {
    final fixture = _AiFixture();
    await tester.pumpWidget(fixture.app());
    await tester.pumpAndSettle();
    await goToUploaderStep(tester, 1);
    await _enterCaption(tester, 'แคปชั่นเดิม');
    fixture.replacementVideo = _video('fresh-review.mp4');
    await _pickAgain(tester);
    expect(find.byKey(const ValueKey('uploader-caption-review-notice')),
        findsOneWidget);
    await goToUploaderStep(tester, 0);
    await _generate(tester);
    await _show(tester, find.byKey(_captionKey));
    expect(_caption(tester), 'แคปชันจาก AI ของคลิปเดิม');
    expect(find.byKey(const ValueKey('uploader-caption-review-notice')),
        findsNothing);
  });

  testWidgets(
      'fallback review persists in drafts and known warning survives repick',
      (tester) async {
    final gate = Completer<RealClipCaptionResult>();
    final fixture = _AiFixture(captionGate: gate);
    await tester.pumpWidget(fixture.app());
    await tester.pumpAndSettle();
    await _generate(tester);
    gate.complete(_aiResult(isFallback: true, caption: 'ข้อความสำรอง'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('uploader-caption-review-notice')),
        findsOneWidget);
    final save = find.byKey(const ValueKey('uploader-save-draft-button'));
    await _show(tester, save);
    await tester.tap(save);
    await tester.pumpAndSettle();
    expect(fixture.draftStore.savedRequests.single.captionNeedsReview, isTrue);
    fixture.replacementVideo = _video('fallback-review.mp4');
    await _pickAgain(tester);
    expect(_caption(tester), 'ข้อความสำรอง');
    await _show(
        tester, find.byKey(const ValueKey('uploader-ai-caption-fallback')));
    expect(find.textContaining('แคปชันนี้เป็นข้อความสำรอง'), findsOneWidget);
    await _saveAndRestore(tester, fixture);
    expect(_caption(tester), 'ข้อความสำรอง');
    expect(find.byKey(const ValueKey('uploader-caption-review-notice')),
        findsOneWidget);
  });

  testWidgets(
      'shows a fallback notice beside the caption without claiming an AI quota charge',
      (tester) async {
    final gate = Completer<RealClipCaptionResult>();
    final fixture = _AiFixture(captionGate: gate);
    await tester.pumpWidget(fixture.app());
    await tester.pumpAndSettle();
    await _generate(tester);
    gate.complete(_aiResult(isFallback: true, caption: 'ข้อความสำรอง'));
    await tester.pumpAndSettle();
    await _show(
        tester, find.byKey(const ValueKey('uploader-ai-caption-fallback')));
    expect(find.textContaining('แคปชันนี้เป็นข้อความสำรอง'), findsOneWidget);
    expect(find.textContaining('ไม่หักโควตา AI'), findsOneWidget);
    expect(_caption(tester), 'ข้อความสำรอง');
    expect(fixture.postsCreated, 0);
  });

  testWidgets(
      'picking a clip and navigating never automatically runs AI or upload',
      (tester) async {
    final fixture = _AiFixture();
    await tester.pumpWidget(fixture.app(prefill: false));
    await tester.pumpAndSettle();
    await tester
        .tap(find.byKey(const ValueKey('uploader-video-preview-picker')));
    await tester.pumpAndSettle();
    expect(find.text(fixture.firstVideo.name), findsOneWidget);
    for (final step in [1, 2, 3, 0]) {
      await goToUploaderStep(tester, step);
    }
    await _openAi(tester);
    fixture.expectNoApiWrites();

    final button = find.byKey(const ValueKey('uploader-ai-generate-button'));
    await _show(tester, button);
    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(fixture.uploadsCreated, 1);
    expect(fixture.filesUploaded, 1);
    expect(fixture.uploadedPaths, [fixture.firstVideo.path]);
    expect(fixture.captionsGenerated, 1);
    expect(fixture.postsCreated, 0);
    await _show(tester, find.byKey(_captionKey));
    expect(_caption(tester), 'แคปชันจาก AI ของคลิปเดิม');
  });

  testWidgets('a late AI result preserves the caption edited while waiting',
      (tester) async {
    final gate = Completer<RealClipCaptionResult>();
    final fixture = _AiFixture(captionGate: gate);
    await tester.pumpWidget(fixture.app());
    await tester.pumpAndSettle();
    await _generate(tester);
    expect(fixture.captionsGenerated, 1);
    await _enterCaption(tester, 'ข้อความที่ฉันเขียนเองระหว่างรอ');

    gate.complete(_aiResult());
    await tester.pumpAndSettle();
    expect(_caption(tester), 'ข้อความที่ฉันเขียนเองระหว่างรอ');
    expect(fixture.postsCreated, 0);
    await _show(tester, find.byKey(const ValueKey('uploader-ai-open-panel')));
    expect(
        find.text(
            'คุณแก้ข้อความระหว่างที่ AI ทำงาน จึงเก็บข้อความที่คุณเขียนไว้'),
        findsOneWidget);
  });

  testWidgets(
      'changing AI guidance keeps the current caption instead of stale output',
      (tester) async {
    final gate = Completer<RealClipCaptionResult>();
    final fixture = _AiFixture(captionGate: gate);
    await tester.pumpWidget(fixture.app());
    await tester.pumpAndSettle();
    await goToUploaderStep(tester, 1);
    await _enterCaption(tester, 'แคปชันก่อนเรียก AI');
    await _generate(tester);
    final guidance = find.byKey(const ValueKey('uploader-ai-guidance-field'));
    await _show(tester, guidance);
    await tester.enterText(guidance, 'ขอเปลี่ยนเป็นโทนจริงใจ');

    gate.complete(_aiResult());
    await tester.pumpAndSettle();
    await _show(tester, find.byKey(_captionKey));
    expect(_caption(tester), 'แคปชันก่อนเรียก AI');
    expect(fixture.captionsGenerated, 1);
    expect(fixture.postsCreated, 0);
  });

  testWidgets('changing video while AI waits ignores the old clip result',
      (tester) async {
    final gate = Completer<RealClipCaptionResult>();
    final fixture = _AiFixture(captionGate: gate)
      ..replacementVideo = _video('new-clip.mp4');
    await tester.pumpWidget(fixture.app());
    await tester.pumpAndSettle();
    await goToUploaderStep(tester, 1);
    await _enterCaption(tester, 'ข้อความสำหรับคลิปใหม่');
    await _generate(tester);
    await goToUploaderStep(tester, 0);
    final picker = find.byKey(const ValueKey('uploader-video-preview-picker'));
    await _show(tester, picker);
    await tester.tap(picker);
    await tester.pumpAndSettle();
    expect(find.text('new-clip.mp4'), findsOneWidget);

    gate.complete(_aiResult());
    await tester.pumpAndSettle();
    await goToUploaderStep(tester, 1);
    expect(_caption(tester), 'ข้อความสำหรับคลิปใหม่');
    expect(fixture.captionsGenerated, 1);
    expect(fixture.uploadsCreated, 1);
    expect(fixture.postsCreated, 0);
  });

  testWidgets(
      'a late AI result does not cross into a different signed-in owner',
      (tester) async {
    final sessions = PostDeeAuthSessionStore.instance;
    final previous = sessions.session;
    addTearDown(() {
      previous.isSignedIn ? sessions.signIn(previous) : sessions.clear();
    });
    sessions.signIn(
        AuthSession.authenticated(userId: 'owner-a', idToken: 'token-a'));
    final gate = Completer<RealClipCaptionResult>();
    final fixture = _AiFixture(captionGate: gate);
    await tester.pumpWidget(fixture.app());
    await tester.pumpAndSettle();
    await goToUploaderStep(tester, 1);
    await _enterCaption(tester, 'ข้อความที่ต้องเก็บไว้');
    await _generate(tester);
    sessions.signIn(
        AuthSession.authenticated(userId: 'owner-b', idToken: 'token-b'));
    gate.complete(_aiResult());
    await tester.pumpAndSettle();
    await _show(tester, find.byKey(_captionKey));
    expect(_caption(tester), 'ข้อความที่ต้องเก็บไว้');
    expect(fixture.captionsGenerated, 1);
    expect(fixture.postsCreated, 0);
  });

  for (final changeOwner in [true, false]) {
    testWidgets(
        'Pro extraction stops all remaining uploads when ${changeOwner ? 'owner' : 'clip'} changes',
        (tester) async {
      final sessions = PostDeeAuthSessionStore.instance;
      final previous = sessions.session;
      addTearDown(() {
        previous.isSignedIn ? sessions.signIn(previous) : sessions.clear();
      });
      sessions.signIn(
          AuthSession.authenticated(userId: 'owner-a', idToken: 'token-a'));
      final frameGate = Completer<List<File>>();
      final frame = File(_video('extracted-frame.jpg').path);
      var extracted = 0;
      final fixture = _AiFixture(
        isPro: true,
        extractFrames: (file, {int maxFrames = 3}) async {
          extracted++;
          expect(maxFrames, 3);
          return frameGate.future;
        },
      )..replacementVideo = _video('replacement-clip.mp4');
      await tester.pumpWidget(fixture.app());
      await tester.pumpAndSettle();
      await _generate(tester);
      expect(extracted, 1);
      expect(fixture.uploadRequests.single.contentType, 'video/mp4');
      expect(fixture.uploadedPaths, [fixture.firstVideo.path]);

      if (changeOwner) {
        sessions.signIn(
            AuthSession.authenticated(userId: 'owner-b', idToken: 'token-b'));
      } else {
        await goToUploaderStep(tester, 0);
        final picker =
            find.byKey(const ValueKey('uploader-video-preview-picker'));
        await _show(tester, picker);
        await tester.tap(picker);
        await tester.pumpAndSettle();
      }
      frameGate.complete([frame]);
      await tester.pumpAndSettle();
      expect(fixture.uploadRequests.map((request) => request.contentType),
          ['video/mp4']);
      expect(fixture.uploadedPaths, [fixture.firstVideo.path]);
      expect(fixture.captionsGenerated, 0);
      expect(fixture.postsCreated, 0);
      expect(frame.existsSync(), isFalse);
      expect(File(fixture.firstVideo.path).existsSync(), isTrue);
    });
  }

  testWidgets(
      'owner change during upload creation prevents old media sending and retry',
      (tester) async {
    final sessions = PostDeeAuthSessionStore.instance;
    final previous = sessions.session;
    addTearDown(() {
      previous.isSignedIn ? sessions.signIn(previous) : sessions.clear();
    });
    sessions.signIn(
        AuthSession.authenticated(userId: 'owner-a', idToken: 'token-a'));
    final uploadGate = Completer<UploadResult>();
    final fixture = _AiFixture(
      firstUploadCreationGate: uploadGate,
      expireFirstUpload: true,
    );
    await tester.pumpWidget(fixture.app());
    await tester.pumpAndSettle();
    await _generate(tester);
    expect(fixture.uploadsCreated, 1);
    expect(fixture.filesUploaded, 0);
    sessions.signIn(
        AuthSession.authenticated(userId: 'owner-b', idToken: 'token-b'));
    uploadGate.complete(const UploadResult(
      id: 'old-owner-upload',
      videoS3Key: 'uploads/old-owner-clip.mp4',
      storageProvider: 's3',
    ));
    await tester.pumpAndSettle();

    expect(fixture.uploadsCreated, 1);
    expect(fixture.filesUploaded, 0);
    expect(fixture.captionsGenerated, 0);
    expect(fixture.postsCreated, 0);
  });

  testWidgets(
      'Pro owner change during frame upload creation stops frame sending and later frames',
      (tester) async {
    final sessions = PostDeeAuthSessionStore.instance;
    final previous = sessions.session;
    addTearDown(() {
      previous.isSignedIn ? sessions.signIn(previous) : sessions.clear();
    });
    sessions.signIn(
        AuthSession.authenticated(userId: 'owner-a', idToken: 'token-a'));
    final uploadGate = Completer<UploadResult>();
    final frameFiles = [
      File(_video('first-frame.jpg').path),
      File(_video('second-frame.jpg').path),
    ];
    final fixture = _AiFixture(
      isPro: true,
      firstUploadCreationGate: uploadGate,
      gatedUploadNumber: 2,
      extractFrames: (_, {int maxFrames = 3}) async => frameFiles,
    );
    await tester.pumpWidget(fixture.app());
    await tester.pumpAndSettle();
    await _generate(tester);
    expect(fixture.uploadRequests.map((request) => request.contentType),
        ['video/mp4', 'image/jpeg']);
    expect(fixture.uploadedPaths, [fixture.firstVideo.path]);

    sessions.signIn(
        AuthSession.authenticated(userId: 'owner-b', idToken: 'token-b'));
    uploadGate.complete(const UploadResult(
      id: 'old-owner-frame-upload',
      videoS3Key: 'uploads/old-owner-frame.jpg',
      storageProvider: 's3',
    ));
    await tester.pumpAndSettle();
    expect(fixture.uploadsCreated, 2);
    expect(fixture.uploadedPaths, [fixture.firstVideo.path]);
    expect(fixture.captionsGenerated, 0);
    expect(fixture.postsCreated, 0);
  });

  testWidgets(
      'new clip unlocks AI immediately and old completion cannot unlock newer work',
      (tester) async {
    final firstGate = Completer<RealClipCaptionResult>();
    final secondGate = Completer<RealClipCaptionResult>();
    final fixture = _AiFixture(captionGates: [firstGate, secondGate])
      ..replacementVideo = _video('new-caption-clip.mp4');
    await tester.pumpWidget(fixture.app());
    await tester.pumpAndSettle();
    await _generate(tester);
    expect(fixture.captionsGenerated, 1);
    await goToUploaderStep(tester, 0);
    final picker = find.byKey(const ValueKey('uploader-video-preview-picker'));
    await _show(tester, picker);
    await tester.tap(picker);
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<OutlinedButton>(
              find.byKey(const ValueKey('uploader-save-draft-button')),
            )
            .onPressed,
        isNotNull);
    await _openAi(tester);
    final generate = find.byKey(const ValueKey('uploader-ai-generate-button'));
    await _show(tester, generate);
    expect(tester.widget<PostDeeGradientButton>(generate).onPressed, isNotNull);
    await tester.tap(generate);
    await tester.pumpAndSettle();
    expect(fixture.captionsGenerated, 2);

    firstGate.complete(_aiResult(caption: 'ผลเก่าของคลิป A'));
    await tester.pumpAndSettle();
    expect(tester.widget<PostDeeGradientButton>(generate).onPressed, isNull);
    expect(
        tester
            .widget<OutlinedButton>(
              find.byKey(const ValueKey('uploader-save-draft-button')),
            )
            .onPressed,
        isNull);
    await _show(tester, find.byKey(_captionKey));
    expect(_caption(tester), isNot(contains('ผลเก่าของคลิป A')));

    secondGate.complete(_aiResult(caption: 'ผลใหม่ของคลิป B'));
    await tester.pumpAndSettle();
    expect(_caption(tester), 'ผลใหม่ของคลิป B');
    expect(
        tester
            .widget<OutlinedButton>(
              find.byKey(const ValueKey('uploader-save-draft-button')),
            )
            .onPressed,
        isNotNull);
    expect(fixture.uploadsCreated, 2);
    expect(fixture.uploadedPaths,
        [fixture.firstVideo.path, fixture.replacementVideo!.path]);
    expect(fixture.postsCreated, 0);
  });
}
