import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postdee_mobile/core/network/postdee_api_client.dart';
import 'package:postdee_mobile/core/theme/app_theme.dart';
import 'package:postdee_mobile/features/platforms/social_platform.dart';
import 'package:postdee_mobile/features/uploader/publish_flow_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final outputDirectory =
      Platform.environment['POSTDEE_PUBLISH_PROGRESS_PREVIEW_DIR'];

  testWidgets(
      'renders publishing motion and truthful outcomes with local fixtures',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final originalThemeMode =
        AppTheme.isLightMode ? ThemeMode.light : ThemeMode.dark;
    addTearDown(() => AppTheme.applyThemeMode(originalThemeMode));

    await tester.runAsync(() async {
      final fonts = FontLoader('Anuphan');
      for (final weight in ['Regular', 'Medium', 'SemiBold', 'Bold']) {
        fonts.addFont(
            rootBundle.load('assets/fonts/anuphan/Anuphan-$weight.ttf'));
      }
      await fonts.load();
      final icons = FontLoader('MaterialIcons')
        ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
      await icons.load();
    });

    final boundaryKey = GlobalKey();
    Widget host(Widget screen, {bool reduced = false, bool dark = false}) {
      AppTheme.applyThemeMode(dark ? ThemeMode.dark : ThemeMode.light);
      return RepaintBoundary(
        key: boundaryKey,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: dark ? AppTheme.dark : AppTheme.light,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(disableAnimations: reduced),
            child: child!,
          ),
          home: screen,
        ),
      );
    }

    Future<void> capture(String name) async {
      await tester.pump();
      expect(tester.takeException(), isNull);
      final boundary = boundaryKey.currentContext!.findRenderObject()!
          as RenderRepaintBoundary;
      await tester.runAsync(() async {
        final image = await boundary.toImage(pixelRatio: 2);
        try {
          final data = await image.toByteData(format: ui.ImageByteFormat.png);
          expect(data, isNotNull);
          final directory = Directory(outputDirectory!);
          await directory.create(recursive: true);
          await File('${directory.path}/$name.png')
              .writeAsBytes(data!.buffer.asUint8List());
        } finally {
          image.dispose();
        }
      });
    }

    final operation = Completer<QueuedPostResult?>();
    late PublishProgressReporter reportProgress;
    var attempts = 0;
    PublishFlowScreen pendingScreen() => PublishFlowScreen(
          platforms: const [
            SocialPlatform.tiktok,
            SocialPlatform.youtubeShorts
          ],
          isScheduled: false,
          publish: (reporter) {
            attempts++;
            reportProgress = reporter;
            return operation.future;
          },
        );
    await tester.pumpWidget(host(pendingScreen()));
    await tester.pump();
    reportProgress(const PublishFlowProgress(
      stage: PublishFlowStage.uploadingVideo,
      fraction: 0.55,
    ));
    await tester.pump(const Duration(milliseconds: 230));
    await capture('publish-smooth-upload-55');

    reportProgress(const PublishFlowProgress(
      stage: PublishFlowStage.creatingPost,
      fraction: 0.9,
    ));
    await tester.pump(const Duration(milliseconds: 230));
    await capture('publish-smooth-queue-90-frame-1');
    await tester.pump(const Duration(milliseconds: 460));
    await capture('publish-smooth-queue-90-frame-2');
    expect(find.text('90% · ความคืบหน้าตามขั้นตอน'), findsOneWidget);
    expect(attempts, 1);

    await tester.pumpWidget(host(pendingScreen(), dark: true));
    await tester.pump(const Duration(milliseconds: 230));
    await capture('publish-smooth-queue-90-dark');
    expect(AppTheme.isLightMode, isFalse);
    expect(find.text('90% · ความคืบหน้าตามขั้นตอน'), findsOneWidget);
    expect(attempts, 1);

    await tester.pumpWidget(host(pendingScreen(), reduced: true));
    await tester.pump(const Duration(milliseconds: 300));
    await capture('publish-smooth-queue-reduced-motion');
    expect(AppTheme.isLightMode, isTrue);
    expect(find.byKey(const ValueKey('publish-flow-sheen')), findsNothing);
    expect(tester.binding.hasScheduledFrame, isFalse);

    operation.complete(const QueuedPostResult(
      id: 'preview-local-queued',
      videoS3Key: 'uploads/preview-local.mp4',
      platforms: ['TIKTOK', 'YOUTUBE_SHORTS'],
      status: 'QUEUED',
    ));
    await tester.pumpAndSettle();
    expect(find.text('รับรายการแล้ว'), findsOneWidget);
    expect(find.text('โพสต์สำเร็จ!'), findsNothing);
    // Preserve outcome assertions without capturing their existing button font
    // fallback: widget-test Ahem differs from Android's system Thai fallback.

    await tester.pumpWidget(host(PublishFlowScreen(
      key: const ValueKey('preview-error'),
      platforms: const [SocialPlatform.youtubeShorts],
      isScheduled: false,
      publish: (_) async {
        throw const ApiException('ตัวอย่างการเชื่อมต่อขัดข้อง กรุณาลองใหม่');
      },
    )));
    await tester.pumpAndSettle();
    expect(find.text('ส่งโพสต์ไม่สำเร็จ'), findsOneWidget);
    expect(find.byKey(const ValueKey('publish-flow-retry')), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  }, skip: outputDirectory == null || outputDirectory.isEmpty);
}
