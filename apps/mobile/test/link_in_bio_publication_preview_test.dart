import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postdee_mobile/core/auth/auth_session.dart';
import 'package:postdee_mobile/core/localization/postdee_localizations.dart';
import 'package:postdee_mobile/core/network/postdee_api_client.dart';
import 'package:postdee_mobile/core/theme/app_theme.dart';
import 'package:postdee_mobile/features/home/home_screen.dart';
import 'package:postdee_mobile/features/link_in_bio/link_in_bio_draft_store.dart';
import 'package:postdee_mobile/features/link_in_bio/link_in_bio_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _draft = LinkInBioDraft(
  storeName: 'ร้านของเรา',
  slug: 'our-shop',
  autoUpdateFromScheduledPosts: false,
  enabledLinkIds: {'shop', 'video'},
  customLinks: [
    LinkInBioCustomLink(
        id: 'shop', title: 'Shopee', url: 'https://example.com/shop'),
    LinkInBioCustomLink(
        id: 'video', title: 'YouTube', url: 'https://example.com/video'),
  ],
);

class _PreviewDraftStore implements LinkInBioDraftStore {
  @override
  Future<LinkInBioDraft?> loadDraft() async => _draft;

  @override
  Future<void> saveDraft(LinkInBioDraft draft) async {}
}

LinkInBioProfileResult _profile(bool published) => LinkInBioProfileResult(
      storeName: _draft.storeName,
      slug: _draft.slug,
      links: [
        for (final link in _draft.customLinks)
          LinkInBioLinkResult(id: link.id, title: link.title, url: link.url),
      ],
      isPublished: published,
      updatedAt: DateTime.utc(2026, 10, 20),
      publishedAt: published ? DateTime.utc(2026, 10, 20) : null,
      publicPath: published ? '/p/our-shop' : null,
      publicUrl: published ? Uri.parse('https://example.com/p/our-shop') : null,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final outputDirectory =
      Platform.environment['POSTDEE_LINK_PUBLICATION_PREVIEW_DIR'];

  testWidgets('renders real shop publication dots with local data only',
      (tester) async {
    final originalTheme =
        AppTheme.isLightMode ? ThemeMode.light : ThemeMode.dark;
    final sessions = PostDeeAuthSessionStore.instance;
    final originalSession = sessions.session;
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      sessions.signIn(originalSession);
      AppTheme.applyThemeMode(originalTheme);
      SharedPreferences.setMockInitialValues({});
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    sessions.signIn(const AuthSession(
        userId: 'preview-shop-owner', idToken: 'preview-local-token'));
    await tester.runAsync(() async {
      final fonts = FontLoader('Anuphan');
      for (final weight in ['Regular', 'Medium', 'SemiBold', 'Bold']) {
        fonts.addFont(
            rootBundle.load('assets/fonts/anuphan/Anuphan-$weight.ttf'));
      }
      await fonts.load();
      await (FontLoader('MaterialIcons')
            ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf')))
          .load();
    });

    final boundaryKey = GlobalKey();
    var profileLoads = 0;
    var mutations = 0;
    Future<LinkInBioProfileResult?> read(LinkInBioProfileResult? profile) async {
      profileLoads++;
      return profile;
    }

    HomeScreen home(HomeLinkProfileLoader loader) => HomeScreen(
          key: UniqueKey(),
          userName: 'ร้านของเรา',
          now: () => DateTime(2026, 10, 20, 15, 30),
          loadSubscription: () async => const SubscriptionStatusResult(
            userId: 'preview-shop-owner',
            plan: 'PRO',
            status: 'ACTIVE',
            remainingPostsThisMonth: 242,
            canSchedule: true,
            canUseAiCaptions: true,
            canUseAnalytics: true,
          ),
          loadRecentPosts: () async => [],
          loadDrafts: () async => [],
          loadConnections: () async => [],
          loadScheduledPosts: () async => [],
          loadLinkProfile: loader,
          onCreatePost: () async {},
          onOpenLinkInBio: () {},
        );

    LinkInBioScreen manager(LinkInBioProfileLoader loader) => LinkInBioScreen(
          key: UniqueKey(),
          draftStore: _PreviewDraftStore(),
          loadProfile: loader,
          publishProfile: (
              {required storeName,
              required slug,
              required links,
              appearance}) async {
            mutations++;
            throw StateError('Preview cannot publish');
          },
          unpublishProfile: () async {
            mutations++;
            throw StateError('Preview cannot unpublish');
          },
        );

    Future<void> capture(Widget screen, String name,
        {bool dark = false, bool? published}) async {
      AppTheme.applyThemeMode(dark ? ThemeMode.dark : ThemeMode.light);
      await tester.pumpWidget(RepaintBoundary(
        key: boundaryKey,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: dark ? AppTheme.dark : AppTheme.light,
          locale: const Locale('th'),
          supportedLocales: PostDeeLocalizations.supportedLocales,
          localizationsDelegates: const [
            PostDeeLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(disableAnimations: true),
            child: child!,
          ),
          home: Scaffold(body: screen),
        ),
      ));
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      if (screen is HomeScreen) {
        final shortcut = find.byKey(const ValueKey('home-link-in-bio-shortcut'));
        await Scrollable.ensureVisible(tester.element(shortcut), alignment: .35);
        await tester.pump();
      }
      final dot = find.byKey(const ValueKey('link-in-bio-publication-dot'));
      expect(dot, findsOneWidget);
      expect(
          (tester.widget<DecoratedBox>(dot).decoration as BoxDecoration).color,
          switch (published) {
            true => AppTheme.successInk,
            false => const Color(0xFFEF4444),
            null => AppTheme.textMuted,
          });
      expect(tester.takeException(), isNull);
      final boundary = boundaryKey.currentContext!.findRenderObject()!
          as RenderRepaintBoundary;
      await tester.runAsync(() async {
        final image = await boundary.toImage(pixelRatio: 2);
        try {
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          expect(bytes, isNotNull);
          final directory = Directory(outputDirectory!);
          await directory.create(recursive: true);
          await File('${directory.path}/$name.png')
              .writeAsBytes(bytes!.buffer.asUint8List());
        } finally {
          image.dispose();
        }
      });
    }

    for (final dark in [false, true]) {
      for (final published in [false, true]) {
        final suffix = '${published ? 'published' : 'unpublished'}-'
            '${dark ? 'dark' : 'light'}';
        await capture(home(() => read(_profile(published))), 'home-$suffix',
            dark: dark, published: published);
        await capture(manager(() => read(_profile(published))), 'shop-$suffix',
            dark: dark, published: published);
      }
    }
    expect(profileLoads, 8,
        reason: 'Rendering must not perform extra profile reads.');
    final pendingHome = Completer<LinkInBioProfileResult?>();
    await capture(home(() => pendingHome.future), 'home-checking-light');
    pendingHome.complete(null);
    await tester.pump();
    final pendingShop = Completer<LinkInBioProfileResult?>();
    await capture(manager(() => pendingShop.future), 'shop-checking-light');
    pendingShop.complete(null);
    await tester.pump();
    expect(mutations, 0);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  }, skip: outputDirectory == null || outputDirectory.isEmpty);
}
