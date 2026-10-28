import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postdee_mobile/core/localization/postdee_localizations.dart';
import 'package:postdee_mobile/core/theme/app_theme.dart';
import 'package:postdee_mobile/features/shared/growth_tool_detail_sheet.dart';
import 'package:postdee_mobile/features/shared/growth_tool_settings_store.dart';

const _hashtag = GrowthToolDetail(
  id: 'hashtag_radar',
  title: 'เรดาร์แฮชแท็กฮิต',
  description: 'ดูแฮชแท็ก/คีย์เวิร์ดที่กำลังขึ้น เพื่อใช้กับคลิปต่อไป',
  status: 'เร็ว ๆ นี้',
  icon: Icons.tag,
  color: AppTheme.accent,
  prototypeOnly: true,
  settings: [
    GrowthToolSettingOption(
        id: 'content_category', label: 'เลือกหมวดสินค้าหรือกลุ่มคอนเทนต์'),
    GrowthToolSettingOption(
        id: 'next_clip_hashtags', label: 'ดูแฮชแท็กที่น่าลองใช้กับคลิปถัดไป'),
  ],
);
const _comment = GrowthToolDetail(
  id: 'ai_comment_center',
  title: 'ศูนย์คอมเมนต์ AI',
  description: 'สรุปคอมเมนต์และเตรียมร่างคำตอบให้ตรวจภายหลัง',
  status: 'เร็ว ๆ นี้',
  icon: Icons.forum_outlined,
  color: AppTheme.accent,
  prototypeOnly: true,
  settings: [
    GrowthToolSettingOption(
        id: 'sentiment_summary',
        label: 'ดูสรุปคอมเมนต์บวก ลบ และคำถามที่พบบ่อย'),
    GrowthToolSettingOption(
        id: 'reply_drafts', label: 'ให้ AI ร่างคำตอบไว้รอตรวจ'),
  ],
);
const _custom = GrowthToolDetail(
  id: 'custom-local-tool',
  title: 'ข้อความของผู้ใช้ 42',
  description: 'คำอธิบายที่ไม่รู้จัก ไม่ควรแปล',
  status: 'สถานะเฉพาะ',
  icon: Icons.settings,
  color: AppTheme.accent,
  settings: [
    GrowthToolSettingOption(id: 'custom-option', label: 'ตัวเลือกของผู้ใช้')
  ],
);

class _FakeStore implements PostDeeGrowthToolSettingsStore {
  final loads = <String>[];
  final saves = <({String id, GrowthToolSettings value})>[];
  GrowthToolSettings? saved;
  Future<GrowthToolSettings?> Function()? onLoad;
  Future<void> Function()? onSave;

  @override
  Future<GrowthToolSettings?> loadSettings(String toolId) async {
    loads.add(toolId);
    return onLoad != null ? onLoad!() : saved;
  }

  @override
  Future<void> saveSettings(String toolId, GrowthToolSettings settings) async {
    saves.add((id: toolId, value: settings));
    await onSave?.call();
    saved = settings;
  }
}

class _Fixture {
  _Fixture({String language = 'en', this.dark = false, this.scale = 1})
      : locale = ValueNotifier(Locale(language));
  final ValueNotifier<Locale> locale;
  final bool dark;
  final double scale;
  final store = _FakeStore();

  Widget app(GrowthToolDetail detail) => ValueListenableBuilder<Locale>(
        valueListenable: locale,
        builder: (_, value, __) {
          AppTheme.applyThemeMode(dark ? ThemeMode.dark : ThemeMode.light);
          return MaterialApp(
            locale: value,
            supportedLocales: PostDeeLocalizations.supportedLocales,
            localizationsDelegates: const [
              PostDeeLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate
            ],
            theme: dark ? AppTheme.dark : AppTheme.light,
            builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context).copyWith(
                    disableAnimations: true,
                    textScaler: TextScaler.linear(scale)),
                child: child!),
            home: Scaffold(
                body: Builder(
                    builder: (context) => TextButton(
                        key: const ValueKey('open-growth-tool'),
                        onPressed: () => showGrowthToolDetailSheet(
                            context, detail,
                            settingsStore: store),
                        child: const Text('Open tool')))),
          );
        },
      );
}

Future<void> _open(
    WidgetTester tester, _Fixture fixture, GrowthToolDetail detail) async {
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox());
    fixture.locale.dispose();
    AppTheme.applyThemeMode(ThemeMode.light);
  });
  await tester.pumpWidget(fixture.app(detail));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const ValueKey('open-growth-tool')));
  await tester.pumpAndSettle();
}

Finder _option(GrowthToolDetail detail, String id) =>
    find.byKey(ValueKey('growth-tool-option-${detail.id}-$id'));

Future<void> _tap(WidgetTester tester, Finder target) async {
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
  await tester.tap(target);
  await tester.pump();
}

bool _checked(WidgetTester tester, GrowthToolDetail detail, String id) =>
    tester.widget<Checkbox>(_option(detail, id)).value!;

void _readable(WidgetTester tester, String text) {
  final finder = find.text(text);
  expect(finder, findsOneWidget);
  final paragraph = tester.renderObject<RenderParagraph>(finder);
  expect(paragraph.didExceedMaxLines, isFalse, reason: 'Clipped text: $text');
  expect(
      paragraph.size.height,
      greaterThanOrEqualTo(
          paragraph.getMinIntrinsicHeight(paragraph.size.width) - .1),
      reason: 'Clipped text height: $text');
}

void main() {
  testWidgets('English prototype sheet names known analytics metadata honestly',
      (tester) async {
    final fixture = _Fixture();
    await _open(tester, fixture, _hashtag);
    expect(find.text('Details and settings'), findsOneWidget);
    expect(find.text('Settings: Trending hashtag radar'), findsOneWidget);
    expect(find.text('Coming soon'), findsOneWidget);
    expect(find.text('Local draft'), findsOneWidget);
    expect(find.text('Save draft'), findsOneWidget);
    expect(
        find.text('Find trending hashtags and keywords for your next video.'),
        findsOneWidget);
    expect(find.text('Choose a product or content category'), findsOneWidget);
    expect(
        find.text('Find hashtags to try in your next video'), findsOneWidget);
    expect(find.text('Options'), findsOneWidget);
    expect(
        find.text(
            'This feature is not connected to a live service yet. Your choices are saved only as a draft on this device.'),
        findsOneWidget);
    expect(
        find.byKey(const ValueKey('growth-tool-enabled-switch')), findsNothing);
    expect(fixture.store.saves, isEmpty);
  });

  testWidgets('English common settings keep unknown tool metadata raw',
      (tester) async {
    final fixture = _Fixture();
    await _open(tester, fixture, _custom);
    expect(find.text('Settings: ข้อความของผู้ใช้ 42'), findsOneWidget);
    expect(find.text('คำอธิบายที่ไม่รู้จัก ไม่ควรแปล'), findsOneWidget);
    expect(find.text('ตัวเลือกของผู้ใช้'), findsOneWidget);
    expect(find.text('Save settings'), findsOneWidget);
    expect(
        find.text(
            'These are initial settings. Your choices are saved on this device for future integration with the live service.'),
        findsOneWidget);
  });

  testWidgets('English comment prototype labels all review-only options',
      (tester) async {
    final fixture = _Fixture();
    await _open(tester, fixture, _comment);
    expect(find.text('Settings: AI comment center'), findsOneWidget);
    expect(find.text('Summarize comments and prepare reply drafts for review.'),
        findsOneWidget);
    expect(find.text('See positive and negative comments and common questions'),
        findsOneWidget);
    expect(find.text('Prepare AI reply drafts for review'), findsOneWidget);
    expect(
        find.byKey(const ValueKey('growth-tool-enabled-switch')), findsNothing);
    expect(fixture.store.loads, ['ai_comment_center']);
    expect(fixture.store.saves, isEmpty);
  });

  testWidgets('plain MaterialApp retains Thai shared and metadata copy',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
        home: Builder(
            builder: (context) =>
                Text(localizeGrowthToolMessage(context, 'เรดาร์แฮชแท็กฮิต')))));
    expect(find.text('เรดาร์แฮชแท็กฮิต'), findsOneWidget);
  });

  testWidgets('live locale preserves prototype choices and all stored IDs',
      (tester) async {
    final fixture = _Fixture();
    fixture.store.saved = const GrowthToolSettings(
        isEnabled: true,
        enabledOptionIds: {'content_category', 'unknown-old-id'});
    await _open(tester, fixture, _hashtag);
    expect(_checked(tester, _hashtag, 'content_category'), isTrue);
    expect(_checked(tester, _hashtag, 'next_clip_hashtags'), isFalse);
    await _tap(tester, _option(_hashtag, 'next_clip_hashtags'));
    fixture.locale.value = const Locale('th');
    await tester.pumpAndSettle();
    expect(find.text('ตั้งค่า: เรดาร์แฮชแท็กฮิต'), findsOneWidget);
    expect(_checked(tester, _hashtag, 'content_category'), isTrue);
    expect(_checked(tester, _hashtag, 'next_clip_hashtags'), isTrue);
    fixture.locale.value = const Locale('en');
    await tester.pumpAndSettle();
    expect(find.text('Settings: Trending hashtag radar'), findsOneWidget);
    expect(fixture.store.loads, ['hashtag_radar']);
    expect(fixture.store.saves, isEmpty);
    await _tap(tester, find.text('Save draft'));
    await tester.pumpAndSettle();
    expect(fixture.store.saves.single.id, 'hashtag_radar');
    expect(fixture.store.saves.single.value.isEnabled, isFalse);
    expect(fixture.store.saves.single.value.enabledOptionIds,
        {'content_category', 'next_clip_hashtags', 'unknown-old-id'});
  });

  testWidgets('pending load never enables or implicitly saves a prototype',
      (tester) async {
    final pending = Completer<GrowthToolSettings?>();
    final fixture = _Fixture()..store.onLoad = () => pending.future;
    await _open(tester, fixture, _comment);
    expect(
        find.byKey(const ValueKey('growth-tool-enabled-switch')), findsNothing);
    expect(_checked(tester, _comment, 'sentiment_summary'), isTrue);
    expect(fixture.store.saves, isEmpty);
    pending.complete(const GrowthToolSettings(
        isEnabled: true, enabledOptionIds: {'reply_drafts'}));
    await tester.pumpAndSettle();
    expect(find.text('Local draft'), findsOneWidget);
    expect(_checked(tester, _comment, 'sentiment_summary'), isFalse);
    expect(_checked(tester, _comment, 'reply_drafts'), isTrue);
    expect(fixture.store.saves, isEmpty);
  });

  testWidgets(
      'non-prototype settings retain enabled state and local-save behavior',
      (tester) async {
    final fixture = _Fixture();
    await _open(tester, fixture, _custom);
    expect(find.text('Not enabled'), findsOneWidget);
    expect(find.text('Settings on this device'), findsOneWidget);
    expect(find.text('Enable this tool'), findsOneWidget);
    await _tap(
        tester, find.byKey(const ValueKey('growth-tool-enabled-switch')));
    expect(find.text('Enabled'), findsOneWidget);
    await _tap(tester, find.text('Save settings'));
    await tester.pumpAndSettle();
    expect(fixture.store.saves.single.id, 'custom-local-tool');
    expect(fixture.store.saves.single.value.isEnabled, isTrue);
    expect(
        fixture.store.saves.single.value.enabledOptionIds, {'custom-option'});
    expect(find.text('Settings saved'), findsOneWidget);
  });

  testWidgets('pending prototype save follows locale and stays disabled',
      (tester) async {
    final pending = Completer<void>();
    final fixture = _Fixture(language: 'th')
      ..store.onSave = () => pending.future;
    await _open(tester, fixture, _hashtag);
    await _tap(tester, find.text('บันทึกแบบร่าง'));
    expect(find.text('กำลังบันทึก...'), findsOneWidget);
    expect(fixture.store.saves, hasLength(1));
    expect(fixture.store.saves.single.value.isEnabled, isFalse);
    expect(
        tester
            .widget<Checkbox>(_option(_hashtag, 'content_category'))
            .onChanged,
        isNull);
    expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull);
    expect(tester.widget<OutlinedButton>(find.byType(OutlinedButton)).onPressed,
        isNull);
    expect(
        tester.widget<IconButton>(find.byType(IconButton)).onPressed, isNull);
    fixture.locale.value = const Locale('en');
    await tester.pump();
    expect(find.text('Saving...'), findsOneWidget);
    pending.complete();
    await tester.pumpAndSettle();
    expect(
        find.text(
            'Draft saved on this device. This feature is still disabled.'),
        findsOneWidget);
    fixture.locale.value = const Locale('th');
    await tester.pump();
    expect(
        find.text('บันทึกแบบร่างไว้ในเครื่องแล้ว ยังไม่ได้เปิดใช้งานฟีเจอร์'),
        findsOneWidget);
    expect(fixture.store.saves, hasLength(1));
  });

  testWidgets('Close cancels edited local choices without saving',
      (tester) async {
    final fixture = _Fixture();
    await _open(tester, fixture, _comment);
    await _tap(tester, _option(_comment, 'reply_drafts'));
    await _tap(tester, find.byTooltip('Close'));
    await tester.pumpAndSettle();
    expect(find.text('Settings: AI comment center'), findsNothing);
    expect(fixture.store.saves, isEmpty);
  });

  testWidgets(
      'save failure uses current locale and permits a disabled-draft retry',
      (tester) async {
    final pending = Completer<void>();
    final fixture = _Fixture(language: 'th')
      ..store.onSave = () => pending.future;
    await _open(tester, fixture, _comment);
    await _tap(tester, find.text('บันทึกแบบร่าง'));
    fixture.locale.value = const Locale('en');
    await tester.pump();
    pending.completeError(StateError('fake local save failure'));
    await tester.pumpAndSettle();
    expect(find.text('Could not save settings.'), findsOneWidget);
    fixture.locale.value = const Locale('th');
    await tester.pump();
    expect(find.text('บันทึกการตั้งค่าไม่สำเร็จ'), findsOneWidget);
    fixture.locale.value = const Locale('en');
    await tester.pump();
    expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNotNull);
    expect(_checked(tester, _comment, 'reply_drafts'), isTrue);
    fixture.store.onSave = null;
    await _tap(tester, find.text('Save draft'));
    await tester.pumpAndSettle();
    expect(fixture.store.saves, hasLength(2));
    expect(fixture.store.saves.every((call) => !call.value.isEnabled), isTrue);
  });

  testWidgets('failed load retains the existing default choices',
      (tester) async {
    final fixture = _Fixture()
      ..store.onLoad = () async => throw StateError('fake load');
    await _open(tester, fixture, _hashtag);
    expect(_checked(tester, _hashtag, 'content_category'), isTrue);
    expect(_checked(tester, _hashtag, 'next_clip_hashtags'), isTrue);
    expect(fixture.store.saves, isEmpty);
    expect(find.text('Local draft'), findsOneWidget);
  });

  testWidgets('dismissed sheet ignores late load completion', (tester) async {
    final pending = Completer<GrowthToolSettings?>();
    final fixture = _Fixture()..store.onLoad = () => pending.future;
    await _open(tester, fixture, _hashtag);
    await _tap(tester, find.byTooltip('Close'));
    await tester.pumpAndSettle();
    pending.complete(
        const GrowthToolSettings(isEnabled: true, enabledOptionIds: {}));
    await tester.pumpAndSettle();
    expect(fixture.store.saves, isEmpty);
    expect(find.text('Settings: Trending hashtag radar'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('disposed sheet ignores late local-save feedback',
      (tester) async {
    final pending = Completer<void>();
    final fixture = _Fixture()..store.onSave = () => pending.future;
    await _open(tester, fixture, _hashtag);
    await _tap(tester, find.text('Save draft'));
    await tester.pumpWidget(const SizedBox());
    pending.complete();
    await tester.pump();
    expect(fixture.store.saves, hasLength(1));
    expect(fixture.store.saves.single.value.isEnabled, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('unknown custom note and metadata stay raw across locale changes',
      (tester) async {
    const detail = GrowthToolDetail(
        id: 'custom',
        title: 'หัวข้อเฉพาะ',
        description: 'ข้อความผู้ใช้',
        status: 'สถานะเฉพาะ',
        icon: Icons.settings,
        color: AppTheme.accent,
        note: 'คำแนะนำที่เขียนเอง 123',
        settings: [
          GrowthToolSettingOption(id: 'raw-id', label: 'ตัวเลือกที่เขียนเอง')
        ]);
    final fixture = _Fixture();
    await _open(tester, fixture, detail);
    for (final language in ['en', 'th', 'en']) {
      fixture.locale.value = Locale(language);
      await tester.pumpAndSettle();
      expect(find.text('ข้อความผู้ใช้'), findsOneWidget);
      expect(find.text('คำแนะนำที่เขียนเอง 123'), findsOneWidget);
      expect(find.text('ตัวเลือกที่เขียนเอง'), findsOneWidget);
      expect(fixture.store.saves, isEmpty);
    }
  });

  for (final dark in [false, true]) {
    for (final detail in [_hashtag, _comment, _custom]) {
      testWidgets(
          'all ${detail.id} controls remain readable at 320dp 2x (dark=$dark)',
          (tester) async {
        tester.view.physicalSize = const Size(320, 852);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final fixture = _Fixture(dark: dark, scale: 2);
        await _open(tester, fixture, detail);
        _readable(tester, 'Details and settings');
        final title = detail == _hashtag
            ? 'Settings: Trending hashtag radar'
            : detail == _comment
                ? 'Settings: AI comment center'
                : 'Settings: ${detail.title}';
        _readable(tester, title);
        if (!detail.prototypeOnly) _readable(tester, 'Settings on this device');
        final label = detail.prototypeOnly ? 'Save draft' : 'Save settings';
        await tester.ensureVisible(find.text(label));
        await tester.pumpAndSettle();
        _readable(tester, label);
        final button = find.ancestor(
            of: find.text(label), matching: find.byType(FilledButton));
        final textRect = tester.getRect(find.text(label));
        final buttonRect = tester.getRect(button);
        expect(textRect.top, greaterThanOrEqualTo(buttonRect.top));
        expect(textRect.bottom, lessThanOrEqualTo(buttonRect.bottom));
        expect(tester.takeException(), isNull);
      });
    }
  }
}
