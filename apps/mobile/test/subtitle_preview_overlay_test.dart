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
      maxLines: 2,
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
}
