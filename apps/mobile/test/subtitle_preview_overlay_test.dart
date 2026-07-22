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
    expect(tester.getTopLeft(find.byType(SubtitlePreviewOverlay)).dy,
        lessThan(100));
  });
}
