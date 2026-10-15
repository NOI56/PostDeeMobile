import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postdee_mobile/core/auth/auth_session.dart';
import 'package:postdee_mobile/core/network/postdee_api_client.dart';
import 'package:postdee_mobile/core/theme/app_theme.dart';
import 'package:postdee_mobile/features/uploader/publish_draft.dart';
import 'package:postdee_mobile/features/uploader/uploader_screen.dart';
import 'package:postdee_mobile/features/uploader/video_picker_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/publish_preflight_fixtures.dart';
import 'support/test_publish_draft_store.dart';
import 'support/uploader_wizard_test_navigation.dart';

Finder _key(String value) => find.byKey(ValueKey(value));
Finder get _captionField => _key('uploader-caption-field');
Finder get _saveButton => _key('uploader-save-draft-button');
Finder get _savedIndicator => _key('uploader-draft-saved-indicator');
Finder get _waitingIndicator => _key('uploader-ai-waiting-indicator');
Finder get _readyIndicator => _key('uploader-ai-caption-ready');

class _DraftStore extends TestPublishDraftStore {
  _DraftStore() : super(ownerUserId: 'feedback-owner');

  Completer<void>? saveGate;
  Completer<void>? readbackGate;
  var attempts = 0;
  var failSave = false;

  @override
  Future<PublishDraft> saveDraft(PublishDraftSaveRequest request) async {
    attempts++;
    await saveGate?.future;
    if (failSave) throw const FileSystemException('fixture write failed');
    return super.saveDraft(request);
  }

  @override
  Future<List<PublishDraft>> listDrafts() async {
    if (savedRequests.isNotEmpty) await readbackGate?.future;
    return super.listDrafts();
  }
}

RealClipCaptionResult _result({bool fallback = false}) => RealClipCaptionResult(
      caption: 'แคปชันทั้งหมดจากคลิปจริง',
      isFallback: fallback,
      captionOptions: const [],
      hooks: const [],
      hashtags: const [],
      seoKeywords: const [],
      searchTitle: 'คลิปจริง',
      source: const RealClipCaptionSource(
        videoS3Key: 'uploads/feedback-owner/clip.mp4',
        mode: 'AUDIO_ONLY',
        selectedFrameCount: 0,
      ),
      quota: RealClipCaptionQuota(
        limit: 50,
        usedThisMonth: 1,
        remainingThisMonth: 49,
        charged: !fallback,
      ),
    );

class _Fixture {
  _Fixture() {
    final root = Directory.systemTemp.createTempSync('postdee-feedback-');
    addTearDown(() => root.deleteSync(recursive: true));
    final file = File('${root.path}${Platform.pathSeparator}clip.mp4')
      ..writeAsBytesSync(List<int>.filled(512, 1));
    video = PickedVideoFile(
      path: file.path,
      name: 'clip.mp4',
      sizeBytes: file.lengthSync(),
      width: 1080,
      height: 1920,
    );
    final next = File('${root.path}${Platform.pathSeparator}replacement.mp4')
      ..writeAsBytesSync(List<int>.filled(512, 2));
    replacement = PickedVideoFile(
      path: next.path,
      name: 'replacement.mp4',
      sizeBytes: next.lengthSync(),
      width: 1080,
      height: 1920,
    );
  }

  late final PickedVideoFile video;
  late final PickedVideoFile replacement;
  final drafts = _DraftStore();
  final captionGate = Completer<RealClipCaptionResult>();
  var uploads = 0;
  var generators = 0;
  var posts = 0;
  var readiness = 0;
  var connected = false;

  Widget app({bool reducedMotion = false, bool tickerEnabled = true}) =>
      MaterialApp(
        theme: AppTheme.light,
        builder: (context, child) => MediaQuery(
          data:
              MediaQuery.of(context).copyWith(disableAnimations: reducedMotion),
          child: child!,
        ),
        home: Scaffold(
          body: TickerMode(
            enabled: tickerEnabled,
            child: UploaderScreen(
              probePublishMedia: probeValidPublishMedia,
              loadSocialPublishingReadiness: connectedPublishingReadinessForTests,
              fullScreen: true,
              draftStore: drafts,
              initialVideoPath: video.path,
              initialVideoName: video.name,
              initialVideoSizeBytes: video.sizeBytes,
              initialVideoWidth: video.width,
              initialVideoHeight: video.height,
              loadSocialConnections: () async => connected
                  ? const [
                      SocialConnectionResult(
                        platform: 'TIKTOK',
                        connected: true,
                        displayName: 'ร้านของเรา',
                        externalAccountId: 'feedback-tiktok',
                      ),
                    ]
                  : const [],
              enableRevenueCatBilling: false,
              loadSubscription: () async => const SubscriptionStatusResult(
                userId: 'feedback-owner',
                plan: 'STARTER',
                status: 'ACTIVE',
                canSchedule: true,
                canUseAiCaptions: true,
                canUseAnalytics: false,
              ),
              pickVideo: () async => replacement,
              createUpload: (request) async {
                uploads++;
                return UploadResult(
                  id: 'ai-upload-$uploads',
                  videoS3Key: 'uploads/feedback-owner/${request.fileName}',
                  storageProvider: 's3',
                );
              },
              uploadVideoFile: (_, __) async {},
              generateRealClipCaption: (_) async {
                generators++;
                return captionGate.future;
              },
              createPost: (_) async {
                posts++;
                throw StateError('feedback must never publish');
              },
              checkPublishingReadiness: () async {
                readiness++;
                throw StateError('feedback must never prepare publishing');
              },
            ),
          ),
        ),
      );

  void expectNoPublishing() {
    expect(posts, 0);
    expect(readiness, 0);
  }

  void expectNoRemoteWrites() {
    expect(uploads, 0);
    expect(generators, 0);
    expectNoPublishing();
  }
}

Future<void> _show(WidgetTester tester, Finder finder) async {
  await tester.pumpAndSettle();
  await tester.scrollUntilVisible(finder, 200,
      scrollable: find.byType(Scrollable).first);
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
}

Future<void> _captionStep(WidgetTester tester, _Fixture fixture,
    {String caption = ''}) async {
  await tester.pumpWidget(fixture.app());
  await tester.pumpAndSettle();
  await goToUploaderStep(tester, 1);
  await _show(tester, _captionField);
  if (caption.isNotEmpty) {
    await tester.enterText(_captionField, caption);
    await tester.pumpAndSettle();
  }
}

String _caption(WidgetTester tester) =>
    tester.widget<TextField>(_captionField).controller!.text;

double _revealOpacity(WidgetTester tester) => tester
    .widget<Opacity>(find
        .descendant(
            of: _key('uploader-caption-reveal'), matching: find.byType(Opacity))
        .first)
    .opacity;

Future<void> _startAi(WidgetTester tester, _Fixture fixture) async {
  final generate = _key('uploader-ai-generate-button');
  await _show(tester, generate);
  await tester.tap(generate);
  for (var attempt = 0; attempt < 12 && fixture.generators == 0; attempt++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
  expect(fixture.generators, 1);
  // The async pipeline may enter the generator at the end of the preceding
  // frame; draw its pending state before inspecting the visible indicator.
  await tester.pump();
}

Future<void> _replaceClip(WidgetTester tester) async {
  await tester.tap(_key('uploader-progress-0'));
  await tester.pumpAndSettle();
  final picker = _key('uploader-video-preview-picker');
  await _show(tester, picker);
  await tester.tap(picker);
  await tester.pumpAndSettle();
  await goToUploaderStep(tester, 1);
  await _show(tester, _captionField);
}

Future<void> _save(WidgetTester tester) async {
  await tester.tap(_saveButton);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
}

void _resumeApp(WidgetTester tester) {
  final binding = tester.binding;
  if (binding.lifecycleState == AppLifecycleState.paused) {
    binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
  }
  if (binding.lifecycleState == AppLifecycleState.hidden) {
    binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
  }
  if (binding.lifecycleState != AppLifecycleState.resumed) {
    binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  }
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AppTheme.applyThemeMode(ThemeMode.light);
    final sessions = PostDeeAuthSessionStore.instance;
    final previous = sessions.session;
    addTearDown(() => sessions.signIn(previous));
    sessions.signIn(const AuthSession(
        userId: 'feedback-owner', idToken: 'feedback-test-token'));
  });

  for (final mode in ['reduced', 'ticker', 'background']) {
    for (final target in ['step', 'platform']) {
      testWidgets('motion audit $mode finishes $target color without replay',
          (tester) async {
        addTearDown(() => _resumeApp(tester));
        _resumeApp(tester);
        final fixture = _Fixture()..connected = true;
        await _captionStep(tester, fixture, caption: 'ข้อความของร้านยังอยู่');
        final editable = find.descendant(
            of: _captionField, matching: find.byType(EditableText));
        late Finder control;
        late Color expectedColor;
        if (target == 'step') {
          await tester.tap(_key('uploader-progress-0'));
          await tester.pumpAndSettle();
          await tester.tap(_key('uploader-progress-1'));
          control = _key('uploader-progress-circle-1');
          expectedColor = AppTheme.accent;
        } else {
          await goToUploaderStep(tester, 2);
          final row = _key('uploader-platform-TIKTOK');
          await _show(tester, row);
          await tester.tap(row);
          control =
              find.ancestor(of: row, matching: find.byType(DecoratedBox)).first;
          expectedColor = AppTheme.accent.withValues(alpha: .10);
        }
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 40));
        Color? visibleColor() => (tester
                .widget<DecoratedBox>(find
                    .descendant(
                        of: control,
                        matching: find.byType(DecoratedBox),
                        matchRoot: true)
                    .first)
                .decoration as BoxDecoration)
            .color;
        expect(visibleColor(), isNot(expectedColor));
        final bounds = tester.getRect(control);
        final currentEditor =
            target == 'step' ? tester.state<EditableTextState>(editable) : null;
        if (mode == 'background') {
          tester.binding
              .handleAppLifecycleStateChanged(AppLifecycleState.inactive);
          tester.binding
              .handleAppLifecycleStateChanged(AppLifecycleState.hidden);
          tester.binding
              .handleAppLifecycleStateChanged(AppLifecycleState.paused);
          await tester.pump();
        } else {
          await tester.pumpWidget(fixture.app(
              reducedMotion: mode == 'reduced',
              tickerEnabled: mode != 'ticker'));
        }
        expect(visibleColor(), expectedColor,
            reason: 'A disabled effect must finish at its selected color.');
        expect(tester.getRect(control), bounds);
        if (target == 'step') {
          expect(
              tester.state<EditableTextState>(editable), same(currentEditor));
          expect(_caption(tester), 'ข้อความของร้านยังอยู่');
        } else {
          expect(find.text('เลือกแล้ว 1 ช่องทาง'), findsOneWidget);
        }
        await tester.pumpAndSettle();
        expect(tester.binding.hasScheduledFrame, isFalse);
        if (mode == 'background') {
          _resumeApp(tester);
          await tester.pump();
        } else {
          await tester.pumpWidget(fixture.app());
        }
        expect(visibleColor(), expectedColor);
        await tester.pump(const Duration(milliseconds: 40));
        expect(visibleColor(), expectedColor);
        if (target == 'platform') {
          await tester.tap(_key('uploader-platform-TIKTOK'));
          await tester.pumpAndSettle();
          expect(find.text('เลือกแล้ว 0 ช่องทาง'), findsOneWidget);
          await goToUploaderStep(tester, 1);
          expect(_caption(tester), 'ข้อความของร้านยังอยู่');
        }
        fixture.expectNoRemoteWrites();
        expect(fixture.drafts.attempts, 0);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
      });
    }
  }

  testWidgets(
      'empty caption focuses the field and its inline notice clears on edit',
      (tester) async {
    final fixture = _Fixture();
    await _captionStep(tester, fixture);
    await tester.tap(_key('uploader-wizard-next'));
    await tester.pumpAndSettle();
    final notice = _key('uploader-caption-required-notice');
    await _show(tester, _captionField);
    expect(notice, findsOneWidget);
    final editable =
        find.descendant(of: _captionField, matching: find.byType(EditableText));
    expect(tester.widget<EditableText>(editable).focusNode.hasFocus, isTrue);
    expect(_key('uploader-step-platforms'), findsNothing);
    await tester.enterText(_captionField, 'แคปชันที่เขียนเอง');
    await tester.pump();
    expect(notice, findsNothing);
    expect(_caption(tester), 'แคปชันที่เขียนเอง');
    fixture.expectNoRemoteWrites();
    expect(fixture.drafts.attempts, 0);
  });

  testWidgets(
      'pending AI keeps the old text until a full accepted response arrives',
      (tester) async {
    final fixture = _Fixture();
    await _captionStep(tester, fixture, caption: 'ข้อความที่มีอยู่ก่อน');
    final editable =
        find.descendant(of: _captionField, matching: find.byType(EditableText));
    final originalFieldState = tester.state<EditableTextState>(editable);
    await _startAi(tester, fixture);
    expect(_waitingIndicator, findsOneWidget);
    expect(_readyIndicator, findsNothing);
    expect(_revealOpacity(tester), 1);
    expect(_caption(tester), 'ข้อความที่มีอยู่ก่อน');
    expect(find.textContaining(RegExp(r'\d+\s*%')), findsNothing);
    await tester.pump(const Duration(milliseconds: 400));
    expect(_waitingIndicator, findsOneWidget);
    expect(_caption(tester), 'ข้อความที่มีอยู่ก่อน');
    fixture.captionGate.complete(_result());
    await tester.pump();
    expect(_caption(tester), 'แคปชันทั้งหมดจากคลิปจริง');
    expect(_waitingIndicator, findsNothing);
    expect(_readyIndicator, findsOneWidget);
    expect(_revealOpacity(tester), lessThan(1));
    expect(tester.state<EditableTextState>(editable), same(originalFieldState));
    await tester.pumpAndSettle();
    expect(_revealOpacity(tester), 1);
    expect(fixture.generators, 1);
    expect(fixture.uploads, 1);
    fixture.expectNoPublishing();
    expect(fixture.drafts.attempts, 0);
  });

  testWidgets(
      'failed and fallback AI responses never claim a verified ready caption',
      (tester) async {
    for (final failure in ['error', 'fallback']) {
      final fixture = _Fixture();
      await _captionStep(tester, fixture, caption: 'ข้อความที่ร้านเขียนเอง');
      await _startAi(tester, fixture);
      expect(_waitingIndicator, findsOneWidget);
      if (failure == 'error') {
        fixture.captionGate.completeError(
            const ApiException('fixture AI unavailable', statusCode: 503));
      } else {
        fixture.captionGate.complete(_result(fallback: true));
      }
      await tester.pumpAndSettle();
      expect(_waitingIndicator, findsNothing);
      expect(_readyIndicator, findsNothing);
      expect(_revealOpacity(tester), 1);
      expect(
          _caption(tester),
          failure == 'error'
              ? 'ข้อความที่ร้านเขียนเอง'
              : 'แคปชันทั้งหมดจากคลิปจริง');
      fixture.expectNoPublishing();
      expect(fixture.drafts.attempts, 0);
      await tester.pumpWidget(const SizedBox.shrink());
    }
  });

  testWidgets('old clip and old owner responses cannot show ready feedback',
      (tester) async {
    for (final replacement in ['clip', 'owner']) {
      final fixture = _Fixture();
      await _captionStep(tester, fixture, caption: 'ข้อความที่เก็บไว้');
      await _startAi(tester, fixture);
      expect(_waitingIndicator, findsOneWidget);
      if (replacement == 'clip') {
        await _replaceClip(tester);
      } else {
        PostDeeAuthSessionStore.instance.signIn(
            const AuthSession(userId: 'other-owner', idToken: 'other-token'));
        await tester.pumpAndSettle();
        await goToUploaderStep(tester, 1);
      }
      fixture.captionGate.complete(_result());
      await tester.pumpAndSettle();
      expect(_readyIndicator, findsNothing);
      expect(_waitingIndicator, findsNothing);
      expect(_revealOpacity(tester), 1);
      expect(_caption(tester), isNot('แคปชันทั้งหมดจากคลิปจริง'));
      fixture.expectNoPublishing();
      expect(fixture.drafts.attempts, 0);
      await tester.pumpWidget(const SizedBox.shrink());
      PostDeeAuthSessionStore.instance.signIn(const AuthSession(
          userId: 'feedback-owner', idToken: 'feedback-test-token'));
    }
  });

  testWidgets(
      'AI waiting and arrival respect reduced motion ticker mode and background',
      (tester) async {
    addTearDown(() => _resumeApp(tester));
    for (final mode in ['reduced', 'ticker', 'background']) {
      final fixture = _Fixture();
      await _captionStep(tester, fixture);
      await _startAi(tester, fixture);
      expect(_waitingIndicator, findsOneWidget);
      await tester.pump(const Duration(milliseconds: 100));
      expect(tester.binding.hasScheduledFrame, isTrue);
      if (mode == 'background') {
        tester.binding
            .handleAppLifecycleStateChanged(AppLifecycleState.inactive);
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
        await tester.pumpAndSettle();
        expect(tester.binding.hasScheduledFrame, isFalse);
        expect(_readyIndicator, findsNothing);
        _resumeApp(tester);
        await tester.pump();
      } else {
        await tester.pumpWidget(fixture.app(
            reducedMotion: mode == 'reduced', tickerEnabled: mode != 'ticker'));
        await tester.pumpAndSettle();
        expect(_waitingIndicator, findsOneWidget);
        expect(tester.binding.hasScheduledFrame, isFalse);
      }
      fixture.captionGate.complete(_result());
      await tester.pump();
      await tester.pump();
      expect(_caption(tester), 'แคปชันทั้งหมดจากคลิปจริง');
      expect(_readyIndicator, findsOneWidget);
      expect(_waitingIndicator, findsNothing);
      if (mode != 'background') expect(_revealOpacity(tester), 1);
      await tester.pumpAndSettle();
      expect(_revealOpacity(tester), 1);
      expect(tester.binding.hasScheduledFrame, isFalse);
      fixture.expectNoPublishing();
      await tester.pumpWidget(const SizedBox.shrink());
    }
  });

  testWidgets(
      'save confirms verified completion once and restores its normal button label',
      (tester) async {
    final fixture = _Fixture();
    fixture.drafts.saveGate = Completer<void>();
    fixture.drafts.readbackGate = Completer<void>();
    await _captionStep(tester, fixture, caption: 'บันทึกฉบับนี้');
    await _save(tester);
    expect(fixture.drafts.attempts, 1);
    expect(_savedIndicator, findsNothing);
    expect(find.text('กำลังบันทึก...'), findsOneWidget);
    expect(tester.widget<OutlinedButton>(_saveButton).onPressed, isNull);
    fixture.drafts.saveGate!.complete();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(fixture.drafts.savedRequests, hasLength(1));
    expect(_savedIndicator, findsNothing);
    fixture.drafts.readbackGate!.complete();
    await tester.pumpAndSettle();
    expect(_savedIndicator, findsOneWidget);
    expect(find.descendant(of: _saveButton, matching: find.text('บันทึกแล้ว')),
        findsOneWidget);
    expect(fixture.drafts.savedRequests.single.caption, 'บันทึกฉบับนี้');
    await tester.pump(const Duration(milliseconds: 1500));
    expect(_savedIndicator, findsOneWidget);
    await tester.pump(const Duration(milliseconds: 1000));
    await tester.pumpAndSettle();
    expect(_savedIndicator, findsNothing);
    expect(find.descendant(of: _saveButton, matching: find.text('บันทึกร่าง')),
        findsOneWidget);
    expect(fixture.drafts.attempts, 1);
    fixture.expectNoRemoteWrites();
  });

  testWidgets('rapid repeated save taps keep one verified success receipt',
      (tester) async {
    final fixture = _Fixture();
    fixture.drafts.saveGate = Completer<void>();
    await _captionStep(tester, fixture, caption: 'ร่างที่กดบันทึกติดกัน');
    // Both taps reach the same enabled button before the pending UI rebuild.
    await tester.tap(_saveButton);
    await tester.tap(_saveButton);
    for (var frame = 0; frame < 12 && fixture.drafts.attempts == 0; frame++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    await tester.pump();
    expect(fixture.drafts.attempts, 1);
    expect(fixture.drafts.savedRequests, isEmpty);
    expect(_savedIndicator, findsNothing);
    expect(find.text('กำลังบันทึก...'), findsOneWidget);
    expect(tester.widget<OutlinedButton>(_saveButton).onPressed, isNull);

    fixture.drafts.saveGate!.complete();
    await tester.pumpAndSettle();
    expect(fixture.drafts.attempts, 1);
    expect(fixture.drafts.savedRequests, hasLength(1));
    expect(
        fixture.drafts.savedRequests.single.caption, 'ร่างที่กดบันทึกติดกัน');
    expect(_savedIndicator, findsOneWidget);
    expect(find.descendant(of: _saveButton, matching: find.text('บันทึกแล้ว')),
        findsOneWidget);
    fixture.expectNoRemoteWrites();
  });

  testWidgets('failed draft saves never show the check and remain retryable',
      (tester) async {
    final fixture = _Fixture();
    fixture.drafts.failSave = true;
    await _captionStep(tester, fixture, caption: 'ข้อความที่ยังไม่ได้บันทึก');
    await _save(tester);
    await tester.pumpAndSettle();
    expect(_savedIndicator, findsNothing);
    await tester.drag(_key('uploader-scroll'), const Offset(0, 1200));
    await tester.pumpAndSettle();
    expect(find.textContaining('บันทึกร่างไม่สำเร็จ'), findsOneWidget);
    await _show(tester, _captionField);
    expect(_caption(tester), 'ข้อความที่ยังไม่ได้บันทึก');
    expect(fixture.drafts.savedRequests, isEmpty);
    expect(tester.widget<OutlinedButton>(_saveButton).onPressed, isNotNull);
    fixture.drafts.failSave = false;
    await _save(tester);
    await tester.pumpAndSettle();
    expect(_savedIndicator, findsOneWidget);
    expect(fixture.drafts.attempts, 2);
    expect(fixture.drafts.savedRequests, hasLength(1));
    fixture.expectNoRemoteWrites();
  });

  testWidgets(
      'editing replacing or clearing the saved form invalidates its check',
      (tester) async {
    for (final change in ['caption', 'clip', 'reset']) {
      final fixture = _Fixture();
      await _captionStep(tester, fixture, caption: 'ฉบับที่บันทึกแล้ว');
      fixture.drafts.readbackGate = Completer<void>();
      await _save(tester);
      for (var attempt = 0;
          attempt < 12 && fixture.drafts.savedRequests.isEmpty;
          attempt++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(fixture.drafts.savedRequests, hasLength(1));
      fixture.drafts.readbackGate!.complete();
      await tester.pump();
      await tester.pump();
      expect(_savedIndicator, findsOneWidget);
      final savedAt = tester.binding.clock.now();
      if (change == 'caption') {
        await _show(tester, _captionField);
        await tester.enterText(_captionField, 'ข้อความฉบับแก้ไข');
        await tester.pump();
      } else if (change == 'clip') {
        await _replaceClip(tester);
      } else {
        await tester.tap(_key('uploader-open-drafts'));
        await tester.pumpAndSettle();
        expect(
            find.byKey(const ValueKey('uploader-draft-saved-indicator'),
                skipOffstage: false),
            findsOneWidget,
            reason: 'Receipt after opening drafts at '
                '${tester.binding.clock.now().difference(savedAt).inMilliseconds} ms; '
                'saved labels: ${find.text('บันทึกแล้ว', skipOffstage: false).evaluate().length}; '
                'caption fields: ${find.byKey(const ValueKey('uploader-caption-field'), skipOffstage: false).evaluate().length}');
        final draftId = fixture.drafts.drafts.keys.single;
        await tester.tap(_key('publish-draft-delete-$draftId'));
        await tester.pumpAndSettle();
        expect(tester.binding.clock.now().difference(savedAt).inMilliseconds,
            lessThan(1800));
        expect(
            find.byKey(const ValueKey('uploader-draft-saved-indicator'),
                skipOffstage: false),
            findsOneWidget);
        await tester.tap(_key('publish-draft-delete-confirm'));
        await tester.pumpAndSettle();
      }
      expect(_savedIndicator, findsNothing, reason: change);
      expect(fixture.drafts.attempts, 1);
      fixture.expectNoRemoteWrites();
      await tester.pumpWidget(const SizedBox.shrink());
    }
  });

  testWidgets(
      'focused IME cannot alter a pending save and a changed owner gets no check',
      (tester) async {
    for (final change in ['ime', 'owner']) {
      final fixture = _Fixture();
      fixture.drafts.saveGate = Completer<void>();
      await _captionStep(tester, fixture, caption: 'เนื้อหาที่กำลังบันทึก');
      await _save(tester);
      expect(_savedIndicator, findsNothing);
      if (change == 'ime') {
        expect(tester.widget<TextField>(_captionField).readOnly, isTrue);
        if (tester.testTextInput.hasAnyClients) {
          tester.testTextInput
              .enterText('ข้อความใหม่ที่ IME ส่งมาระหว่างบันทึก');
          await tester.pump();
        }
        expect(_caption(tester), 'เนื้อหาที่กำลังบันทึก');
      } else {
        PostDeeAuthSessionStore.instance.signIn(
            const AuthSession(userId: 'other-owner', idToken: 'other-token'));
        await tester.pump();
      }
      fixture.drafts.saveGate!.complete();
      await tester.pumpAndSettle();
      expect(
          _savedIndicator, change == 'owner' ? findsNothing : findsOneWidget);
      expect(fixture.drafts.attempts, 1);
      fixture.expectNoRemoteWrites();
      await tester.pumpWidget(const SizedBox.shrink());
      PostDeeAuthSessionStore.instance.signIn(const AuthSession(
          userId: 'feedback-owner', idToken: 'feedback-test-token'));
    }
  });
}
