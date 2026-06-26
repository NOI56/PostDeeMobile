import 'package:flutter_test/flutter_test.dart';
import 'package:postdee_mobile/core/auth/firebase_bootstrap.dart';

void main() {
  test('describes local mock auth mode when Firebase auth is disabled', () {
    expect(
      describeFirebaseAuthSetup(
        enableFirebaseAuth: false,
        allowLocalMockAuth: true,
      ),
      'Local mock auth is active. Enable Firebase Auth after project files are ready.',
    );
  });

  test('describes disabled Firebase auth when local mock auth is blocked', () {
    expect(
      describeFirebaseAuthSetup(
        enableFirebaseAuth: false,
        allowLocalMockAuth: false,
      ),
      'Firebase Auth is disabled. Enable Firebase Auth for sign-in.',
    );
  });

  test('describes Firebase setup errors when Firebase auth is enabled', () {
    expect(
      describeFirebaseAuthSetup(
        enableFirebaseAuth: true,
        firebaseBootstrapResult: const FirebaseBootstrapResult.setupError(
          'Missing Firebase project files',
        ),
      ),
      'Missing Firebase project files',
    );
  });

  test('skips Firebase initialization when Firebase auth is disabled',
      () async {
    var initializeCalls = 0;

    final result = await initializeFirebaseForPostDee(
      enableFirebaseAuth: false,
      hasInitializedApps: () => false,
      initializeApp: () async {
        initializeCalls += 1;
      },
    );

    expect(initializeCalls, 0);
    expect(result, FirebaseBootstrapResult.disabled);
  });

  test('initializes Firebase when Firebase auth is enabled and no app exists',
      () async {
    var initializeCalls = 0;

    final result = await initializeFirebaseForPostDee(
      enableFirebaseAuth: true,
      hasInitializedApps: () => false,
      initializeApp: () async {
        initializeCalls += 1;
      },
    );

    expect(initializeCalls, 1);
    expect(result, FirebaseBootstrapResult.initialized);
  });

  test(
      'returns a setup error instead of throwing when Firebase initialization fails',
      () async {
    final result = await initializeFirebaseForPostDee(
      enableFirebaseAuth: true,
      hasInitializedApps: () => false,
      initializeApp: () async {
        throw Exception('missing google-services.json');
      },
    );

    expect(result.isEnabled, isTrue);
    expect(result.isInitialized, isFalse);
    expect(result.errorMessage, contains('Firebase Auth is enabled'));
    expect(result.errorMessage, contains('google-services.json'));
  });
}
