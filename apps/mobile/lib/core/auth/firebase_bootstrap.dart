import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

import '../config/app_config.dart';
import 'firebase_web_options.dart';

typedef FirebaseInitializedAppsChecker = bool Function();
typedef FirebaseAppInitializer = Future<void> Function();

class FirebaseBootstrapResult {
  const FirebaseBootstrapResult._({
    required this.isEnabled,
    required this.isInitialized,
    this.errorMessage,
  });

  const FirebaseBootstrapResult.setupError(String message)
      : this._(
          isEnabled: true,
          isInitialized: false,
          errorMessage: message,
        );

  static const disabled = FirebaseBootstrapResult._(
    isEnabled: false,
    isInitialized: false,
  );

  static const initialized = FirebaseBootstrapResult._(
    isEnabled: true,
    isInitialized: true,
  );

  final bool isEnabled;
  final bool isInitialized;
  final String? errorMessage;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FirebaseBootstrapResult &&
          isEnabled == other.isEnabled &&
          isInitialized == other.isInitialized &&
          errorMessage == other.errorMessage;

  @override
  int get hashCode => Object.hash(isEnabled, isInitialized, errorMessage);
}

String? describeFirebaseAuthSetup({
  bool enableFirebaseAuth = AppConfig.enableFirebaseAuth,
  bool allowLocalMockAuth = AppConfig.allowLocalMockAuth,
  FirebaseBootstrapResult? firebaseBootstrapResult,
}) {
  if (!enableFirebaseAuth) {
    return allowLocalMockAuth
        ? 'Local mock auth is active. Enable Firebase Auth after project files are ready.'
        : 'Firebase Auth is disabled. Enable Firebase Auth for sign-in.';
  }

  final result = firebaseBootstrapResult ?? FirebaseBootstrapResult.initialized;

  if (!result.isInitialized) {
    return result.errorMessage ??
        'Firebase Auth is enabled but not initialized.';
  }

  return null;
}

Future<FirebaseBootstrapResult> initializeFirebaseForPostDee({
  bool enableFirebaseAuth = AppConfig.enableFirebaseAuth,
  FirebaseInitializedAppsChecker? hasInitializedApps,
  FirebaseAppInitializer? initializeApp,
}) async {
  if (!enableFirebaseAuth) {
    return FirebaseBootstrapResult.disabled;
  }

  final hasApps = hasInitializedApps ?? () => Firebase.apps.isNotEmpty;

  if (hasApps()) {
    return FirebaseBootstrapResult.initialized;
  }

  try {
    await (initializeApp ?? _initializeFirebaseApp)();
    return FirebaseBootstrapResult.initialized;
  } catch (error) {
    return FirebaseBootstrapResult.setupError(
      'Firebase Auth is enabled but Firebase is not configured. '
      'Add Android, iOS, or Web Firebase configuration for the active platform, '
      'then test Google Sign-In on a real device. Original error: $error',
    );
  }
}

Future<void> _initializeFirebaseApp() async {
  await Firebase.initializeApp(
    options: kIsWeb ? PostDeeFirebaseWebOptions.currentPlatform : null,
  );
}
