import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> showBioControl(WidgetTester tester, Finder finder,
    {double delta = 250}) async {
  if (finder.evaluate().isEmpty) {
    await tester.scrollUntilVisible(finder, delta,
        scrollable: find.byType(Scrollable).last);
  }
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
}

Future<void> _tapVisibleBioKey(WidgetTester tester, String key) async {
  final finder = find.byKey(ValueKey(key));
  await showBioControl(tester, finder);
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<void> showBioStep(WidgetTester tester, String step) async {
  await tester.pumpAndSettle();
  final current = switch (step) {
    'info' => 'link-in-bio-store-name',
    'theme' => 'link-in-bio-decorate',
    'review' => 'link-in-bio-publish',
    _ => 'link-in-bio-add',
  };
  if (find.byKey(ValueKey(current)).evaluate().isNotEmpty) return;
  for (final key in [
    'link-in-bio-close-editor',
    'link-in-bio-back-to-links',
  ]) {
    if (find.byKey(ValueKey(key)).evaluate().isNotEmpty) {
      await _tapVisibleBioKey(tester, key);
      break;
    }
  }
  if (step != 'links') {
    await _tapVisibleBioKey(tester, 'link-in-bio-step-$step');
  }
}

Future<void> showBioUrlSettings(WidgetTester tester) async {
  await showBioStep(tester, 'info');
  final field = find.byKey(const ValueKey('link-in-bio-slug'));
  if (field.evaluate().isEmpty) {
    await _tapVisibleBioKey(tester, 'link-in-bio-url-settings');
  }
  await showBioControl(tester, field);
}

Future<void> tapBioControl(WidgetTester tester, String key) async {
  await tester.pumpAndSettle();
  if ({'link-in-bio-save-draft', 'link-in-bio-refresh', 'link-in-bio-unpublish'}
      .contains(key)) {
    await _tapVisibleBioKey(tester, 'link-in-bio-more');
  } else if (key == 'link-in-bio-copy' || key == 'link-in-bio-open') {
    await showBioStep(tester, 'links');
  } else if (key == 'link-in-bio-publish' || key == 'link-in-bio-preview') {
    await showBioStep(tester, 'review');
  } else if (key == 'link-in-bio-decorate' ||
      key.startsWith('link-in-bio-theme-')) {
    await showBioStep(tester, 'theme');
  } else if (key == 'link-in-bio-add' ||
      key.startsWith('link-in-bio-edit-') ||
      key.startsWith('link-in-bio-toggle-')) {
    await showBioStep(tester, 'links');
  } else {
    final menuAction =
        RegExp(r'^link-in-bio-(?:feature|move-up|move-down|delete)-(.+)$')
            .firstMatch(key);
    if (menuAction != null) {
      await showBioStep(tester, 'links');
      await _tapVisibleBioKey(
          tester, 'link-in-bio-link-menu-${menuAction.group(1)}');
    }
  }
  await _tapVisibleBioKey(tester, key);
}
