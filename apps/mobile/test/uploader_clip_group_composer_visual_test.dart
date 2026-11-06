import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postdee_mobile/core/auth/auth_session.dart';
import 'package:postdee_mobile/core/network/postdee_api_client.dart';
import 'package:postdee_mobile/core/theme/app_theme.dart';
import 'package:postdee_mobile/features/uploader/clip_group_draft.dart';
import 'package:postdee_mobile/features/uploader/clip_group_review_screen.dart';
import 'package:postdee_mobile/features/uploader/publish_draft.dart';
import 'package:postdee_mobile/features/uploader/uploader_screen.dart';
import 'package:postdee_mobile/features/uploader/video_picker_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/publish_preflight_fixtures.dart';
import 'uploader_video_english_test.dart';

const _captureDirectory = String.fromEnvironment('POSTDEE_UI_CAPTURE_DIR');
const _captureKey = ValueKey('actual-caption-composer-capture');
const _sourceId = 'visual-source';
const _fullId = 'visual-full';
const _firstId = 'visual-first';
const _secondId = 'visual-second';
final _now = DateTime.utc(2026, 11, 5, 10);

class _ComposerVisualFixture extends VideoEnglishFixture {
  _ComposerVisualFixture({required super.locale, super.dark, super.scale});

  final durations = <String, double>{};
  late final String sharedCaption;

  Future<void> seed() async {
    final english = language.value.languageCode == 'en';
    sharedCaption = english
        ? 'Visual fixture: a complete product demonstration with care '
            'instructions, practical examples and the details a customer needs '
            'before choosing the right product for their home.'
        : 'ข้อมูลทดสอบภาพ: สาธิตสินค้าแบบครบถ้วน พร้อมวิธีดูแล '
            'ตัวอย่างการใช้งานจริง และรายละเอียดสำหรับช่วยเลือกสินค้า'
            'ให้เหมาะกับพื้นที่ในบ้าน สอบถามข้อมูลเพิ่มเติมได้ก่อนตัดสินใจ';
    final items = [
      ClipGroupItem(
        draftId: _firstId,
        index: 0,
        sourceStartSeconds: 0,
        sourceEndSeconds: 90,
        platformApiValues: {'FACEBOOK_REELS'},
      ),
      ClipGroupItem(
        draftId: _fullId,
        index: 1,
        sourceStartSeconds: 0,
        sourceEndSeconds: 180,
        platformApiValues: {'TIKTOK', 'YOUTUBE_SHORTS', 'INSTAGRAM_REELS'},
      ),
      ClipGroupItem(
        draftId: _secondId,
        index: 2,
        sourceStartSeconds: 90,
        sourceEndSeconds: 180,
        platformApiValues: {'FACEBOOK_REELS'},
      ),
    ];
    for (final id in [_sourceId, ...items.map((item) => item.draftId)]) {
      final item = items.where((item) => item.draftId == id).firstOrNull;
      final duration = item?.durationSeconds ?? 180.0;
      final video = makeVideo('$id.mp4', duration: duration);
      durations[video.path] = duration;
      await store.saveDraft(PublishDraftSaveRequest(
        id: id,
        createdAt: _now,
        updatedAt: _now,
        videoFile: File(video.path),
        videoName: english
            ? 'Visual fixture - Product demonstration and complete care '
                'instructions - $id.mp4'
            : 'ข้อมูลทดสอบภาพ สาธิตสินค้าและวิธีดูแลอย่างละเอียด $id.mp4',
        videoSizeBytes: video.sizeBytes,
        videoWidth: video.width,
        videoHeight: video.height,
        caption: id == _sourceId ? 'Retained backup caption' : sharedCaption,
        aiGuidance: '',
        watermarkEnabled: false,
        platformApiValues: item?.platformApiValues ??
            {'TIKTOK', 'YOUTUBE_SHORTS', 'INSTAGRAM_REELS', 'FACEBOOK_REELS'},
        clipGroupId: 'visual-caption-set',
        isClipGroupSource: id == _sourceId,
      ));
    }
    final group = ClipGroupDraft(
      id: 'visual-caption-set',
      ownerUserId: videoEnglishOwner,
      sourceDraftId: _sourceId,
      title: english
          ? 'Visual fixture - Complete product demonstration and care instructions'
          : 'ข้อมูลทดสอบภาพ สาธิตสินค้าและวิธีดูแลอย่างละเอียด',
      sharedCaption: sharedCaption,
      deliveryMode: ClipGroupDeliveryMode.immediate,
      items: items,
      createdAt: _now,
      updatedAt: _now,
    );
    await store.saveClipGroup(
      ClipGroupDraft.fromJson(
          jsonDecode(jsonEncode(group.toJson())) as Map<String, dynamic>),
      expectedRevision: null,
    );
    initialDraftId = _sourceId;
  }

  @override
  Widget app() => RepaintBoundary(key: _captureKey, child: super.app());

  @override
  UploaderScreen screen() => UploaderScreen(
        fullScreen: true,
        draftStore: store,
        initialDraftId: initialDraftId,
        enableRevenueCatBilling: false,
        now: () => _now,
        readVideoMetadata: (path) async => VideoDimensions(
            width: 1080, height: 1920, durationSeconds: durations[path]),
        probePublishMedia: probeValidPublishMedia,
        loadTemplates: () async => const [],
        loadSubscription: () async => quota,
        loadPostQuota: () async => quota,
        loadCaptionQuota: () async => const CaptionQuotaResult(
          plan: 'PRO',
          quota: RealClipCaptionQuota(
              limit: 120, usedThisMonth: 0, remainingThisMonth: 120),
        ),
        loadSocialConnections: () async => const [],
        loadSocialPublishingReadiness: () async => const [],
        createUpload: (_) async {
          apiWrites++;
          throw StateError('Visual checks must not upload');
        },
        createPost: (_) async {
          apiWrites++;
          throw StateError('Visual checks must not publish');
        },
        generateRealClipCaption: (_) async {
          apiWrites++;
          throw StateError('Visual checks must not generate captions');
        },
      );
}

Finder _key(String value) => find.byKey(ValueKey(value));

Future<void> _fonts(WidgetTester tester) => tester.runAsync(() async {
      final anuphan = FontLoader('Anuphan');
      for (final weight in ['Regular', 'Medium', 'SemiBold', 'Bold']) {
        anuphan.addFont(
            rootBundle.load('assets/fonts/anuphan/Anuphan-$weight.ttf'));
      }
      await anuphan.load();
      await (FontLoader('MaterialIcons')
            ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf')))
          .load();
    });

Future<void> _tap(WidgetTester tester, String key) async {
  await tester.ensureVisible(_key(key));
  await tester.pumpAndSettle();
  expect(tester.takeException(), isNull, reason: 'Before tapping $key');
  FlutterErrorDetails? layoutError;
  final previousHandler = FlutterError.onError;
  try {
    FlutterError.onError = (details) {
      layoutError ??= details;
      previousHandler?.call(details);
    };
    await tester.tap(_key(key));
    await tester.pumpAndSettle();
  } finally {
    FlutterError.onError = previousHandler;
  }
  expect(tester.takeException(), isNull,
      reason: 'After tapping $key\n${layoutError ?? ''}');
}

Future<void> _capture(WidgetTester tester, String name) async {
  expect(tester.takeException(), isNull, reason: name);
  if (_captureDirectory.isEmpty) return;
  final boundary =
      tester.renderObject<RenderRepaintBoundary>(_key(_captureKey.value));
  await tester.runAsync(() async {
    final bitmap = await boundary.toImage(pixelRatio: 2);
    try {
      final png = await bitmap.toByteData(format: ui.ImageByteFormat.png);
      final directory = Directory(_captureDirectory);
      await directory.create(recursive: true);
      await File('${directory.path}${Platform.pathSeparator}$name.png')
          .writeAsBytes(png!.buffer.asUint8List());
    } finally {
      bitmap.dispose();
    }
  });
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    final sessions = PostDeeAuthSessionStore.instance;
    final previous = sessions.session;
    final previousMode =
        AppTheme.isLightMode ? ThemeMode.light : ThemeMode.dark;
    sessions.signIn(AuthSession.authenticated(
        userId: videoEnglishOwner, idToken: 'offline-composer-visual'));
    addTearDown(() {
      previous.isSignedIn ? sessions.signIn(previous) : sessions.clear();
      AppTheme.applyThemeMode(previousMode);
    });
  });

  for (final mode in [
    (
      name: 'th-light-390',
      language: 'th',
      dark: false,
      width: 390.0,
      scale: 1.0
    ),
    (
      name: 'en-dark-320-large',
      language: 'en',
      dark: true,
      width: 320.0,
      scale: 2.0
    ),
  ]) {
    testWidgets('actual normal composer real fonts ${mode.name}',
        (tester) async {
      tester.view.physicalSize = Size(mode.width, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await _fonts(tester);
      final fixture = _ComposerVisualFixture(
          locale: Locale(mode.language), dark: mode.dark, scale: mode.scale);
      addTearDown(fixture.dispose);
      await fixture.seed();
      final writes = fixture.store.savedRequests.length;
      await fixture.mount(tester);
      expect(tester.takeException(), isNull, reason: 'Initial normal Caption');
      expect(find.byType(UploaderScreen), findsOneWidget);
      expect(find.byType(ClipGroupReviewScreen), findsNothing);
      final state = tester.state(find.byType(UploaderScreen));
      expect(_key('uploader-step-caption'), findsOneWidget);
      expect(_key('clip-group-caption-scopes'), findsOneWidget);
      expect(find.text(mode.language == 'th' ? 'คลิปเต็ม' : 'Full clip'),
          findsOneWidget);
      expect(_key('clip-group-caption-scope-$_sourceId'), findsNothing);
      expect(_key('uploader-ai-generate-button'), findsNothing);
      await _capture(tester, '${mode.name}-all');

      await _tap(tester, 'clip-group-caption-scope-$_fullId');
      expect(
          tester.widget<Text>(_key('clip-group-caption-scope-platforms')).data,
          'TikTok · YouTube Shorts · Instagram Reels');
      await _tap(tester, 'clip-group-caption-custom-$_fullId');
      final customFull = mode.language == 'th'
          ? 'ข้อความทดสอบเฉพาะคลิปเต็ม พร้อมรายละเอียดเพิ่มเติมสำหรับผู้ชม '
              'และวิธีเลือกสินค้าให้เหมาะกับการใช้งาน เก็บข้อความนี้แยกจากตอนอื่น'
          : 'Visual fixture: custom full-length caption with detailed product '
              'information and care instructions. Keep this text separate '
              'from the Facebook parts and shared caption.';
      await tester.enterText(_key('uploader-caption-field'), customFull);
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: 'Long full-clip caption');
      await _capture(tester, '${mode.name}-full-custom');
      await _tap(tester, 'clip-group-platform-captions-toggle');
      await _tap(tester, 'clip-group-caption-platform');
      await tester.tap(find.text('Instagram Reels').last);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: 'Eligible channel picker');
      await _tap(tester, 'clip-group-platform-custom-$_fullId-INSTAGRAM_REELS');
      final platformField =
          _key('clip-group-platform-caption-$_fullId-INSTAGRAM_REELS');
      await tester.ensureVisible(platformField);
      await tester.enterText(platformField, customFull);
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      expect(
          tester.widget<TextField>(platformField).controller!.text, customFull);
      expect(tester.takeException(), isNull, reason: 'Platform leaf caption');
      await _capture(tester, '${mode.name}-platform-caption');

      await _tap(tester, 'clip-group-caption-scope-$_firstId');
      expect(
          tester.widget<Text>(_key('clip-group-caption-scope-platforms')).data,
          'Facebook Reels');
      await _tap(tester, 'clip-group-caption-custom-$_firstId');
      final customPart = mode.language == 'th'
          ? 'ข้อความทดสอบเฉพาะตอนแรกของ Facebook พร้อมรายละเอียดที่ยาวขึ้น '
              'เพื่อให้ตรวจการตัดบรรทัดและการเลื่อนบนหน้าจอขนาดเล็กได้'
          : 'Visual fixture: this longer Facebook part-one caption keeps its '
              'own product details while the full-length caption remains intact.';
      await tester.enterText(_key('uploader-caption-field'), customPart);
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: 'Long part caption');
      await _capture(tester, '${mode.name}-part-custom');
      await _tap(tester, 'clip-group-caption-scope-all');
      expect(
          tester
              .widget<TextField>(_key('uploader-caption-field'))
              .controller!
              .text,
          fixture.sharedCaption);
      expect(_key('uploader-ai-generate-button'), findsNothing);
      await _tap(tester, 'uploader-ai-card-toggle');
      await tester.ensureVisible(_key('uploader-ai-generate-button'));
      await tester.pumpAndSettle();
      expect(_key('uploader-ai-generate-button'), findsOneWidget);
      await _capture(tester, '${mode.name}-ai-open');
      await _tap(tester, 'uploader-ai-card-toggle');
      expect(_key('uploader-ai-generate-button'), findsNothing);
      await _tap(tester, 'clip-group-caption-scope-$_fullId');
      expect(
          tester
              .widget<TextField>(_key('uploader-caption-field'))
              .controller!
              .text,
          customFull);
      expect(tester.state(find.byType(UploaderScreen)), same(state));
      expect(fixture.store.savedRequests, hasLength(writes));
      expect(
          fixture.store.drafts[_sourceId]!.caption, 'Retained backup caption');
      expect(fixture.apiWrites, 0);
      expect(tester.takeException(), isNull);
    });
  }
}
