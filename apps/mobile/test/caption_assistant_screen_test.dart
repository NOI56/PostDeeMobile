import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postdee_mobile/core/network/postdee_api_client.dart';
import 'package:postdee_mobile/features/captions/caption_assistant_screen.dart';

void main() {
  testWidgets('points the legacy caption assistant to the upload clip flow',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: CaptionAssistantScreen(),
        ),
      ),
    );

    expect(find.byKey(const ValueKey('caption-assistant-real-clip-message')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('caption-assistant-starter-mode')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('caption-assistant-pro-mode')),
        findsOneWidget);
    expect(find.byType(TextField), findsNothing);
    expect(find.text('สร้างแคปชั่น'), findsNothing);
    expect(find.text('หัวข้อ / คีย์เวิร์ด'), findsNothing);
  });

  testWidgets('does not call the prompt-only caption generator',
      (tester) async {
    var didGenerate = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CaptionAssistantScreen(
            generateCaption: (_) async {
              didGenerate = true;

              return const CaptionResult(
                caption: 'Should not generate',
                hashtags: [],
              );
            },
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(didGenerate, isFalse);
    expect(find.byType(TextButton), findsNothing);
    expect(find.byType(TextField), findsNothing);
  });
}
