import 'dart:io';

import 'package:ffmpeg_kit_flutter_new_video/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new_video/return_code.dart';

typedef AiEditVisualProxyFfmpegRunner = Future<bool> Function(
  List<String> arguments,
);

enum AiEditVisualProxyFailure {
  sourceMissing,
  ffmpegFailed,
  emptyOutput,
}

class AiEditVisualProxyException implements Exception {
  const AiEditVisualProxyException(this.failure);

  final AiEditVisualProxyFailure failure;

  @override
  String toString() => switch (failure) {
        AiEditVisualProxyFailure.sourceMissing =>
          'ไม่พบวิดีโอต้นฉบับสำหรับวิเคราะห์ภาพ',
        AiEditVisualProxyFailure.ffmpegFailed =>
          'สร้างวิดีโอตัวอย่างสำหรับวิเคราะห์ภาพไม่สำเร็จ',
        AiEditVisualProxyFailure.emptyOutput =>
          'วิดีโอตัวอย่างสำหรับวิเคราะห์ภาพใช้งานไม่ได้',
      };
}

class AiEditVisualProxyArtifact {
  AiEditVisualProxyArtifact({
    required this.file,
    required this.workingDirectory,
  });

  final File file;
  final Directory workingDirectory;
  Future<void>? _cleanupFuture;

  Future<void> cleanup() => _cleanupFuture ??= _cleanupOnce();

  Future<void> _cleanupOnce() async {
    if (workingDirectory.existsSync()) {
      workingDirectory.deleteSync(recursive: true);
    }
  }
}

class AiEditVisualProxyExtractor {
  AiEditVisualProxyExtractor({
    AiEditVisualProxyFfmpegRunner? runFfmpeg,
    Future<Directory> Function()? createWorkingDirectory,
  })  : _runFfmpeg = runFfmpeg ?? _runNativeFfmpeg,
        _createWorkingDirectory = createWorkingDirectory ??
            (() => Directory.systemTemp.createTemp('postdee-visual-proxy-'));

  final AiEditVisualProxyFfmpegRunner _runFfmpeg;
  final Future<Directory> Function() _createWorkingDirectory;

  Future<AiEditVisualProxyArtifact> extract(File source) async {
    if (!await source.exists()) {
      throw const AiEditVisualProxyException(
        AiEditVisualProxyFailure.sourceMissing,
      );
    }

    Directory? workingDirectory;
    try {
      workingDirectory = await _createWorkingDirectory();
      final output = File(
        '${workingDirectory.path}${Platform.pathSeparator}'
        'postdee-ai-edit-visual-proxy.mp4',
      );
      final succeeded = await _runFfmpeg([
        '-y',
        '-i',
        source.path,
        '-vf',
        'fps=1,scale=360:-2',
        '-c:v',
        'mpeg4',
        '-q:v',
        '5',
        '-pix_fmt',
        'yuv420p',
        '-ac',
        '1',
        '-ar',
        '16000',
        '-c:a',
        'aac',
        '-b:a',
        '32k',
        '-movflags',
        '+faststart',
        output.path,
      ]);

      if (!succeeded) {
        throw const AiEditVisualProxyException(
          AiEditVisualProxyFailure.ffmpegFailed,
        );
      }
      if (!await output.exists() || await output.length() <= 0) {
        throw const AiEditVisualProxyException(
          AiEditVisualProxyFailure.emptyOutput,
        );
      }

      return AiEditVisualProxyArtifact(
        file: output,
        workingDirectory: workingDirectory,
      );
    } on AiEditVisualProxyException {
      await _cleanupBestEffort(workingDirectory);
      rethrow;
    } catch (_) {
      await _cleanupBestEffort(workingDirectory);
      throw const AiEditVisualProxyException(
        AiEditVisualProxyFailure.ffmpegFailed,
      );
    }
  }
}

Future<bool> _runNativeFfmpeg(List<String> arguments) async {
  final session = await FFmpegKit.executeWithArguments(arguments);
  return ReturnCode.isSuccess(await session.getReturnCode());
}

Future<void> _cleanupBestEffort(Directory? directory) async {
  if (directory != null && await directory.exists()) {
    await directory.delete(recursive: true);
  }
}
