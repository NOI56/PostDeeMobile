import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postdee_mobile/core/auth/auth_session.dart';
import 'package:postdee_mobile/core/network/postdee_api_client.dart';

// Existing workflow fixtures use Pro access so quota behavior is tested only
// by dedicated plan-limit cases, rather than an implicit mock API response.
Future<SubscriptionStatusResult> loadBioProSubscription() async =>
    SubscriptionStatusResult(
        userId: PostDeeAuthSessionStore.instance.session.stableUserId ?? 'bio-test-owner',
        plan: 'PRO',
        status: 'ACTIVE',
        maxProfileLinks: 20,
        canSchedule: true,
        canUseAiCaptions: true,
        canUseAnalytics: true);

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
  final scrollables = find.ancestor(of: finder, matching: find.byType(Scrollable));
  if (key.startsWith('link-in-bio-template-minimal-') &&
      scrollables.evaluate().isNotEmpty) {
    // Tall template cards can extend below a sticky footer even after
    // ensureVisible. Tap the part that is inside the actual scroll viewport.
    final visible = tester.getRect(finder).intersect(
        tester.getRect(scrollables.first));
    expect(visible.isEmpty, isFalse);
    await tester.tapAt(visible.center);
  } else {
    await tester.tap(finder);
  }
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
  } else if (key == 'link-in-bio-decorate') {
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

Future<void> selectBioTemplate(WidgetTester tester, String templateId) async {
  await showBioStep(tester, 'theme');
  await _tapVisibleBioKey(tester, 'link-in-bio-template-$templateId');
  expect(find.byKey(const ValueKey('link-in-bio-template-preview')),
      findsOneWidget);
  await _tapVisibleBioKey(tester, 'link-in-bio-template-use');
}
