import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postdee_mobile/core/auth/auth_session.dart';
import 'package:postdee_mobile/core/localization/postdee_localizations.dart';
import 'package:postdee_mobile/core/network/postdee_api_client.dart';
import 'package:postdee_mobile/core/theme/app_theme.dart';
import 'package:postdee_mobile/features/posts/posts_screen.dart';

const _missing =
    'This post was not found in your account. It may have been canceled or removed.';
const _failed = 'Could not load this post. Please try again when connected.';
const _ownerChanged = 'Your account has changed. Reopen Post details.';

Widget _app(Widget child,
    {Locale locale = const Locale('en'), bool dark = false, double scale = 1}) {
  AppTheme.applyThemeMode(dark ? ThemeMode.dark : ThemeMode.light);
  return MaterialApp(
    locale: locale,
    supportedLocales: PostDeeLocalizations.supportedLocales,
    localizationsDelegates: const [
      PostDeeLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    theme: dark ? AppTheme.dark : AppTheme.light,
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(
          disableAnimations: true, textScaler: TextScaler.linear(scale)),
      child: child!,
    ),
    home: child,
  );
}

void _expectEnglish(WidgetTester tester) {
  for (final text in tester.widgetList<Text>(find.byType(Text))) {
    expect(text.data ?? text.textSpan?.toPlainText() ?? '',
        isNot(matches(RegExp(r'[\u0E00-\u0E7F]'))));
  }
  expect(tester.takeException(), isNull);
}

void main() {
  setUp(() => PostDeeAuthSessionStore.instance.signIn(
      const AuthSession(userId: 'detail-loader-owner', idToken: 'fixture')));
  tearDown(PostDeeAuthSessionStore.instance.clear);
  tearDown(() => AppTheme.applyThemeMode(ThemeMode.dark));

  testWidgets('loader defaults to Thai without app localization delegates',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
        home: PostDetailLoaderScreen(
            postId: 'missing', loadPost: (_) async => null)));
    await tester.pumpAndSettle();
    expect(find.text('รายละเอียดโพสต์'), findsOneWidget);
    expect(find.text('ไม่พบโพสต์นี้ในบัญชีที่ใช้งาน อาจถูกยกเลิกหรือถูกนำออก'),
        findsOneWidget);
    expect(find.text('ลองใหม่'), findsOneWidget);
  });

  testWidgets('English loader translates loading and missing states',
      (tester) async {
    final result = Completer<PostSummaryResult?>();
    final ids = <String>[];
    await tester.pumpWidget(_app(PostDetailLoaderScreen(
      postId: 'missing',
      loadPost: (id) {
        ids.add(id);
        return result.future;
      },
    )));
    await tester.pump();
    expect(find.text('Post details'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    result.complete(null);
    await tester.pumpAndSettle();
    expect(find.text(_missing), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
    expect(ids, ['missing']);
    _expectEnglish(tester);
  });

  testWidgets('English loader retry reads the same post and clears old error',
      (tester) async {
    var reads = 0;
    final ids = <String>[];
    await tester.pumpWidget(_app(PostDetailLoaderScreen(
      postId: 'retry-target',
      loadPost: (id) async {
        ids.add(id);
        if (++reads == 1) throw StateError('opaque-provider-error');
        return null;
      },
    )));
    await tester.pumpAndSettle();
    expect(find.text(_failed), findsOneWidget);
    expect(find.textContaining('opaque-provider-error'), findsNothing);
    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();
    expect(find.text(_missing), findsOneWidget);
    expect(find.text(_failed), findsNothing);
    expect(ids, ['retry-target', 'retry-target']);
    _expectEnglish(tester);
  });

  testWidgets('existing loader failure changes language without another read',
      (tester) async {
    var reads = 0;
    final loader = PostDetailLoaderScreen(
      key: const ValueKey('stable-loader'),
      postId: 'unavailable',
      loadPost: (_) async {
        reads++;
        throw StateError('offline');
      },
    );
    await tester.pumpWidget(_app(loader, locale: const Locale('th')));
    await tester.pumpAndSettle();
    expect(find.text('โหลดโพสต์ไม่สำเร็จ กรุณาลองใหม่เมื่อเชื่อมต่อได้'),
        findsOneWidget);
    expect(reads, 1);
    await tester.pumpWidget(_app(loader));
    await tester.pumpAndSettle();
    expect(find.text('Post details'), findsOneWidget);
    expect(find.text(_failed), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
    expect(reads, 1);
    _expectEnglish(tester);
    await tester.pumpWidget(_app(loader, locale: const Locale('th')));
    await tester.pumpAndSettle();
    expect(find.text('รายละเอียดโพสต์'), findsOneWidget);
    expect(reads, 1);
  });

  testWidgets('English owner change rejects a late result and disables retry',
      (tester) async {
    final result = Completer<PostSummaryResult?>();
    var reads = 0;
    await tester.pumpWidget(_app(PostDetailLoaderScreen(
      postId: 'private',
      loadPost: (_) {
        reads++;
        return result.future;
      },
    )));
    await tester.pump();
    PostDeeAuthSessionStore.instance.signIn(
        const AuthSession(userId: 'replacement-owner', idToken: 'replacement'));
    result.complete(PostSummaryResult(
      id: 'private',
      caption: 'Private owner caption',
      videoS3Key: '',
      platforms: const ['TIKTOK'],
      status: 'PUBLISHED',
      createdAt: DateTime(2026, 10, 27),
    ));
    await tester.pumpAndSettle();
    expect(find.text(_ownerChanged), findsOneWidget);
    expect(find.text('Try again'), findsNothing);
    expect(find.text('Private owner caption'), findsNothing);
    expect(reads, 1);
    _expectEnglish(tester);
  });

  testWidgets('English loader hides a late failure after owner change',
      (tester) async {
    final result = Completer<PostSummaryResult?>();
    await tester.pumpWidget(_app(PostDetailLoaderScreen(
        postId: 'private', loadPost: (_) => result.future)));
    await tester.pump();
    PostDeeAuthSessionStore.instance.signIn(
        const AuthSession(userId: 'replacement-owner', idToken: 'replacement'));
    result.completeError(StateError('old-owner-error'));
    await tester.pumpAndSettle();
    expect(find.text(_ownerChanged), findsOneWidget);
    expect(find.text(_failed), findsNothing);
    expect(find.textContaining('old-owner-error'), findsNothing);
    _expectEnglish(tester);
  });

  for (final dark in [false, true]) {
    testWidgets('English loader fits 320dp with 2x text (dark=$dark)',
        (tester) async {
      tester.view.physicalSize = const Size(320, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var reads = 0;
      await tester.pumpWidget(_app(
          PostDetailLoaderScreen(
              postId: 'missing',
              loadPost: (_) async {
                reads++;
                return null;
              }),
          dark: dark,
          scale: 2));
      await tester.pumpAndSettle();
      expect(find.text(_missing), findsOneWidget);
      expect(find.text('Try again').hitTestable(), findsOneWidget);
      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();
      expect(reads, 2);
      _expectEnglish(tester);
    });
  }
}
