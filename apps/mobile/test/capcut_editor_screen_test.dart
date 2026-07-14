import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postdee_mobile/core/network/postdee_api_client.dart';
import 'package:postdee_mobile/features/ai_editing/capcut_editor_screen.dart';
import 'package:postdee_mobile/features/ai_editing/edit_styles.dart';
import 'package:postdee_mobile/features/ai_editing/style_options.dart';
import 'package:postdee_mobile/features/ai_editing/subtitle_burn_video_processor.dart';

File _createVideoFixture(String name) {
  final directory = Directory.systemTemp.createTempSync('postdee-capcut-');
  addTearDown(() {
    if (directory.existsSync()) {
      directory.deleteSync(recursive: true);
    }
  });

  final file = File('${directory.path}${Platform.pathSeparator}$name');
  file.writeAsBytesSync(List<int>.filled(2048, 1));

  return file;
}

void main() {
  testWidgets(
      'transcribes the real uploaded video key instead of a local preview',
      (tester) async {
    String? requestedVideoS3Key;

    await tester.pumpWidget(
      MaterialApp(
        home: CapCutEditorScreen(
          videoName: 'real-demo.mp4',
          videoS3Key: 'uploads/real-demo.mp4',
          transcribeClip: (videoS3Key) async {
            requestedVideoS3Key = videoS3Key;

            return const ClipTranscriptResult(
              text: 'Real transcript',
              segments: [
                ClipTranscriptSegment(
                  text: 'Real transcript',
                  start: 0,
                  end: 2,
                ),
              ],
              durationSeconds: 2,
            );
          },
        ),
      ),
    );

    await tester.tap(find.byIcon(Icons.closed_caption_outlined));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.auto_awesome));
    await tester.pumpAndSettle();

    expect(requestedVideoS3Key, 'uploads/real-demo.mp4');
    expect(requestedVideoS3Key, isNot(startsWith('local-preview/')));
  });

  testWidgets('does not show a demo export without a real video file',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: CapCutEditorScreen(
          videoName: 'missing.mp4',
          videoS3Key: 'uploads/missing.mp4',
        ),
      ),
    );

    await tester.tap(find.byIcon(Icons.ios_share));
    await tester.pump();

    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets('does not show a demo export when there are no edits',
      (tester) async {
    final videoFile = _createVideoFixture('unedited.mp4');

    await tester.pumpWidget(
      MaterialApp(
        home: CapCutEditorScreen(
          videoName: 'unedited.mp4',
          videoS3Key: 'uploads/unedited.mp4',
          videoFile: videoFile,
          probeDuration: (_) async => 10,
        ),
      ),
    );

    await tester.tap(find.byIcon(Icons.ios_share));
    await tester.pump();

    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets('applies manual trim on export without running AI captions',
      (tester) async {
    final videoFile = _createVideoFixture('trim-only.mp4');
    BurnSubtitleRequest? captured;

    await tester.pumpWidget(
      MaterialApp(
        home: CapCutEditorScreen(
          videoName: 'trim-only.mp4',
          videoS3Key: 'uploads/trim-only.mp4',
          videoFile: videoFile,
          probeDuration: (_) async => 10,
          burnVideo: (request) async {
            captured = request;

            return BurnedSubtitleResult(
              file: videoFile,
              fileName: 'trim-only_subtitled.mp4',
              sizeBytes: 2048,
            );
          },
        ),
      ),
    );
    // Let the duration probe resolve so trim knows the real clip length.
    await tester.pumpAndSettle();

    // Drag the end trim handle inward to trim the tail of the clip.
    await tester.drag(
      find.byIcon(Icons.drag_indicator).at(1),
      const Offset(-80, 0),
    );
    await tester.pump();

    await tester.tap(find.byIcon(Icons.ios_share));
    await tester.pumpAndSettle();

    expect(captured, isNotNull);
    expect(captured!.trimEndSec, isNotNull);
    expect(captured!.trimEndSec, lessThan(10));
  });

  testWidgets('drops a removed split segment on export via a cut range',
      (tester) async {
    final videoFile = _createVideoFixture('split.mp4');
    BurnSubtitleRequest? captured;

    await tester.pumpWidget(
      MaterialApp(
        home: CapCutEditorScreen(
          videoName: 'split.mp4',
          videoS3Key: 'uploads/split.mp4',
          videoFile: videoFile,
          probeDuration: (_) async => 10,
          burnVideo: (request) async {
            captured = request;

            return BurnedSubtitleResult(
              file: videoFile,
              fileName: 'split_subtitled.mp4',
              sizeBytes: 2048,
            );
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Open the split tool, cut at the default playhead, then drop the tail.
    await tester.ensureVisible(find.text('แบ่ง'));
    await tester.tap(find.text('แบ่ง'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('แบ่งตรงนี้'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(Switch).at(1));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.ios_share));
    await tester.pumpAndSettle();

    expect(captured, isNotNull);
    expect(captured!.silenceRanges, isNotEmpty);
    expect(captured!.silenceRanges.first.start, closeTo(3.5, 0.01));
    expect(captured!.silenceRanges.first.end, closeTo(10, 0.01));
  });

  testWidgets('hands the rendered clip to the posting flow on export',
      (tester) async {
    final videoFile = _createVideoFixture('handoff.mp4');
    BurnedSubtitleResult? exported;

    await tester.pumpWidget(
      MaterialApp(
        home: CapCutEditorScreen(
          videoName: 'handoff.mp4',
          videoS3Key: 'uploads/handoff.mp4',
          videoFile: videoFile,
          probeDuration: (_) async => 10,
          burnVideo: (request) async => BurnedSubtitleResult(
            file: videoFile,
            fileName: 'handoff_subtitled.mp4',
            sizeBytes: 4096,
          ),
          onExported: (result) => exported = result,
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Trim, export, then choose to take the result to posting.
    await tester.drag(
      find.byIcon(Icons.drag_indicator).at(1),
      const Offset(-80, 0),
    );
    await tester.pump();
    await tester.tap(find.byIcon(Icons.ios_share));
    await tester.pumpAndSettle();
    await tester.tap(find.text('นำไปโพสต์'));
    await tester.pumpAndSettle();

    expect(exported, isNotNull);
    expect(exported!.fileName, 'handoff_subtitled.mp4');
  });

  testWidgets('rasterizes added stickers and passes them to the render',
      (tester) async {
    final videoFile = _createVideoFixture('stickers.mp4');
    BurnSubtitleRequest? captured;

    await tester.pumpWidget(
      MaterialApp(
        home: CapCutEditorScreen(
          videoName: 'stickers.mp4',
          videoS3Key: 'uploads/stickers.mp4',
          videoFile: videoFile,
          probeDuration: (_) async => 10,
          rasterizeSticker: (sticker) async {
            final directory =
                Directory.systemTemp.createTempSync('test-sticker-');
            addTearDown(() {
              if (directory.existsSync()) {
                directory.deleteSync(recursive: true);
              }
            });
            final file =
                File('${directory.path}${Platform.pathSeparator}s.png');
            file.writeAsBytesSync(const [1, 2, 3]);
            return file;
          },
          burnVideo: (request) async {
            captured = request;
            return BurnedSubtitleResult(
              file: videoFile,
              fileName: 'stickers_subtitled.mp4',
              sizeBytes: 2048,
            );
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Open the sticker tool and add one emoji.
    await tester.ensureVisible(find.text('สติกเกอร์'));
    await tester.tap(find.text('สติกเกอร์'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('🔥').first);
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.ios_share));
    await tester.pumpAndSettle();

    expect(captured, isNotNull);
    expect(captured!.stickerImagePaths, hasLength(1));
  });

  testWidgets('applying the Flash Sale style cuts non-price spans on export',
      (tester) async {
    final videoFile = _createVideoFixture('style.mp4');
    BurnSubtitleRequest? captured;

    await tester.pumpWidget(
      MaterialApp(
        home: CapCutEditorScreen(
          videoName: 'style.mp4',
          videoS3Key: 'uploads/style.mp4',
          videoFile: videoFile,
          probeDuration: (_) async => 10,
          transcribeClip: (_) async => const ClipTranscriptResult(
            text: 'ราคา',
            segments: [
              ClipTranscriptSegment(text: 'สวัสดีค่ะ', start: 0, end: 3),
              ClipTranscriptSegment(text: 'ราคาพิเศษ 99 บาท', start: 3, end: 6),
              ClipTranscriptSegment(text: 'ขอบคุณค่ะ', start: 6, end: 10),
            ],
            durationSeconds: 10,
          ),
          burnVideo: (request) async {
            captured = request;
            return BurnedSubtitleResult(
              file: videoFile,
              fileName: 'style_subtitled.mp4',
              sizeBytes: 2048,
            );
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Open the style gallery and pick "ชี้เป้าโปรเด็ด" (Flash Sale).
    await tester.tap(find.byIcon(Icons.movie_filter));
    await tester.pumpAndSettle();
    await tester.tap(find.text('ชี้เป้าโปรเด็ด'));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.ios_share));
    await tester.pumpAndSettle();

    expect(captured, isNotNull);
    // Keeps the 3-6s price segment, cuts 0-3 and 6-10.
    expect(captured!.silenceRanges, hasLength(2));
    expect(captured!.silenceRanges[0].start, closeTo(0, 0.01));
    expect(captured!.silenceRanges[0].end, closeTo(3, 0.01));
    expect(captured!.silenceRanges[1].start, closeTo(6, 0.01));
    expect(captured!.silenceRanges[1].end, closeTo(10, 0.01));
  });

  testWidgets('applying the Aesthetic style gives the export a warm look',
      (tester) async {
    final videoFile = _createVideoFixture('aesthetic.mp4');
    BurnSubtitleRequest? captured;

    await tester.pumpWidget(
      MaterialApp(
        home: CapCutEditorScreen(
          videoName: 'aesthetic.mp4',
          videoS3Key: 'uploads/aesthetic.mp4',
          videoFile: videoFile,
          probeDuration: (_) async => 10,
          burnVideo: (request) async {
            captured = request;
            return BurnedSubtitleResult(
              file: videoFile,
              fileName: 'aesthetic_subtitled.mp4',
              sizeBytes: 2048,
            );
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.movie_filter));
    await tester.pumpAndSettle();
    // The Aesthetic card sits far down the gallery sheet — scroll to it.
    await tester.scrollUntilVisible(
      find.text('มินิมอลสายคาเฟ่'),
      300,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('มินิมอลสายคาเฟ่'));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.ios_share));
    await tester.pumpAndSettle();

    expect(captured, isNotNull);
    expect(captured!.filterIndex, 4); // อบอุ่น / warm
  });

  testWidgets('custom prompt "เหลือ 5 วิ" trims the clip to the target',
      (tester) async {
    final videoFile = _createVideoFixture('prompt.mp4');
    BurnSubtitleRequest? captured;

    await tester.pumpWidget(
      MaterialApp(
        home: CapCutEditorScreen(
          videoName: 'prompt.mp4',
          videoS3Key: 'uploads/prompt.mp4',
          videoFile: videoFile,
          probeDuration: (_) async => 10,
          burnVideo: (request) async {
            captured = request;
            return BurnedSubtitleResult(
              file: videoFile,
              fileName: 'prompt_subtitled.mp4',
              sizeBytes: 2048,
            );
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.movie_filter));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('ให้ AI ตัดให้'),
      300,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'เหลือ 5 วิ');
    await tester.tap(find.text('ให้ AI ตัดให้'));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.ios_share));
    await tester.pumpAndSettle();

    expect(captured, isNotNull);
    // 10s clip, keep 5s → cut [5,10].
    expect(captured!.silenceRanges, hasLength(1));
    expect(captured!.silenceRanges.first.start, closeTo(5, 0.01));
    expect(captured!.silenceRanges.first.end, closeTo(10, 0.01));
  });

  testWidgets('custom prompt uses the server planner cuts when available',
      (tester) async {
    final videoFile = _createVideoFixture('server.mp4');
    BurnSubtitleRequest? captured;
    AiEditPlanRequest? planRequest;

    await tester.pumpWidget(
      MaterialApp(
        home: CapCutEditorScreen(
          videoName: 'server.mp4',
          videoS3Key: 'uploads/server.mp4',
          videoFile: videoFile,
          probeDuration: (_) async => 10,
          transcribeClip: (_) async => const ClipTranscriptResult(
            text: 'hi',
            segments: [ClipTranscriptSegment(text: 'hi', start: 0, end: 10)],
            durationSeconds: 10,
          ),
          requestEditPlan: (request) async {
            planRequest = request;
            return const AiEditPlanResult(
              cuts: [AiEditCut(start: 2, end: 4)],
              summary: 'mock',
              model: 'mock-rule',
            );
          },
          burnVideo: (request) async {
            captured = request;
            return BurnedSubtitleResult(
              file: videoFile,
              fileName: 'server_subtitled.mp4',
              sizeBytes: 2048,
            );
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.movie_filter));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('ให้ AI ตัดให้'),
      300,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'ตัดให้หน่อย');
    await tester.tap(find.text('ให้ AI ตัดให้'));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.ios_share));
    await tester.pumpAndSettle();

    expect(planRequest, isNotNull);
    expect(planRequest!.prompt, 'ตัดให้หน่อย');
    expect(captured, isNotNull);
    expect(captured!.silenceRanges, hasLength(1));
    expect(captured!.silenceRanges.first.start, closeTo(2, 0.01));
    expect(captured!.silenceRanges.first.end, closeTo(4, 0.01));
  });

  testWidgets('export shows a cancellable dialog that invokes the canceller',
      (tester) async {
    final videoFile = _createVideoFixture('cancel.mp4');
    final completer = Completer<BurnedSubtitleResult>();
    var cancelCalls = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: CapCutEditorScreen(
          videoName: 'cancel.mp4',
          videoS3Key: 'uploads/cancel.mp4',
          videoFile: videoFile,
          probeDuration: (_) async => 10,
          cancelRender: () async => cancelCalls += 1,
          burnVideo: (_) => completer.future,
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Make an edit so export proceeds, then start the (hanging) render.
    await tester.drag(
      find.byIcon(Icons.drag_indicator).at(1),
      const Offset(-80, 0),
    );
    await tester.pump();
    await tester.tap(find.byIcon(Icons.ios_share));
    await tester.pump();
    await tester.pump();

    expect(find.text('ยกเลิก'), findsOneWidget);

    await tester.tap(find.text('ยกเลิก'));
    await tester.pump();
    expect(cancelCalls, 1);

    // Let the hung render unwind so teardown is clean.
    completer
        .completeError(const SubtitleBurnException('ยกเลิกการเรนเดอร์แล้ว'));
    await tester.pumpAndSettle();
  });

  testWidgets('a coming-soon style is not applied and says so', (tester) async {
    final asmr = editStyles.firstWhere((style) => style.id == 'asmr');

    await tester.pumpWidget(
      MaterialApp(
        home: CapCutEditorScreen(
          videoName: 'x.mp4',
          videoS3Key: 'uploads/x.mp4',
          initialStyle: EditStyleSelection(style: asmr),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Honest message shown; the style banner ("จะเหลือ ...") is NOT applied.
    expect(find.textContaining('เร็วๆ นี้'), findsWidgets);
    expect(find.textContaining('จะเหลือ'), findsNothing);
  });

  testWidgets('initial options override the initial style on export',
      (tester) async {
    final videoFile = _createVideoFixture('initial-options.mp4');
    final fastReview =
        editStyles.firstWhere((style) => style.id == 'fast_review');
    BurnSubtitleRequest? captured;

    await tester.pumpWidget(
      MaterialApp(
        home: CapCutEditorScreen(
          videoName: 'initial-options.mp4',
          videoS3Key: 'uploads/initial-options.mp4',
          videoFile: videoFile,
          probeDuration: (_) async => 10,
          transcribeClip: (_) async => const ClipTranscriptResult(
            text: 'รีวิวสินค้า',
            segments: [
              ClipTranscriptSegment(
                text: 'รีวิวสินค้า',
                start: 0,
                end: 10,
              ),
            ],
            durationSeconds: 10,
          ),
          initialStyle: EditStyleSelection(style: fastReview),
          initialCaptionEnabled: true,
          initialOptions: const EditStyleOptions(
            speed: 1.5,
            filterIndex: 5,
            subtitleFontSize: 24,
            subtitleAtBottom: false,
            brightness: 0.25,
            contrast: -0.3,
          ),
          burnVideo: (request) async {
            captured = request;
            return BurnedSubtitleResult(
              file: videoFile,
              fileName: 'initial-options_subtitled.mp4',
              sizeBytes: 2048,
            );
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.ios_share));
    await tester.pumpAndSettle();

    expect(captured, isNotNull);
    expect(captured!.speed, 1.5);
    expect(captured!.filterIndex, 5);
    expect(captured!.subtitleFontSize, 24);
    expect(captured!.subtitleAtBottom, isFalse);
    expect(captured!.brightness, 0.25);
    expect(captured!.contrast, -0.3);
    expect(captured!.segments, hasLength(1));
    expect(captured!.segments.single.text, 'รีวิวสินค้า');
  });
}
