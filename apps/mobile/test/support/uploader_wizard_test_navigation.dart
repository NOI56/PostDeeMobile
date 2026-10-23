import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _uploaderStepKeys = [
  'uploader-step-video',
  'uploader-step-caption',
  'uploader-step-platforms',
  'uploader-step-review',
];

/// The composer list, independent of its scrollable header or open sheets.
Finder get uploaderMainScroll => find
    .descendant(
      of: find.byKey(const ValueKey('uploader-scroll')),
      matching: find.byType(Scrollable),
    )
    .first;

Finder get uploaderHeaderScroll => find
    .descendant(
      of: find.byKey(const ValueKey('uploader-header-scroll')),
      matching: find.byType(Scrollable),
    )
    .first;

/// Navigate through the same progress controls available to the seller.
/// This prepares a section only; it never confirms or submits a post.
Future<void> goToUploaderStep(WidgetTester tester, int index) async {
  final progress = find.byKey(ValueKey('uploader-progress-$index'));
  expect(progress, findsOneWidget);
  // enterText schedules caret visibility for the next frame. Flush it and
  // dismiss focus before scrolling the progress control, so that deferred
  // keyboard/caret scrolling cannot move a different step under the tap.
  await tester.pump();
  FocusManager.instance.primaryFocus?.unfocus();
  await tester.pump();
  await tester.ensureVisible(progress);
  await tester.pump();
  await tester.tap(progress);
  // Allow the finite step entrance to finish without waiting on unrelated AI
  // spinners whose asynchronous result may be deliberately gated by the test.
  await tester.pump(const Duration(milliseconds: 250));
  await tester.pump();
  expect(find.byKey(ValueKey(_uploaderStepKeys[index])), findsOneWidget);
  for (var other = 0; other < _uploaderStepKeys.length; other += 1) {
    if (other == index) continue;
    expect(find.byKey(ValueKey(_uploaderStepKeys[other])), findsNothing);
  }
}
