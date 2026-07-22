import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postdee_mobile/features/ai_editing/subtitle_studio/subtitle_draft_store.dart';
import 'package:postdee_mobile/features/ai_editing/subtitle_studio/subtitle_project.dart';
import 'package:postdee_mobile/features/ai_editing/subtitle_studio/subtitle_studio_screen.dart';

void main() {
  testWidgets('edits text immediately and returns the finished project',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final file = File(
      '${Directory.systemTemp.path}${Platform.pathSeparator}studio-screen.mp4',
    )..writeAsBytesSync([1]);
    addTearDown(() {
      if (file.existsSync()) file.deleteSync();
    });
    final store = _MemoryDraftStore();
    SubtitleProject? result;

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: ElevatedButton(
              onPressed: () async {
                result = await Navigator.of(context).push<SubtitleProject>(
                  MaterialPageRoute(
                    builder: (_) => SubtitleStudioScreen(
                      sourceFile: file,
                      initialProject: _project(),
                      draftStore: store,
                      videoPreviewBuilder: (_, __) =>
                          const ColoredBox(color: Colors.black),
                    ),
                  ),
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(
        find.byKey(const ValueKey('subtitle-studio-screen')), findsOneWidget);
    expect(find.text('สวัสดีค่ะ'), findsWidgets);

    await tester.enterText(
      find.byKey(const ValueKey('subtitle-cue-text-field')),
      'แก้แล้วเห็นทันที',
    );
    await tester.pump();
    expect(find.text('แก้แล้วเห็นทันที'), findsWidgets);

    final tabBarRect = tester.getRect(find.byType(TabBar));
    await tester.tapAt(Offset(tabBarRect.right - 70, tabBarRect.center.dy));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('subtitle-font-anuphan')));
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('subtitle-position-middle')),
      220,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(find.byKey(const ValueKey('subtitle-position-middle')));
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey('subtitle-finish')));
    await tester.pumpAndSettle();

    expect(result?.cues.single.text, 'แก้แล้วเห็นทันที');
    expect(result?.defaultStyle.fontId, 'Anuphan');
    expect(result?.defaultStyle.alignment, SubtitleAlignment.middle);
    expect(store.saved?.toJson(), result?.toJson());
  });
}

class _MemoryDraftStore implements SubtitleDraftStore {
  SubtitleProject? saved;

  @override
  Future<void> deleteDraft(String projectId) async => saved = null;

  @override
  Future<SubtitleProject?> loadDraft(String projectId) async => saved;

  @override
  Future<void> saveDraft(SubtitleProject project) async => saved = project;
}

SubtitleProject _project() => SubtitleProject(
      schemaVersion: 1,
      projectId: 'screen-project',
      sourceFingerprint: 'screen-source',
      sourceDurationMs: 5000,
      language: 'th',
      cues: [
        SubtitleCue(
          cueId: 'cue-1',
          sourceStartMs: 0,
          sourceEndMs: 2000,
          text: 'สวัสดีค่ะ',
          timingMode: SubtitleTimingMode.segment,
        ),
      ],
      defaultStyle: SubtitleStyle.defaults,
      cutRanges: const [],
      revision: 0,
      createdAt: DateTime.utc(2026, 7, 22),
      updatedAt: DateTime.utc(2026, 7, 22),
    );
