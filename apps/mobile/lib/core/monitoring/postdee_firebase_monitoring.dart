import 'dart:async';

import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';

import '../auth/firebase_bootstrap.dart';
import '../config/app_config.dart';
import 'postdee_analytics.dart';

typedef CrashErrorRecorder = Future<void> Function(
  Object error,
  StackTrace stackTrace, {
  required bool fatal,
});
typedef CrashCollectionSetter = Future<void> Function(bool enabled);
typedef FlutterErrorHandlerSetter = void Function(
  FlutterExceptionHandler handler,
);
typedef PlatformErrorHandlerSetter = void Function(
  bool Function(Object error, StackTrace stackTrace) handler,
);

Future<void> configurePostDeeFirebaseMonitoring({
  required FirebaseBootstrapResult firebaseBootstrapResult,
  bool enableFirebaseAuth = AppConfig.enableFirebaseAuth,
  PostDeeAnalytics? analytics,
  AnalyticsEventLogger? logAnalyticsEvent,
  CrashErrorRecorder? recordCrashError,
  CrashCollectionSetter? setCrashCollectionEnabled,
  FlutterErrorHandlerSetter? setFlutterErrorHandler,
  PlatformErrorHandlerSetter? setPlatformErrorHandler,
  void Function(FlutterErrorDetails details)? presentFlutterError,
}) async {
  final analyticsReporter = analytics ?? PostDeeAnalytics.instance;
  final isMonitoringEnabled =
      enableFirebaseAuth && firebaseBootstrapResult.isInitialized;

  analyticsReporter.configure(
    isEnabled: isMonitoringEnabled,
    logEvent: isMonitoringEnabled
        ? (logAnalyticsEvent ?? _logFirebaseAnalyticsEvent)
        : null,
  );

  if (!isMonitoringEnabled) {
    return;
  }

  // Crashlytics is not available on Flutter web. Keep web analytics enabled,
  // but do not let an unsupported crash reporter block Firebase sign-in before
  // the application has rendered its first screen.
  if (kIsWeb) {
    return;
  }

  final recordError = recordCrashError ?? _recordFirebaseCrashError;
  await (setCrashCollectionEnabled ?? _setFirebaseCrashCollectionEnabled)(true);

  (setFlutterErrorHandler ?? _setFlutterErrorHandler)(
    (details) {
      (presentFlutterError ?? FlutterError.presentError)(details);
      unawaited(
        recordError(
          details.exception,
          details.stack ?? StackTrace.current,
          fatal: true,
        ),
      );
    },
  );

  (setPlatformErrorHandler ?? _setPlatformErrorHandler)(
    (error, stackTrace) {
      unawaited(recordError(error, stackTrace, fatal: true));
      return true;
    },
  );
}

Future<void> _logFirebaseAnalyticsEvent(RecordedAnalyticsEvent event) =>
    FirebaseAnalytics.instance.logEvent(
      name: event.name,
      parameters: event.parameters,
    );

Future<void> _setFirebaseCrashCollectionEnabled(bool enabled) =>
    FirebaseCrashlytics.instance.setCrashlyticsCollectionEnabled(enabled);

Future<void> _recordFirebaseCrashError(
  Object error,
  StackTrace stackTrace, {
  required bool fatal,
}) =>
    FirebaseCrashlytics.instance.recordError(
      error,
      stackTrace,
      fatal: fatal,
    );

void _setFlutterErrorHandler(FlutterExceptionHandler handler) {
  FlutterError.onError = handler;
}

void _setPlatformErrorHandler(
  bool Function(Object error, StackTrace stackTrace) handler,
) {
  PlatformDispatcher.instance.onError = handler;
}
