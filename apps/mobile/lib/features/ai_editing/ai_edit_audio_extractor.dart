import 'dart:io';

import 'package:ffmpeg_kit_flutter_new_video/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new_video/ffprobe_kit.dart';
import 'package:ffmpeg_kit_flutter_new_video/return_code.dart';

typedef AiEditFfmpegRunner = Future<bool> Function(List<String> arguments);
typedef AiEditAudioStreamProbe = Future<bool> Function(File source);
typedef AiEditWorkingDirectoryFactory = Future<Directory> Function();

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

class AiEditAudioExtractor {
  AiEditAudioExtractor({
    AiEditFfmpegRunner? runFfmpeg,
    AiEditAudioStreamProbe? hasAudioStream,
    AiEditWorkingDirectoryFactory? createWorkingDirectory,
  })  : _runFfmpeg = runFfmpeg ?? _runNativeFfmpeg,
        _hasAudioStream = hasAudioStream ?? _probeNativeAudioStream,
        _createWorkingDirectory =
            createWorkingDirectory ?? _createSystemWorkingDirectory;

  final AiEditFfmpegRunner _runFfmpeg;
  final AiEditAudioStreamProbe _hasAudioStream;
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

  Future<bool> _readAudioStreamSafely(File source) async {
    try {
      return await _hasAudioStream(source);
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
