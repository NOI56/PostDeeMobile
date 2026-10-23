import 'dart:async';

import 'package:sentry_flutter/sentry_flutter.dart';

import '../config/app_config.dart';

/// Explicit build configuration: an absent or invalid DSN never enables sending.
class PostDeeSentryConfig {
  const PostDeeSentryConfig._(this.dsn, this.environment, this.release);

  static const disabled = PostDeeSentryConfig._('', 'development', null);
  final String dsn;
  final String environment;
  final String? release;
  bool get isEnabled => dsn.isNotEmpty;

  static PostDeeSentryConfig get fromEnvironment =>
      tryParse(
        dsn: AppConfig.sentryDsn,
        environment: AppConfig.sentryEnvironment,
        release: AppConfig.sentryRelease,
        isStagingBuild: AppConfig.isStagingBuild,
      ) ?? disabled;

  static PostDeeSentryConfig? tryParse({
    required String dsn,
    required String environment,
    String? release,
    bool isStagingBuild = false,
  }) {
    final uri = Uri.tryParse(dsn);
    if (dsn.length > 2048 || uri == null || uri.scheme != 'https' ||
        !(uri.host == 'sentry.io' || uri.host.endsWith('.sentry.io')) ||
        !RegExp(r'^[a-fA-F0-9]{32}$').hasMatch(uri.userInfo) ||
        !RegExp(r'^/[0-9]+$').hasMatch(uri.path) ||
        uri.hasQuery || uri.hasFragment || uri.port != 443 ||
        !const {'development', 'staging', 'production'}
            .contains(environment) ||
        (isStagingBuild && environment != 'staging')) {
      return null;
    }
    final configuredRelease = release == null || release.isEmpty ? null : release;
    if (configuredRelease != null &&
        !_safeRelease.hasMatch(configuredRelease)) {
      return null;
    }
    return PostDeeSentryConfig._(dsn, environment, configuredRelease);
  }
}

typedef PostDeeSentryInitializer = Future<void> Function(
    PostDeeSentryConfig config, Future<void> Function() appRunner);

/// Starts once even when SDK setup fails. An application failure is rethrown,
/// rather than being mistaken for an SDK failure and starting a second app.
Future<void> runPostDeeWithSentry({
  required PostDeeSentryConfig config,
  required Future<void> Function(bool sentryEnabled) appRunner,
  PostDeeSentryInitializer? initialize,
}) async {
  var launched = false;
  Future<void>? launch;
  Future<void> launchOnce(bool enabled) {
    if (launched) {
      return launch!;
    }
    launched = true;
    return launch = Future<void>.sync(() => appRunner(enabled));
  }

  if (!config.isEnabled) {
    await launchOnce(false);
    return;
  }
  try {
    await (initialize ?? _initializeSentry)(
        config, () => launchOnce(true));
  } catch (_) {
    if (launched) {
      rethrow;
    }
    // Closing partial setup restores SDK error hooks before Crashlytics owns
    // them again. Never let cleanup prevent the application from opening.
    if (initialize == null) {
      try {
        await Sentry.close();
      } catch (_) {}
    }
    await launchOnce(false);
    return;
  }
  if (!launched) {
    await launchOnce(false);
  }
}

Future<void> _initializeSentry(PostDeeSentryConfig config,
        Future<void> Function() runner) =>
    SentryFlutter.init((options) => applyPostDeeSentryOptions(options, config),
        appRunner: () async {
          if (!Sentry.isEnabled) {
            throw StateError('Error reporting unavailable');
          }
          await runner();
        });

void applyPostDeeSentryOptions(
    SentryFlutterOptions options, PostDeeSentryConfig config) {
  options
    ..dsn = config.dsn
    ..environment = config.environment
    ..release = config.release
    ..debug = false
    ..sendDefaultPii = false
    ..autoInitializeNativeSdk = false
    ..enableNativeCrashHandling = false
    ..enableAutoSessionTracking = false
    ..anrEnabled = false
    ..enableTombstone = false
    ..enableWatchdogTerminationTracking = false
    ..enableNdkScopeSync = false
    ..enableAutoPerformanceTracing = false
    ..attachScreenshot = false
    // Sentry 9.30.1 marks this option experimental; explicitly disable it.
    // ignore: experimental_member_use
    ..attachViewHierarchy = false
    ..attachThreads = false
    ..reportPackages = false
    ..enablePrintBreadcrumbs = false
    ..enableAutoNativeBreadcrumbs = false
    ..enableAppLifecycleBreadcrumbs = false
    ..enableWindowMetricBreadcrumbs = false
    ..enableBrightnessChangeBreadcrumbs = false
    ..enableTextScaleChangeBreadcrumbs = false
    ..enableMemoryPressureBreadcrumbs = false
    ..enableUserInteractionBreadcrumbs = false
    ..recordHttpBreadcrumbs = false
    ..captureFailedRequests = false
    ..captureNativeFailedRequests = false
    ..sendClientReports = false
    ..enableLogs = false
    ..enableMetrics = false
    ..maxBreadcrumbs = 0
    ..tracesSampleRate = 0
    ..beforeBreadcrumb = ((_, __) => null)
    ..beforeSendLog = ((_) => null)
    ..beforeSendMetric = ((_) => null)
    ..beforeSendTransaction = ((_, __) => null)
    ..beforeSendFeedback = ((_, __) => null)
    ..beforeSend = ((event, _) => _isErrorEvent(event)
        ? sanitizePostDeeSentryEvent(event) : null);
  options.tracePropagationTargets.clear();
  options.replay
    ..sessionSampleRate = 0
    ..onErrorSampleRate = 0;

  // Flutter normally installs a native filesystem transport even when native
  // initialization is disabled. Use the supported core Dart HTTP client and
  // filter its envelope too, so attachments and trace baggage cannot bypass
  // the final event allowlist. The owning SDK closes this same HTTP client.
  options.transport = DartHttpTransport(options);
}

class DartHttpTransport implements Transport {
  DartHttpTransport(SentryFlutterOptions options, {Transport? delegate})
      : _sdk = options.sdk, _dsn = options.dsn {
    if (delegate != null) {
      _transport = delegate;
      return;
    }
    final dartOptions = SentryOptions()
      ..dsn = options.dsn
      ..debug = false
      ..sendDefaultPii = false
      ..sendClientReports = false
      ..enableLogs = false
      ..enableMetrics = false;
    SentryClient(dartOptions);
    options.httpClient = dartOptions.httpClient;
    _transport = dartOptions.transport;
  }

  late final Transport _transport;
  final String? _dsn;
  final SdkVersion _sdk;

  @override
  Future<SentryId?> send(SentryEnvelope envelope) async {
    SentryId? result;
    // Rebuild instead of forwarding unknown envelope items or header baggage.
    for (final item in envelope.items) {
      final event = item.originalObject;
      if (item.header.type != 'event' || event is! SentryEvent ||
          !_isErrorEvent(event)) {
        continue;
      }
      result = await _transport.send(SentryEnvelope.fromEvent(
        sanitizePostDeeSentryEvent(event), _sdk, dsn: _dsn,
      ));
    }
    return result ?? SentryId.empty();
  }
}

final _safeRelease = RegExp(r'^[A-Za-z0-9][A-Za-z0-9_.@+\-]{0,99}$');
bool _isErrorEvent(SentryEvent event) =>
    event.level == SentryLevel.error || event.level == SentryLevel.fatal ||
    (event.level == null && (event.exceptions?.isNotEmpty ?? false));
final _safeFunction = RegExp(r'^[A-Za-z_$][A-Za-z0-9_$.<> ]{0,159}$');
final _safeFilename = RegExp(
    r'^(?:[A-Za-z0-9_]+\.dart|package:[A-Za-z0-9_]+/[A-Za-z0-9_./-]+\.dart|dart:[A-Za-z0-9_./-]+)$');
const _exceptionTypes = {
  'StateError', 'ArgumentError', 'RangeError', 'TypeError', 'FormatException',
  'ApiException', 'PlatformException', 'MissingPluginException', 'Exception',
  'Error', 'SocketException', 'TimeoutException', 'HttpException',
  'FileSystemException', 'FlutterError', 'AssertionError', 'NoSuchMethodError',
  'ConcurrentModificationError', 'PostDeeApiServerError',
};

/// Construct a fresh event from known-safe fields. Never copy unknown maps:
/// SDK enrichers, exception messages, requests and customer content are omitted.
SentryEvent sanitizePostDeeSentryEvent(SentryEvent event) {
  final exceptions = event.exceptions?.take(8).map((exception) {
    final frames = exception.stackTrace?.frames.take(80).map((frame) =>
        SentryStackFrame(
          fileName: frame.fileName != null &&
                  frame.fileName!.length <= 240 &&
                  _safeFilename.hasMatch(frame.fileName!) &&
                  !frame.fileName!.contains('..')
              ? frame.fileName : null,
          function: frame.function != null &&
                  _safeFunction.hasMatch(frame.function!)
              ? frame.function : null,
          lineNo: _safePosition(frame.lineNo),
          colNo: _safePosition(frame.colNo),
          inApp: frame.inApp,
        )).toList();
    return SentryException(
      type: _exceptionTypes.contains(exception.type) ? exception.type : 'Exception',
      value: 'Application error (customer details removed)',
      stackTrace: frames == null ? null : SentryStackTrace(frames: frames),
      mechanism: Mechanism(type: 'generic', handled: exception.mechanism?.handled),
    );
  }).toList();
  final safeTags = <String, String>{};
  final status = event.tags?['http.status_code'];
  if (status != null && RegExp(r'^5[0-9]{2}$').hasMatch(status)) {
    safeTags['http.status_code'] = status;
  }
  final operation = event.tags?['operation'];
  if (const {'publish', 'calendar', 'caption', 'ai_edit', 'billing',
      'profile', 'social', 'api'}.contains(operation)) {
    safeTags['operation'] = operation!;
  }
  return SentryEvent(
    eventId: event.eventId,
    timestamp: event.timestamp,
    platform: 'dart',
    level: event.level,
    release: event.release != null && _safeRelease.hasMatch(event.release!)
        ? event.release : null,
    environment: const {'development', 'staging', 'production'}
            .contains(event.environment)
        ? event.environment : null,
    exceptions: exceptions,
    message: exceptions == null || exceptions.isEmpty
        ? SentryMessage('Application error (customer details removed)') : null,
    tags: safeTags.isEmpty ? null : safeTags,
    contexts: _safeContexts(event.contexts),
  );
}

Contexts _safeContexts(Contexts source) {
  final contexts = Contexts();
  final device = source.device;
  if (device != null) {
    final model = _technicalLabel(device.model);
    final manufacturer = _technicalLabel(device.manufacturer);
    if (model != null || manufacturer != null) {
      contexts.device = SentryDevice(model: model, manufacturer: manufacturer);
    }
  }
  final os = source.operatingSystem;
  if (os != null && const {'Android', 'iOS', 'macOS', 'Windows', 'Linux'}
      .contains(os.name)) {
    contexts.operatingSystem = SentryOperatingSystem(
      name: os.name,
      version: _numericVersion(os.version),
      build: os.build != null && RegExp(r'^[A-Z0-9][A-Z0-9.]{0,39}$')
          .hasMatch(os.build!) ? os.build : null,
    );
  }
  contexts.runtimes = source.runtimes.take(4)
      .where((runtime) => const {'Dart', 'Flutter'}.contains(runtime.name))
      .map((runtime) => SentryRuntime(name: runtime.name,
          version: _numericVersion(runtime.version)))
      .toList();
  return contexts;
}

String? _technicalLabel(String? value) => value != null &&
    RegExp(r'^[A-Za-z0-9][A-Za-z0-9 ._()\-]{0,63}$').hasMatch(value)
        ? value : null;

String? _numericVersion(String? value) => value != null &&
    RegExp(r'^[0-9]{1,4}(?:\.[0-9]{1,4}){0,4}$').hasMatch(value)
        ? value : null;

int? _safePosition(int? value) =>
    value != null && value >= 0 && value <= 10000000 ? value : null;

/// Only bounded labels enter handled API reports; no URL, body or exception
/// message is accepted by this boundary.
Future<void> reportPostDeeApiServerError({
  required String operation,
  required int statusCode,
}) => capturePostDeeApiServerError(operation, statusCode);

Future<void> capturePostDeeApiServerError(String operation, int statusCode) async {
  if (!Sentry.isEnabled || statusCode < 500 || statusCode >= 600) {
    return;
  }
  try {
    await Sentry.captureEvent(SentryEvent(
      level: SentryLevel.error,
      exceptions: [SentryException(type: 'PostDeeApiServerError',
          value: 'API server error',
          mechanism: Mechanism(type: 'generic', handled: true))],
      tags: {'operation': operation, 'http.status_code': '$statusCode'},
    ));
  } catch (_) {
    // Monitoring must not alter the request result or break publishing.
  }
}
