import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postdee_mobile/features/ai/ai_tools_screen.dart';

void main() {
  testWidgets('does not expose legacy clip review UI', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: AiToolsScreen(),
        ),
      ),
    );

    expect(find.byKey(const ValueKey('ai-tools-real-clip-caption')),
        findsOneWidget);
    expect(find.text('รีวิวคลิปด้วย AI'), findsNothing);
    expect(find.text('รีวิวคลิป'), findsNothing);
  });
}
