import 'dart:io';
import 'dart:math' as math;

import 'package:ffmpeg_kit_flutter_new_video/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new_video/ffprobe_kit.dart';
import 'package:ffmpeg_kit_flutter_new_video/return_code.dart';

import 'video_duration_probe.dart';

typedef AiEditFfmpegRunner = Future<bool> Function(List<String> arguments);
typedef AiEditAudioStreamProbe = Future<bool> Function(File source);
typedef AiEditWorkingDirectoryFactory = Future<Directory> Function();

const aiEditAudioChunkSeconds = 30.0;

double balancedAiEditAudioChunkSeconds(double durationSeconds) {
  if (!durationSeconds.isFinite || durationSeconds <= 0) {
    throw ArgumentError.value(
      durationSeconds,
      'durationSeconds',
      'must be a positive finite number',
    );
  }

  final chunkCount = math.max(
    1,
    (durationSeconds / aiEditAudioChunkSeconds).ceil(),
  );
  return durationSeconds / chunkCount;
}

List<double> balancedAiEditAudioSegmentTimes(double durationSeconds) {
  final chunkSeconds = balancedAiEditAudioChunkSeconds(durationSeconds);
  final chunkCount = math.max(
    1,
    (durationSeconds / aiEditAudioChunkSeconds).ceil(),
  );
  return [
    for (var index = 1; index < chunkCount; index += 1) index * chunkSeconds,
  ];
}

enum AiEditAudioExtractionFailure {
  sourceMissing,
  noAudioStream,
  inspectionFailed,
  ffmpegFailed,
  emptyOutput,
}

class AiEditAudioExtractionException implements Exception {
  const AiEditAudioExtractionException(this.failure);

  final AiEditAudioExtractionFailure failure;

  String get message => switch (failure) {
        AiEditAudioExtractionFailure.sourceMissing => 'ไม่พบไฟล์วิดีโอต้นฉบับ',
        AiEditAudioExtractionFailure.noAudioStream =>
          'วิดีโอนี้ไม่มีเสียงให้ AI วิเคราะห์',
        AiEditAudioExtractionFailure.inspectionFailed =>
          'ตรวจสอบเสียงในวิดีโอไม่สำเร็จ',
        AiEditAudioExtractionFailure.ffmpegFailed =>
          'เตรียมเสียงสำหรับ AI ไม่สำเร็จ',
        AiEditAudioExtractionFailure.emptyOutput =>
          'ไฟล์เสียงที่เตรียมไว้ใช้งานไม่ได้',
      };

  @override
  String toString() => message;
}

class AiEditAudioArtifact {
  AiEditAudioArtifact({
    required this.file,
    required Directory workingDirectory,
  }) : _workingDirectory = workingDirectory;

  final File file;
  final Directory _workingDirectory;
  Future<void>? _cleanupFuture;

  Future<void> cleanup() => _cleanupFuture ??= _cleanupOnce();

  Future<void> _cleanupOnce() async {
    if (_workingDirectory.existsSync()) {
      _workingDirectory.deleteSync(recursive: true);
    }
  }
}

class AiEditAudioChunk {
  const AiEditAudioChunk({
    required this.file,
    required this.startSeconds,
  });

  final File file;
  final double startSeconds;
}

class AiEditAudioChunksArtifact {
  AiEditAudioChunksArtifact({
    required List<AiEditAudioChunk> chunks,
    required Directory workingDirectory,
  })  : chunks = List.unmodifiable(chunks),
        _workingDirectory = workingDirectory;

  final List<AiEditAudioChunk> chunks;
  final Directory _workingDirectory;
  Future<void>? _cleanupFuture;

  Future<void> cleanup() => _cleanupFuture ??= _cleanupOnce();

  Future<void> _cleanupOnce() async {
    if (_workingDirectory.existsSync()) {
      _workingDirectory.deleteSync(recursive: true);
    }
  }
}

class AiEditAudioExtractor {
  AiEditAudioExtractor({
    AiEditFfmpegRunner? runFfmpeg,
    AiEditAudioStreamProbe? hasAudioStream,
    VideoDurationProbe? probeDuration,
    AiEditWorkingDirectoryFactory? createWorkingDirectory,
  })  : _runFfmpeg = runFfmpeg ?? _runNativeFfmpeg,
        _hasAudioStream = hasAudioStream ?? _probeNativeAudioStream,
        _probeDuration =
            probeDuration ?? const FfprobeVideoDurationProbe().call,
        _createWorkingDirectory =
            createWorkingDirectory ?? _createSystemWorkingDirectory;

  final AiEditFfmpegRunner _runFfmpeg;
  final AiEditAudioStreamProbe _hasAudioStream;
  final VideoDurationProbe _probeDuration;
  final AiEditWorkingDirectoryFactory _createWorkingDirectory;

  Future<AiEditAudioArtifact> extract(File source) async {
    if (!await source.exists()) {
      throw const AiEditAudioExtractionException(
        AiEditAudioExtractionFailure.sourceMissing,
      );
    }

    if (!await _readAudioStreamSafely(source)) {
      throw const AiEditAudioExtractionException(
        AiEditAudioExtractionFailure.noAudioStream,
      );
    }

    Directory? workingDirectory;
    try {
      workingDirectory = await _createWorkingDirectory();
      final output = File(
        '${workingDirectory.path}${Platform.pathSeparator}'
        'postdee-ai-edit-audio.m4a',
      );
      final succeeded = await _runFfmpeg([
        '-y',
        '-i',
        source.path,
        '-vn',
        '-ac',
        '1',
        '-ar',
        '16000',
        '-c:a',
        'aac',
        '-b:a',
        '64k',
        output.path,
      ]);

      if (!succeeded) {
        throw const AiEditAudioExtractionException(
          AiEditAudioExtractionFailure.ffmpegFailed,
        );
      }

      if (!await output.exists() || await output.length() <= 0) {
        throw const AiEditAudioExtractionException(
          AiEditAudioExtractionFailure.emptyOutput,
        );
      }

      if (!await _readAudioStreamSafely(output)) {
        throw const AiEditAudioExtractionException(
          AiEditAudioExtractionFailure.emptyOutput,
        );
      }

      return AiEditAudioArtifact(
        file: output,
        workingDirectory: workingDirectory,
      );
    } on AiEditAudioExtractionException {
      await _deleteWorkingDirectoryBestEffort(workingDirectory);
      rethrow;
    } catch (_) {
      await _deleteWorkingDirectoryBestEffort(workingDirectory);
      throw const AiEditAudioExtractionException(
        AiEditAudioExtractionFailure.ffmpegFailed,
      );
    }
  }

  Future<AiEditAudioChunksArtifact> extractChunks(File source) async {
    if (!await source.exists()) {
      throw const AiEditAudioExtractionException(
        AiEditAudioExtractionFailure.sourceMissing,
      );
    }

    if (!await _readAudioStreamSafely(source)) {
      throw const AiEditAudioExtractionException(
        AiEditAudioExtractionFailure.noAudioStream,
      );
    }

    final durationSeconds = await _readDurationSafely(source);
    final chunkSeconds = balancedAiEditAudioChunkSeconds(durationSeconds);
    final segmentTimes = balancedAiEditAudioSegmentTimes(durationSeconds);
    final expectedChunkCount = segmentTimes.length + 1;

    Directory? workingDirectory;
    try {
      workingDirectory = await _createWorkingDirectory();
      final outputPattern = File(
        '${workingDirectory.path}${Platform.pathSeparator}'
        'postdee-ai-edit-audio-%03d.m4a',
      );
      final succeeded = await _runFfmpeg([
        '-y',
        '-i',
        source.path,
        '-map',
        '0:a:0',
        '-vn',
        '-ac',
        '1',
        '-ar',
        '16000',
        '-c:a',
        'aac',
        '-b:a',
        '64k',
        '-f',
        'segment',
        if (segmentTimes.isEmpty) ...[
          '-segment_time',
          (durationSeconds + 1).toStringAsFixed(3),
        ] else ...[
          '-segment_times',
          segmentTimes.map((seconds) => seconds.toStringAsFixed(3)).join(','),
        ],
        '-reset_timestamps',
        '1',
        outputPattern.path,
      ]);

      if (!succeeded) {
        throw const AiEditAudioExtractionException(
          AiEditAudioExtractionFailure.ffmpegFailed,
        );
      }

      final files = await workingDirectory
          .list()
          .where((entry) =>
              entry is File && entry.path.toLowerCase().endsWith('.m4a'))
          .cast<File>()
          .toList()
        ..sort((left, right) => left.path.compareTo(right.path));
      if (files.length != expectedChunkCount) {
        throw const AiEditAudioExtractionException(
          AiEditAudioExtractionFailure.emptyOutput,
        );
      }

      for (final file in files) {
        if (await file.length() <= 0 || !await _readAudioStreamSafely(file)) {
          throw const AiEditAudioExtractionException(
            AiEditAudioExtractionFailure.emptyOutput,
          );
        }
      }

      return AiEditAudioChunksArtifact(
        chunks: [
          for (var index = 0; index < files.length; index += 1)
            AiEditAudioChunk(
              file: files[index],
              startSeconds: index * chunkSeconds,
            ),
        ],
        workingDirectory: workingDirectory,
      );
    } on AiEditAudioExtractionException {
      await _deleteWorkingDirectoryBestEffort(workingDirectory);
      rethrow;
    } catch (_) {
      await _deleteWorkingDirectoryBestEffort(workingDirectory);
      throw const AiEditAudioExtractionException(
        AiEditAudioExtractionFailure.ffmpegFailed,
      );
    }
  }

  Future<bool> _readAudioStreamSafely(File source) async {
    try {
      return await _hasAudioStream(source);
    } catch (_) {
      throw const AiEditAudioExtractionException(
        AiEditAudioExtractionFailure.inspectionFailed,
      );
    }
  }

  Future<double> _readDurationSafely(File source) async {
    try {
      final durationSeconds = await _probeDuration(source);
      if (durationSeconds == null ||
          !durationSeconds.isFinite ||
          durationSeconds <= 0) {
        throw const AiEditAudioExtractionException(
          AiEditAudioExtractionFailure.inspectionFailed,
        );
      }
      return durationSeconds;
    } on AiEditAudioExtractionException {
      rethrow;
    } catch (_) {
      throw const AiEditAudioExtractionException(
        AiEditAudioExtractionFailure.inspectionFailed,
      );
    }
  }
}

Future<bool> _runNativeFfmpeg(List<String> arguments) async {
  final session = await FFmpegKit.executeWithArguments(arguments);
  return ReturnCode.isSuccess(await session.getReturnCode());
}

Future<bool> _probeNativeAudioStream(File source) async {
  final session = await FFprobeKit.getMediaInformation(source.path);
  final mediaInformation = session.getMediaInformation();
  if (mediaInformation == null) {
    return false;
  }

  return mediaInformation.getStreams().any(
        (stream) => stream.getType() == 'audio',
      );
}

Future<Directory> _createSystemWorkingDirectory() =>
    Directory.systemTemp.createTemp('postdee-ai-edit-audio-');

Future<void> _deleteWorkingDirectoryBestEffort(Directory? directory) async {
  if (directory == null) {
    return;
  }

  try {
    if (await directory.exists()) {
      await directory.delete(recursive: true);
    }
  } catch (_) {
    // The caller still receives the original safe extraction error.
  }
}
