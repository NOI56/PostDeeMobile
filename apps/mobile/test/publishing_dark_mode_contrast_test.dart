import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postdee_mobile/core/localization/postdee_localizations.dart';
import 'package:postdee_mobile/core/network/postdee_api_client.dart';
import 'package:postdee_mobile/core/theme/app_theme.dart';
import 'package:postdee_mobile/features/platforms/social_platform.dart';
import 'package:postdee_mobile/features/posts/post_detail_screen.dart';
import 'package:postdee_mobile/features/uploader/publish_flow_screen.dart';

const _postId = 'publishing-contrast';

class _NoNetworkClient extends PostDeeApiClient {
  int reads = 0;

  @override
  Future<PostSummaryResult?> getPostById(String postId,
      {bool includeMedia = false}) async {
    reads++;
    throw StateError('Contrast checks must not read a post.');
  }
}

double _contrast(Color first, Color second) {
  final a = first.computeLuminance();
  final b = second.computeLuminance();
  return a > b ? (a + .05) / (b + .05) : (b + .05) / (a + .05);
}

Container _paintedContainer(WidgetTester tester, Finder content) {
  Container? surface;
  tester.element(content).visitAncestorElements((element) {
    final widget = element.widget;
    if (widget is Container &&
        (widget.color != null ||
            widget.decoration is BoxDecoration &&
                (widget.decoration! as BoxDecoration).color != null)) {
      surface = widget;
      return false;
    }
    return true;
  });
  expect(surface, isNotNull, reason: 'Content must have a painted surface.');
  return surface!;
}

Color _background(WidgetTester tester, Finder content) {
  final surface = _paintedContainer(tester, content);
  return surface.color ?? (surface.decoration! as BoxDecoration).color!;
}

void _expectReadableText(WidgetTester tester, Finder text,
    {required String reason}) {
  expect(text, findsOneWidget);
  final paragraph = tester.renderObject<RenderParagraph>(text);
  final foreground = paragraph.text.style!.color!;
  final background = _background(tester, text);
  expect(_contrast(foreground, background), greaterThanOrEqualTo(4.5),
      reason: reason);
}

Widget _host(Widget screen, {required bool dark}) {
  AppTheme.applyThemeMode(dark ? ThemeMode.dark : ThemeMode.light);
  return MaterialApp(
    locale: const Locale('th'),
    supportedLocales: PostDeeLocalizations.supportedLocales,
    localizationsDelegates: const [
      PostDeeLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    theme: dark ? AppTheme.dark : AppTheme.light,
    themeAnimationDuration: Duration.zero,
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(disableAnimations: true),
      child: child!,
    ),
    home: screen,
  );
}

void _prepare(WidgetTester tester) {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final previousMode = AppTheme.isLightMode ? ThemeMode.light : ThemeMode.dark;
  addTearDown(() => AppTheme.applyThemeMode(previousMode));
}

Future<_NoNetworkClient> _showFailedDetail(WidgetTester tester,
    {required bool dark, Uri? coverImageUrl}) async {
  final api = _NoNetworkClient();
  final post = PostSummaryResult(
    id: _postId,
    caption: 'ตรวจการแสดงผลโพสต์',
    videoS3Key: '',
    platforms: const ['YOUTUBE_SHORTS'],
    status: 'FAILED',
    createdAt: DateTime(2026, 11, 1, 10),
    coverImageUrl: coverImageUrl,
    platformResults: const [
      PostPlatformResult(
        postId: _postId,
        platform: 'YOUTUBE_SHORTS',
        status: 'FAILED',
        errorMessage:
            'Publishing to this platform failed. Please try again later.',
      ),
    ],
  );
  await tester.pumpWidget(_host(
      PostDetailScreen(post: post, apiClient: api, refreshOnOpen: false),
      dark: dark));
  await tester.pumpAndSettle();
  expect(tester.takeException(), isNull);
  expect(api.reads, 0);
  return api;
}

void main() {
  for (final dark in [false, true]) {
    final mode = dark ? 'dark' : 'light';

    testWidgets('unavailable post preview text is readable in $mode mode',
        (tester) async {
      _prepare(tester);
      await _showFailedDetail(tester, dark: dark);
      _expectReadableText(tester, find.text('ตัวอย่างยังไม่พร้อม'),
          reason: 'Unavailable preview text must contrast with its own fill.');
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('cover-only preview keeps its label readable in $mode mode',
        (tester) async {
      _prepare(tester);
      // The widget-test HTTP client returns 400 without making a network
      // request. Image remains mounted, so this also checks the layering that
      // must protect the label when the cover loads successfully on a device.
      final cover = Uri.parse('https://media.test/contrast-cover-$mode.png');
      await _showFailedDetail(tester, dark: dark, coverImageUrl: cover);
      final preview =
          find.byKey(const ValueKey('post-detail-preview-unavailable'));
      final image = find.descendant(of: preview, matching: find.byType(Image));
      expect(image, findsOneWidget);
      expect((tester.widget<Image>(image).image as NetworkImage).url,
          cover.toString());
      expect(find.byKey(const ValueKey('post-detail-preview')), findsNothing);
      expect(find.byIcon(Icons.play_circle_fill_rounded), findsNothing);

      final label = find.text('ตัวอย่างยังไม่พร้อม');
      final labelSurface = _paintedContainer(tester, label);
      final surfaceFinder = find.byWidget(labelSurface);
      final previewStack =
          find.descendant(of: preview, matching: find.byType(Stack)).first;
      expect(find.descendant(of: previewStack, matching: surfaceFinder),
          findsOneWidget,
          reason: 'The label fill must be above the cover inside the Stack.');
      expect(find.descendant(of: surfaceFinder, matching: find.byType(Image)),
          findsNothing,
          reason: 'A background behind the cover cannot protect label text.');
      final stackChildren = tester.widget<Stack>(previewStack).children;
      int branchIndex(Finder content) =>
          stackChildren.indexWhere((child) => find
              .descendant(
                  of: find.byWidget(child), matching: content, matchRoot: true)
              .evaluate()
              .isNotEmpty);
      expect(branchIndex(label), greaterThan(branchIndex(image)),
          reason: 'The label must paint after the cover image.');
      expect(_background(tester, label).a, 1,
          reason:
              'The label needs an opaque fill over arbitrary cover images.');
      _expectReadableText(tester, label,
          reason: 'Cover-only preview text must contrast with its own fill.');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('failed channel status text is readable in $mode mode',
        (tester) async {
      _prepare(tester);
      await _showFailedDetail(tester, dark: dark);
      final card = _paintedContainer(tester, find.text('YouTube Shorts'));
      final status = find.descendant(
          of: find.byWidget(card), matching: find.text('ส่งไม่สำเร็จ'));
      _expectReadableText(tester, status,
          reason: 'Failed status text must contrast with the channel card.');
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('failed channel reason text is readable in $mode mode',
        (tester) async {
      _prepare(tester);
      await _showFailedDetail(tester, dark: dark);
      _expectReadableText(tester, find.textContaining('สาเหตุ:'),
          reason: 'The reason for failure must remain readable on the card.');
      await tester.pumpWidget(const SizedBox.shrink());
    });

    for (final outcome in ['failed', 'published', 'unconfirmed']) {
      testWidgets('publish $outcome result stays clear in $mode mode',
          (tester) async {
        _prepare(tester);
        final failed = outcome == 'failed';
        final unconfirmed = outcome == 'unconfirmed';
        final title = failed
            ? 'ส่งไม่สำเร็จ'
            : unconfirmed
                ? 'ผลยังไม่ยืนยัน'
                : 'เผยแพร่แล้ว';
        final resultIcon = failed
            ? Icons.error_outline_rounded
            : unconfirmed
                ? Icons.help_outline_rounded
                : Icons.check_rounded;
        var calls = 0;
        await tester.pumpWidget(_host(
            PublishFlowScreen(
              platforms: const [SocialPlatform.youtubeShorts],
              isScheduled: false,
              publish: (_) async {
                calls++;
                return QueuedPostResult(
                  id: _postId,
                  videoS3Key: '',
                  platforms: const ['YOUTUBE_SHORTS'],
                  status: failed ? 'FAILED' : 'PUBLISHED',
                  platformResults: [
                    PostPlatformResult(
                      postId: _postId,
                      platform: 'YOUTUBE_SHORTS',
                      status: failed ? 'FAILED' : 'PUBLISHED',
                      deliveryOutcome: failed
                          ? null
                          : unconfirmed
                              ? 'UNRECOGNIZED_OUTCOME'
                              : 'LIVE',
                    ),
                  ],
                );
              },
              onViewPost: (_) {},
            ),
            dark: dark));
        await tester.pumpAndSettle();

        expect(calls, 1);
        expect(find.text(title), findsOneWidget);
        final iconFinder = find.byIcon(resultIcon);
        expect(iconFinder, findsOneWidget);
        expect(find.byKey(const ValueKey('publish-flow-view-post')),
            findsOneWidget);
        expect(
            find.byKey(const ValueKey('publish-flow-finish')), findsOneWidget);
        if (failed) {
          final icon = tester.widget<Icon>(iconFinder);
          expect(_contrast(icon.color!, _background(tester, iconFinder)),
              greaterThanOrEqualTo(3),
              reason: 'The result symbol must remain visible on its fill.');
        }
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      });
    }
  }
}
