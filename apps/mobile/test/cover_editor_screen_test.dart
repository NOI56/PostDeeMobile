import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postdee_mobile/features/platforms/social_platform.dart';
import 'package:postdee_mobile/features/uploader/cover_editor_screen.dart';
import 'package:postdee_mobile/features/uploader/cover_image_processor.dart';

Future<void> _dragUntilBuilt(WidgetTester tester, Finder finder) async {
  for (var attempt = 0;
      attempt < 8 && finder.evaluate().isEmpty;
      attempt += 1) {
    await tester.drag(find.byType(ListView), const Offset(0, -260));
    await tester.pumpAndSettle();
  }
  expect(finder, findsOneWidget);
}

void main() {
  testWidgets('selects a frame and Thai cover design then exports it',
      (tester) async {
    final root = Directory.systemTemp.createTempSync('postdee-cover-ui-');
    addTearDown(() {
      if (root.existsSync()) root.deleteSync(recursive: true);
    });
    final video = File('${root.path}${Platform.pathSeparator}clip.mp4')
      ..writeAsBytesSync(List<int>.filled(16, 1));
    final cover = File('${root.path}${Platform.pathSeparator}cover.png')
      ..writeAsBytesSync(const [137, 80, 78, 71]);
    CoverImageRequest? processedRequest;
    CoverEditorResult? savedResult;

    await tester.pumpWidget(
      MaterialApp(
        home: CoverEditorScreen(
          videoFile: video,
          videoName: 'clip.mp4',
          initialResult: CoverEditorResult(
            localImagePath: cover.path,
            sizeBytes: cover.lengthSync(),
            design: const CoverDesign(coverFrameTimeMs: 20000),
            durationMs: 20000,
          ),
          platforms: const [
            SocialPlatform.tiktok,
            SocialPlatform.youtubeShorts,
            SocialPlatform.instagramReels,
            SocialPlatform.facebookReels,
          ],
          probeDuration: (_) async => 20,
          processCover: (request) async {
            processedRequest = request;
            return CoverEditorResult(
              localImagePath: cover.path,
              sizeBytes: cover.lengthSync(),
              design: request.design,
              durationMs: request.durationMs,
            );
          },
          onSaved: (result) => savedResult = result,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('แต่งหน้าปก'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('cover-source-gallery')),
      findsNothing,
    );
    await _dragUntilBuilt(
      tester,
      find.byKey(const ValueKey('cover-frame-instruction')),
    );
    expect(
        find.byKey(const ValueKey('cover-frame-instruction')), findsOneWidget);
    expect(find.text('เลื่อนเลือกภาพจากคลิป'), findsOneWidget);
    await _dragUntilBuilt(
      tester,
      find.byKey(const ValueKey('cover-frame-slider')),
    );

    final slider = tester.widget<Slider>(
      find.byKey(const ValueKey('cover-frame-slider')),
    );
    expect(slider.max, 19900);
    expect(slider.value, 19900);
    slider.onChanged!(20000);
    await tester.pump();
    await _dragUntilBuilt(
      tester,
      find.byKey(const ValueKey('cover-text-field')),
    );
    await tester.enterText(
      find.byKey(const ValueKey('cover-text-field')),
      'สินค้าเด็ดวันนี้',
    );
    await tester.pump();
    final previewText = tester.widget<Text>(
      find.descendant(
        of: find.byKey(const ValueKey('cover-draggable-text')),
        matching: find.byType(Text, skipOffstage: false),
      ),
    );
    expect(previewText.maxLines, 4);
    expect(previewText.overflow, TextOverflow.ellipsis);
    await _dragUntilBuilt(
      tester,
      find.byKey(const ValueKey('cover-font-anuphan')),
    );
    tester
        .widget<ChoiceChip>(find.byKey(const ValueKey('cover-font-anuphan')))
        .onSelected!(true);
    await _dragUntilBuilt(
      tester,
      find.byKey(const ValueKey('cover-weight-700')),
    );
    tester
        .widget<ChoiceChip>(find.byKey(const ValueKey('cover-weight-700')))
        .onSelected!(true);
    await _dragUntilBuilt(
      tester,
      find.byKey(const ValueKey('cover-size-64')),
    );
    tester
        .widget<ChoiceChip>(find.byKey(const ValueKey('cover-size-64')))
        .onSelected!(true);
    await _dragUntilBuilt(
      tester,
      find.byKey(const ValueKey('cover-position-bottom')),
    );
    tester
        .widget<ChoiceChip>(find.byKey(const ValueKey('cover-position-bottom')))
        .onSelected!(true);
    await tester.pump();

    await _dragUntilBuilt(
      tester,
      find.byKey(const ValueKey('cover-platform-capability-notice')),
    );
    expect(find.byKey(const ValueKey('cover-platform-capability-notice')),
        findsOneWidget);
    expect(find.textContaining('TikTok: ใช้เฉพาะเฟรมที่เลือก'), findsOneWidget);
    expect(find.textContaining('YouTube Shorts: แต่งต่อในแอป YouTube'),
        findsOneWidget);

    await tester.ensureVisible(find.byKey(const ValueKey('cover-save-button')));
    await tester.tap(find.byKey(const ValueKey('cover-save-button')));
    await tester.pumpAndSettle();

    expect(processedRequest, isNotNull);
    expect(processedRequest!.design.coverFrameTimeMs, 19900);
    expect(processedRequest!.durationMs, 20000);
    expect(processedRequest!.sourceKind, CoverSourceKind.videoFrame);
    expect(processedRequest!.sourceImageFile, isNull);
    expect(processedRequest!.design.text, 'สินค้าเด็ดวันนี้');
    expect(processedRequest!.design.fontFamily, CoverFontFamily.anuphan);
    expect(processedRequest!.design.fontWeight, 700);
    expect(processedRequest!.design.fontSize, 64);
    expect(processedRequest!.design.dy, 0.78);
    expect(savedResult?.localImagePath, cover.path);
  });
}
