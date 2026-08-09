import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postdee_mobile/features/ai_editing/subtitle_burn_video_processor.dart';
import 'package:postdee_mobile/features/ai_editing/subtitle_studio/subtitle_preview_overlay.dart';
import 'package:postdee_mobile/features/ai_editing/subtitle_studio/subtitle_project.dart';
import 'package:postdee_mobile/features/ai_editing/subtitle_studio/subtitle_studio_controller.dart';

void main() {
  testWidgets('places subtitle by normalized center coordinates',
      (tester) async {
    final style = copySubtitleStyle(
      SubtitleStyle.defaults,
      normalizedX: 0.25,
      normalizedY: 0.40,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 360,
            height: 640,
            child: SubtitlePreviewOverlay(
              text: 'ซับ',
              style: style,
            ),
          ),
        ),
      ),
    );

    final overlayRect = tester.getRect(find.byType(SubtitlePreviewOverlay));
    final subtitleCenter = tester.getCenter(
      find.byKey(const ValueKey('subtitle-preview-positioned-content')),
    );
    expect(
      subtitleCenter.dx,
      closeTo(overlayRect.left + overlayRect.width * 0.25, 1),
    );
    expect(
      subtitleCenter.dy,
      closeTo(overlayRect.top + overlayRect.height * 0.40, 1),
    );
  });

  testWidgets('dragging emits safe normalized coordinates', (tester) async {
    Offset? changed;
    final style = copySubtitleStyle(
      SubtitleStyle.defaults,
      normalizedX: 0.5,
      normalizedY: 0.5,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 360,
            height: 640,
            child: SubtitlePreviewOverlay(
              text: 'ซับ',
              style: style,
              onPositionChanged: (position) => changed = position,
            ),
          ),
        ),
      ),
    );
    final overlayRect = tester.getRect(find.byType(SubtitlePreviewOverlay));

    await tester.drag(
      find.byKey(const ValueKey('subtitle-preview-draggable')),
      const Offset(72, -128),
    );
    await tester.pump();

    expect(changed, isNotNull);
    expect(changed!.dx, closeTo(0.5 + 72 / overlayRect.width, 0.02));
    expect(changed!.dy, closeTo(0.5 - 128 / overlayRect.height, 0.02));
    expect(changed!.dx, inInclusiveRange(0, 1));
    expect(changed!.dy, inInclusiveRange(0, 1));
  });

  testWidgets(
      'longer project text and preview use one effective layout near an edge',
      (tester) async {
    final style = copySubtitleStyle(
      SubtitleStyle.defaults,
      fontSize: 30,
      outlineWidth: 2,
      shadowDepth: 2,
      normalizedX: 0.08,
      normalizedY: 0.01,
    );
    const texts = <String>[
      'สั้น',
      'ข้อความจริงที่ยาวกว่าข้อความตัวอย่างมาก',
    ];
    final layout = resolveSubtitleCanvasLayout(
      texts: texts,
      style: style,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 304,
            height: 540,
            child: SubtitlePreviewOverlay(
              text: texts.first,
              layoutTexts: texts,
              style: style,
            ),
          ),
        ),
      ),
    );

    final overlayRect = tester.getRect(find.byType(SubtitlePreviewOverlay));
    final subtitleCenter = tester.getCenter(
      find.byKey(const ValueKey('subtitle-preview-positioned-content')),
    );
    expect(layout.normalizedPosition.dx, greaterThan(style.normalizedX));
    expect(layout.normalizedPosition.dy, greaterThan(style.normalizedY));
    expect(
      subtitleCenter.dx,
      closeTo(
        overlayRect.left + overlayRect.width * layout.normalizedPosition.dx,
        1,
      ),
    );
    expect(
      subtitleCenter.dy,
      closeTo(
        overlayRect.top + overlayRect.height * layout.normalizedPosition.dy,
        1,
      ),
    );
    expect(
      tester
          .widgetList<Text>(find.text(texts.first))
          .every((text) => text.style?.fontSize == layout.fontSize),
      isTrue,
    );
  });

  testWidgets(
      'landscape preview resolves the same aspect-aware canvas used by ASS',
      (tester) async {
    final style = copySubtitleStyle(
      SubtitleStyle.defaults,
      fontSize: 30,
      normalizedX: 0.05,
      normalizedY: 0.50,
    );
    const texts = <String>['ข้อความยาวใกล้ขอบของคลิปแนวนอน'];
    final canvasSize = subtitleAssCanvasSizeForDisplay(
      const Size(320, 180),
    );
    final layout = resolveSubtitleCanvasLayout(
      texts: texts,
      style: style,
      canvasSize: canvasSize,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 320,
            height: 180,
            child: SubtitlePreviewOverlay(
              text: texts.single,
              layoutTexts: texts,
              style: style,
            ),
          ),
        ),
      ),
    );

    final overlayRect = tester.getRect(find.byType(SubtitlePreviewOverlay));
    final subtitleCenter = tester.getCenter(
      find.byKey(const ValueKey('subtitle-preview-positioned-content')),
    );
    expect(canvasSize, const Size(960, 540));
    expect(
      subtitleCenter.dx,
      closeTo(
        overlayRect.left + overlayRect.width * layout.normalizedPosition.dx,
        1,
      ),
    );
    expect(
      subtitleCenter.dy,
      closeTo(
        overlayRect.top + overlayRect.height * layout.normalizedPosition.dy,
        1,
      ),
    );
  });

  testWidgets('video subtitle preview ignores the system text scale',
      (tester) async {
    const text = 'ขนาดในวิดีโอต้องคงเดิม';

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: const TextScaler.linear(2),
            ),
            child: const Scaffold(
              body: SizedBox(
                width: 304,
                height: 540,
                child: SubtitlePreviewOverlay(
                  text: text,
                  style: SubtitleStyle.defaults,
                ),
              ),
            ),
          ),
        ),
      ),
    );

    final renderedTexts = tester.widgetList<Text>(find.text(text)).toList();
    expect(renderedTexts, hasLength(2));
    expect(
      renderedTexts
          .every((rendered) => rendered.textScaler == TextScaler.noScaling),
      isTrue,
    );
  });

  testWidgets('shows draft text immediately with the selected subtitle style',
      (tester) async {
    final style = copySubtitleStyle(
      SubtitleStyle.defaults,
      fontId: 'Anuphan',
      fontSize: 30,
      textColor: '#00FF00',
      alignment: SubtitleAlignment.top,
      normalizedY: 0.12,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 360,
            height: 640,
            child: SubtitlePreviewOverlay(
              text: 'แก้แล้วเห็นทันที',
              style: style,
            ),
          ),
        ),
      ),
    );

    expect(find.text('แก้แล้วเห็นทันที'), findsNWidgets(2));
    final fills = tester.widgetList<Text>(find.text('แก้แล้วเห็นทันที'));
    expect(fills.any((text) => text.style?.fontFamily == 'Anuphan'), isTrue);
    expect(fills.any((text) => text.style?.color == const Color(0xFF00FF00)),
        isTrue);
    final safeAreaPadding = tester.widget<Padding>(
      find.descendant(
        of: find.byType(SubtitlePreviewOverlay),
        matching: find.byType(Padding),
      ),
    );
    final previewSize = tester.getSize(find.byType(SubtitlePreviewOverlay));
    final padding = safeAreaPadding.padding as EdgeInsets;
    expect(padding.left, closeTo(24 * previewSize.width / 304, 0.0001));
    expect(padding.right, closeTo(padding.left, 0.0001));
    expect(padding.top, closeTo(28 * previewSize.height / 540, 0.0001));
    expect(padding.bottom, closeTo(padding.top, 0.0001));
    expect(tester.getTopLeft(find.byType(SubtitlePreviewOverlay)).dy,
        lessThan(100));
  });

  testWidgets('shrinks a long Thai cue instead of hiding it with an ellipsis',
      (tester) async {
    final style = copySubtitleStyle(
      SubtitleStyle.defaults,
      fontSize: 30,
      maxLines: 1,
    );
    const text = 'จนกระทั่งแทบจะไม่มีที่เดินสำหรับคน';

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 220,
            height: 360,
            child: SubtitlePreviewOverlay(text: text, style: style),
          ),
        ),
      ),
    );
    await tester.pump();

    final subtitles = tester.widgetList<Text>(find.text(text)).toList();
    expect(subtitles, hasLength(2));
    expect(
      subtitles.every((subtitle) => subtitle.overflow != TextOverflow.ellipsis),
      isTrue,
    );
    expect(
      subtitles.every((subtitle) => (subtitle.style?.fontSize ?? 30) < 30),
      isTrue,
    );
  });

  testWidgets('scales ASS typography and margins to the preview canvas',
      (tester) async {
    final style = copySubtitleStyle(
      SubtitleStyle.defaults,
      fontSize: 18,
      outlineWidth: 2,
      shadowDepth: 2,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 152,
            height: 270,
            child: SubtitlePreviewOverlay(text: 'สเกลตรงกัน', style: style),
          ),
        ),
      ),
    );

    final renderedTexts = tester.widgetList<Text>(find.text('สเกลตรงกัน'));
    expect(renderedTexts, hasLength(2));
    expect(
      renderedTexts.every((text) => text.style?.fontSize == 9),
      isTrue,
    );
    final outlineText = renderedTexts.singleWhere(
      (text) => text.style?.foreground != null,
    );
    expect(outlineText.style?.foreground?.strokeWidth, 2);
    final safeAreaPadding = tester.widget<Padding>(
      find.descendant(
        of: find.byType(SubtitlePreviewOverlay),
        matching: find.byType(Padding),
      ),
    );
    expect(
      safeAreaPadding.padding,
      const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
    );
  });

  testWidgets('can shrink the live preview to the scaled safety floor',
      (tester) async {
    final style = copySubtitleStyle(
      SubtitleStyle.defaults,
      fontSize: 30,
    );
    final text = List.filled(12, 'ข้อความยาวมาก').join();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 110,
            height: 360,
            child: SubtitlePreviewOverlay(text: text, style: style),
          ),
        ),
      ),
    );

    final subtitles = tester.widgetList<Text>(find.text(text)).toList();
    expect(subtitles, hasLength(2));
    expect(
      subtitles.every((subtitle) => subtitle.style?.fontSize == 4),
      isTrue,
    );
  });

  testWidgets(
      'highlights only the timed word while keeping the preview on one line',
      (tester) async {
    final style = copySubtitleStyle(
      SubtitleStyle.defaults,
      textColor: '#FFFFFF',
      activeWordColor: '#FF0055',
      outlineWidth: 0,
    );
    const words = [
      SubtitleWord(
        wordId: 'word-1',
        text: 'one',
        sourceStartMs: 100,
        sourceEndMs: 300,
        separatorAfter: ' ',
      ),
      SubtitleWord(
        wordId: 'word-2',
        text: 'two',
        sourceStartMs: 300,
        sourceEndMs: 700,
        separatorAfter: ' ',
      ),
      SubtitleWord(
        wordId: 'word-3',
        text: 'three',
        sourceStartMs: 700,
        sourceEndMs: 900,
      ),
    ];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 360,
            height: 640,
            child: SubtitlePreviewOverlay(
              text: 'one two three',
              style: style,
              currentPlaybackTimeMs: 300,
              words: words,
            ),
          ),
        ),
      ),
    );

    final richText = tester.widget<RichText>(
      find.byKey(const ValueKey('subtitle-preview-active-words')),
    );
    final rootSpan = richText.text as TextSpan;
    final wordSpans = rootSpan.children!
        .whereType<TextSpan>()
        .where((span) => const {'one', 'two', 'three'}.contains(span.text))
        .toList(growable: false);

    expect(richText.maxLines, 1);
    expect(richText.overflow, TextOverflow.clip);
    expect(wordSpans, hasLength(3));
    expect(
      wordSpans.singleWhere((span) => span.text == 'two').style?.color,
      const Color(0xFFFF0055),
    );
    expect(
      wordSpans.singleWhere((span) => span.text == 'one').style?.color,
      isNot(const Color(0xFFFF0055)),
    );
    expect(
      wordSpans.singleWhere((span) => span.text == 'three').style?.color,
      isNot(const Color(0xFFFF0055)),
    );
  });

  testWidgets('falls back to the original sentence when word timing is unsafe',
      (tester) async {
    const text = 'one two';
    const words = [
      SubtitleWord(
        wordId: 'word-1',
        text: 'one',
        sourceStartMs: 100,
        sourceEndMs: 500,
        separatorAfter: ' ',
      ),
      SubtitleWord(
        wordId: 'word-2',
        text: 'two',
        sourceStartMs: 400,
        sourceEndMs: 800,
      ),
    ];

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 360,
            height: 640,
            child: SubtitlePreviewOverlay(
              text: text,
              style: SubtitleStyle.defaults,
              currentPlaybackTimeMs: 450,
              words: words,
            ),
          ),
        ),
      ),
    );

    expect(
      find.byKey(const ValueKey('subtitle-preview-active-words')),
      findsNothing,
    );
    expect(find.text(text), findsNWidgets(2));
  });

  testWidgets('keeps a highlighted Thai word intact for mark-safe fonts',
      (tester) async {
    final style = copySubtitleStyle(
      SubtitleStyle.defaults,
      fontId: 'Bai Jamjuree',
    );
    const markedWord = 'ที่';
    const words = [
      SubtitleWord(
        wordId: 'word-1',
        text: 'ไป',
        sourceStartMs: 0,
        sourceEndMs: 300,
        separatorAfter: ' ',
      ),
      SubtitleWord(
        wordId: 'word-2',
        text: markedWord,
        sourceStartMs: 300,
        sourceEndMs: 600,
        separatorAfter: ' ',
      ),
      SubtitleWord(
        wordId: 'word-3',
        text: 'บ้าน',
        sourceStartMs: 600,
        sourceEndMs: 900,
      ),
    ];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 360,
            height: 640,
            child: SubtitlePreviewOverlay(
              text: 'ไป ที่ บ้าน',
              style: style,
              currentPlaybackTimeMs: 450,
              words: words,
            ),
          ),
        ),
      ),
    );

    final richText = tester.widget<RichText>(
      find.byKey(const ValueKey('subtitle-preview-active-words')),
    );
    final rootSpan = richText.text as TextSpan;
    final activeSpan = rootSpan.children!
        .whereType<TextSpan>()
        .singleWhere((span) => span.text == markedWord);

    expect(activeSpan.text, markedWord);
    expect(
      activeSpan.style?.color,
      subtitleColor(style.activeWordColor),
    );
    expect(rootSpan.style?.fontFamily, 'Bai Jamjuree');
  });

  testWidgets('uses the 78 to 103 to 100 pop keyframes within 220ms',
      (tester) async {
    final style = copySubtitleStyle(
      SubtitleStyle.defaults,
      animation: 'pop',
      outlineWidth: 0,
    );

    Future<double> scaleAt(int currentPlaybackTimeMs) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 360,
              height: 640,
              child: SubtitlePreviewOverlay(
                text: 'เด้งตามเสียง',
                style: style,
                currentPlaybackTimeMs: currentPlaybackTimeMs,
                cueStartMs: 1000,
                cueEndMs: 3000,
              ),
            ),
          ),
        ),
      );
      return tester
          .widget<Transform>(
            find.byKey(const ValueKey('subtitle-preview-effect-pop')),
          )
          .transform
          .storage[0];
    }

    expect(await scaleAt(1000), closeTo(0.78, 0.0001));
    expect(await scaleAt(1120), closeTo(1.03, 0.0001));
    expect(await scaleAt(1220), closeTo(1, 0.0001));
  });

  test('reserves the pop peak while keeping other effect widths unchanged', () {
    expect(
      subtitleSafeWidthForEffect(maxWidth: 103, animation: 'pop'),
      closeTo(100, 0.0001),
    );
    expect(
      subtitleSafeWidthForEffect(maxWidth: 103, animation: 'fade'),
      103,
    );
  });

  testWidgets('fades at both cue edges and stays opaque in the middle',
      (tester) async {
    final style = copySubtitleStyle(
      SubtitleStyle.defaults,
      animation: 'fade',
      outlineWidth: 0,
    );

    Future<double> opacityAt(int currentPlaybackTimeMs) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 360,
              height: 640,
              child: SubtitlePreviewOverlay(
                text: 'ค่อย ๆ ปรากฏ',
                style: style,
                currentPlaybackTimeMs: currentPlaybackTimeMs,
                cueStartMs: 1000,
                cueEndMs: 3000,
              ),
            ),
          ),
        ),
      );
      return tester
          .widget<Opacity>(
            find.byKey(const ValueKey('subtitle-preview-effect-fade')),
          )
          .opacity;
    }

    final entering = await opacityAt(1050);
    final middle = await opacityAt(2000);
    final leaving = await opacityAt(2950);

    expect(entering, lessThan(middle));
    expect(middle, 1);
    expect(leaving, lessThan(middle));
  });

  testWidgets('unknown effects safely keep the original preview',
      (tester) async {
    final style = copySubtitleStyle(
      SubtitleStyle.defaults,
      animation: 'future-effect',
      outlineWidth: 0,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 360,
            height: 640,
            child: SubtitlePreviewOverlay(
              text: 'แสดงตามเดิม',
              style: style,
              currentPlaybackTimeMs: 1200,
              cueStartMs: 1000,
              cueEndMs: 3000,
            ),
          ),
        ),
      ),
    );

    expect(find.text('แสดงตามเดิม'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('subtitle-preview-effect-pop')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('subtitle-preview-effect-fade')),
      findsNothing,
    );
  });
}
