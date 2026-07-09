import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';

import 'app.dart';
import 'core/auth/firebase_bootstrap.dart';
import 'core/config/app_config.dart';
import 'core/monitoring/postdee_firebase_monitoring.dart';
import 'core/theme/theme_controller.dart';
import 'features/auth/firebase_session_restorer.dart';

/// Handles push messages that arrive while the app is in the background or
/// terminated. Runs in its own isolate, so it stays minimal: the OS shows the
/// notification and the in-app list refreshes from FCM when the app reopens.
@pragma('vm:entry-point')
Future<void> postDeeFirebaseMessagingBackgroundHandler(
  RemoteMessage message,
) async {}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await PostDeeThemeController.instance.loadSavedThemeMode();
  final firebaseBootstrapResult = await initializeFirebaseForPostDee();
  await configurePostDeeFirebaseMonitoring(
    firebaseBootstrapResult: firebaseBootstrapResult,
  );

  // Register the FCM background handler only once Firebase is really set up, so
  // default (Firebase-off) builds are unaffected.
  if (AppConfig.enableFirebaseAuth && firebaseBootstrapResult.isInitialized) {
    FirebaseMessaging.onBackgroundMessage(
      postDeeFirebaseMessagingBackgroundHandler,
    );
    // Restore the persisted Firebase session so a returning user skips the login
    // gate instead of having to sign in again on every launch.
    await restoreFirebaseSession();
  }

  runApp(
    PostDeeApp(
      firebaseBootstrapResult: firebaseBootstrapResult,
      showSplash: true,
    ),
  );
}
