import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postdee_mobile/core/auth/firebase_bootstrap.dart';
import 'package:postdee_mobile/core/monitoring/postdee_analytics.dart';
import 'package:postdee_mobile/core/monitoring/postdee_firebase_monitoring.dart';

void main() {
  test('keeps monitoring disabled when Firebase is unavailable', () async {
    final analyticsEvents = <RecordedAnalyticsEvent>[];
    final crashEvents = <Object>[];
    FlutterExceptionHandler? flutterErrorHandler;
    bool Function(Object, StackTrace)? platformErrorHandler;
    final analytics = PostDeeAnalytics(
      isEnabled: true,
      logEvent: (event) async => analyticsEvents.add(event),
    );

    await configurePostDeeFirebaseMonitoring(
      enableFirebaseAuth: true,
      firebaseBootstrapResult:
          const FirebaseBootstrapResult.setupError('missing config'),
      analytics: analytics,
      logAnalyticsEvent: (event) async => analyticsEvents.add(event),
      recordCrashError: (error, stackTrace, {required fatal}) async {
        crashEvents.add(error);
      },
      setCrashCollectionEnabled: (_) async {},
      presentFlutterError: (_) {},
      setFlutterErrorHandler: (handler) => flutterErrorHandler = handler,
      setPlatformErrorHandler: (handler) => platformErrorHandler = handler,
    );

    await analytics.logSignInStarted('google');

    expect(analytics.isEnabled, isFalse);
    expect(analyticsEvents, isEmpty);
    expect(crashEvents, isEmpty);
    expect(flutterErrorHandler, isNull);
    expect(platformErrorHandler, isNull);
  });

  test('enables analytics and crash handlers after Firebase initializes',
      () async {
    final analyticsEvents = <RecordedAnalyticsEvent>[];
    final crashEvents = <({Object error, bool fatal})>[];
    FlutterExceptionHandler? flutterErrorHandler;
    bool Function(Object, StackTrace)? platformErrorHandler;
    final analytics = PostDeeAnalytics();

    await configurePostDeeFirebaseMonitoring(
      enableFirebaseAuth: true,
      firebaseBootstrapResult: FirebaseBootstrapResult.initialized,
      analytics: analytics,
      logAnalyticsEvent: (event) async => analyticsEvents.add(event),
      recordCrashError: (error, stackTrace, {required fatal}) async {
        crashEvents.add((error: error, fatal: fatal));
      },
      setCrashCollectionEnabled: (_) async {},
      presentFlutterError: (_) {},
      setFlutterErrorHandler: (handler) => flutterErrorHandler = handler,
      setPlatformErrorHandler: (handler) => platformErrorHandler = handler,
    );

    await analytics.logSignInStarted('google');
    flutterErrorHandler!(
      FlutterErrorDetails(exception: StateError('flutter crash')),
    );
    final handled = platformErrorHandler!(
      StateError('platform crash'),
      StackTrace.current,
    );

    expect(analytics.isEnabled, isTrue);
    expect(analyticsEvents.single.name, 'auth_sign_in_started');
    expect(crashEvents.map((event) => event.fatal), [true, true]);
    expect(handled, isTrue);
  });
}
