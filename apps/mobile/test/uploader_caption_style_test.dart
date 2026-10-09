import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postdee_mobile/core/auth/auth_session.dart';
import 'package:postdee_mobile/core/models/caption_writing_style.dart';
import 'package:postdee_mobile/core/network/postdee_api_client.dart';
import 'package:postdee_mobile/core/theme/app_theme.dart';
import 'package:postdee_mobile/features/captions/caption_writing_style_store.dart';
import 'package:postdee_mobile/features/shared/postdee_card.dart';
import 'package:postdee_mobile/features/uploader/uploader_screen.dart';
import 'package:postdee_mobile/features/uploader/video_picker_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/test_publish_draft_store.dart';
import 'support/uploader_wizard_test_navigation.dart';

const _styleButton = ValueKey('uploader-ai-style-button');
const _styleSheet = ValueKey('uploader-ai-style-sheet');
const _rememberSwitch = ValueKey('uploader-ai-style-remember');
const _captionField = ValueKey('uploader-caption-field');
const _generateButton = ValueKey('uploader-ai-generate-button');
int _videoSerial = 0;

File _video() {
  final file = File('${Directory.systemTemp.path}${Platform.pathSeparator}'
      'postdee-caption-style-${_videoSerial++}.mp4')
    ..writeAsBytesSync(List<int>.filled(512, 1));
  addTearDown(() {
    if (file.existsSync()) file.deleteSync();
  });
  return file;
}

class _StyleStore implements CaptionWritingStyleStore {
  final profiles = <String, CaptionWritingStyleProfile>{};
  final loads = <String>[];
  final saves = <({String owner, CaptionWritingStyleProfile profile})>[];
  Future<CaptionWritingStyleProfile> Function(String)? onLoad;
  Future<void> Function(String, CaptionWritingStyleProfile)? onSave;

  @override
  Future<CaptionWritingStyleProfile> load(String ownerUserId) async {
    loads.add(ownerUserId);
    return onLoad?.call(ownerUserId) ??
        profiles[ownerUserId] ??
        const CaptionWritingStyleProfile();
  }

  @override
  Future<void> save(
      String ownerUserId, CaptionWritingStyleProfile profile) async {
    await onSave?.call(ownerUserId, profile);
    saves.add((owner: ownerUserId, profile: profile));
    profiles[ownerUserId] = profile;
  }

  @override
  Future<void> clear(String ownerUserId) async => profiles.remove(ownerUserId);
}

RealClipCaptionResult _aiResult({bool fallback = false}) =>
    RealClipCaptionResult(
      caption: 'ข้อความจาก AI',
      isFallback: fallback,
      captionOptions: const [],
      hooks: const [],
      hashtags: const ['#review'],
      seoKeywords: const [],
      searchTitle: 'คลิป',
      source: const RealClipCaptionSource(
        videoS3Key: 'uploads/owner-a/clip.mp4',
        mode: 'AUDIO_ONLY',
        selectedFrameCount: 0,
      ),
      quota: const RealClipCaptionQuota(
        limit: 50,
        usedThisMonth: 1,
        remainingThisMonth: 49,
      ),
    );

class _Fixture {
  final store = _StyleStore();
  final draftStore = TestPublishDraftStore(ownerUserId: 'owner-a');
  final video = _video();
  final requests = <GenerateRealClipCaptionRequest>[];
  File? replacement;
  bool fallback = false;
  Completer<RealClipCaptionResult>? resultGate;
  int uploads = 0;
  double textScale = 1;

  Widget app() => MaterialApp(
        theme: AppTheme.light,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: Scaffold(
          body: UploaderScreen(
            draftStore: draftStore,
            captionWritingStyleStore: store,
            loadSocialConnections: () async => const [],
            loadSubscription: () async => const SubscriptionStatusResult(
              userId: 'owner-a',
              plan: 'STARTER',
              status: 'ACTIVE',
              canSchedule: true,
              canUseAiCaptions: true,
              canUseAnalytics: false,
            ),
            initialVideoPath: video.path,
            initialVideoName: 'clip.mp4',
            initialVideoSizeBytes: video.lengthSync(),
            initialVideoWidth: 1080,
            initialVideoHeight: 1920,
            createUpload: (request) async {
              uploads++;
              return UploadResult(
                id: 'upload-$uploads',
                videoS3Key: 'uploads/owner-a/${request.fileName}',
                storageProvider: 's3',
              );
            },
            uploadVideoFile: (_, __) async {},
            generateRealClipCaption: (request) async {
              requests.add(request);
              return resultGate?.future ?? _aiResult(fallback: fallback);
            },
            pickVideo: () async => PickedVideoFile(
              path: (replacement ?? video).path,
              name: 'replacement.mp4',
              sizeBytes: 512,
              width: 1080,
              height: 1920,
            ),
          ),
        ),
      );
}

Future<void> _show(WidgetTester tester, Finder finder) async {
  await tester.scrollUntilVisible(finder, 250,
      scrollable: find.byType(Scrollable).first);
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
}

Future<void> _showAiPanel(WidgetTester tester, _Fixture fixture) async {
  await tester.binding.setSurfaceSize(const Size(430, 1000));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(fixture.app());
  await tester.pumpAndSettle();
  await goToUploaderStep(tester, 1);
  final panel = find.byKey(const ValueKey('uploader-ai-open-panel'));
  await tester.scrollUntilVisible(panel, 250,
      scrollable: find.byType(Scrollable).first);
  await tester.ensureVisible(panel);
  await tester.pumpAndSettle();
  await tester.tap(panel);
  await tester.pumpAndSettle();
}

Future<void> _generate(WidgetTester tester) async {
  await _show(tester, find.byKey(_generateButton));
  await tester.tap(find.byKey(_generateButton));
  await tester.pumpAndSettle();
}

Future<void> _editAndNext(WidgetTester tester, String caption) async {
  await _show(tester, find.byKey(_captionField));
  await tester.enterText(find.byKey(_captionField), caption);
  await tester.tap(find.byKey(const ValueKey('uploader-wizard-next')));
  await tester.pumpAndSettle();
}

Future<void> _openStyle(WidgetTester tester) async {
  await _show(tester, find.byKey(_styleButton));
  await tester.tap(find.byKey(_styleButton));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AppTheme.applyThemeMode(ThemeMode.light);
    final sessions = PostDeeAuthSessionStore.instance;
    final previous = sessions.session;
    addTearDown(() {
      previous.isSignedIn ? sessions.signIn(previous) : sessions.clear();
    });
    sessions.signIn(
        AuthSession.authenticated(userId: 'owner-a', idToken: 'token-a'));
  });

  testWidgets('offers a compact style control inside the AI panel',
      (tester) async {
    await _showAiPanel(tester, _Fixture());
    expect(find.byKey(_styleButton), findsOneWidget);
    expect(find.byKey(const ValueKey('uploader-ai-style-summary')),
        findsOneWidget);
  });

  testWidgets('style sheet starts with remember edits enabled', (tester) async {
    await _showAiPanel(tester, _Fixture());
    expect(find.byKey(_styleButton), findsOneWidget);
    await tester.ensureVisible(find.byKey(_styleButton));
    await tester.tap(find.byKey(_styleButton));
    await tester.pumpAndSettle();
    expect(find.byKey(_styleSheet), findsOneWidget);
    expect(tester.widget<SwitchListTile>(find.byKey(_rememberSwitch)).value,
        isTrue);
    expect(find.text('น้ำเสียง'), findsOneWidget);
    expect(find.text('ความยาว'), findsOneWidget);
    expect(find.text('Emoji'), findsOneWidget);
  });

  testWidgets('saves manual choices for the owner and passes them to AI',
      (tester) async {
    final fixture = _Fixture();
    await _showAiPanel(tester, fixture);
    await _openStyle(tester);
    for (final key in ['tone-playful', 'length-short', 'emoji-none']) {
      await tester.tap(find.byKey(ValueKey('uploader-ai-style-$key')));
      await tester.pumpAndSettle();
    }
    await tester.tap(find.byKey(const ValueKey('uploader-ai-style-save')));
    await tester.pumpAndSettle();
    expect(fixture.store.saves.single.owner, 'owner-a');
    await _generate(tester);
    final style = fixture.requests.single.writingStyle!;
    expect(style.tone, CaptionWritingTone.playful);
    expect(style.length, CaptionWritingLength.short);
    expect(style.emoji, CaptionWritingEmoji.none);
  });

  testWidgets('only Caption Next learns a changed accepted AI caption',
      (tester) async {
    final fixture = _Fixture();
    await _showAiPanel(tester, fixture);
    await _generate(tester);
    expect(fixture.store.saves, isEmpty);
    await _editAndNext(tester, 'ข้อความที่ฉันแก้ให้เป็นตัวเอง');
    expect(
        find.byKey(const ValueKey('uploader-step-platforms')), findsOneWidget);
    expect(fixture.store.saves.single.profile.style.examples,
        ['ข้อความที่ฉันแก้ให้เป็นตัวเอง']);
    expect(fixture.store.saves.single.owner, 'owner-a');
  });

  for (final kind in ['manual', 'unchanged AI', 'fallback', 'progress jump']) {
    testWidgets('$kind never becomes a learned edit', (tester) async {
      final fixture = _Fixture()..fallback = kind == 'fallback';
      await _showAiPanel(tester, fixture);
      if (kind != 'manual') await _generate(tester);
      if (kind == 'fallback') {
        await _show(
            tester, find.byKey(const ValueKey('uploader-caption-reviewed')));
        await tester
            .tap(find.byKey(const ValueKey('uploader-caption-reviewed')));
        await tester.pumpAndSettle();
      }
      if (kind == 'progress jump') {
        await _show(tester, find.byKey(_captionField));
        await tester.enterText(
            find.byKey(_captionField), 'แก้แล้วแต่ยังไม่ยืนยัน');
        await goToUploaderStep(tester, 2);
      } else {
        await _editAndNext(
            tester,
            kind == 'unchanged AI'
                ? 'ข้อความจาก AI\n\n#review'
                : 'ข้อความแก้แล้ว');
      }
      expect(fixture.store.saves, isEmpty);
    });
  }

  testWidgets('remember off preserves memory but sends no learned examples',
      (tester) async {
    final fixture = _Fixture();
    fixture.store.profiles['owner-a'] = const CaptionWritingStyleProfile(
      style: CaptionWritingStyle(examples: ['ตัวอย่างของฉัน']),
      rememberEdits: false,
    );
    await _showAiPanel(tester, fixture);
    await _generate(tester);
    expect(fixture.requests.single.writingStyle!.examples, isEmpty);
    await _editAndNext(tester, 'แก้ผล AI');
    expect(fixture.store.saves, isEmpty);
    expect(
        fixture.store.profiles['owner-a']!.style.examples, ['ตัวอย่างของฉัน']);
  });

  testWidgets('clear removes learned examples and keeps manual preferences',
      (tester) async {
    final fixture = _Fixture();
    fixture.store.profiles['owner-a'] = const CaptionWritingStyleProfile(
      style: CaptionWritingStyle(
        tone: CaptionWritingTone.softSell,
        length: CaptionWritingLength.short,
        emoji: CaptionWritingEmoji.none,
        examples: ['ตัวอย่างส่วนตัว'],
      ),
      rememberEdits: false,
    );
    await _showAiPanel(tester, fixture);
    await _openStyle(tester);
    await tester.tap(find.byKey(const ValueKey('uploader-ai-style-clear')));
    await tester.pumpAndSettle();
    final profile = fixture.store.saves.single.profile;
    expect(profile.style.examples, isEmpty);
    expect(profile.style.tone, CaptionWritingTone.softSell);
    expect(profile.style.length, CaptionWritingLength.short);
    expect(profile.style.emoji, CaptionWritingEmoji.none);
    expect(profile.rememberEdits, isFalse);
  });

  testWidgets('saving and restoring a draft never carries a learning baseline',
      (tester) async {
    final fixture = _Fixture();
    await _showAiPanel(tester, fixture);
    await _generate(tester);
    await _show(tester, find.byKey(_captionField));
    await tester.enterText(
        find.byKey(_captionField), 'ข้อความแก้ก่อนบันทึกร่าง');
    await tester.tap(find.byKey(const ValueKey('uploader-save-draft-button')));
    await tester.pumpAndSettle();
    expect(fixture.draftStore.drafts, hasLength(1));
    expect(fixture.store.saves, isEmpty);
    await tester.tap(find.byKey(const ValueKey('uploader-open-drafts')));
    await tester.pumpAndSettle();
    final open = find.byKey(
        ValueKey('publish-draft-${fixture.draftStore.drafts.keys.single}'));
    await tester.ensureVisible(open);
    await tester.tap(open);
    await tester.pumpAndSettle();
    await goToUploaderStep(tester, 1);
    await _editAndNext(tester, 'ข้อความแก้หลังเปิดร่าง');
    expect(fixture.store.saves, isEmpty);
  });

  testWidgets(
      'clip replacement clears the baseline even after review acknowledgement',
      (tester) async {
    final fixture = _Fixture()..replacement = _video();
    await _showAiPanel(tester, fixture);
    await _generate(tester);
    await goToUploaderStep(tester, 0);
    final picker = find.byKey(const ValueKey('uploader-video-preview-picker'));
    await _show(tester, picker);
    await tester.tap(picker);
    await tester.pumpAndSettle();
    await goToUploaderStep(tester, 1);
    await _show(
        tester, find.byKey(const ValueKey('uploader-caption-reviewed')));
    await tester.tap(find.byKey(const ValueKey('uploader-caption-reviewed')));
    await tester.pumpAndSettle();
    await _editAndNext(tester, 'ข้อความให้ตรงกับคลิปใหม่');
    expect(fixture.store.saves, isEmpty);
  });

  testWidgets('a delayed owner load never exposes another account style',
      (tester) async {
    final fixture = _Fixture();
    final oldLoad = Completer<CaptionWritingStyleProfile>();
    fixture.store.onLoad = (owner) async => owner == 'owner-a'
        ? oldLoad.future
        : const CaptionWritingStyleProfile(
            style: CaptionWritingStyle(tone: CaptionWritingTone.directReview));
    await _showAiPanel(tester, fixture);
    PostDeeAuthSessionStore.instance.signIn(
        AuthSession.authenticated(userId: 'owner-b', idToken: 'token-b'));
    await tester.pumpAndSettle();
    oldLoad.complete(const CaptionWritingStyleProfile(
        style: CaptionWritingStyle(
            tone: CaptionWritingTone.playful,
            examples: ['ตัวอย่างของบัญชีเก่า'])));
    await tester.pumpAndSettle();
    await _openStyle(tester);
    expect(
        tester
            .widget<ChoiceChip>(find
                .byKey(const ValueKey('uploader-ai-style-tone-direct_review')))
            .selected,
        isTrue);
    expect(
        tester
            .widget<ChoiceChip>(
                find.byKey(const ValueKey('uploader-ai-style-tone-playful')))
            .selected,
        isFalse);
    expect(fixture.store.loads, ['owner-a', 'owner-b']);
  });

  testWidgets('generation waits for style loading and keeps clip guards',
      (tester) async {
    final fixture = _Fixture()..replacement = _video();
    final loadGate = Completer<CaptionWritingStyleProfile>();
    fixture.store.onLoad = (_) => loadGate.future;
    await _showAiPanel(tester, fixture);
    await _generate(tester);
    expect(fixture.uploads, 0);
    await goToUploaderStep(tester, 0);
    final picker = find.byKey(const ValueKey('uploader-video-preview-picker'));
    await _show(tester, picker);
    await tester.tap(picker);
    await tester.pumpAndSettle();
    loadGate.complete(const CaptionWritingStyleProfile(
        style: CaptionWritingStyle(examples: ['ตัวอย่าง'])));
    await tester.pumpAndSettle();
    expect(fixture.uploads, 0);
    expect(fixture.requests, isEmpty);
  });

  testWidgets(
      'text edited while AI runs is never learned from a rejected result',
      (tester) async {
    final fixture = _Fixture()..resultGate = Completer<RealClipCaptionResult>();
    await _showAiPanel(tester, fixture);
    await _generate(tester);
    await _show(tester, find.byKey(_captionField));
    await tester.enterText(find.byKey(_captionField), 'ข้อความระหว่างรอ AI');
    fixture.resultGate!.complete(_aiResult());
    await tester.pumpAndSettle();
    await _editAndNext(tester, 'ข้อความระหว่างรอ AI');
    expect(fixture.store.saves, isEmpty);
  });

  testWidgets('cancelled style choices are not saved or sent to AI',
      (tester) async {
    final fixture = _Fixture();
    await _showAiPanel(tester, fixture);
    await _openStyle(tester);
    await tester
        .tap(find.byKey(const ValueKey('uploader-ai-style-tone-friendly')));
    await tester.tap(find.text('ยกเลิก'));
    await tester.pumpAndSettle();
    expect(fixture.store.saves, isEmpty);
    await _generate(tester);
    expect(fixture.requests.single.writingStyle!.tone, CaptionWritingTone.auto);
  });

  testWidgets('failed local preference loading keeps AI working with defaults',
      (tester) async {
    final fixture = _Fixture();
    fixture.store.onLoad = (_) async => throw StateError('Local read failed');
    await _showAiPanel(tester, fixture);
    await _generate(tester);
    expect(fixture.requests.single.writingStyle!.toJson(),
        const CaptionWritingStyle().toJson());
    await _editAndNext(tester, 'ข้อความแก้แล้ว');
    expect(fixture.store.saves, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'failed manual save stays open and retries without claiming success',
      (tester) async {
    final fixture = _Fixture();
    var fail = true;
    fixture.store.onSave = (_, __) async {
      if (fail) throw StateError('Local write failed');
    };
    await _showAiPanel(tester, fixture);
    await _openStyle(tester);
    await tester
        .tap(find.byKey(const ValueKey('uploader-ai-style-tone-friendly')));
    final save = find.byKey(const ValueKey('uploader-ai-style-save'));
    await tester.tap(save);
    await tester.pumpAndSettle();
    expect(find.byKey(_styleSheet), findsOneWidget);
    expect(find.text('บันทึกสไตล์ไม่สำเร็จ กรุณาลองใหม่'), findsOneWidget);
    expect(fixture.store.saves, isEmpty);
    expect(
        tester
            .widget<Text>(
                find.byKey(const ValueKey('uploader-ai-style-summary')))
            .data,
        const CaptionWritingStyle().summary);
    fail = false;
    await tester.tap(save);
    await tester.pumpAndSettle();
    expect(find.byKey(_styleSheet), findsNothing);
    expect(fixture.store.saves.single.profile.style.tone,
        CaptionWritingTone.friendly);
  });

  testWidgets('late confirmed learning reloads memory for the replacement clip',
      (tester) async {
    final fixture = _Fixture()..replacement = _video();
    final saveGate = Completer<void>();
    fixture.store.onSave = (_, __) => saveGate.future;
    await _showAiPanel(tester, fixture);
    await _generate(tester);
    await _editAndNext(tester, 'ข้อความแก้ของคลิปแรก');
    await goToUploaderStep(tester, 0);
    final picker = find.byKey(const ValueKey('uploader-video-preview-picker'));
    await _show(tester, picker);
    await tester.tap(picker);
    await tester.pumpAndSettle();
    saveGate.complete();
    await tester.pumpAndSettle();
    // The prior confirmed edit may finish storing for its owner. Reload its
    // committed profile rather than applying the stale save snapshot.
    expect(fixture.store.saves.single.profile.style.examples,
        ['ข้อความแก้ของคลิปแรก']);
    await goToUploaderStep(tester, 1);
    final panel = find.byKey(const ValueKey('uploader-ai-open-panel'));
    await _show(tester, panel);
    await tester.tap(panel);
    await tester.pumpAndSettle();
    await _generate(tester);
    expect(
        fixture.requests.last.writingStyle!.examples, ['ข้อความแก้ของคลิปแรก']);
    expect(fixture.store.loads, ['owner-a', 'owner-a']);
  });

  testWidgets('owner switch clears the accepted learning baseline',
      (tester) async {
    final fixture = _Fixture();
    await _showAiPanel(tester, fixture);
    await _generate(tester);
    PostDeeAuthSessionStore.instance.signIn(
        AuthSession.authenticated(userId: 'owner-b', idToken: 'token-b'));
    await tester.pumpAndSettle();
    await _editAndNext(tester, 'ข้อความแก้หลังเปลี่ยนบัญชี');
    expect(fixture.store.saves, isEmpty);
    expect(fixture.store.loads, ['owner-a', 'owner-b']);
  });

  testWidgets('style sheet scrolls on a small phone with larger text',
      (tester) async {
    final fixture = _Fixture()..textScale = 1.3;
    await _showAiPanel(tester, fixture);
    await tester.binding.setSurfaceSize(const Size(390, 760));
    await tester.pumpAndSettle();
    await _openStyle(tester);
    final save = find.byKey(const ValueKey('uploader-ai-style-save'));
    await tester.ensureVisible(save);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.tap(save);
    await tester.pumpAndSettle();
    expect(find.byKey(_styleSheet), findsNothing);
    expect(fixture.store.saves, hasLength(1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('A to B to A cannot accept the first account generation result',
      (tester) async {
    final fixture = _Fixture()..resultGate = Completer<RealClipCaptionResult>();
    await _showAiPanel(tester, fixture);
    await _generate(tester);
    final sessions = PostDeeAuthSessionStore.instance;
    sessions.signIn(
        AuthSession.authenticated(userId: 'owner-b', idToken: 'token-b'));
    sessions.signIn(
        AuthSession.authenticated(userId: 'owner-a', idToken: 'token-a-new'));
    fixture.resultGate!.complete(_aiResult());
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(find.byKey(_captionField)).controller!.text,
        isEmpty);
    await _editAndNext(tester, 'ข้อความของรอบบัญชีใหม่');
    expect(fixture.store.saves, isEmpty);
  });

  testWidgets('pending confirmed edit save disables another Generate',
      (tester) async {
    final fixture = _Fixture();
    final saveGate = Completer<void>();
    fixture.store.onSave = (_, __) => saveGate.future;
    await _showAiPanel(tester, fixture);
    await _generate(tester);
    await _editAndNext(tester, 'ข้อความที่กำลังจำ');
    await goToUploaderStep(tester, 1);
    final panel = find.byKey(const ValueKey('uploader-ai-open-panel'));
    await _show(tester, panel);
    await tester.tap(panel);
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<PostDeeGradientButton>(find.byKey(_generateButton))
            .onPressed,
        isNull);
    expect(fixture.requests, hasLength(1));
    saveGate.complete();
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<PostDeeGradientButton>(find.byKey(_generateButton))
            .onPressed,
        isNotNull);
  });
}
