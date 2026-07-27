import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postdee_mobile/features/ai_editing/subtitle_studio/subtitle_preview_overlay.dart';
import 'package:postdee_mobile/features/ai_editing/subtitle_studio/subtitle_project.dart';
import 'package:postdee_mobile/features/ai_editing/subtitle_studio/subtitle_studio_controller.dart';

void main() {
  testWidgets('shows draft text immediately with the selected subtitle style',
      (tester) async {
    final style = copySubtitleStyle(
      SubtitleStyle.defaults,
      fontId: 'Anuphan',
      fontSize: 30,
      textColor: '#00FF00',
      alignment: SubtitleAlignment.top,
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
    expect(
      safeAreaPadding.padding,
      const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
    );
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

  testWidgets('can shrink the live preview down to the six-pixel safety floor',
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
      subtitles.every((subtitle) => subtitle.style?.fontSize == 6),
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
