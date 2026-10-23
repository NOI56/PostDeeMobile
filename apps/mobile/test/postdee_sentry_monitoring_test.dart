import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:postdee_mobile/core/monitoring/postdee_sentry_monitoring.dart';

const _testDsn = 'https://0123456789abcdef0123456789abcdef@o1.ingest.sentry.io/2';

void main() {
  test('missing DSN remains disabled without constructing an SDK', () async {
    var initializations = 0;
    final launches = <bool>[];
    await runPostDeeWithSentry(
      config: PostDeeSentryConfig.disabled,
      appRunner: (enabled) async => launches.add(enabled),
      initialize: (_, runner) async {
        initializations++;
        await runner();
      },
    );
    expect(initializations, 0);
    expect(launches, [false]);
  });

  test('configured staging must not be labelled as production', () {
    expect(PostDeeSentryConfig.tryParse(dsn: _testDsn,
        environment: 'production', isStagingBuild: true), isNull);
    final config = PostDeeSentryConfig.tryParse(dsn: _testDsn,
        environment: 'staging', isStagingBuild: true)!;
    expect(config.environment, 'staging');
    expect(config.isEnabled, isTrue);
  });

  test('rejects malformed DSN and unbounded release/environment data', () {
    for (final dsn in [
      'not-a-dsn', 'http://public@o1.ingest.sentry.io/2',
      'https://public:private@o1.ingest.sentry.io/2',
      'https://public@o1.ingest.sentry.io/2?token=private',
    ]) {
      expect(PostDeeSentryConfig.tryParse(dsn: dsn,
          environment: 'development'), isNull);
    }
    expect(PostDeeSentryConfig.tryParse(dsn: _testDsn,
        environment: 'customer@example.test'), isNull);
    expect(PostDeeSentryConfig.tryParse(dsn: _testDsn,
        environment: 'development', release: 'release with private data'), isNull);
  });

  test('Sentry initialization failure launches the app once with fallback', () async {
    final launches = <bool>[];
    await runPostDeeWithSentry(
      config: PostDeeSentryConfig.tryParse(dsn: _testDsn,
          environment: 'development')!,
      appRunner: (enabled) async => launches.add(enabled),
      initialize: (_, __) async => throw StateError('SDK unavailable'),
    );
    expect(launches, [false]);
  });

  test('a repeated SDK callback cannot start the application twice', () async {
    final launches = <bool>[];
    await runPostDeeWithSentry(
      config: PostDeeSentryConfig.tryParse(dsn: _testDsn,
          environment: 'development')!,
      appRunner: (enabled) async => launches.add(enabled),
      initialize: (_, runner) async { await runner(); await runner(); },
    );
    expect(launches, [true]);
  });

  test('application startup errors are not mistaken for SDK setup failures', () async {
    var launches = 0;
    await expectLater(runPostDeeWithSentry(
      config: PostDeeSentryConfig.tryParse(dsn: _testDsn,
          environment: 'development')!,
      appRunner: (_) async { launches++; throw StateError('app failure'); },
      initialize: (_, runner) => runner(),
    ), throwsStateError);
    expect(launches, 1);
  });

  test('outbound events retain stack positions without customer content', () {
    const private = 'customer-private-123';
    final event = SentryEvent.fromJson({
      'event_id': 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
      'timestamp': '2026-10-22T00:00:00Z',
      'level': 'error',
      'message': {'formatted': private},
      'user': {'id': private, 'email': '$private@example.test'},
      'request': {'url': 'https://media.test/$private?token=$private',
        'headers': {'Authorization': private}, 'data': private},
      'extra': {'caption': private}, 'private_extension': private,
      'breadcrumbs': [{'message': private, 'data': {'token': private}}],
      'contexts': {'device': {'name': private, 'model': 'Pixel 8',
          'manufacturer': 'Google', 'id': private, 'uuid': private,
          'serial': private, 'ip_address': private},
        'os': {'name': 'Android', 'version': '14', 'build': 'AP1A.240505.005',
          'kernel_version': private},
        'runtime': {'name': 'Dart', 'version': '3.12.0', 'raw_description': private},
        'customer': private},
      'tags': {'user_id': private, 'operation': 'publish'},
      'exception': {'values': [{
        'type': 'StateError', 'value': private,
        'stacktrace': {'frames': [{
          'filename': 'package:postdee_mobile/features/uploader/uploader_screen.dart',
          'function': '_submit', 'lineno': 42, 'colno': 7,
          'abs_path': 'C:/Users/$private/app.dart',
          'vars': {'token': private}, 'context_line': private,
        }]},
      }]},
    });
    final clean = sanitizePostDeeSentryEvent(event);
    final payload = clean.toJson();
    final encoded = jsonEncode(payload);
    expect(encoded, isNot(contains(private)));
    expect(encoded, contains('_submit'));
    expect(encoded, contains('uploader_screen.dart'));
    expect(encoded, contains('StateError'));
    expect(payload['request'], isNull);
    expect(payload['user'], isNull);
    expect(payload['breadcrumbs'], isNull);
    expect(payload['contexts']['device']['model'], 'Pixel 8');
    expect(payload['contexts']['device']['manufacturer'], 'Google');
    expect(payload['contexts']['os']['name'], 'Android');
    expect(payload['contexts']['os']['version'], '14');
    expect(payload['contexts']['os']['build'], 'AP1A.240505.005');
    expect(encoded, contains('3.12.0'));
    expect((payload['exception']['values'] as List).single['stacktrace']
        ['frames'][0]['lineno'], 42);
  });

  test('unsafe stack filenames and exception type data are discarded', () {
    final event = SentryEvent.fromJson({
      'event_id': 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
      'exception': {'values': [{
        'type': 'https://media.test/private?token=abc', 'value': 'secret-caption',
        'stacktrace': {'frames': [{
          'filename': 'https://media.test/private?token=abc',
          'function': 'https://media.test/private?token=abc',
        }]},
      }]},
    });
    final encoded = jsonEncode(sanitizePostDeeSentryEvent(event).toJson());
    expect(encoded, isNot(contains('media.test')));
    expect(encoded, isNot(contains('secret-caption')));
  });

  test('real SDK stack frame basenames retain useful code locations', () {
    final event = SentryEvent(exceptions: [SentryException(
      type: 'StateError', value: 'private error message',
      stackTrace: SentryStackTrace(frames: [SentryStackFrame(
        fileName: 'uploader_screen.dart',
        absPath: 'app:///C:/Users/private/app/uploader_screen.dart',
        function: '_UploaderScreenState._submit', lineNo: 72, colNo: 9,
      )]),
    )]);
    final frame = sanitizePostDeeSentryEvent(event).exceptions!.single
        .stackTrace!.frames.single;
    expect(frame.fileName, 'uploader_screen.dart');
    expect(frame.function, '_UploaderScreenState._submit');
    expect(frame.lineNo, 72);
    expect(frame.absPath, isNull);
  });

  test('technical contexts reject free text and keep only explicit fields', () {
    final event = SentryEvent.fromJson({
      'event_id': 'dddddddddddddddddddddddddddddddd',
      'contexts': {
        'device': {'model': 'https://private.test/device?token=secret',
          'manufacturer': 'customer@example.test', 'name': 'private', 'id': 'private'},
        'os': {'name': 'Customer OS', 'version': 'private version',
          'build': 'private-custom-build'},
        'runtime': {'name': 'Customer runtime', 'version': 'private version'},
      },
    });
    expect(jsonEncode(sanitizePostDeeSentryEvent(event).toJson()),
        isNot(contains('private')));
  });

  test('SDK options enforce Dart-only errors and no automatic private payloads', () async {
    final options = SentryFlutterOptions();
    applyPostDeeSentryOptions(options, PostDeeSentryConfig.tryParse(
        dsn: _testDsn, environment: 'development')!);
    expect(options.sendDefaultPii, isFalse);
    expect(options.autoInitializeNativeSdk, isFalse);
    expect(options.enableNativeCrashHandling, isFalse);
    expect(options.attachScreenshot, isFalse);
    // Explicit privacy disable for the experimental Sentry 9.30.1 option.
    // ignore: experimental_member_use
    expect(options.attachViewHierarchy, isFalse);
    expect(options.enablePrintBreadcrumbs, isFalse);
    expect(options.recordHttpBreadcrumbs, isFalse);
    expect(options.captureFailedRequests, isFalse);
    expect(options.tracesSampleRate, 0);
    expect(options.replay.sessionSampleRate, 0);
    expect(options.replay.onErrorSampleRate, 0);
    expect(options.beforeBreadcrumb!(Breadcrumb(message: 'private'), Hint()),
        isNull);
    expect(await options.beforeSend!(SentryEvent(level: SentryLevel.info,
        message: SentryMessage('private log')), Hint()), isNull);
  });

  test('transport rejects attachments and rechecks events after SDK processing', () async {
    const private = 'private-customer-attachment';
    final event = SentryEvent.fromJson({
      'event_id': 'cccccccccccccccccccccccccccccccc',
      'level': 'error',
      'message': {'formatted': private},
      'user': {'id': private},
      'extra': {'caption': private},
    });
    final sdk = SdkVersion(name: 'sentry.dart.flutter', version: '9.30.1');
    final envelope = SentryEnvelope.fromEvent(event, sdk,
      attachments: [SentryAttachment.fromIntList([1, 2, 3], '$private.txt')]);
    final delegate = _RecordingTransport();
    final transport = DartHttpTransport(SentryFlutterOptions(), delegate: delegate);
    await transport.send(envelope);
    expect(delegate.envelopes, hasLength(1));
    final delivered = delegate.envelopes.single;
    expect(delivered.items, hasLength(1));
    final clean = delivered.items.single.originalObject! as SentryEvent;
    expect(jsonEncode(clean.toJson()), isNot(contains(private)));
    expect(jsonEncode(delivered.header.toJson()), isNot(contains(private)));

    await transport.send(SentryEnvelope(envelope.header, [envelope.items.last]));
    expect(delegate.envelopes, hasLength(1));
  });

  test('named API reporter delegates to the production positional reporter', () async {
    final transport = _RecordingTransport();
    await Sentry.init((options) {
      options
        ..dsn = _testDsn
        ..transport = transport
        ..sendClientReports = false
        ..enableLogs = false
        ..enableMetrics = false
        ..beforeSend = ((event, _) => sanitizePostDeeSentryEvent(event));
    });
    try {
      await reportPostDeeApiServerError(operation: 'api', statusCode: 500);
      await capturePostDeeApiServerError('api', 500);
      expect(transport.envelopes, hasLength(2));
      final events = transport.envelopes.map((envelope) =>
          envelope.items.single.originalObject! as SentryEvent).toList();
      expect(events.first.tags, events.last.tags);
      expect(events.first.exceptions!.single.toJson(),
          events.last.exceptions!.single.toJson());
      expect(events.first.tags,
          {'operation': 'api', 'http.status_code': '500'});
      await capturePostDeeApiServerError('api', 403);
      expect(transport.envelopes, hasLength(2));
    } finally {
      await Sentry.close();
    }
  });
}

class _RecordingTransport implements Transport {
  final envelopes = <SentryEnvelope>[];
  @override
  Future<SentryId?> send(SentryEnvelope envelope) async {
    envelopes.add(envelope);
    return SentryId.empty();
  }
}
