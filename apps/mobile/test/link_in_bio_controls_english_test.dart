import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postdee_mobile/core/localization/postdee_localizations.dart';
import 'package:postdee_mobile/core/models/link_in_bio_appearance.dart';
import 'package:postdee_mobile/core/theme/app_theme.dart';
import 'package:postdee_mobile/features/link_in_bio/link_in_bio_appearance_editor.dart';
import 'package:postdee_mobile/features/link_in_bio/link_in_bio_color_picker.dart';
import 'package:postdee_mobile/features/link_in_bio/link_in_bio_logo_crop.dart';
import 'package:postdee_mobile/features/link_in_bio/link_in_bio_platform_picker.dart';

final _png = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGP4z8DwHwAFAAH/iZk9HQAAAABJRU5ErkJggg==');
const _appearance = LinkInBioAppearance(
    description: 'ภาพและพื้นหลัง',
    featuredLabel: 'โปรของร้าน',
    buttonColor: '#123456',
    nameStyle: LinkInBioTextStyle(color: '#234567', font: 'prompt'));
Finder _key(String value) => find.byKey(ValueKey(value));

class _Fixture {
  _Fixture({String language = 'en', this.dark = false, this.scale = 1})
      : locale = ValueNotifier(Locale(language));

  final ValueNotifier<Locale> locale;
  final bool dark;
  final double scale;

  Widget app(Widget body) => ValueListenableBuilder<Locale>(
        valueListenable: locale,
        builder: (_, value, __) {
          AppTheme.applyThemeMode(dark ? ThemeMode.dark : ThemeMode.light);
          return MaterialApp(
            locale: value,
            localizationsDelegates: const [
              PostDeeLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            supportedLocales: PostDeeLocalizations.supportedLocales,
            theme: dark ? AppTheme.dark : AppTheme.light,
            builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context).copyWith(
                    disableAnimations: true,
                    textScaler: TextScaler.linear(scale)),
                child: child!),
            home: Scaffold(body: body),
          );
        },
      );
}

Future<void> _mount(WidgetTester tester, _Fixture fixture, Widget body) async {
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox());
    fixture.locale.dispose();
    AppTheme.applyThemeMode(ThemeMode.light);
  });
  await tester.pumpWidget(fixture.app(body));
  await tester.pumpAndSettle();
}

Widget _colorLauncher(ValueChanged<String?> onResult) => Builder(
    builder: (context) => TextButton(
          onPressed: () async =>
              onResult(await selectBioColor(context, const Color(0xff305d36))),
          child: const Text('Open color'),
        ));

Widget _editor({bool themes = false}) => LinkInBioAppearanceEditor(
      appearance: const LinkInBioAppearance(description: 'ข้อความร้านของฉัน'),
      storeName: 'ร้านของคุณ',
      slug: 'raw-store',
      links: const [],
      images: const {},
      uploadImage: (_) async => throw StateError('No image upload allowed'),
      showThemePicker: themes,
    );

Widget _editorLauncher(ValueChanged<LinkInBioAppearance?> onResult,
        {BioImageUpload? upload}) =>
    Builder(
        builder: (context) => TextButton(
            onPressed: () async => onResult(
                await showModalBottomSheet<LinkInBioAppearance>(
                    context: context,
                    isScrollControlled: true,
                    builder: (_) => LinkInBioAppearanceEditor(
                        appearance: _appearance,
                        storeName: 'ร้านของคุณ',
                        slug: 'raw-store',
                        links: const [],
                        images: const {},
                        showThemePicker: false,
                        uploadImage: upload ??
                            (_) async =>
                                throw StateError('No upload allowed')))),
            child: const Text('Open editor')));

Widget _cropLauncher(ValueChanged<Uint8List?> onResult,
        {Future<Uint8List> Function(ui.Image, Rect)? export}) =>
    Builder(
        builder: (context) => TextButton(
            onPressed: () async => onResult(await showDialog<Uint8List>(
                context: context,
                builder: (_) =>
                    LinkInBioLogoCropDialog(bytes: _png, exportImage: export))),
            child: const Text('Open crop')));

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<void> _decodeReady(WidgetTester tester) async {
  for (var attempt = 0; attempt < 8; attempt++) {
    await tester.pump();
    await tester
        .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
  }
  await tester.pumpAndSettle();
}

void _narrow(WidgetTester tester) {
  tester.view.physicalSize = const Size(320, 852);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void _readable(WidgetTester tester, String text) {
  final finder = find.text(text).last;
  expect(finder, findsOneWidget);
  final paragraph = tester.renderObject<RenderParagraph>(finder);
  expect(paragraph.didExceedMaxLines, isFalse,
      reason: 'Clipped text: $text; ${paragraph.constraints}; ${paragraph.size}');
}

void main() {
  testWidgets('English color dialog labels its controls', (tester) async {
    final fixture = _Fixture();
    await _mount(tester, fixture, _colorLauncher((_) {}));
    await tester.tap(find.text('Open color'));
    await tester.pumpAndSettle();
    expect(find.text('Choose a color'), findsOneWidget);
    expect(find.text('Hue'), findsOneWidget);
    expect(find.text('Use this color'), findsOneWidget);
  });

  testWidgets('English platform picker labels its choices', (tester) async {
    final fixture = _Fixture();
    await _mount(tester, fixture,
        BioPlatformPicker(selected: 'auto', onSelected: (_) {}));
    expect(find.text('Choose a logo'), findsOneWidget);
    expect(find.text('Auto-detect from link'), findsOneWidget);
  });

  testWidgets('English appearance editor labels its groups', (tester) async {
    final fixture = _Fixture();
    await _mount(tester, fixture, _editor());
    expect(find.text('More customization'), findsOneWidget);
    expect(find.text('Effects'), findsOneWidget);
    expect(find.text('Apply to draft'), findsOneWidget);
  });

  testWidgets('English theme picker names its template collection',
      (tester) async {
    final fixture = _Fixture();
    await _mount(
        tester,
        fixture,
        SingleChildScrollView(
            child: BioThemePicker(
                appearance: const LinkInBioAppearance(), onChanged: (_) {})));
    expect(find.text('Minimal · 20 templates'), findsOneWidget);
  });

  testWidgets('English crop dialog shows a readable image failure',
      (tester) async {
    final fixture = _Fixture();
    await _mount(tester, fixture,
        LinkInBioLogoCropDialog(bytes: Uint8List.fromList([0, 1, 2])));
    expect(find.text('Adjust logo'), findsOneWidget);
    expect(find.text('Could not open this image. Please choose another image.'),
        findsOneWidget);
  });

  testWidgets(
      'color selection survives locale changes and returns the selected hex',
      (tester) async {
    final fixture = _Fixture();
    final results = <String?>[];
    await _mount(tester, fixture, _colorLauncher(results.add));
    await _tap(tester, find.text('Open color'));
    await _tap(tester, _key('link-in-bio-color-swatch-3b82f6'));
    expect(find.text('#3b82f6'), findsOneWidget);
    fixture.locale.value = const Locale('th');
    await tester.pumpAndSettle();
    expect(find.text('เลือกสี'), findsOneWidget);
    expect(find.text('#3b82f6'), findsOneWidget);
    fixture.locale.value = const Locale('en');
    await tester.pumpAndSettle();
    await _tap(tester, find.text('Use this color'));
    expect(results, ['#3b82f6']);
  });

  testWidgets('canceling color selection returns no replacement value',
      (tester) async {
    final fixture = _Fixture();
    final results = <String?>[];
    await _mount(tester, fixture, _colorLauncher(results.add));
    await _tap(tester, find.text('Open color'));
    await _tap(tester, _key('link-in-bio-color-swatch-ef4444'));
    await _tap(tester, find.text('Cancel'));
    expect(results, [null]);
  });

  testWidgets('platform picker keeps raw search and selected ID across locale',
      (tester) async {
    final fixture = _Fixture();
    final selected = <String>[];
    await _mount(tester, fixture,
        BioPlatformPicker(selected: 'phone', onSelected: selected.add));
    await tester.enterText(_key('bio-platform-search'), 'โทรศัพท์');
    await tester.pumpAndSettle();
    expect(find.text('Phone'), findsOneWidget);
    expect(tester.widget<ListTile>(_key('bio-platform-option-phone')).selected,
        isTrue);
    fixture.locale.value = const Locale('th');
    await tester.pumpAndSettle();
    expect(
        tester.widget<TextField>(_key('bio-platform-search')).controller!.text,
        'โทรศัพท์');
    expect(find.text('โทรศัพท์'), findsWidgets);
    fixture.locale.value = const Locale('en');
    await tester.pumpAndSettle();
    await _tap(tester, _key('bio-platform-option-phone'));
    expect(selected, ['phone']);
    await tester.enterText(_key('bio-platform-search'), 'no-such-logo-xyz');
    await tester.pumpAndSettle();
    expect(find.text('No matching logos'), findsOneWidget);
    await _tap(tester, _key('bio-platform-search-clear'));
    expect(
        tester.widget<TextField>(_key('bio-platform-search')).controller!.text,
        isEmpty);
    expect(find.text('Auto-detect from link'), findsOneWidget);
  });

  testWidgets('English automatic-logo search remains matched after Thai switch',
      (tester) async {
    final fixture = _Fixture();
    await _mount(tester, fixture,
        BioPlatformPicker(selected: 'auto', onSelected: (_) {}));
    await tester.enterText(_key('bio-platform-search'), 'Auto-detect');
    await tester.pumpAndSettle();
    expect(_key('bio-platform-option-auto'), findsOneWidget);
    fixture.locale.value = const Locale('th');
    await tester.pumpAndSettle();
    expect(_key('bio-platform-option-auto'), findsOneWidget);
    expect(
        tester.widget<TextField>(_key('bio-platform-search')).controller!.text,
        'Auto-detect');
  });

  testWidgets('color validation follows locale without changing typed value',
      (tester) async {
    final fixture = _Fixture();
    final changes = <String?>[];
    await _mount(
        tester,
        fixture,
        Form(
            child: BioColorField(
                label: 'Custom color',
                value: '#123456',
                onChanged: changes.add)));
    await tester.enterText(find.byType(TextFormField), '#bad');
    await tester.pumpAndSettle();
    expect(find.text('Enter a color as #RRGGBB'), findsOneWidget);
    fixture.locale.value = const Locale('th');
    await tester.pumpAndSettle();
    expect(find.text('กรอกสีแบบ #RRGGBB'), findsOneWidget);
    expect(
        tester
            .widget<TextFormField>(find.byType(TextFormField))
            .controller!
            .text,
        '#bad');
    expect(changes, isEmpty);
  });

  testWidgets(
      'editor live locale preserves typed descriptions and applies values only to draft',
      (tester) async {
    final fixture = _Fixture();
    final results = <LinkInBioAppearance?>[];
    await _mount(tester, fixture, _editorLauncher(results.add));
    await _tap(tester, find.text('Open editor'));
    await _tap(tester, _key('link-in-bio-decoration-images'));
    final description = _key('link-in-bio-description');
    final controller = tester.widget<TextFormField>(description).controller!;
    expect(controller.text, 'ภาพและพื้นหลัง');
    await tester.enterText(description, 'ข้อความร้านที่กรอกใหม่');
    fixture.locale.value = const Locale('th');
    await tester.pumpAndSettle();
    expect(
        tester.widget<TextFormField>(description).controller, same(controller));
    expect(controller.text, 'ข้อความร้านที่กรอกใหม่');
    fixture.locale.value = const Locale('en');
    await tester.pumpAndSettle();
    expect(controller.text, 'ข้อความร้านที่กรอกใหม่');
    await _tap(tester, _key('link-in-bio-decoration-featured'));
    await tester.enterText(
        _key('link-in-bio-featured-label'), 'Choose a color');
    await _tap(tester, _key('link-in-bio-decoration-done'));
    expect(results, hasLength(1));
    expect(results.single!.description, 'ข้อความร้านที่กรอกใหม่');
    expect(results.single!.featuredLabel, 'Choose a color');
    expect(results.single!.buttonColor, _appearance.buttonColor);
    expect(results.single!.nameStyle.toJson(), _appearance.nameStyle.toJson());
  });

  testWidgets(
      'untouched English editor keeps saved Thai customer values exactly',
      (tester) async {
    final fixture = _Fixture();
    final results = <LinkInBioAppearance?>[];
    await _mount(tester, fixture, _editorLauncher(results.add));
    await _tap(tester, find.text('Open editor'));
    await _tap(tester, _key('link-in-bio-decoration-done'));
    expect(results.single!.toJson(), _appearance.toJson());
  });

  testWidgets(
      'pending image error uses current locale and keeps previous design',
      (tester) async {
    final fixture = _Fixture(language: 'th');
    final pending = Completer<String?>();
    final slots = <String>[];
    final results = <LinkInBioAppearance?>[];
    await _mount(
        tester,
        fixture,
        _editorLauncher(results.add, upload: (slot) {
          slots.add(slot);
          return pending.future;
        }));
    await _tap(tester, find.text('Open editor'));
    await _tap(tester, _key('link-in-bio-decoration-images'));
    final upload = _key('link-in-bio-image-logo');
    await tester.ensureVisible(upload);
    await tester.tap(upload);
    await tester.pump();
    expect(tester.widget<ButtonStyleButton>(upload).onPressed, isNull);
    expect(
        tester
            .widget<ButtonStyleButton>(_key('link-in-bio-decoration-done'))
            .onPressed,
        isNull);
    fixture.locale.value = const Locale('en');
    await tester.pump();
    pending.completeError(StateError('fake upload failure'));
    await tester.pumpAndSettle();
    expect(
        find.text(
            'Could not upload the image. Please try again. Your previous image has been kept.'),
        findsOneWidget);
    expect(slots, ['logo']);
    await _tap(tester, _key('link-in-bio-decoration-done'));
    expect(results.single!.toJson(), _appearance.toJson());
  });

  testWidgets('unknown image format error is preserved across locales',
      (tester) async {
    final fixture = _Fixture();
    const raw = 'custom-image-code: รายละเอียดเดิม';
    await _mount(
        tester,
        fixture,
        _editorLauncher((_) {}, upload: (_) async {
          throw const FormatException(raw);
        }));
    await _tap(tester, find.text('Open editor'));
    await _tap(tester, _key('link-in-bio-decoration-images'));
    await _tap(tester, _key('link-in-bio-image-logo'));
    expect(find.text(raw), findsOneWidget);
    fixture.locale.value = const Locale('th');
    await tester.pumpAndSettle();
    expect(find.text(raw), findsOneWidget);
  });

  testWidgets('logo crop keeps zoom across locale and fake export returns once',
      (tester) async {
    final fixture = _Fixture();
    final pending = Completer<Uint8List>();
    final results = <Uint8List?>[];
    var exports = 0;
    await _mount(
        tester,
        fixture,
        _cropLauncher(results.add, export: (_, __) {
          exports++;
          return pending.future;
        }));
    await tester.tap(find.text('Open crop'));
    await _decodeReady(tester);
    final zoom = _key('link-in-bio-logo-crop-zoom');
    await tester.ensureVisible(zoom);
    await tester.pumpAndSettle();
    await tester.drag(zoom, const Offset(50, 0));
    await tester.pumpAndSettle();
    final value = tester.widget<Slider>(zoom).value;
    expect(value, greaterThan(1));
    fixture.locale.value = const Locale('th');
    await tester.pumpAndSettle();
    expect(tester.widget<Slider>(zoom).value, value);
    final confirm = _key('link-in-bio-logo-crop-confirm');
    await tester.ensureVisible(confirm);
    await tester.tap(confirm);
    await tester.pump();
    expect(exports, 1);
    expect(find.text('กำลังบันทึก…'), findsOneWidget);
    expect(tester.widget<ButtonStyleButton>(confirm).onPressed, isNull);
    fixture.locale.value = const Locale('en');
    await tester.pump();
    expect(find.text('Saving…'), findsOneWidget);
    final output = Uint8List.fromList([1, 2, 3]);
    pending.complete(output);
    await tester.pumpAndSettle();
    expect(results, [same(output)]);
    expect(exports, 1);
  });

  testWidgets('logo export error follows live locale without closing dialog',
      (tester) async {
    final fixture = _Fixture();
    await _mount(
        tester,
        fixture,
        _cropLauncher((_) {}, export: (_, __) async {
          throw StateError('fake export');
        }));
    await tester.tap(find.text('Open crop'));
    await _decodeReady(tester);
    await _tap(tester, _key('link-in-bio-logo-crop-confirm'));
    expect(find.text('Could not save the logo. Please try again.'),
        findsOneWidget);
    fixture.locale.value = const Locale('th');
    await tester.pumpAndSettle();
    expect(find.text('บันทึกโลโก้ไม่สำเร็จ กรุณาลองใหม่'), findsOneWidget);
    expect(
        tester
            .widget<ButtonStyleButton>(_key('link-in-bio-logo-crop-confirm'))
            .onPressed,
        isNotNull);
  });

  testWidgets('plain MaterialApp keeps Thai control copy and platform labels',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: BioPlatformPicker(selected: 'auto', onSelected: (_) {}))));
    expect(find.text('เลือกโลโก้'), findsOneWidget);
    expect(find.text('เลือกจากลิงก์อัตโนมัติ'), findsOneWidget);
    expect(bioPlatformLabel('auto'), 'เลือกจากลิงก์อัตโนมัติ');
    expect(bioPlatformLabel('phone'), 'โทรศัพท์');
    expect(bioPlatformLabel('youtube'), 'YouTube');
  });

  testWidgets(
      'English template preview cancels then applies once with customer content kept',
      (tester) async {
    final fixture = _Fixture();
    final results = <LinkInBioAppearance>[];
    await _mount(
        tester,
        fixture,
        SingleChildScrollView(
            child: BioThemePicker(
                appearance: _appearance,
                storeName: 'ร้านของคุณ',
                onChanged: results.add)));
    await _tap(tester, _key('link-in-bio-template-minimal-white-editorial'));
    expect(find.text('Type and fine lines'), findsWidgets);
    expect(find.text('Minimal'), findsOneWidget);
    await _tap(tester, _key('link-in-bio-template-preview-close'));
    expect(results, isEmpty);
    await _tap(tester, _key('link-in-bio-template-minimal-white-editorial'));
    await _tap(tester, _key('link-in-bio-template-use'));
    expect(results, hasLength(1));
    expect(results.single.templateId, 'minimal-white-editorial');
    expect(results.single.description, _appearance.description);
    expect(results.single.featuredLabel, _appearance.featuredLabel);
    expect(results.single.logoKey, _appearance.logoKey);
  });

  for (final dark in [false, true]) {
    testWidgets('English color and platform controls fit 320dp 2x (dark=$dark)',
        (tester) async {
      _narrow(tester);
      final fixture = _Fixture(dark: dark, scale: 2);
      await _mount(tester, fixture, _colorLauncher((_) {}));
      await _tap(tester, find.text('Open color'));
      _readable(tester, 'Choose a color');
      _readable(tester, 'Use this color');
      await _tap(tester, find.text('Cancel'));
      await tester.pumpWidget(
          fixture.app(BioPlatformPicker(selected: 'auto', onSelected: (_) {})));
      await tester.pumpAndSettle();
      _readable(tester, 'Choose a logo');
      _readable(tester, 'Search app or country');
      _readable(tester, 'Auto-detect from link');
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        'font and color field labels remain readable at 320dp 2x (dark=$dark)',
        (tester) async {
      _narrow(tester);
      final fixture = _Fixture(dark: dark, scale: 2);
      await _mount(
          tester,
          fixture,
          Padding(
              padding: const EdgeInsets.all(16),
              child: SingleChildScrollView(
                  child: Column(children: [
                BioColorField(
                    label: 'Background color',
                    value: '#123456',
                    onChanged: (_) {}),
                BioFontField(
                    label: 'Store description font',
                    value: 'anuphan',
                    onChanged: (_) {}),
              ]))));
      _readable(tester, 'Background color');
      _readable(tester, 'Store description font');
      _readable(tester, 'Anuphan • Sample text');
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        'appearance sections and crop controls fit 320dp 2x (dark=$dark)',
        (tester) async {
      _narrow(tester);
      final fixture = _Fixture(dark: dark, scale: 2);
      await _mount(tester, fixture, _editor());
      _readable(tester, 'More customization');
      _readable(tester, 'Apply to draft');
      await _tap(tester, _key('link-in-bio-decoration-effects'));
      await tester
          .ensureVisible(find.text('Gently animate the featured button'));
      _readable(tester, 'Gently animate the featured button');
      await _tap(tester, _key('link-in-bio-decoration-featured'));
      await tester.ensureVisible(_key('link-in-bio-featured-label'));
      _readable(tester, 'Featured promotion heading');
      await tester.pumpWidget(
          fixture.app(LinkInBioLogoCropDialog(bytes: Uint8List.fromList([0]))));
      await tester.pumpAndSettle();
      _readable(tester, 'Adjust logo');
      _readable(
          tester, 'Could not open this image. Please choose another image.');
      _readable(tester, 'Use this logo');
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        'theme names and apply action are readable at 320dp 2x (dark=$dark)',
        (tester) async {
      _narrow(tester);
      final fixture = _Fixture(dark: dark, scale: 2);
      final results = <LinkInBioAppearance>[];
      await _mount(
          tester,
          fixture,
          SingleChildScrollView(
              child: BioThemePicker(
                  appearance: _appearance,
                  storeName: 'ร้านของคุณ',
                  onChanged: results.add)));
      await tester
          .ensureVisible(_key('link-in-bio-template-minimal-clean-cover'));
      await tester.pumpAndSettle();
      expect(tester.getSize(_key('link-in-bio-template-minimal-clean-cover')).width,
          greaterThan(280));
      _readable(tester, 'Simple featured image');
      await _tap(tester, _key('link-in-bio-template-minimal-clean-cover'));
      _readable(tester, 'Apply to draft');
      await _tap(tester, _key('link-in-bio-template-use'));
      expect(results.single.templateId, 'minimal-clean-cover');
      expect(results.single.description, _appearance.description);
      expect(tester.takeException(), isNull);
    });
  }
}
