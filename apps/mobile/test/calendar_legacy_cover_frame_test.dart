import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:postdee_mobile/features/calendar/calendar_legacy_cover_frame.dart';
import 'package:postdee_mobile/features/calendar/calendar_cover_video_proxy.dart';

const _jpeg = [0xff, 0xd8, 0xff, 0xd9];
final _videoUrl =
    Uri.parse('https://media.example.com/owned-video.mp4?token=private');

Future<CalendarLegacyCoverFrameTask> _writeFrame(List<String> arguments) async {
  await File(arguments.last).writeAsBytes(_jpeg);
  return CalendarLegacyCoverFrameTask(
    result: Future.value(true),
    cancel: () async {},
  );
}

class _CoverProxy extends Fake implements CalendarCoverVideoProxy {
  @override
  final url = Uri.parse('http://127.0.0.1:54321/private-frame');
  bool closed = false;
  @override
  Future<void> close() async {
    closed = true;
  }
}

void main() {
  test('native input uses a private loopback proxy and closes it after success',
      () async {
    final proxy = _CoverProxy();
    final extract = FfmpegCalendarLegacyCoverFrame(
      openVideoProxy: (source, {isCurrent}) async {
        expect(source, _videoUrl);
        expect(isCurrent?.call(), isTrue);
        return proxy;
      },
      runCommand: (arguments) async {
        expect(arguments[arguments.indexOf('-i') + 1], proxy.url.toString());
        expect(arguments, isNot(contains(_videoUrl.toString())));
        return _writeFrame(arguments);
      },
    );
    expect(await extract(_videoUrl), _jpeg);
    expect(proxy.closed, isTrue);
  });

  test(
      'a timed-out native task closes its loopback source and cancels only that task',
      () async {
    final proxy = _CoverProxy();
    final result = Completer<bool>();
    var cancellations = 0;
    final extract = FfmpegCalendarLegacyCoverFrame(
      openVideoProxy: (source, {isCurrent}) async => proxy,
      timeout: const Duration(milliseconds: 5),
      runCommand: (_) async => CalendarLegacyCoverFrameTask(
        result: result.future,
        cancel: () async {
          cancellations++;
        },
      ),
    );
    expect(await extract(_videoUrl), isNull);
    expect(proxy.closed, isTrue);
    expect(cancellations, 1);
    result.complete(false);
  });
  test('extracts a small selected frame without writing a local video',
      () async {
    final directory =
        await Directory.systemTemp.createTemp('calendar-frame-test-');
    List<String>? command;
    final extract = FfmpegCalendarLegacyCoverFrame(
      createWorkingDirectory: () async => directory,
      runCommand: (arguments) async {
        command = arguments;
        expect(await directory.list().toList(), isEmpty);
        return _writeFrame(arguments);
      },
    );

    expect(await extract(_videoUrl, frameTimeMs: 12345), _jpeg);
    final arguments = command!;
    expect(arguments, containsAll(['-nostdin', '-loglevel', 'error']));
    expect(arguments.indexOf('-ss'), lessThan(arguments.indexOf('-i')));
    expect(arguments[arguments.indexOf('-ss') + 1], '12.345');
    expect(arguments[arguments.indexOf('-i') + 1], _videoUrl.toString());
    expect(arguments[arguments.indexOf('-frames:v') + 1], '1');
    expect(arguments[arguments.indexOf('-vf') + 1], contains('144:256'));
    expect(arguments, contains('-an'));
    expect(arguments.last, endsWith('.jpg'));
    expect(await directory.exists(), isFalse);
  });

  for (final rawUrl in [
    'file:///private/video.mp4',
    'ftp://media.example.com/video.mp4',
    'https:///video.mp4',
    'https://username:password@media.example.com/video.mp4',
  ]) {
    test('rejects unsafe media URL $rawUrl before creating work', () async {
      var starts = 0;
      var directories = 0;
      final extract = FfmpegCalendarLegacyCoverFrame(
        createWorkingDirectory: () async {
          directories++;
          return Directory.systemTemp.createTemp('unexpected-calendar-frame-');
        },
        runCommand: (_) async {
          starts++;
          throw StateError('must not run');
        },
      );
      expect(await extract(Uri.parse(rawUrl)), isNull);
      expect(starts, 0);
      expect(directories, 0);
    });
  }

  test('does not dispatch when the owner or selected day is stale', () async {
    var starts = 0;
    final extract = FfmpegCalendarLegacyCoverFrame(
      runCommand: (_) async {
        starts++;
        throw StateError('must not run');
      },
    );
    expect(await extract(_videoUrl, isCurrent: () => false), isNull);
    expect(starts, 0);
  });

  test('cancels its task when the owner or selected day changes', () async {
    final directory =
        await Directory.systemTemp.createTemp('calendar-frame-test-');
    final started = Completer<void>();
    final result = Completer<bool>();
    var current = true;
    var cancellations = 0;
    final extract = FfmpegCalendarLegacyCoverFrame(
      createWorkingDirectory: () async => directory,
      ownerCheckInterval: const Duration(milliseconds: 1),
      runCommand: (_) async {
        started.complete();
        return CalendarLegacyCoverFrameTask(
          result: result.future,
          cancel: () async => cancellations++,
        );
      },
    );
    final pending = extract(_videoUrl, isCurrent: () => current);
    await started.future;
    current = false;
    expect(await pending, isNull);
    expect(cancellations, 1);
    result.completeError(StateError('late native cancellation'));
    await Future<void>.delayed(Duration.zero);
    expect(await directory.exists(), isFalse);
  });

  test('bounds extraction time and observes a late native failure', () async {
    final directory =
        await Directory.systemTemp.createTemp('calendar-frame-test-');
    final result = Completer<bool>();
    var cancellations = 0;
    final extract = FfmpegCalendarLegacyCoverFrame(
      createWorkingDirectory: () async => directory,
      timeout: const Duration(milliseconds: 5),
      runCommand: (_) async => CalendarLegacyCoverFrameTask(
        result: result.future,
        cancel: () async => cancellations++,
      ),
    );
    expect(await extract(_videoUrl), isNull);
    expect(cancellations, 1);
    result.completeError(StateError('signed URL must not escape'));
    await Future<void>.delayed(Duration.zero);
    expect(await directory.exists(), isFalse);
  });

  test('cancels a native task that starts after the deadline', () async {
    final directory =
        await Directory.systemTemp.createTemp('calendar-frame-test-');
    final started = Completer<CalendarLegacyCoverFrameTask>();
    final result = Completer<bool>();
    var cancellations = 0;
    final extract = FfmpegCalendarLegacyCoverFrame(
      createWorkingDirectory: () async => directory,
      timeout: const Duration(milliseconds: 5),
      runCommand: (_) => started.future,
    );
    expect(await extract(_videoUrl), isNull);
    started.complete(CalendarLegacyCoverFrameTask(
      result: result.future,
      cancel: () async => cancellations++,
    ));
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(cancellations, 1);
    result.completeError(StateError('late native task'));
    await Future<void>.delayed(Duration.zero);
    expect(await directory.exists(), isFalse);
  });

  for (final failure in ['throw', 'false', 'missing', 'empty', 'oversized']) {
    test('returns no image and cleans up $failure extraction', () async {
      final directory =
          await Directory.systemTemp.createTemp('calendar-frame-test-');
      final extract = FfmpegCalendarLegacyCoverFrame(
        createWorkingDirectory: () async => directory,
        runCommand: (arguments) async {
          if (failure == 'throw') throw StateError('private source');
          if (failure == 'empty') await File(arguments.last).writeAsBytes([]);
          if (failure == 'oversized') {
            await File(arguments.last)
                .writeAsBytes(List.filled(512 * 1024 + 1, 0));
          }
          return CalendarLegacyCoverFrameTask(
            result: Future.value(failure != 'false'),
            cancel: () async {},
          );
        },
      );
      expect(await extract(_videoUrl), isNull);
      expect(await directory.exists(), isFalse);
    });
  }

  test('uses frame zero when none was requested and clamps negative times',
      () async {
    for (final frameTimeMs in [0, -42]) {
      List<String>? command;
      final extract = FfmpegCalendarLegacyCoverFrame(
        runCommand: (arguments) async {
          command = arguments;
          return _writeFrame(arguments);
        },
      );
      expect(await extract(_videoUrl, frameTimeMs: frameTimeMs), _jpeg);
      expect(command![command!.indexOf('-ss') + 1], '0.000');
    }
  });
}
