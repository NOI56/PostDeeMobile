import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postdee_mobile/core/localization/postdee_localizations.dart';
import 'package:postdee_mobile/core/models/caption_language.dart';
import 'package:postdee_mobile/core/theme/app_theme.dart';
import 'package:postdee_mobile/features/uploader/caption_language_picker.dart';

const _fieldKey = ValueKey('test-caption-language-field');
const _sheetKey = ValueKey('caption-language-sheet');
const _searchKey = ValueKey('caption-language-search');
const _autoKey = ValueKey('caption-language-option-auto');
bool _fontsLoaded = false;

class _PickerFixture extends StatefulWidget {
  const _PickerFixture({super.key, this.initialValue = 'auto'});

  final String initialValue;

  @override
  State<_PickerFixture> createState() => _PickerFixtureState();
}

class _PickerFixtureState extends State<_PickerFixture> {
  late String value = widget.initialValue;
  bool enabled = true;
  Object scope = 'first-owner';
  final changes = <String>[];

  void changeScope() => setState(() {
        scope = 'second-owner';
        value = 'auto';
      });

  void disable() => setState(() => enabled = false);

  void restoreValue(String restored) => setState(() => value = restored);

  @override
  Widget build(BuildContext context) => Scaffold(
        body: SafeArea(
          child: SingleChildScrollView(
            padding: AppTheme.screenPadding,
            child: CaptionLanguagePicker(
              key: _fieldKey,
              value: value,
              selectionScope: scope,
              onChanged: enabled
                  ? (selected) => setState(() {
                        changes.add(selected);
                        value = selected;
                      })
                  : null,
            ),
          ),
        ),
      );
}

Future<GlobalKey<_PickerFixtureState>> _mount(
  WidgetTester tester, {
  String initialValue = 'auto',
  Locale locale = const Locale('en'),
  bool dark = false,
  double scale = 1,
  Size size = const Size(430, 850),
}) async {
  if (!_fontsLoaded) {
    await tester.runAsync(() async {
      final fonts = FontLoader('Anuphan');
      for (final weight in ['Regular', 'Medium', 'SemiBold', 'Bold']) {
        fonts.addFont(
            rootBundle.load('assets/fonts/anuphan/Anuphan-$weight.ttf'));
      }
      await fonts.load();
    });
    _fontsLoaded = true;
  }
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  addTearDown(() {
    tester.view.resetViewInsets();
    AppTheme.applyThemeMode(ThemeMode.light);
  });
  final fixtureKey = GlobalKey<_PickerFixtureState>();
  AppTheme.applyThemeMode(dark ? ThemeMode.dark : ThemeMode.light);
  await tester.pumpWidget(MaterialApp(
    locale: locale,
    supportedLocales: PostDeeLocalizations.supportedLocales,
    localizationsDelegates: const [
      PostDeeLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    theme: AppTheme.light,
    darkTheme: AppTheme.dark,
    themeMode: dark ? ThemeMode.dark : ThemeMode.light,
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(
        textScaler: TextScaler.linear(scale),
        disableAnimations: true,
      ),
      child: child!,
    ),
    home: _PickerFixture(key: fixtureKey, initialValue: initialValue),
  ));
  await tester.pumpAndSettle();
  return fixtureKey;
}

Future<void> _open(WidgetTester tester) async {
  await tester.tap(find.byKey(_fieldKey));
  await tester.pumpAndSettle();
  expect(find.byKey(_sheetKey), findsOneWidget);
}

Future<void> _search(WidgetTester tester, String query) async {
  await tester.enterText(find.byKey(_searchKey), query);
  await tester.pumpAndSettle();
}

Finder _sheetScrollable() => find
    .descendant(
        of: find
            .descendant(
                of: find.byKey(_sheetKey), matching: find.byType(ListView))
            .first,
        matching: find.byType(Scrollable))
    .first;

Future<void> _revealShortSheetControl(
    WidgetTester tester, Finder target) async {
  await tester.scrollUntilVisible(target, 40, scrollable: _sheetScrollable());
  await tester.pumpAndSettle();
  // A language row can exceed a very short landscape viewport at 2x text.
  // Keep its tappable center in view after scrolling, rather than its top edge.
  await Scrollable.ensureVisible(tester.element(target), alignment: 0.5);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
      'default Auto and manual native name are distinct from app locale',
      (tester) async {
    final fixture = await _mount(tester);
    expect(find.text('Caption language'), findsOneWidget);
    expect(find.text('Auto (match clip)'), findsOneWidget);
    await _open(tester);
    expect(find.text('Choose caption language'), findsOneWidget);
    await _search(tester, 'Russian');
    final russian =
        captionLanguageCatalog.singleWhere((entry) => entry.code == 'ru');
    expect(find.textContaining(russian.nativeName), findsWidgets);
    await tester.tap(find.byKey(const ValueKey('caption-language-option-ru')));
    await tester.pumpAndSettle();
    expect(fixture.currentState!.changes, ['ru']);
    expect(fixture.currentState!.value, 'ru');
    expect(find.byKey(_sheetKey), findsNothing);
    expect(find.text(russian.nativeName), findsOneWidget);
    expect(find.text('Caption language'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'search reaches Hebrew alias, Manipuri script and native endonyms',
      (tester) async {
    final fixture = await _mount(tester);
    for (final choice in <(String, String)>[
      ('iw', 'he'),
      ('Manipuri', 'mni-Mtei'),
      ('tl', 'fil'),
      (captionOutputLanguages['ru']!, 'ru'),
    ]) {
      await _open(tester);
      await _search(tester, choice.$1);
      final row = find.byKey(ValueKey('caption-language-option-${choice.$2}'));
      expect(row, findsOneWidget);
      await tester.ensureVisible(row);
      await tester.tap(row);
      await tester.pumpAndSettle();
      expect(fixture.currentState!.value, choice.$2);
    }
    expect(fixture.currentState!.changes, ['he', 'mni-Mtei', 'fil', 'ru']);
    expect(tester.takeException(), isNull);
  });

  testWidgets('manual selection is marked and remains recoverable as Auto',
      (tester) async {
    final semantics = tester.ensureSemantics();
    try {
      final fixture = await _mount(tester, initialValue: 'ru');
      await _open(tester);
      final selected = find.byKey(const ValueKey('caption-language-option-ru'));
      expect(selected, findsOneWidget);
      expect(
          tester
              .getSemantics(selected)
              .getSemanticsData()
              .flagsCollection
              .isSelected
              .toBoolOrNull(),
          isTrue);
      await _search(tester, 'no language matches 12345');
      expect(find.byKey(_autoKey), findsOneWidget);
      await tester.tap(find.byKey(_autoKey));
      await tester.pumpAndSettle();
      expect(fixture.currentState!.value, 'auto');
      expect(fixture.currentState!.changes, ['auto']);
      expect(tester.takeException(), isNull);
    } finally {
      semantics.dispose();
    }
  });

  testWidgets('empty search can clear and closing preserves the chosen value',
      (tester) async {
    final fixture = await _mount(tester, initialValue: 'ja');
    await _open(tester);
    await _search(tester, 'no language matches 12345');
    expect(
        find.byKey(const ValueKey('caption-language-option-ru')), findsNothing);
    final clear = find.byKey(const ValueKey('caption-language-clear-search'));
    expect(clear, findsOneWidget);
    await tester.tap(clear);
    await tester.pumpAndSettle();
    expect(
        tester.widget<TextField>(find.byKey(_searchKey)).controller!.text, '');
    await _search(tester, 'ru');
    expect(find.byKey(const ValueKey('caption-language-option-ru')),
        findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('caption-language-close')));
    await tester.pumpAndSettle();
    expect(fixture.currentState!.value, 'ja');
    expect(fixture.currentState!.changes, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('disabled picker cannot open or replace its value',
      (tester) async {
    final fixture = await _mount(tester, initialValue: 'en');
    fixture.currentState!.disable();
    await tester.pumpAndSettle();
    expect(
        tester.widget<CaptionLanguagePicker>(find.byKey(_fieldKey)).onChanged,
        isNull);
    await tester.tap(find.byKey(_fieldKey));
    await tester.pumpAndSettle();
    expect(find.byKey(_sheetKey), findsNothing);
    expect(fixture.currentState!.value, 'en');
    expect(fixture.currentState!.changes, isEmpty);
  });

  for (final changeScope in [false, true]) {
    testWidgets(
        '${changeScope ? 'owner change' : 'disabling'} invalidates an open selection',
        (tester) async {
      final fixture = await _mount(tester, initialValue: 'en');
      await _open(tester);
      await _search(tester, 'Russian');
      if (changeScope) {
        fixture.currentState!.changeScope();
      } else {
        fixture.currentState!.disable();
      }
      await tester.pumpAndSettle();
      final staleRow = find.byKey(const ValueKey('caption-language-option-ru'));
      if (staleRow.evaluate().isNotEmpty) {
        await tester.tap(staleRow);
        await tester.pumpAndSettle();
      }
      expect(fixture.currentState!.changes, isEmpty);
      expect(fixture.currentState!.value, changeScope ? 'auto' : 'en');
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('restoring another draft value invalidates an open selection',
      (tester) async {
    final fixture = await _mount(tester, initialValue: 'en');
    await _open(tester);
    await _search(tester, 'Russian');
    fixture.currentState!.restoreValue('ja');
    await tester.pumpAndSettle();
    final staleRow = find.byKey(const ValueKey('caption-language-option-ru'));
    if (staleRow.evaluate().isNotEmpty) {
      await tester.tap(staleRow);
      await tester.pumpAndSettle();
    }
    expect(fixture.currentState!.changes, isEmpty);
    expect(fixture.currentState!.value, 'ja');
    expect(tester.takeException(), isNull);
  });

  testWidgets('keyboard search action dismisses the keyboard without choosing',
      (tester) async {
    final fixture = await _mount(tester);
    await _open(tester);
    await _search(tester, 'Russian');
    expect(tester.testTextInput.isVisible, isTrue);
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();
    expect(tester.testTextInput.isVisible, isFalse);
    expect(find.byKey(_sheetKey), findsOneWidget);
    expect(find.byKey(const ValueKey('caption-language-option-ru')),
        findsOneWidget);
    expect(fixture.currentState!.changes, isEmpty);
    expect(fixture.currentState!.value, 'auto');
    expect(tester.takeException(), isNull);
  });

  for (final dark in [false, true]) {
    for (final locale in [const Locale('th'), const Locale('en')]) {
      testWidgets(
          'search works at 320px and 2x text with keyboard in ${locale.languageCode} ${dark ? 'dark' : 'light'}',
          (tester) async {
        final fixture = await _mount(tester,
            locale: locale, dark: dark, scale: 2, size: const Size(320, 640));
        await _open(tester);
        expect(
            find.text(locale.languageCode == 'th'
                ? 'เลือกภาษาแคปชั่น'
                : 'Choose caption language'),
            findsOneWidget);
        tester.view.viewInsets =
            FakeViewPadding(bottom: 220 * tester.view.devicePixelRatio);
        await tester.pumpAndSettle();
        await _search(tester, 'mni');
        final row =
            find.byKey(const ValueKey('caption-language-option-mni-Mtei'));
        await tester.scrollUntilVisible(row, 80,
            scrollable: find
                .descendant(
                    of: find.byKey(_sheetKey),
                    matching: find.byType(Scrollable))
                .last);
        await tester.pumpAndSettle();
        expect(row.hitTestable(), findsOneWidget,
            reason: 'Option ${tester.getRect(row)} must remain tappable in '
                'sheet ${tester.getRect(find.byKey(_sheetKey))} with keyboard');
        await tester.tap(row);
        await tester.pumpAndSettle();
        expect(fixture.currentState!.value, 'mni-Mtei');
        expect(fixture.currentState!.changes, ['mni-Mtei']);
        expect(tester.takeException(), isNull);
      });
    }
  }

  for (final dimensions in <(Size, double)>[
    (const Size(320, 360), 220),
    (const Size(640, 320), 260),
  ]) {
    testWidgets(
        'short ${dimensions.$1.width.toInt()}x${dimensions.$1.height.toInt()} viewport keeps search and options usable with ${dimensions.$2.toInt()}px keyboard at 2x',
        (tester) async {
      final fixture = await _mount(tester,
          locale: const Locale('th'), scale: 2, size: dimensions.$1);
      await _open(tester);
      await _revealShortSheetControl(tester, find.byKey(_searchKey));
      await _search(tester, 'mni');
      final controller =
          tester.widget<TextField>(find.byKey(_searchKey)).controller!;

      tester.view.viewInsets =
          FakeViewPadding(bottom: dimensions.$2 * tester.view.devicePixelRatio);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await _revealShortSheetControl(tester, find.byKey(_searchKey));
      expect(find.byKey(_searchKey).hitTestable(), findsOneWidget);
      expect(tester.widget<TextField>(find.byKey(_searchKey)).controller,
          same(controller));
      expect(controller.text, 'mni');
      await _search(tester, 'Russian');

      final row = find.byKey(const ValueKey('caption-language-option-ru'));
      await _revealShortSheetControl(tester, row);
      expect(row.hitTestable(), findsOneWidget);
      expect(controller.text, 'Russian');
      await tester.tap(row);
      await tester.pumpAndSettle();
      expect(fixture.currentState!.value, 'ru');
      expect(fixture.currentState!.changes, ['ru']);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('very large keyboard cannot create negative sheet constraints',
      (tester) async {
    final fixture = await _mount(tester,
        locale: const Locale('th'), scale: 2, size: const Size(320, 360));
    await _open(tester);
    await _revealShortSheetControl(tester, find.byKey(_searchKey));
    await _search(tester, 'Russian');
    final controller =
        tester.widget<TextField>(find.byKey(_searchKey)).controller!;

    tester.view.viewInsets =
        FakeViewPadding(bottom: 340 * tester.view.devicePixelRatio);
    await tester.pumpAndSettle();
    expect(find.byKey(_sheetKey), findsOneWidget);
    expect(
        tester.getSize(find.byKey(_sheetKey)).height, greaterThanOrEqualTo(0));
    expect(controller.text, 'Russian');
    expect(tester.takeException(), isNull);

    tester.view.resetViewInsets();
    await tester.pumpAndSettle();
    final row = find.byKey(const ValueKey('caption-language-option-ru'));
    await _revealShortSheetControl(tester, row);
    expect(row.hitTestable(), findsOneWidget);
    expect(controller.text, 'Russian');
    await tester.tap(row);
    await tester.pumpAndSettle();
    expect(fixture.currentState!.value, 'ru');
    expect(fixture.currentState!.changes, ['ru']);
    expect(tester.takeException(), isNull);
  });
}
