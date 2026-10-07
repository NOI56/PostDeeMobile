import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postdee_mobile/core/auth/auth_session.dart';
import 'package:postdee_mobile/core/localization/language_controller.dart';
import 'package:postdee_mobile/core/localization/postdee_localizations.dart';
import 'package:postdee_mobile/core/network/postdee_api_client.dart';
import 'package:postdee_mobile/core/theme/app_theme.dart';
import 'package:postdee_mobile/features/auth/firebase_account_access_revoker.dart';
import 'package:postdee_mobile/features/calendar/calendar_screen.dart';
import 'package:postdee_mobile/features/link_in_bio/link_in_bio_draft_store.dart';
import 'package:postdee_mobile/features/shell/postdee_shell.dart';
import 'package:postdee_mobile/features/notifications/push_messaging_gateway.dart';
import 'package:postdee_mobile/features/uploader/publish_draft.dart';
import 'package:postdee_mobile/features/uploader/publish_draft_store.dart';
import 'package:postdee_mobile/features/uploader/uploader_screen.dart';
import 'package:postdee_mobile/features/uploader/video_picker_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

Finder _referenceNav() =>
    find.byKey(const ValueKey('postdee-reference-bottom-nav'));

Finder _referenceNavButton(String label) => find.descendant(
      of: _referenceNav(),
      matching: find.bySemanticsLabel(label),
    );

Widget _shellApp(PostDeeShell shell) => MaterialApp(
      theme: AppTheme.dark,
      locale: const Locale('en'),
      localizationsDelegates: const [
        PostDeeLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: PostDeeLocalizations.supportedLocales,
      home: shell,
    );

PostDeeLanguageController _signInShell() {
  SharedPreferences.setMockInitialValues({'postdee_onboarding_seen': true});
  final sessionStore = PostDeeAuthSessionStore.instance;
  final languageController = PostDeeLanguageController(
    initialLocale: const Locale('en'),
  );
  sessionStore.signIn(
    const AuthSession(
      userId: 'firebase-user-shell',
      idToken: 'firebase-id-token',
      email: 'seller@example.com',
      displayName: 'PostDee Seller',
    ),
  );
  addTearDown(sessionStore.clear);
  addTearDown(languageController.dispose);
  return languageController;
}

class _ShellDraftStore implements PublishDraftStore {
  final Map<String, PublishDraft> drafts = {};

  @override
  Future<void> deleteAllDrafts() async => drafts.clear();

  @override
  Future<void> deleteDraft(String draftId) async => drafts.remove(draftId);

  @override
  Future<List<PublishDraft>> listDrafts() async => drafts.values.toList();

  @override
  Future<PublishDraft?> loadDraft(String draftId) async => drafts[draftId];

  @override
  Future<PublishDraft> saveDraft(PublishDraftSaveRequest request) async {
    final draft = PublishDraft(
      version: publishDraftManifestVersion,
      id: request.id,
      ownerUserId: 'firebase-user-shell',
      submissionRequestId:
          'submit_bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
      createdAt: request.createdAt,
      updatedAt: request.updatedAt,
      videoPath: request.videoFile.path,
      videoName: request.videoName,
      videoSizeBytes: request.videoFile.lengthSync(),
      videoWidth: request.videoWidth,
      videoHeight: request.videoHeight,
      caption: request.caption,
      aiGuidance: request.aiGuidance,
      watermarkEnabled: request.watermarkEnabled,
      platformApiValues: request.platformApiValues,
      platformSettings: request.platformSettings,
      scheduledAt: request.scheduledAt,
    );
    drafts[draft.id] = draft;
    return draft;
  }
}

void main() {
  testWidgets('opens one full screen composer without a hidden uploader',
      (tester) async {
    final languageController = _signInShell();
    var connectionLoads = 0;
    await tester.pumpWidget(
      _shellApp(
        PostDeeShell(
          languageController: languageController,
          uploaderDraftStore: _ShellDraftStore(),
          loadSocialConnections: () async {
            connectionLoads += 1;
            return const [];
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(UploaderScreen, skipOffstage: false), findsNothing);
    expect(connectionLoads, 0);

    final createAction = tester
        .widget<Semantics>(
          _referenceNavButton('Create post'),
        )
        .properties
        .onTap!;
    createAction();
    createAction();
    await tester.pumpAndSettle();

    expect(find.byType(UploaderScreen, skipOffstage: false), findsOneWidget);
    expect(_referenceNav(), findsNothing);
    expect(connectionLoads, 1);
    expect(
      ModalRoute.of(tester.element(find.byType(UploaderScreen)))?.settings.name,
      '/create-post',
    );
    expect(find.byKey(const ValueKey('uploader-close')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('uploader-close')));
    await tester.pumpAndSettle();
    expect(_referenceNav(), findsOneWidget);
    expect(find.byType(UploaderScreen, skipOffstage: false), findsNothing);
    expect(tester.widget<IndexedStack>(find.byType(IndexedStack)).index, 0);
  });

  testWidgets('calendar starts the composer and returns to the same calendar',
      (tester) async {
    final languageController = _signInShell();
    await tester.pumpWidget(
      _shellApp(
        PostDeeShell(
          languageController: languageController,
          uploaderDraftStore: _ShellDraftStore(),
          loadScheduledPosts: () async => const [],
          loadSocialConnections: () async => const [],
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(_referenceNavButton('Calendar'));
    await tester.pumpAndSettle();
    final calendarState = tester.state(find.byType(CalendarScreen));
    final calendar = tester.widget<CalendarScreen>(find.byType(CalendarScreen));
    calendar.onAddPost!();
    await tester.pumpAndSettle();
    expect(_referenceNav(), findsNothing);
    expect(find.byType(UploaderScreen), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('uploader-close')));
    await tester.pumpAndSettle();
    expect(_referenceNav(), findsOneWidget);
    expect(tester.widget<IndexedStack>(find.byType(IndexedStack)).index, 3);
    expect(tester.state(find.byType(CalendarScreen)), same(calendarState));
  });

  testWidgets('composer callbacks close only their own active route',
      (tester) async {
    final languageController = _signInShell();
    await tester.pumpWidget(
      _shellApp(
        PostDeeShell(
          languageController: languageController,
          uploaderDraftStore: _ShellDraftStore(),
          loadSocialConnections: () async => const [],
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(_referenceNavButton('Create post'));
    await tester.pumpAndSettle();
    final oldUploader = tester.widget<UploaderScreen>(
      find.byType(UploaderScreen),
    );
    oldUploader.onPublishFinished!();
    await tester.pumpAndSettle();
    expect(_referenceNav(), findsOneWidget);
    expect(tester.widget<IndexedStack>(find.byType(IndexedStack)).index, 0);

    await tester.tap(_referenceNavButton('Create post'));
    await tester.pumpAndSettle();
    oldUploader.onViewAnalytics!();
    await tester.pumpAndSettle();
    expect(find.byType(UploaderScreen), findsOneWidget);
    expect(_referenceNav(), findsNothing);
    final activeUploader = tester.widget<UploaderScreen>(
      find.byType(UploaderScreen),
    );
    activeUploader.onViewAnalytics!();
    await tester.pumpAndSettle();
    expect(_referenceNav(), findsOneWidget);
    expect(tester.widget<IndexedStack>(find.byType(IndexedStack)).index, 4);
    expect(find.byType(UploaderScreen, skipOffstage: false), findsNothing);
  });

  testWidgets('changing the signed-in owner closes the active composer',
      (tester) async {
    final languageController = _signInShell();
    await tester.pumpWidget(
      _shellApp(
        PostDeeShell(
          languageController: languageController,
          uploaderDraftStore: _ShellDraftStore(),
          loadSocialConnections: () async => const [],
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(_referenceNavButton('Create post'));
    await tester.pumpAndSettle();
    final oldUploader = tester.widget<UploaderScreen>(
      find.byType(UploaderScreen),
    );
    Navigator.of(tester.element(find.byType(UploaderScreen))).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: Text('Composer child route')),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Composer child route'), findsOneWidget);
    PostDeeAuthSessionStore.instance.signIn(
      const AuthSession(
        userId: 'different-shell-user',
        idToken: 'different-id-token',
        email: 'other@example.com',
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(UploaderScreen, skipOffstage: false), findsNothing);
    expect(find.text('Composer child route'), findsNothing);
    expect(_referenceNav(), findsOneWidget);
    oldUploader.onViewAnalytics!();
    await tester.pumpAndSettle();
    expect(tester.widget<IndexedStack>(find.byType(IndexedStack)).index, 0);
    expect(_referenceNav(), findsOneWidget);
  });

  for (final width in const [360.0, 393.0]) {
    for (final textScale in const [1.45, 2.0]) {
      testWidgets(
          'login actions fit ${width}dp with ${textScale}x accessibility text',
          (tester) async {
        SharedPreferences.setMockInitialValues({
          'postdee_onboarding_seen': true,
        });
        tester.view.physicalSize = Size(width, 852);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        final sessionStore = PostDeeAuthSessionStore.instance;
        final languageController = PostDeeLanguageController(
          initialLocale: const Locale('th'),
        );
        sessionStore.clear();
        addTearDown(sessionStore.clear);
        addTearDown(languageController.dispose);

        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.dark,
            locale: const Locale('th'),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(
                textScaler: TextScaler.linear(textScale),
              ),
              child: child!,
            ),
            localizationsDelegates: const [
              PostDeeLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            supportedLocales: PostDeeLocalizations.supportedLocales,
            home: PostDeeShell(languageController: languageController),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('เข้าสู่ระบบด้วย Google'), findsOneWidget);
        final googleButton = find.ancestor(
          of: find.byKey(const ValueKey('google-sign-in-logo')),
          matching: find.byType(FilledButton),
        );
        expect(tester.getSize(googleButton).height, greaterThanOrEqualTo(54));
        expect(tester.takeException(), isNull);

        final scrollable = find.byType(SingleChildScrollView);
        for (var attempt = 0; attempt < 8; attempt += 1) {
          await tester.drag(scrollable, const Offset(0, -260));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
        }
        expect(find.text('เข้าสู่ระบบด้วยอีเมล'), findsOneWidget);
      });
    }
  }

  testWidgets('requests notification permission only after tapping the bell',
      (tester) async {
    SharedPreferences.setMockInitialValues({'postdee_onboarding_seen': true});
    final sessionStore = PostDeeAuthSessionStore.instance;
    final languageController = PostDeeLanguageController(
      initialLocale: const Locale('en'),
    );
    final pushGateway = _FakePushMessagingGateway();
    sessionStore.signIn(
      const AuthSession(
        userId: 'firebase-user-shell',
        idToken: 'firebase-id-token',
        email: 'seller@example.com',
        displayName: 'PostDee Seller',
      ),
    );
    addTearDown(sessionStore.clear);
    addTearDown(languageController.dispose);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        locale: const Locale('en'),
        localizationsDelegates: const [
          PostDeeLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: PostDeeLocalizations.supportedLocales,
        home: PostDeeShell(
          languageController: languageController,
          pushMessagingGateway: pushGateway,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(pushGateway.initializeCalls, 0);
    await tester.tap(find.bySemanticsLabel('Notifications'));
    await tester.pumpAndSettle();
    expect(pushGateway.initializeCalls, 1);
    expect(find.text('การแจ้งเตือน'), findsOneWidget);
  });

  testWidgets('opens the email sign-in form from the login gate',
      (tester) async {
    SharedPreferences.setMockInitialValues({'postdee_onboarding_seen': true});

    final sessionStore = PostDeeAuthSessionStore.instance;
    final languageController = PostDeeLanguageController(
      initialLocale: const Locale('en'),
    );
    sessionStore.clear();
    addTearDown(sessionStore.clear);
    addTearDown(languageController.dispose);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        locale: const Locale('en'),
        localizationsDelegates: const [
          PostDeeLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: PostDeeLocalizations.supportedLocales,
        home: PostDeeShell(languageController: languageController),
      ),
    );
    await tester.pumpAndSettle();

    final brandMark = tester.widget<Image>(
      find.byKey(const ValueKey('login-brand-mark')),
    );
    expect(
      (brandMark.image as AssetImage).assetName,
      'assets/images/brand/postdee_mark.png',
    );
    expect(
      tester.getSize(find.byKey(const ValueKey('login-brand-mark-box'))),
      const Size.square(64),
    );
    expect(
      tester.getSize(find.byKey(const ValueKey('login-brand-gap'))).width,
      4,
    );

    await tester.tap(find.byKey(const ValueKey('login-email-sign-in')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('email-sign-in-form')), findsOneWidget);
  });

  testWidgets('uses docked bottom navigation in the approved tab order',
      (tester) async {
    final semantics = tester.ensureSemantics();
    SharedPreferences.setMockInitialValues({'postdee_onboarding_seen': true});
    tester.view.padding = const FakeViewPadding(bottom: 24);
    addTearDown(tester.view.resetPadding);

    final sessionStore = PostDeeAuthSessionStore.instance;
    final languageController = PostDeeLanguageController(
      initialLocale: const Locale('en'),
    );

    sessionStore.signIn(
      const AuthSession(
        userId: 'firebase-user-shell',
        idToken: 'firebase-id-token',
        email: 'seller@example.com',
        displayName: 'PostDee Seller',
      ),
    );
    addTearDown(sessionStore.clear);
    addTearDown(languageController.dispose);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        locale: const Locale('en'),
        localizationsDelegates: const [
          PostDeeLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: PostDeeLocalizations.supportedLocales,
        home: PostDeeShell(languageController: languageController),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(BottomNavigationBar), findsNothing);
    final referenceNav =
        find.byKey(const ValueKey('postdee-reference-bottom-nav'));
    expect(referenceNav, findsOneWidget);
    for (final label in [
      'Home',
      'Calendar',
      'Create post',
      'Store link',
      'Account'
    ]) {
      expect(
        find.descendant(
          of: referenceNav,
          matching: find.bySemanticsLabel(label),
        ),
        findsOneWidget,
      );
    }

    final homeX = tester.getCenter(_referenceNavButton('Home')).dx;
    final storeLinkX = tester.getCenter(_referenceNavButton('Store link')).dx;
    final createX = tester.getCenter(_referenceNavButton('Create post')).dx;
    final calendarX = tester.getCenter(_referenceNavButton('Calendar')).dx;
    final accountX = tester.getCenter(_referenceNavButton('Account')).dx;
    expect(homeX, lessThan(calendarX));
    expect(calendarX, lessThan(createX));
    expect(createX, lessThan(storeLinkX));
    expect(storeLinkX, lessThan(accountX));

    final createButton = _referenceNavButton('Create post');
    expect(
      find.descendant(of: referenceNav, matching: find.text('Create post')),
      findsNothing,
      reason: 'The center upload action is icon-only in the approved design.',
    );
    expect(
      tester
          .widget<Tooltip>(find.descendant(
            of: createButton,
            matching: find.byType(Tooltip),
          ))
          .message,
      'Create post',
      reason: 'The unlabeled action keeps its accessible name and tooltip.',
    );
    expect(
      find.descendant(
        of: createButton,
        matching: find.byIcon(Icons.ios_share_outlined),
      ),
      findsOneWidget,
      reason:
          'Create post starts by uploading a video, so use the upload icon.',
    );
    expect(
      find.ancestor(
        of: createButton,
        matching: find.byType(ClipRRect),
      ),
      findsNothing,
      reason: 'The circular create button must not be clipped by the nav.',
    );

    final navSurface = tester.widget<Material>(
      find.byKey(const ValueKey('postdee-nav-surface')),
    );
    expect(navSurface.color, AppTheme.navSurface);
    expect(navSurface.color!.a, 1);
    expect(navSurface.elevation, 0);
    final surfaceRect = tester.getRect(
      find.byKey(const ValueKey('postdee-nav-surface')),
    );
    final viewportSize =
        tester.view.physicalSize / tester.view.devicePixelRatio;
    final bottomSafeArea =
        tester.view.padding.bottom / tester.view.devicePixelRatio;
    expect(surfaceRect.left, 0);
    expect(surfaceRect.right, viewportSize.width);
    expect(surfaceRect.bottom, viewportSize.height);
    expect(
      tester.getBottomLeft(_referenceNavButton('Home')).dy,
      surfaceRect.bottom - bottomSafeArea,
      reason: 'The opaque surface fills the bottom safe area as well.',
    );
    final outerNav = tester.widget(referenceNav);
    if (outerNav is DecoratedBox && outerNav.decoration is BoxDecoration) {
      expect(
        (outerNav.decoration as BoxDecoration).boxShadow ?? const <BoxShadow>[],
        isEmpty,
      );
    }
    for (final decoratedBox in tester.widgetList<DecoratedBox>(
      find.descendant(of: referenceNav, matching: find.byType(DecoratedBox)),
    )) {
      if (decoratedBox.decoration case final BoxDecoration decoration) {
        expect(decoration.boxShadow ?? const <BoxShadow>[], isEmpty);
      }
    }
    expect(
      find.descendant(of: referenceNav, matching: find.byType(BackdropFilter)),
      findsNothing,
      reason: 'The approved bar has an opaque surface instead of blur.',
    );

    final createSurface = tester.widget<DecoratedBox>(
      find.byKey(const ValueKey('postdee-nav-create-surface')),
    );
    final createDecoration = createSurface.decoration as BoxDecoration;
    expect(createDecoration.shape, BoxShape.circle);
    expect(createDecoration.color, AppTheme.accent);
    expect(createDecoration.gradient, isNull);
    expect(createDecoration.boxShadow ?? const <BoxShadow>[], isEmpty);
    final navRect = tester.getRect(referenceNav);
    final createRect = tester.getRect(
      find.byKey(const ValueKey('postdee-nav-create-surface')),
    );
    expect(navRect.contains(createRect.topLeft), isTrue);
    expect(navRect.contains(createRect.bottomRight), isTrue);

    const tabIndices = {
      'Home': 0,
      'Calendar': 3,
      'Store link': 1,
      'Account': 5,
    };
    final selectedIndicator =
        find.byKey(const ValueKey('postdee-nav-selected-indicator'));
    for (final currentTab in tabIndices.entries) {
      await tester.tap(_referenceNavButton(currentTab.key));
      await tester.pumpAndSettle();

      expect(tester.widget<IndexedStack>(find.byType(IndexedStack)).index,
          currentTab.value);
      expect(selectedIndicator, findsOneWidget);
      for (final label in [...tabIndices.keys, 'Create post']) {
        final button = _referenceNavButton(label);
        expect(
          tester.getSemantics(button),
          isSemantics(
            label: label,
            isButton: true,
            hasTapAction: true,
            isSelected: label == currentTab.key,
            hasSelectedState: true,
          ),
        );
        expect(
          find.descendant(of: button, matching: selectedIndicator),
          label == currentTab.key ? findsOneWidget : findsNothing,
        );
      }
    }

    // Publishing can still open Analytics, which is not one of the five nav
    // destinations. It must not incorrectly mark another destination selected.
    await tester.tap(_referenceNavButton('Create post'));
    await tester.pumpAndSettle();
    expect(_referenceNav(), findsNothing);
    final uploader = tester.widget<UploaderScreen>(
      find.byType(UploaderScreen),
    );
    expect(uploader.onViewAnalytics, isNotNull);
    uploader.onViewAnalytics!();
    await tester.pumpAndSettle();
    expect(tester.widget<IndexedStack>(find.byType(IndexedStack)).index, 4);
    expect(_referenceNav(), findsOneWidget);
    expect(selectedIndicator, findsNothing);
    for (final label in [...tabIndices.keys, 'Create post']) {
      expect(
        tester.getSemantics(_referenceNavButton(label)),
        isSemantics(isSelected: false),
      );
    }
    await tester.tap(_referenceNavButton('Home'));
    await tester.pumpAndSettle();
    expect(tester.widget<IndexedStack>(find.byType(IndexedStack)).index, 0);
    expect(selectedIndicator, findsOneWidget);
    semantics.dispose();
  });

  testWidgets(
      'opens profile links from home and nav while keeping navigation visible',
      (tester) async {
    SharedPreferences.setMockInitialValues({'postdee_onboarding_seen': true});

    final sessionStore = PostDeeAuthSessionStore.instance;
    final languageController = PostDeeLanguageController(
      initialLocale: const Locale('en'),
    );

    sessionStore.signIn(
      const AuthSession(
        userId: 'firebase-user-shell',
        idToken: 'firebase-id-token',
        email: 'seller@example.com',
        displayName: 'PostDee Seller',
      ),
    );
    addTearDown(sessionStore.clear);
    addTearDown(languageController.dispose);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        locale: const Locale('en'),
        localizationsDelegates: const [
          PostDeeLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: PostDeeLocalizations.supportedLocales,
        home: PostDeeShell(languageController: languageController),
      ),
    );
    await tester.pumpAndSettle();

    expect(_referenceNav(), findsOneWidget);
    final linkShortcut =
        find.byKey(const ValueKey('home-link-in-bio-shortcut'));
    await tester.ensureVisible(linkShortcut);
    await tester.tap(linkShortcut);
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('link-in-bio-back')), findsOneWidget);
    expect(_referenceNav(), findsOneWidget);
    expect(
      find.byKey(const ValueKey('ai-advanced-toggle')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('ai-duration-slider')),
      findsNothing,
    );

    await tester.tap(find.byKey(const ValueKey('link-in-bio-back')));
    await tester.pumpAndSettle();

    expect(_referenceNav(), findsOneWidget);
    expect(find.byKey(const ValueKey('ai-editing-back')), findsNothing);
    expect(linkShortcut, findsOneWidget);
    await tester.tap(_referenceNavButton('Store link'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('link-in-bio-back')), findsOneWidget);
    await tester.tap(_referenceNavButton('Create post'));
    await tester.pumpAndSettle();
    expect(_referenceNav(), findsNothing);
    expect(find.byKey(const ValueKey('link-in-bio-back')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('uploader-close')));
    await tester.pumpAndSettle();
    expect(_referenceNav(), findsOneWidget);
    expect(find.byKey(const ValueKey('link-in-bio-back')), findsOneWidget);
  });

  testWidgets('opens profile from the reference bottom navigation',
      (tester) async {
    SharedPreferences.setMockInitialValues({'postdee_onboarding_seen': true});

    final sessionStore = PostDeeAuthSessionStore.instance;
    final languageController = PostDeeLanguageController(
      initialLocale: const Locale('en'),
    );

    sessionStore.signIn(
      const AuthSession(
        userId: 'firebase-user-shell',
        idToken: 'firebase-id-token',
        email: 'seller@example.com',
        displayName: 'PostDee Seller',
      ),
    );
    addTearDown(sessionStore.clear);
    addTearDown(languageController.dispose);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        locale: const Locale('en'),
        localizationsDelegates: const [
          PostDeeLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: PostDeeLocalizations.supportedLocales,
        home: PostDeeShell(languageController: languageController),
      ),
    );
    await tester.pumpAndSettle();

    expect(_referenceNavButton('Account'), findsOneWidget);
    await tester.tap(_referenceNavButton('Account'));
    await tester.pumpAndSettle();

    // Profile is now a tab, so its content shows with the nav still visible.
    expect(find.text('บัญชีและโปรไฟล์'), findsOneWidget);
    expect(find.text('PostDee Seller'), findsOneWidget);
    expect(_referenceNavButton('Account'), findsOneWidget);
  });

  testWidgets('deletes the account then returns to the login gate',
      (tester) async {
    SharedPreferences.setMockInitialValues({'postdee_onboarding_seen': true});
    const ownerDrafts = SharedPreferencesLinkInBioDraftStore(
      ownerUserId: 'firebase-user-shell',
    );
    const otherDrafts = SharedPreferencesLinkInBioDraftStore(
      ownerUserId: 'another-user',
    );
    await ownerDrafts.saveDraft(LinkInBioDraft.defaults());
    await otherDrafts.saveDraft(LinkInBioDraft.defaults());

    final sessionStore = PostDeeAuthSessionStore.instance;
    final languageController = PostDeeLanguageController(
      initialLocale: const Locale('en'),
    );
    var deleteCalls = 0;
    final deletionCalls = <String>[];

    sessionStore.signIn(
      const AuthSession(
        userId: 'firebase-user-shell',
        idToken: 'firebase-id-token',
        email: 'seller@example.com',
        displayName: 'PostDee Seller',
      ),
    );
    addTearDown(sessionStore.clear);
    addTearDown(languageController.dispose);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        locale: const Locale('en'),
        localizationsDelegates: const [
          PostDeeLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: PostDeeLocalizations.supportedLocales,
        home: PostDeeShell(
          languageController: languageController,
          checkAccountDeletionReady: () async {
            deletionCalls.add('ready');
            return false;
          },
          accountAccessRevoker: _RecordingAccountAccessRevoker(deletionCalls),
          deleteAccount: () async {
            deleteCalls += 1;
            deletionCalls.add('delete');
          },
          loadLocalPublishDraftDeleter: () async {
            deletionCalls.add('capture-local-drafts');
            return () async {
              deletionCalls.add('local-drafts');
            };
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(_referenceNavButton('Account'));
    await tester.pumpAndSettle();

    final deleteButton = find.widgetWithText(OutlinedButton, 'ลบบัญชี');
    await tester.scrollUntilVisible(
      deleteButton,
      400,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(deleteButton);
    await tester.pumpAndSettle();

    tester
        .widget<FilledButton>(
          find.widgetWithText(FilledButton, 'ลบบัญชีถาวร'),
        )
        .onPressed!();
    await tester.pumpAndSettle();

    expect(deleteCalls, 1);
    expect(await ownerDrafts.loadDraft(), isNull);
    expect(await otherDrafts.loadDraft(), isNotNull);
    expect(deletionCalls, [
      'capture-local-drafts',
      'ready',
      'revoke',
      'delete',
      'local-drafts',
    ]);
    // Back on the login gate after the account is removed.
    expect(find.text('Sign in to PostDee'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('postdee-undo-toast')),
      findsOneWidget,
    );
    final toastRect = tester.getRect(
      find.byKey(const ValueKey('postdee-undo-toast')),
    );
    final viewSize = tester.view.physicalSize / tester.view.devicePixelRatio;
    expect(toastRect.width, greaterThan(0));
    expect(toastRect.height, greaterThan(0));
    expect(toastRect.left, greaterThanOrEqualTo(0));
    expect(toastRect.top, greaterThanOrEqualTo(0));
    expect(toastRect.right, lessThanOrEqualTo(viewSize.width));
    expect(toastRect.bottom, lessThanOrEqualTo(viewSize.height));
    final toast = tester.widget<SnackBar>(
      find.byKey(const ValueKey('postdee-undo-toast')),
    );
    expect(toast.behavior, SnackBarBehavior.floating);
    expect(toast.action, isNull);
    expect(find.text('ลบบัญชีและออกจากระบบแล้ว'), findsOneWidget);
    expect(find.byIcon(Icons.check_circle_rounded), findsOneWidget);
    expect(find.text('เลิกทำ'), findsNothing);
  });

  testWidgets(
    'still signs out and warns when local draft cleanup cannot finish',
    (tester) async {
      SharedPreferences.setMockInitialValues({'postdee_onboarding_seen': true});

      final sessionStore = PostDeeAuthSessionStore.instance;
      final languageController = PostDeeLanguageController(
        initialLocale: const Locale('en'),
      );
      sessionStore.signIn(
        const AuthSession(
          userId: 'firebase-user-shell',
          idToken: 'firebase-id-token',
          email: 'seller@example.com',
          displayName: 'PostDee Seller',
        ),
      );
      addTearDown(sessionStore.clear);
      addTearDown(languageController.dispose);

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark,
          locale: const Locale('en'),
          localizationsDelegates: const [
            PostDeeLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: PostDeeLocalizations.supportedLocales,
          home: PostDeeShell(
            languageController: languageController,
            checkAccountDeletionReady: () async => true,
            deleteAccount: () async {},
            deleteLocalPublishDrafts: () async {
              throw const FileSystemException('disk unavailable');
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(_referenceNavButton('Account'));
      await tester.pumpAndSettle();
      final deleteButton = find.widgetWithText(OutlinedButton, 'ลบบัญชี');
      await tester.scrollUntilVisible(
        deleteButton,
        400,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await tester.tap(deleteButton);
      await tester.pumpAndSettle();
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'ลบบัญชีถาวร'),
          )
          .onPressed!();
      await tester.pumpAndSettle();

      expect(find.text('Sign in to PostDee'), findsOneWidget);
      expect(
        find.text(
          'ลบบัญชีแล้ว แต่ลบร่างในเครื่องไม่ครบ กรุณาล้างข้อมูลแอป',
        ),
        findsOneWidget,
      );
    },
  );

  testWidgets('retries deletion without revoking Apple when identity is gone',
      (tester) async {
    SharedPreferences.setMockInitialValues({'postdee_onboarding_seen': true});
    final sessionStore = PostDeeAuthSessionStore.instance;
    final languageController = PostDeeLanguageController(
      initialLocale: const Locale('en'),
    );
    final deletionCalls = <String>[];
    sessionStore.signIn(
      const AuthSession(
        userId: 'firebase-user-shell',
        idToken: 'firebase-id-token',
        email: 'seller@example.com',
      ),
    );
    addTearDown(sessionStore.clear);
    addTearDown(languageController.dispose);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        locale: const Locale('en'),
        localizationsDelegates: const [
          PostDeeLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: PostDeeLocalizations.supportedLocales,
        home: PostDeeShell(
          languageController: languageController,
          checkAccountDeletionReady: () async {
            deletionCalls.add('ready');
            return true;
          },
          accountAccessRevoker: _RecordingAccountAccessRevoker(deletionCalls),
          deleteAccount: () async => deletionCalls.add('delete'),
          deleteLocalPublishDrafts: () async {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(_referenceNavButton('Account'));
    await tester.pumpAndSettle();
    final deleteButton = find.widgetWithText(OutlinedButton, 'ลบบัญชี');
    await tester.scrollUntilVisible(
      deleteButton,
      400,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(deleteButton);
    await tester.pumpAndSettle();
    tester
        .widget<FilledButton>(
          find.widgetWithText(FilledButton, 'ลบบัญชีถาวร'),
        )
        .onPressed!();
    await tester.pumpAndSettle();

    expect(deletionCalls, ['ready', 'delete']);
    expect(find.text('Sign in to PostDee'), findsOneWidget);
  });

  testWidgets('does not revoke Apple access when deletion preflight fails',
      (tester) async {
    SharedPreferences.setMockInitialValues({'postdee_onboarding_seen': true});
    final sessionStore = PostDeeAuthSessionStore.instance;
    final languageController = PostDeeLanguageController(
      initialLocale: const Locale('en'),
    );
    final deletionCalls = <String>[];
    sessionStore.signIn(
      const AuthSession(
        userId: 'firebase-user-shell',
        idToken: 'firebase-id-token',
        email: 'seller@example.com',
      ),
    );
    addTearDown(sessionStore.clear);
    addTearDown(languageController.dispose);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        locale: const Locale('en'),
        localizationsDelegates: const [
          PostDeeLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: PostDeeLocalizations.supportedLocales,
        home: PostDeeShell(
          languageController: languageController,
          checkAccountDeletionReady: () async {
            deletionCalls.add('ready');
            throw const ApiException(
              'unavailable',
              statusCode: 503,
              code: 'ACCOUNT_DELETION_UNAVAILABLE',
            );
          },
          accountAccessRevoker: _RecordingAccountAccessRevoker(deletionCalls),
          deleteAccount: () async => deletionCalls.add('delete'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(_referenceNavButton('Account'));
    await tester.pumpAndSettle();
    final deleteButton = find.widgetWithText(OutlinedButton, 'ลบบัญชี');
    await tester.scrollUntilVisible(
      deleteButton,
      400,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(deleteButton);
    await tester.pumpAndSettle();
    tester
        .widget<FilledButton>(
          find.widgetWithText(FilledButton, 'ลบบัญชีถาวร'),
        )
        .onPressed!();
    await tester.pumpAndSettle();

    expect(deletionCalls, ['ready']);
    expect(sessionStore.session.isSignedIn, isTrue);
    expect(find.text('ระบบลบบัญชียังไม่พร้อม กรุณาลองใหม่ภายหลัง'),
        findsOneWidget);
  });

  testWidgets('explains how to reauthenticate before retrying deletion',
      (tester) async {
    SharedPreferences.setMockInitialValues({'postdee_onboarding_seen': true});
    final sessionStore = PostDeeAuthSessionStore.instance;
    final languageController = PostDeeLanguageController(
      initialLocale: const Locale('en'),
    );
    sessionStore.signIn(
      const AuthSession(
        userId: 'firebase-user-shell',
        idToken: 'firebase-id-token',
        email: 'seller@example.com',
      ),
    );
    addTearDown(sessionStore.clear);
    addTearDown(languageController.dispose);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        locale: const Locale('en'),
        localizationsDelegates: const [
          PostDeeLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: PostDeeLocalizations.supportedLocales,
        home: PostDeeShell(
          languageController: languageController,
          checkAccountDeletionReady: () async => false,
          accountAccessRevoker: _RecordingAccountAccessRevoker(<String>[]),
          deleteAccount: () async => throw const ApiException(
            'reauthentication required',
            statusCode: 401,
            code: 'ACCOUNT_REAUTHENTICATION_REQUIRED',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(_referenceNavButton('Account'));
    await tester.pumpAndSettle();
    final deleteButton = find.widgetWithText(OutlinedButton, 'ลบบัญชี');
    await tester.scrollUntilVisible(
      deleteButton,
      400,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(deleteButton);
    await tester.pumpAndSettle();
    tester
        .widget<FilledButton>(
          find.widgetWithText(FilledButton, 'ลบบัญชีถาวร'),
        )
        .onPressed!();
    await tester.pumpAndSettle();

    expect(
      find.text(
        'กรุณาออกจากระบบแล้วเข้าสู่ระบบใหม่ จากนั้นลบบัญชีภายใน 5 นาที',
      ),
      findsOneWidget,
    );
    expect(sessionStore.session.isSignedIn, isTrue);
  });

  testWidgets('keeps reference bottom nav buttons touch-friendly',
      (tester) async {
    SharedPreferences.setMockInitialValues({'postdee_onboarding_seen': true});

    final sessionStore = PostDeeAuthSessionStore.instance;
    final languageController = PostDeeLanguageController(
      initialLocale: const Locale('en'),
    );

    sessionStore.signIn(
      const AuthSession(
        userId: 'firebase-user-shell',
        idToken: 'firebase-id-token',
        email: 'seller@example.com',
        displayName: 'PostDee Seller',
      ),
    );
    addTearDown(sessionStore.clear);
    addTearDown(languageController.dispose);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        locale: const Locale('en'),
        localizationsDelegates: const [
          PostDeeLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: PostDeeLocalizations.supportedLocales,
        home: PostDeeShell(languageController: languageController),
      ),
    );
    await tester.pumpAndSettle();

    final homeSize = tester.getSize(_referenceNavButton('Home'));
    final createSize = tester.getSize(_referenceNavButton('Create post'));
    final profileSize = tester.getSize(_referenceNavButton('Account'));

    expect(homeSize.width, greaterThanOrEqualTo(44));
    expect(homeSize.height, greaterThanOrEqualTo(44));
    expect(createSize.width, greaterThanOrEqualTo(44));
    expect(createSize.height, greaterThanOrEqualTo(44));
    expect(profileSize.width, greaterThanOrEqualTo(44));
    expect(profileSize.height, greaterThanOrEqualTo(44));
  });

  for (final width in const [360.0, 393.0, 411.0]) {
    for (final textScale in const [1.45, 2.0]) {
      testWidgets(
          'shows Thai bottom nav labels at ${width}dp with ${textScale}x text',
          (tester) async {
        SharedPreferences.setMockInitialValues({
          'postdee_onboarding_seen': true,
        });
        tester.view.physicalSize = Size(width, 852);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        final sessionStore = PostDeeAuthSessionStore.instance;
        final languageController = PostDeeLanguageController(
          initialLocale: const Locale('th'),
        );
        sessionStore.signIn(
          const AuthSession(
            userId: 'firebase-user-shell',
            idToken: 'firebase-id-token',
            email: 'seller@example.com',
            displayName: 'PostDee Seller',
          ),
        );
        addTearDown(sessionStore.clear);
        addTearDown(languageController.dispose);

        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.dark,
            locale: const Locale('th'),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(
                textScaler: TextScaler.linear(textScale),
              ),
              child: child!,
            ),
            localizationsDelegates: const [
              PostDeeLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            supportedLocales: PostDeeLocalizations.supportedLocales,
            home: PostDeeShell(languageController: languageController),
          ),
        );
        await tester.pumpAndSettle();

        final navRect = tester.getRect(_referenceNav());
        for (final label in const [
          'หน้าหลัก',
          'ปฏิทิน',
          'สร้างโพสต์',
          'ลิงก์ร้าน',
          'บัญชี',
        ]) {
          final button = _referenceNavButton(label);
          expect(button, findsOneWidget);
          final buttonRect = tester.getRect(button);
          expect(buttonRect.width, greaterThanOrEqualTo(44));
          expect(buttonRect.height, greaterThanOrEqualTo(44));
          final visibleLabel = find.descendant(
            of: _referenceNav(),
            matching: find.text(label),
          );
          if (label == 'สร้างโพสต์') {
            expect(visibleLabel, findsNothing);
            continue;
          }
          expect(visibleLabel, findsOneWidget);
          final labelRect = tester.getRect(visibleLabel);
          expect(labelRect.left, greaterThanOrEqualTo(navRect.left));
          expect(labelRect.right, lessThanOrEqualTo(navRect.right));
          expect(labelRect.top, greaterThanOrEqualTo(navRect.top));
          expect(labelRect.bottom, lessThanOrEqualTo(navRect.bottom));
          expect(labelRect.left, greaterThanOrEqualTo(buttonRect.left));
          expect(labelRect.right, lessThanOrEqualTo(buttonRect.right));
        }
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('opens and refreshes calendar after a scheduled post succeeds',
      (tester) async {
    SharedPreferences.setMockInitialValues({'postdee_onboarding_seen': true});

    final sessionStore = PostDeeAuthSessionStore.instance;
    final languageController = PostDeeLanguageController(
      initialLocale: const Locale('en'),
    );
    var calendarLoadCount = 0;
    CreatePostRequest? createdPostRequest;
    var scheduledPosts = <ScheduledPostResult>[];
    final tempDirectory = Directory.systemTemp.createTempSync(
      'postdee-shell-upload-',
    );
    addTearDown(() => tempDirectory.deleteSync(recursive: true));
    final videoFile = File(
      '${tempDirectory.path}${Platform.pathSeparator}scheduled-shell.mp4',
    )..writeAsBytesSync([1, 2, 3, 4]);

    sessionStore.signIn(
      const AuthSession(
        userId: 'firebase-user-shell',
        idToken: 'firebase-id-token',
        email: 'seller@example.com',
        displayName: 'PostDee Seller',
      ),
    );
    addTearDown(sessionStore.clear);
    addTearDown(languageController.dispose);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        locale: const Locale('en'),
        localizationsDelegates: const [
          PostDeeLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: PostDeeLocalizations.supportedLocales,
        home: PostDeeShell(
          languageController: languageController,
          loadSocialConnections: () async => const [
            SocialConnectionResult(
              platform: 'TIKTOK',
              connected: true,
              externalAccountId: 'tiktok-seller',
            ),
          ],
          loadSubscription: () async => const SubscriptionStatusResult(
            userId: 'seller-pro',
            plan: 'PRO',
            status: 'ACTIVE',
            phoneVerified: true,
            requiresPhoneVerification: false,
            canUseFreePostQuota: false,
            canSchedule: true,
            canUseAiCaptions: true,
            canUseAnalytics: true,
          ),
          pickVideo: () async => PickedVideoFile(
            name: 'scheduled-shell.mp4',
            path: videoFile.path,
            sizeBytes: videoFile.lengthSync(),
            width: 1080,
            height: 1920,
          ),
          createUpload: (_) async => const UploadResult(
            id: 'upload-1',
            videoS3Key: 'uploads/scheduled-shell.mp4',
            storageProvider: 'mock',
          ),
          uploadVideoFile: (_, __) async {},
          checkPublishingReadiness: () async {},
          createPost: (request) async {
            createdPostRequest = request;
            scheduledPosts = [
              ScheduledPostResult(
                id: 'post-shell',
                caption: 'Scheduled shell clip',
                videoS3Key: request.videoS3Key,
                platforms: request.platforms,
                scheduledAt: request.scheduledAt!,
                status: 'QUEUED',
                createdAt: DateTime(2026, 6, 1),
              ),
            ];

            return QueuedPostResult(
              id: 'post-shell',
              videoS3Key: request.videoS3Key,
              platforms: request.platforms,
              status: 'QUEUED',
            );
          },
          uploaderDraftStore: _ShellDraftStore(),
          loadScheduledPosts: () async {
            calendarLoadCount += 1;
            return scheduledPosts;
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(_referenceNavButton('Create post'));
    await tester.pumpAndSettle();
    final pickVideoButton =
        find.byKey(const ValueKey('uploader-video-preview-picker'));
    await tester.ensureVisible(pickVideoButton);
    await tester.pumpAndSettle();
    await tester.tap(pickVideoButton);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('uploader-wizard-next')));
    await tester.pumpAndSettle();
    final captionField = find.byKey(const ValueKey('uploader-caption-field'));
    await tester.enterText(captionField, 'Scheduled shell clip');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('uploader-wizard-next')));
    await tester.pumpAndSettle();

    final selectAll =
        find.byKey(const ValueKey('uploader-select-all-platforms'));
    await tester.scrollUntilVisible(
      selectAll,
      500,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(selectAll);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('uploader-wizard-next')));
    await tester.pumpAndSettle();

    final scheduleButton =
        find.byKey(const ValueKey('uploader-schedule-later'));
    await tester.scrollUntilVisible(
      scheduleButton,
      500,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(scheduleButton);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('publish-review-confirm')));
    await tester.pumpAndSettle();

    expect(createdPostRequest?.scheduledAt, isNotNull);
    expect(find.text('จัดคิวส่งตามเวลาแล้ว'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('publish-flow-finish')));
    await tester.pumpAndSettle();
    await tester.tap(_referenceNavButton('Calendar'));
    await tester.pumpAndSettle();

    expect(calendarLoadCount, greaterThanOrEqualTo(2));
    expect(find.text('Scheduled shell clip'), findsOneWidget);
  });

  testWidgets('refreshes calendar whenever the user returns to its tab',
      (tester) async {
    SharedPreferences.setMockInitialValues({'postdee_onboarding_seen': true});

    final sessionStore = PostDeeAuthSessionStore.instance;
    final languageController = PostDeeLanguageController(
      initialLocale: const Locale('en'),
    );
    var calendarLoadCount = 0;

    sessionStore.signIn(
      const AuthSession(
        userId: 'firebase-user-shell',
        idToken: 'firebase-id-token',
        email: 'seller@example.com',
        displayName: 'PostDee Seller',
      ),
    );
    addTearDown(sessionStore.clear);
    addTearDown(languageController.dispose);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        locale: const Locale('en'),
        localizationsDelegates: const [
          PostDeeLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: PostDeeLocalizations.supportedLocales,
        home: PostDeeShell(
          languageController: languageController,
          loadScheduledPosts: () async {
            calendarLoadCount += 1;
            return const [];
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    // IndexedStack creates the calendar up front, but an inactive tab should
    // not call the API until the user actually opens it.
    expect(calendarLoadCount, 0);

    await tester.tap(_referenceNavButton('Calendar'));
    await tester.pumpAndSettle();
    expect(calendarLoadCount, 1);

    await tester.tap(_referenceNavButton('Home'));
    await tester.pumpAndSettle();
    await tester.tap(_referenceNavButton('Calendar'));
    await tester.pumpAndSettle();
    expect(calendarLoadCount, 2);
  });

  testWidgets('opens published calendar posts in the detail screen',
      (tester) async {
    SharedPreferences.setMockInitialValues({'postdee_onboarding_seen': true});

    final sessionStore = PostDeeAuthSessionStore.instance;
    final languageController = PostDeeLanguageController(
      initialLocale: const Locale('en'),
    );

    sessionStore.signIn(
      const AuthSession(
        userId: 'firebase-user-shell',
        idToken: 'firebase-id-token',
        email: 'seller@example.com',
        displayName: 'PostDee Seller',
      ),
    );
    addTearDown(sessionStore.clear);
    addTearDown(languageController.dispose);

    final publishedAt = DateTime(2026, 7, 16, 19, 25);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        locale: const Locale('en'),
        localizationsDelegates: const [
          PostDeeLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: PostDeeLocalizations.supportedLocales,
        home: PostDeeShell(
          languageController: languageController,
          loadScheduledPosts: () async => [
            ScheduledPostResult(
              id: 'published-calendar-post',
              caption: 'Published calendar clip',
              videoS3Key: 'uploads/published.mp4',
              platforms: const ['YOUTUBE_SHORTS'],
              scheduledAt: publishedAt,
              publishedAt: publishedAt,
              status: 'PUBLISHED',
              createdAt: publishedAt.subtract(const Duration(minutes: 10)),
              platformResults: [
                PostPlatformResult(
                  postId: 'published-calendar-post',
                  platform: 'YOUTUBE_SHORTS',
                  status: 'PUBLISHED',
                  externalPostId: 'https://youtube.example/private-video',
                  publishedAt: publishedAt,
                ),
              ],
            ),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(_referenceNavButton('Calendar'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Published calendar clip'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Published calendar clip'));
    await tester.pumpAndSettle();

    expect(find.text('รายละเอียดโพสต์'), findsOneWidget);
    expect(find.text('เผยแพร่สำเร็จ'), findsOneWidget);
  });

  testWidgets('refreshes latest home posts whenever the user returns home',
      (tester) async {
    SharedPreferences.setMockInitialValues({'postdee_onboarding_seen': true});

    final sessionStore = PostDeeAuthSessionStore.instance;
    final languageController = PostDeeLanguageController(
      initialLocale: const Locale('en'),
    );
    var recentPostsLoadCount = 0;

    sessionStore.signIn(
      const AuthSession(
        userId: 'firebase-user-shell',
        idToken: 'firebase-id-token',
        email: 'seller@example.com',
        displayName: 'PostDee Seller',
      ),
    );
    addTearDown(sessionStore.clear);
    addTearDown(languageController.dispose);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        locale: const Locale('en'),
        localizationsDelegates: const [
          PostDeeLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: PostDeeLocalizations.supportedLocales,
        home: PostDeeShell(
          languageController: languageController,
          loadRecentPosts: () async {
            recentPostsLoadCount += 1;
            return const [];
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(recentPostsLoadCount, 1);

    await tester.tap(_referenceNavButton('Calendar'));
    await tester.pumpAndSettle();
    expect(recentPostsLoadCount, 1);

    await tester.tap(_referenceNavButton('Home'));
    await tester.pumpAndSettle();
    expect(recentPostsLoadCount, 2);
  });

  testWidgets('shows first-run onboarding once, then goes to home',
      (tester) async {
    SharedPreferences.setMockInitialValues({});

    final sessionStore = PostDeeAuthSessionStore.instance;
    final languageController = PostDeeLanguageController(
      initialLocale: const Locale('en'),
    );

    sessionStore.signIn(
      const AuthSession(
        userId: 'firebase-user-shell',
        idToken: 'firebase-id-token',
        email: 'seller@example.com',
        displayName: 'PostDee Seller',
      ),
    );
    addTearDown(sessionStore.clear);
    addTearDown(languageController.dispose);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        locale: const Locale('en'),
        localizationsDelegates: const [
          PostDeeLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: PostDeeLocalizations.supportedLocales,
        home: PostDeeShell(languageController: languageController),
      ),
    );
    await tester.pumpAndSettle();

    // First run: the three-step intro shows before the main shell.
    expect(find.text('เชื่อมช่องทางครั้งเดียว'), findsOneWidget);
    expect(_referenceNav(), findsNothing);

    await tester.tap(find.byKey(const ValueKey('onboarding-next')));
    await tester.pumpAndSettle();
    expect(find.text('คลิปเดียว โพสต์ได้ทุกที่'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('onboarding-next')));
    await tester.pumpAndSettle();
    expect(find.text('ตั้งเวลา + ดูยอดที่เดียว'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('onboarding-next')));
    await tester.pumpAndSettle();

    // "เริ่มใช้งาน" lands on the main shell and persists the seen flag.
    expect(_referenceNav(), findsOneWidget);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('postdee_onboarding_seen'), isTrue);
  });
}

class _RecordingAccountAccessRevoker implements AccountAccessRevoker {
  _RecordingAccountAccessRevoker(this.calls);

  final List<String> calls;

  @override
  Future<void> revokeBeforeAccountDeletion() async {
    calls.add('revoke');
  }
}

class _FakePushMessagingGateway implements PushMessagingGateway {
  int initializeCalls = 0;

  @override
  Future<void> initialize() async => initializeCalls += 1;

  @override
  Future<void> dispose() async {}
}
