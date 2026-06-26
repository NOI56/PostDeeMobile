import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postdee_mobile/core/auth/auth_session.dart';
import 'package:postdee_mobile/core/localization/language_controller.dart';
import 'package:postdee_mobile/core/localization/postdee_localizations.dart';
import 'package:postdee_mobile/core/network/postdee_api_client.dart';
import 'package:postdee_mobile/core/theme/app_theme.dart';
import 'package:postdee_mobile/features/shell/postdee_shell.dart';
import 'package:postdee_mobile/features/uploader/video_picker_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('orders bottom navigation with Edit before Upload',
      (tester) async {
    SharedPreferences.setMockInitialValues({});

    final sessionStore = PostDeeAuthSessionStore.instance;
    final languageController = PostDeeLanguageController(
      initialLocale: const Locale('en'),
    );

    sessionStore.signIn(
      const AuthSession(
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

    final bottomNav = tester.widget<BottomNavigationBar>(
      find.byType(BottomNavigationBar),
    );

    expect(
      bottomNav.items.map((item) => item.label).toList(),
      ['Home', 'Edit', 'Upload', 'Calendar', 'Analytics'],
    );
  });

  testWidgets('keeps the profile action available on every shell tab',
      (tester) async {
    SharedPreferences.setMockInitialValues({});

    final sessionStore = PostDeeAuthSessionStore.instance;
    final languageController = PostDeeLanguageController(
      initialLocale: const Locale('en'),
    );

    sessionStore.signIn(
      const AuthSession(
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

    final bottomNav = find.byType(BottomNavigationBar);
    const tabLabels = ['Home', 'Edit', 'Upload', 'Calendar', 'Analytics'];

    for (final label in tabLabels) {
      await tester.tap(
        find.descendant(of: bottomNav, matching: find.text(label)),
      );
      await tester.pumpAndSettle();

      expect(
        find.bySemanticsLabel('User account'),
        findsOneWidget,
        reason: 'The profile action should be visible on the $label tab.',
      );
    }

    await tester.tap(find.bySemanticsLabel('User account'));
    await tester.pumpAndSettle();

    expect(find.text('Profile'), findsOneWidget);
    expect(find.text('PostDee Seller'), findsOneWidget);
  });

  testWidgets('deletes the account then returns to the login gate',
      (tester) async {
    SharedPreferences.setMockInitialValues({});

    final sessionStore = PostDeeAuthSessionStore.instance;
    final languageController = PostDeeLanguageController(
      initialLocale: const Locale('en'),
    );
    var deleteCalls = 0;

    sessionStore.signIn(
      const AuthSession(
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
          deleteAccount: () async {
            deleteCalls += 1;
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.bySemanticsLabel('User account'));
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

    await tester.tap(find.text('ลบบัญชีถาวร'));
    await tester.pumpAndSettle();

    expect(deleteCalls, 1);
    // Back on the login gate after the account is removed.
    expect(find.text('Sign in to PostDee'), findsOneWidget);
  });

  testWidgets('keeps home header icon buttons the same size', (tester) async {
    SharedPreferences.setMockInitialValues({});

    final sessionStore = PostDeeAuthSessionStore.instance;
    final languageController = PostDeeLanguageController(
      initialLocale: const Locale('en'),
    );

    sessionStore.signIn(
      const AuthSession(
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

    final notificationsSize =
        tester.getSize(find.bySemanticsLabel('Notifications'));
    final accountSize = tester.getSize(find.bySemanticsLabel('User account'));

    expect(notificationsSize, accountSize);
    expect(accountSize.width, greaterThanOrEqualTo(44));
    expect(accountSize.height, greaterThanOrEqualTo(44));
  });

  testWidgets('opens and refreshes calendar after a scheduled post succeeds',
      (tester) async {
    SharedPreferences.setMockInitialValues({});

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
          loadScheduledPosts: () async {
            calendarLoadCount += 1;
            return scheduledPosts;
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    final bottomNav = find.byType(BottomNavigationBar);
    await tester.tap(
      find.descendant(of: bottomNav, matching: find.text('Upload')),
    );
    await tester.pumpAndSettle();
    final pickVideoButton =
        find.byKey(const ValueKey('uploader-video-preview-picker'));
    await tester.ensureVisible(pickVideoButton);
    await tester.pumpAndSettle();
    await tester.tap(pickVideoButton);
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

    final captionField = find.byKey(const ValueKey('uploader-caption-field'));
    await tester.scrollUntilVisible(
      captionField,
      500,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.enterText(captionField, 'Scheduled shell clip');
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('uploader-sticky-post-button')));
    await tester.pumpAndSettle();

    expect(createdPostRequest?.scheduledAt, isNotNull);
    expect(calendarLoadCount, greaterThanOrEqualTo(2));
    expect(find.text('Scheduled shell clip'), findsOneWidget);
  });
}
