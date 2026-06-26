import 'dart:io';

import 'package:ffmpeg_kit_flutter_new_video/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new_video/return_code.dart';
import 'package:flutter/services.dart';

class WatermarkVideoRequest {
  const WatermarkVideoRequest({
    required this.inputFile,
    required this.fileName,
  });

  final File inputFile;
  final String fileName;
}

class WatermarkedVideoResult {
  const WatermarkedVideoResult({
    required this.file,
    required this.fileName,
    required this.sizeBytes,
  });

  final File file;
  final String fileName;
  final int sizeBytes;
}

typedef UploaderWatermarkVideoProcessor = Future<WatermarkedVideoResult>
    Function(WatermarkVideoRequest request);

class WatermarkVideoException implements Exception {
  const WatermarkVideoException(this.message);

  final String message;

  @override
  String toString() => message;
}

class FfmpegWatermarkVideoProcessor {
  FfmpegWatermarkVideoProcessor({
    AssetBundle? assetBundle,
    this.watermarkAssetPath = 'assets/images/brand/postdee_logo_dark.png',
  }) : assetBundle = assetBundle ?? rootBundle;

  final AssetBundle assetBundle;
  final String watermarkAssetPath;

  Future<WatermarkedVideoResult> call(WatermarkVideoRequest request) async {
    if (!await request.inputFile.exists()) {
      throw const WatermarkVideoException('ไม่พบไฟล์วิดีโอสำหรับใส่ลายน้ำ');
    }

    final workingDirectory = await Directory.systemTemp.createTemp(
      'postdee-watermark-',
    );
    final watermarkFile = await _copyWatermarkAsset(workingDirectory);
    final outputFile = File(
      '${workingDirectory.path}${Platform.pathSeparator}${_watermarkedFileName(request.fileName)}',
    );

    final session = await FFmpegKit.executeWithArguments(
      _buildWatermarkArguments(
        inputPath: request.inputFile.path,
        watermarkPath: watermarkFile.path,
        outputPath: outputFile.path,
      ),
    );
    final returnCode = await session.getReturnCode();

    if (!ReturnCode.isSuccess(returnCode)) {
      final logs = await session.getAllLogsAsString();
      final details = logs == null || logs.trim().isEmpty
          ? 'FFmpeg return code: $returnCode'
          : logs.trim();

      throw WatermarkVideoException(
        'ใส่ลายน้ำวิดีโอไม่สำเร็จ: $details',
      );
    }

    if (!await outputFile.exists()) {
      throw const WatermarkVideoException(
        'ใส่ลายน้ำแล้วแต่ไม่พบไฟล์ผลลัพธ์',
      );
    }

    return WatermarkedVideoResult(
      file: outputFile,
      fileName: outputFile.uri.pathSegments.last,
      sizeBytes: await outputFile.length(),
    );
  }

  Future<File> _copyWatermarkAsset(Directory workingDirectory) async {
    final assetData = await assetBundle.load(watermarkAssetPath);
    final watermarkFile = File(
      '${workingDirectory.path}${Platform.pathSeparator}postdee-watermark.png',
    );

    await watermarkFile.writeAsBytes(assetData.buffer.asUint8List());

    return watermarkFile;
  }

  List<String> _buildWatermarkArguments({
    required String inputPath,
    required String watermarkPath,
    required String outputPath,
  }) {
    return [
      '-y',
      '-i',
      inputPath,
      '-i',
      watermarkPath,
      '-filter_complex',
      '[1:v]scale=240:-1,format=rgba,colorchannelmixer=aa=0.72[wm];'
          '[0:v][wm]overlay=W-w-32:H-h-32:format=auto[v]',
      '-map',
      '[v]',
      '-map',
      '0:a?',
      '-c:v',
      'mpeg4',
      '-q:v',
      '4',
      '-c:a',
      'copy',
      '-movflags',
      '+faststart',
      outputPath,
    ];
  }

  String _watermarkedFileName(String fileName) {
    final trimmedFileName = fileName.trim();
    final dotIndex = trimmedFileName.lastIndexOf('.');

    if (dotIndex <= 0) {
      return '${trimmedFileName}_watermarked.mp4';
    }

    final baseName = trimmedFileName.substring(0, dotIndex);
    final extension = trimmedFileName.substring(dotIndex);

    return '${baseName}_watermarked$extension';
  }
}
