import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postdee_mobile/core/auth/auth_session.dart';
import 'package:postdee_mobile/core/localization/postdee_localizations.dart';
import 'package:postdee_mobile/core/network/postdee_api_client.dart';
import 'package:postdee_mobile/core/theme/app_theme.dart';
import 'package:postdee_mobile/features/platforms/social_platform.dart';
import 'package:postdee_mobile/features/uploader/clip_group_draft.dart';
import 'package:postdee_mobile/features/uploader/clip_group_review_screen.dart';
import 'package:postdee_mobile/features/uploader/publish_draft.dart';

const _directory = String.fromEnvironment('POSTDEE_UI_CAPTURE_DIR');
const _captureKey = ValueKey('clip-group-visual-capture');
const _owner = 'clip-group-visual-fixture';
final _now = DateTime(2026, 11, 5, 10);
const _quota = SubscriptionStatusResult(
  userId: _owner,
  plan: 'PRO',
  status: 'ACTIVE',
  availablePostUnits: 10,
  remainingPostsThisMonth: 10,
  canSchedule: true,
  canUseAiCaptions: true,
  canUseAnalytics: false,
);

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

Future<void> _capture(WidgetTester tester, String name) async {
  expect(tester.takeException(), isNull);
  if (_directory.isEmpty) return;
  final boundary =
      tester.renderObject<RenderRepaintBoundary>(find.byKey(_captureKey));
  await tester.runAsync(() async {
    final bitmap = await boundary.toImage(pixelRatio: 2);
    try {
      final data = await bitmap.toByteData(format: ui.ImageByteFormat.png);
      final directory = Directory(_directory);
      await directory.create(recursive: true);
      await File('${directory.path}/$name.png')
          .writeAsBytes(data!.buffer.asUint8List());
    } finally {
      bitmap.dispose();
    }
  });
}

Widget _app(
    {required bool dark, required bool english, required double scale}) {
  final caption = english
      ? 'Visual fixture: a six-minute product demonstration with useful details, '
          'care instructions, and an invitation to ask questions before ordering.'
      : 'ข้อมูลทดสอบภาพ: คลิปสาธิตสินค้า 6 นาที พร้อมรายละเอียด วิธีดูแล '
          'และคำแนะนำให้สอบถามข้อมูลเพิ่มเติมก่อนสั่งซื้อ';
  var group = ClipGroupDraft(
    id: 'visual-group',
    ownerUserId: _owner,
    sourceDraftId: 'visual-source',
    title: english
        ? 'Visual fixture · Six-minute product demonstration and care instructions'
        : 'ข้อมูลทดสอบภาพ · สาธิตสินค้าและวิธีดูแล ความยาว 6 นาที',
    sharedCaption: caption,
    deliveryMode: ClipGroupDeliveryMode.scheduled,
    createdAt: _now,
    updatedAt: _now,
    items: [
      ClipGroupItem(
        draftId: 'yt1',
        index: 0,
        sourceStartSeconds: 0,
        sourceEndSeconds: 180,
        platformApiValues: {'YOUTUBE_SHORTS'},
        scheduledAt: DateTime(2026, 11, 6, 9, 15).toUtc(),
      ),
      ClipGroupItem(
        draftId: 'yt2',
        index: 1,
        sourceStartSeconds: 180,
        sourceEndSeconds: 360,
        platformApiValues: {'YOUTUBE_SHORTS'},
        usesSharedCaption: false,
        scheduledAt: DateTime(2026, 11, 8, 14, 45).toUtc(),
      ),
      ClipGroupItem(
        draftId: 'ig',
        index: 2,
        sourceStartSeconds: 0,
        sourceEndSeconds: 360,
        platformApiValues: {'INSTAGRAM_REELS'},
        scheduledAt: DateTime(2026, 11, 10, 20).toUtc(),
      ),
    ],
  );
  final drafts = {
    for (final item in group.items)
      item.draftId: PublishDraft(
        version: publishDraftManifestVersion,
        id: item.draftId,
        ownerUserId: _owner,
        submissionRequestId: 'visual-${item.draftId}',
        createdAt: _now,
        updatedAt: _now,
        videoPath: '/visual-fixture/${item.draftId}.mp4',
        videoName: '${item.draftId}.mp4',
        videoSizeBytes: 100,
        caption: item.usesSharedCaption
            ? caption
            : english
                ? 'Visual fixture: details for the second YouTube part, '
                    'including the full care instructions and ordering information.'
                : 'ข้อมูลทดสอบภาพ: รายละเอียดเฉพาะตอนที่สองบน YouTube '
                    'พร้อมวิธีดูแลสินค้าและข้อมูลสำหรับการสั่งซื้อ',
        captionNeedsReview: true,
        aiGuidance: '',
        watermarkEnabled: false,
        platformApiValues: item.platformApiValues,
        scheduledAt: item.scheduledAt,
        clipGroupId: group.id,
      ),
  };
  return RepaintBoundary(
    key: _captureKey,
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      locale: Locale(english ? 'en' : 'th'),
      supportedLocales: PostDeeLocalizations.supportedLocales,
      localizationsDelegates: const [
        PostDeeLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: dark ? AppTheme.dark : AppTheme.light,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
      home: ClipGroupReviewScreen(
        initialGroup: group,
        draftsById: drafts,
        ownerSession: PostDeeAuthSessionStore.instance.captureSession(),
        now: () => _now,
        loadSubscription: () async => _quota,
        loadPostQuota: () async => _quota,
        onSaveGroup: (proposed) async {
          group = proposed.copyWith(revision: group.revision + 1);
          return group;
        },
        onSaveCaption: (draft, caption) async => draft,
        onEditClip: (draft, section) async => draft,
        onReloadGroup: () async => group,
        onSubmit: (group, progress) async =>
            throw StateError('Visual fixtures must not submit'),
        previewClip: (draft) async {},
        connectionDisplayNames: const {
          SocialPlatform.youtubeShorts:
              'Visual fixture · Product demonstrations and helpful instructions',
          SocialPlatform.instagramReels: 'Visual fixture · Product collection',
        },
      ),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    final sessions = PostDeeAuthSessionStore.instance;
    final previous = sessions.session;
    final previousMode =
        AppTheme.isLightMode ? ThemeMode.light : ThemeMode.dark;
    sessions.signIn(AuthSession.authenticated(
        userId: _owner, idToken: 'offline-visual-token'));
    addTearDown(() {
      previous.isSignedIn ? sessions.signIn(previous) : sessions.clear();
      AppTheme.applyThemeMode(previousMode);
    });
  });
  for (final mode in [
    (name: 'light-th', dark: false, english: false, width: 430.0, scale: 1.0),
    (
      name: 'dark-th-large',
      dark: true,
      english: false,
      width: 320.0,
      scale: 2.0
    ),
    (
      name: 'light-en-large',
      dark: false,
      english: true,
      width: 320.0,
      scale: 2.0
    ),
    (
      name: 'dark-en-large',
      dark: true,
      english: true,
      width: 320.0,
      scale: 2.0
    ),
  ]) {
    testWidgets('actual grouped review with real fonts ${mode.name}',
        (tester) async {
      tester.view.physicalSize = Size(mode.width, 1100);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      AppTheme.applyThemeMode(mode.dark ? ThemeMode.dark : ThemeMode.light);
      await _fonts(tester);
      await tester.pumpWidget(
          _app(dark: mode.dark, english: mode.english, scale: mode.scale));
      await tester.pumpAndSettle();
      expect(find.text(mode.english ? 'Create post' : 'สร้างโพสต์'),
          findsOneWidget);
      expect(find.byKey(const ValueKey('clip-group-shared-caption')),
          findsOneWidget);
      for (final key in ['clip-group-next', 'clip-group-save']) {
        final bounds = tester.getRect(find.byKey(ValueKey(key)));
        expect(bounds.left, greaterThanOrEqualTo(0));
        expect(bounds.right, lessThanOrEqualTo(mode.width));
        expect(bounds.bottom, lessThanOrEqualTo(1100));
      }
      await _capture(tester, 'clip-group-${mode.name}-caption');
      final captionScroll = find
          .descendant(
              of: find.byKey(const ValueKey('clip-group-scroll')),
              matching: find.byType(Scrollable))
          .first;
      final customCaption =
          find.byKey(const ValueKey('clip-group-caption-yt2'));
      final showParts = find.byKey(const ValueKey('clip-group-show-parts'));
      await tester.ensureVisible(showParts);
      await tester.tap(showParts);
      await tester.pumpAndSettle();
      await _capture(tester, 'clip-group-${mode.name}-parts-sheet');
      await tester.tap(find.byKey(const ValueKey('clip-group-parts-manage')));
      await tester.pumpAndSettle();
      // A long editable caption has its own scrollable; move the outer list
      // directly rather than dragging through the text field's hit area.
      final position = tester.state<ScrollableState>(captionScroll).position;
      for (var i = 0; i < 50 && customCaption.evaluate().isEmpty; i++) {
        position
            .jumpTo((position.pixels + 180).clamp(0, position.maxScrollExtent));
        await tester.pumpAndSettle();
      }
      await tester.ensureVisible(customCaption);
      await tester.pumpAndSettle();
      await _capture(tester, 'clip-group-${mode.name}-clips');

      await tester.tap(find.byKey(const ValueKey('clip-group-next')));
      await tester.pumpAndSettle();
      await _capture(tester, 'clip-group-${mode.name}-schedule');
      final scroll = find.descendant(
          of: find.byKey(const ValueKey('clip-group-scroll')),
          matching: find.byType(Scrollable));
      final thirdDate = find.byKey(const ValueKey('clip-group-date-ig'));
      await tester.scrollUntilVisible(thirdDate, 150, scrollable: scroll);
      await tester.ensureVisible(thirdDate);
      await tester.pumpAndSettle();
      expect(find.text('10/11/2026'), findsOneWidget);
      expect(find.text('20:00'), findsOneWidget);
      await _capture(tester, 'clip-group-${mode.name}-schedule-last');

      await tester.tap(find.byKey(const ValueKey('clip-group-next')));
      await tester.pumpAndSettle();
      final confirm = find.byKey(const ValueKey('clip-group-confirm'));
      expect(tester.widget<FilledButton>(confirm).onPressed, isNotNull);
      final bounds = tester.getRect(confirm);
      expect(bounds.left, greaterThanOrEqualTo(0));
      expect(bounds.right, lessThanOrEqualTo(mode.width));
      expect(bounds.top, greaterThanOrEqualTo(0));
      expect(bounds.bottom, lessThanOrEqualTo(1100));
      await _capture(tester, 'clip-group-${mode.name}-confirmation');
      await tester.fling(find.byKey(const ValueKey('clip-group-scroll')),
          const Offset(0, -2500), 5000);
      await tester.pumpAndSettle();
      await _capture(tester, 'clip-group-${mode.name}-confirmation-last');
    });
  }
}
