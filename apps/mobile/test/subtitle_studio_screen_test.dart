import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postdee_mobile/features/ai_editing/subtitle_studio/subtitle_draft_store.dart';
import 'package:postdee_mobile/features/ai_editing/subtitle_studio/subtitle_preview_overlay.dart';
import 'package:postdee_mobile/features/ai_editing/subtitle_studio/subtitle_project.dart';
import 'package:postdee_mobile/features/ai_editing/subtitle_studio/subtitle_studio_screen.dart';

void main() {
  test('verified portrait dimensions win over a conflicting player size', () {
    expect(
      subtitleStudioPreviewDisplaySize(
        verifiedDisplaySizeHint: const Size(1080, 1920),
        playerDisplaySize: const Size(1920, 1080),
      ),
      const Size(1080, 1920),
    );
  });

  testWidgets('uses the display-oriented video aspect instead of fixed 9:16',
      (tester) async {
    final file = File(
      '${Directory.systemTemp.path}${Platform.pathSeparator}'
      'studio-landscape-preview.mp4',
    )..writeAsBytesSync([1]);
    addTearDown(() {
      if (file.existsSync()) file.deleteSync();
    });

    await tester.pumpWidget(
      MaterialApp(
        home: SubtitleStudioScreen(
          sourceFile: file,
          initialProject: _project(),
          draftStore: _MemoryDraftStore(),
          previewDisplaySizeHint: const Size(1920, 1080),
          videoPreviewBuilder: (_, __) => const ColoredBox(color: Colors.black),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final aspect = tester.widget<AspectRatio>(
      find.byKey(const ValueKey('subtitle-studio-preview-aspect')),
    );
    expect(aspect.aspectRatio, closeTo(16 / 9, 0.0001));
  });

  testWidgets('adapts the studio to landscape with 200 percent text',
      (tester) async {
    tester.view.physicalSize = const Size(844, 390);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final file = File(
      '${Directory.systemTemp.path}${Platform.pathSeparator}'
      'studio-large-text-landscape.mp4',
    )..writeAsBytesSync([1]);
    addTearDown(() {
      if (file.existsSync()) file.deleteSync();
    });

    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: MediaQueryData.fromView(tester.view).copyWith(
            textScaler: const TextScaler.linear(2),
          ),
          child: SubtitleStudioScreen(
            sourceFile: file,
            initialProject: _project(),
            draftStore: _FailingDraftStore(),
            previewDisplaySizeHint: const Size(1080, 1920),
            videoPreviewBuilder: (_, __) =>
                const ColoredBox(color: Colors.black),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(
      find.byKey(const ValueKey('subtitle-studio-responsive-body')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('subtitle-finish')), findsOneWidget);
    expect(find.byKey(const ValueKey('subtitle-text-tab')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('subtitle-validation-banner')),
      findsOneWidget,
    );
    expect(
      tester
          .widget<Text>(find.text(
            'เปิดฉบับร่างเดิมไม่สำเร็จ เริ่มจากซับที่ AI สร้างให้แทน',
          ))
          .maxLines,
      isNull,
    );
  });

  testWidgets('keeps the full preview height on a tall large-text phone',
      (tester) async {
    tester.view.physicalSize = const Size(393, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final file = File(
      '${Directory.systemTemp.path}${Platform.pathSeparator}'
      'studio-large-text-portrait.mp4',
    )..writeAsBytesSync([1]);
    addTearDown(() {
      if (file.existsSync()) file.deleteSync();
    });

    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: MediaQueryData.fromView(tester.view).copyWith(
            textScaler: const TextScaler.linear(2),
          ),
          child: SubtitleStudioScreen(
            sourceFile: file,
            initialProject: _project(),
            draftStore: _MemoryDraftStore(),
            previewDisplaySizeHint: const Size(1080, 1920),
            videoPreviewBuilder: (_, __) =>
                const ColoredBox(color: Colors.black),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(
      find.byKey(const ValueKey('subtitle-preview-controls-scroll')),
      findsNothing,
    );
  });

  testWidgets('disables leaving while the saved draft is still loading',
      (tester) async {
    final loadDraft = Completer<SubtitleProject?>();
    final store = _ControlledDraftStore(loadResult: loadDraft.future);
    final file = File(
      '${Directory.systemTemp.path}${Platform.pathSeparator}'
      'studio-delayed-load.mp4',
    )..writeAsBytesSync([1]);
    addTearDown(() {
      if (file.existsSync()) file.deleteSync();
    });

    await tester.pumpWidget(
      MaterialApp(
        home: SubtitleStudioScreen(
          sourceFile: file,
          initialProject: _project(),
          draftStore: store,
          videoPreviewBuilder: (_, __) => const ColoredBox(color: Colors.black),
        ),
      ),
    );
    await tester.pump();

    expect(
      tester
          .widget<IconButton>(
            find.ancestor(
              of: find.byIcon(Icons.arrow_back_rounded),
              matching: find.byType(IconButton),
            ),
          )
          .onPressed,
      isNull,
    );
    expect(
      tester
          .widget<ElevatedButton>(
            find.byKey(const ValueKey('subtitle-finish')),
          )
          .onPressed,
      isNull,
    );

    loadDraft.complete(null);
    await tester.pumpAndSettle();

    expect(
      tester
          .widget<IconButton>(
            find.ancestor(
              of: find.byIcon(Icons.arrow_back_rounded),
              matching: find.byType(IconButton),
            ),
          )
          .onPressed,
      isNotNull,
    );
    expect(
      tester
          .widget<ElevatedButton>(
            find.byKey(const ValueKey('subtitle-finish')),
          )
          .onPressed,
      isNotNull,
    );
  });

  testWidgets('double finish starts only one save and one navigation',
      (tester) async {
    final pendingSave = Completer<void>();
    final store = _ControlledDraftStore(
      loadResult: Future.value(null),
      pendingSave: pendingSave,
    );
    final file = File(
      '${Directory.systemTemp.path}${Platform.pathSeparator}'
      'studio-double-finish.mp4',
    )..writeAsBytesSync([1]);
    addTearDown(() {
      if (file.existsSync()) file.deleteSync();
    });
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
              child: const Text('open delayed studio'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open delayed studio'));
    await tester.pumpAndSettle();

    final finish = find.byKey(const ValueKey('subtitle-finish'));
    await tester.tap(finish);
    await tester.tap(finish);
    await tester.pump();

    expect(store.saveCalls, 1);
    expect(find.text('กำลังบันทึก...'), findsOneWidget);
    expect(tester.widget<ElevatedButton>(finish).onPressed, isNull);
    expect(
      tester
          .widget<IconButton>(
            find.ancestor(
              of: find.byIcon(Icons.arrow_back_rounded),
              matching: find.byType(IconButton),
            ),
          )
          .onPressed,
      isNull,
    );

    pendingSave.complete();
    await tester.pumpAndSettle();

    expect(result, isNotNull);
    expect(store.saveCalls, 1);
    expect(find.text('open delayed studio'), findsOneWidget);
  });

  testWidgets('keeps the studio open when saving a draft fails',
      (tester) async {
    final file = File(
      '${Directory.systemTemp.path}${Platform.pathSeparator}'
      'studio-save-failure.mp4',
    )..writeAsBytesSync([1]);
    addTearDown(() {
      if (file.existsSync()) file.deleteSync();
    });

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: ElevatedButton(
              onPressed: () => Navigator.of(context).push<void>(
                MaterialPageRoute(
                  builder: (_) => SubtitleStudioScreen(
                    sourceFile: file,
                    initialProject: _project(),
                    draftStore: _SaveFailingDraftStore(),
                    videoPreviewBuilder: (_, __) =>
                        const ColoredBox(color: Colors.black),
                  ),
                ),
              ),
              child: const Text('open failing studio'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open failing studio'));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.arrow_back_rounded));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('subtitle-studio-screen')),
      findsOneWidget,
    );
    expect(find.text('บันทึกฉบับร่างไม่ได้'), findsOneWidget);
    expect(find.text('ลองบันทึกอีกครั้ง'), findsOneWidget);
    expect(find.text('ออกโดยไม่บันทึก'), findsOneWidget);

    await tester.tap(find.text('ออกโดยไม่บันทึก'));
    await tester.pumpAndSettle();
    expect(find.text('open failing studio'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('subtitle-studio-screen')),
      findsNothing,
    );
  });

  test('stops only an explicit cue replay at its end', () {
    expect(
      shouldStopSubtitleCueReplay(
        replayEndMs: null,
        isPlaying: true,
        sourcePositionMs: 2500,
      ),
      isFalse,
    );
    expect(
      shouldStopSubtitleCueReplay(
        replayEndMs: 2000,
        isPlaying: true,
        sourcePositionMs: 1999,
      ),
      isFalse,
    );
    expect(
      shouldStopSubtitleCueReplay(
        replayEndMs: 2000,
        isPlaying: true,
        sourcePositionMs: 2000,
      ),
      isTrue,
    );
  });

  testWidgets('edits text and allows Prompt to override the Anuphan default',
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
    expect(
      find.byKey(const ValueKey('subtitle-font-bai-jamjuree')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('subtitle-style-section-typeface')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('subtitle-style-section-colors')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('subtitle-style-section-effects')),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey('subtitle-font-prompt')));
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('subtitle-position-middle')),
      220,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(find.byKey(const ValueKey('subtitle-position-middle')));
    await tester.tap(
      find.byKey(const ValueKey('subtitle-style-section-colors')),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('subtitle-color-active-ff6b6b')),
    );
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('subtitle-color-shadow-052e21')),
      180,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(
      find.byKey(const ValueKey('subtitle-color-shadow-052e21')),
    );
    await tester.tap(
      find.byKey(const ValueKey('subtitle-style-section-effects')),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('subtitle-effect-none')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('subtitle-effect-pop')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('subtitle-effect-fade')),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey('subtitle-effect-fade')));
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey('subtitle-finish')));
    await tester.pumpAndSettle();

    expect(result?.cues.single.text, 'แก้แล้วเห็นทันที');
    expect(result?.defaultStyle.fontId, 'Prompt');
    expect(result?.defaultStyle.alignment, SubtitleAlignment.middle);
    expect(result?.defaultStyle.activeWordColor, '#FF6B6B');
    expect(result?.defaultStyle.shadowColor, '#052E21');
    expect(result?.defaultStyle.animation, 'fade');
    expect(store.saved?.toJson(), result?.toJson());
  });

  testWidgets('passes word timing into the live subtitle preview',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final file = File(
      '${Directory.systemTemp.path}${Platform.pathSeparator}'
      'studio-word-preview.mp4',
    )..writeAsBytesSync([1]);
    addTearDown(() {
      if (file.existsSync()) file.deleteSync();
    });

    await tester.pumpWidget(
      MaterialApp(
        home: SubtitleStudioScreen(
          sourceFile: file,
          initialProject: _wordTimedProject(),
          draftStore: _MemoryDraftStore(),
          videoPreviewBuilder: (_, __) => const ColoredBox(color: Colors.black),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('subtitle-preview-active-words')),
      findsOneWidget,
    );
  });

  testWidgets(
      'dragging the preview updates position with undo redo and autosave',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final file = File(
      '${Directory.systemTemp.path}${Platform.pathSeparator}'
      'studio-position-drag.mp4',
    )..writeAsBytesSync([1]);
    addTearDown(() {
      if (file.existsSync()) file.deleteSync();
    });
    final store = _MemoryDraftStore();
    SubtitleProject? result;
    final project = _project();
    final shortProject = project.copyWith(
      cues: [project.cues.single.copyWith(text: 'ดี')],
    );

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
                      initialProject: shortProject,
                      draftStore: store,
                      videoPreviewBuilder: (_, __) =>
                          const ColoredBox(color: Colors.black),
                    ),
                  ),
                );
              },
              child: const Text('open drag studio'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open drag studio'));
    await tester.pumpAndSettle();
    final draggable = find.byKey(const ValueKey('subtitle-preview-draggable'));
    final positioned =
        find.byKey(const ValueKey('subtitle-preview-positioned-content'));
    expect(draggable, findsOneWidget);
    final initialCenter = tester.getCenter(positioned);

    final overlay = tester.widget<SubtitlePreviewOverlay>(
      find.byType(SubtitlePreviewOverlay),
    );
    expect(overlay.onPositionChanged, isNotNull);
    overlay.onPositionChanged!(const Offset(0.35, 0.60));
    await tester.pump();
    final draggedCenter = tester.getCenter(positioned);
    expect(draggedCenter.dx, lessThan(initialCenter.dx));
    expect(draggedCenter.dy, lessThan(initialCenter.dy));

    await tester.pump(const Duration(milliseconds: 600));
    final savedAfterDrag = store.saved!.defaultStyle;
    expect(savedAfterDrag.normalizedX, 0.35);
    expect(savedAfterDrag.normalizedY, 0.60);

    await tester.tap(find.byKey(const ValueKey('subtitle-undo')));
    await tester.pump();
    expect(
      tester.getCenter(positioned),
      within(distance: 0.01, from: initialCenter),
    );

    await tester.tap(find.byKey(const ValueKey('subtitle-redo')));
    await tester.pump();
    expect(
      tester.getCenter(positioned),
      within(distance: 0.01, from: draggedCenter),
    );

    await tester.tap(find.byKey(const ValueKey('subtitle-finish')));
    await tester.pumpAndSettle();
    expect(result?.defaultStyle.normalizedX, savedAfterDrag.normalizedX);
    expect(result?.defaultStyle.normalizedY, savedAfterDrag.normalizedY);
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

class _FailingDraftStore implements SubtitleDraftStore {
  @override
  Future<void> deleteDraft(String projectId) async {}

  @override
  Future<SubtitleProject?> loadDraft(String projectId) async {
    throw const FileSystemException('draft unavailable');
  }

  @override
  Future<void> saveDraft(SubtitleProject project) async {}
}

class _ControlledDraftStore implements SubtitleDraftStore {
  _ControlledDraftStore({required this.loadResult, this.pendingSave});

  final Future<SubtitleProject?> loadResult;
  final Completer<void>? pendingSave;
  int saveCalls = 0;

  @override
  Future<void> deleteDraft(String projectId) async {}

  @override
  Future<SubtitleProject?> loadDraft(String projectId) => loadResult;

  @override
  Future<void> saveDraft(SubtitleProject project) async {
    saveCalls += 1;
    await pendingSave?.future;
  }
}

class _SaveFailingDraftStore implements SubtitleDraftStore {
  @override
  Future<void> deleteDraft(String projectId) async {}

  @override
  Future<SubtitleProject?> loadDraft(String projectId) async => null;

  @override
  Future<void> saveDraft(SubtitleProject project) async {
    throw StateError('draft storage unavailable');
  }
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

SubtitleProject _wordTimedProject() => SubtitleProject(
      schemaVersion: 1,
      projectId: 'word-preview-project',
      sourceFingerprint: 'word-preview-source',
      sourceDurationMs: 5000,
      language: 'en',
      cues: [
        SubtitleCue(
          cueId: 'cue-word-1',
          sourceStartMs: 0,
          sourceEndMs: 2000,
          text: 'one two',
          words: const [
            SubtitleWord(
              wordId: 'word-1',
              text: 'one',
              sourceStartMs: 0,
              sourceEndMs: 900,
              separatorAfter: ' ',
            ),
            SubtitleWord(
              wordId: 'word-2',
              text: 'two',
              sourceStartMs: 900,
              sourceEndMs: 2000,
            ),
          ],
          timingMode: SubtitleTimingMode.word,
        ),
      ],
      defaultStyle: SubtitleStyle.defaults,
      cutRanges: const [],
      revision: 0,
      createdAt: DateTime.utc(2026, 7, 22),
      updatedAt: DateTime.utc(2026, 7, 22),
    );
