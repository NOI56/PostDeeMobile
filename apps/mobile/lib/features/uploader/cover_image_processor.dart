import 'dart:io';

import 'package:characters/characters.dart';
import 'package:ffmpeg_kit_flutter_new_video/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new_video/return_code.dart';
import 'package:flutter/services.dart';

enum CoverFontFamily { prompt, anuphan }

enum CoverSourceKind { videoFrame, galleryImage }

class CoverDesign {
  const CoverDesign({
    this.coverFrameTimeMs = 0,
    this.text = '',
    this.fontFamily = CoverFontFamily.prompt,
    this.fontWeight = 800,
    this.fontSize = 52,
    this.textColor = const Color(0xFFFFFFFF),
    this.backgroundColor = const Color(0xB3000000),
    this.dx = 0.5,
    this.dy = 0.22,
  });

  final int coverFrameTimeMs;
  final String text;
  final CoverFontFamily fontFamily;
  final int fontWeight;
  final double fontSize;
  final Color textColor;
  final Color backgroundColor;
  final double dx;
  final double dy;

  CoverDesign copyWith({
    int? coverFrameTimeMs,
    String? text,
    CoverFontFamily? fontFamily,
    int? fontWeight,
    double? fontSize,
    Color? textColor,
    Color? backgroundColor,
    double? dx,
    double? dy,
  }) {
    return CoverDesign(
      coverFrameTimeMs: coverFrameTimeMs ?? this.coverFrameTimeMs,
      text: text ?? this.text,
      fontFamily: fontFamily ?? this.fontFamily,
      fontWeight: fontWeight ?? this.fontWeight,
      fontSize: fontSize ?? this.fontSize,
      textColor: textColor ?? this.textColor,
      backgroundColor: backgroundColor ?? this.backgroundColor,
      dx: dx ?? this.dx,
      dy: dy ?? this.dy,
    );
  }
}

class CoverImageRequest {
  const CoverImageRequest({
    required this.videoFile,
    required this.fileName,
    required this.design,
    this.durationMs,
    this.sourceKind = CoverSourceKind.videoFrame,
    this.sourceImageFile,
    this.sourceImageName,
  });

  final File videoFile;
  final String fileName;
  final CoverDesign design;
  final int? durationMs;
  final CoverSourceKind sourceKind;
  final File? sourceImageFile;
  final String? sourceImageName;
}

class CoverEditorResult {
  const CoverEditorResult({
    required this.localImagePath,
    required this.sizeBytes,
    required this.design,
    this.durationMs,
    this.imageBytes,
    this.sourceKind = CoverSourceKind.videoFrame,
    this.sourceImagePath,
    this.sourceImageName,
  }) : _temporaryFiles = null;

  CoverEditorResult._temporary({
    required this.localImagePath,
    required this.sizeBytes,
    required this.design,
    required Directory temporaryDirectory,
    required CoverWorkingDirectoryDeleter deleteWorkingDirectory,
    this.durationMs,
    required this.imageBytes,
    this.sourceKind = CoverSourceKind.videoFrame,
    this.sourceImagePath,
    this.sourceImageName,
  }) : _temporaryFiles = _CoverTemporaryFiles(
          temporaryDirectory,
          deleteWorkingDirectory,
        );

  final String localImagePath;
  final int sizeBytes;
  final CoverDesign design;
  final int? durationMs;
  final Uint8List? imageBytes;
  final CoverSourceKind sourceKind;
  final String? sourceImagePath;
  final String? sourceImageName;
  final _CoverTemporaryFiles? _temporaryFiles;

  int get coverFrameTimeMs => design.coverFrameTimeMs;
  File get imageFile => File(localImagePath);
  File? get sourceImageFile =>
      sourceImagePath == null ? null : File(sourceImagePath!);

  CoverFileLease? retainTemporaryFiles() => _temporaryFiles?.retain();

  Future<void> cleanupTemporaryFiles() =>
      _temporaryFiles?.requestCleanup() ?? Future<void>.value();
}

class CoverFileLease {
  CoverFileLease._(this._owner);

  _CoverTemporaryFiles? _owner;

  Future<void> release() {
    final owner = _owner;
    _owner = null;
    return owner?.release() ?? Future<void>.value();
  }
}

class _CoverTemporaryFiles {
  _CoverTemporaryFiles(this.directory, this.deleteDirectory);

  final Directory directory;
  final CoverWorkingDirectoryDeleter deleteDirectory;
  int _activeLeases = 0;
  bool _cleanupRequested = false;
  Future<void>? _cleanupFuture;

  CoverFileLease retain() {
    _activeLeases += 1;
    return CoverFileLease._(this);
  }

  Future<void> requestCleanup() {
    _cleanupRequested = true;
    return _deleteIfReady();
  }

  Future<void> release() {
    if (_activeLeases > 0) _activeLeases -= 1;
    return _deleteIfReady();
  }

  Future<void> _deleteIfReady() {
    if (!_cleanupRequested || _activeLeases > 0) {
      return Future<void>.value();
    }
    return _cleanupFuture ??= deleteDirectory(directory);
  }
}

typedef CoverImageProcessor = Future<CoverEditorResult> Function(
  CoverImageRequest request,
);
typedef CoverCommandRunner = Future<bool> Function(List<String> arguments);
typedef CoverWorkingDirectoryCreator = Future<Directory> Function();
typedef CoverWorkingDirectoryDeleter = Future<void> Function(
  Directory directory,
);

class CoverImageException implements Exception {
  const CoverImageException(this.message);

  final String message;

  @override
  String toString() => message;
}

String coverFontAssetPath(CoverFontFamily family, int weight) {
  if (family == CoverFontFamily.anuphan) {
    if (weight <= 400) return 'assets/fonts/anuphan/Anuphan-Regular.ttf';
    if (weight <= 500) return 'assets/fonts/anuphan/Anuphan-Medium.ttf';
    if (weight <= 600) return 'assets/fonts/anuphan/Anuphan-SemiBold.ttf';
    return 'assets/fonts/anuphan/Anuphan-Bold.ttf';
  }

  if (weight <= 400) return 'assets/fonts/prompt/Prompt-Regular.ttf';
  if (weight <= 500) return 'assets/fonts/prompt/Prompt-Medium.ttf';
  if (weight <= 600) return 'assets/fonts/prompt/Prompt-SemiBold.ttf';
  if (weight <= 700) return 'assets/fonts/prompt/Prompt-Bold.ttf';
  if (weight <= 800) return 'assets/fonts/prompt/Prompt-ExtraBold.ttf';
  return 'assets/fonts/prompt/Prompt-Black.ttf';
}

const coverFrameEndMarginMs = 100;

int maxSelectableCoverFrameTimeMs(int durationMs) {
  if (durationMs <= 1) return 0;
  if (durationMs <= coverFrameEndMarginMs) return durationMs - 1;
  return durationMs - coverFrameEndMarginMs;
}

int clampCoverFrameTimeMs(int requestedMs, {required int durationMs}) =>
    requestedMs.clamp(0, maxSelectableCoverFrameTimeMs(durationMs));

/// Keeps long Thai cover copy inside the 1080 px export width. FFmpeg's
/// drawtext filter does not wrap text automatically, so write explicit line
/// breaks into its UTF-8 text file before rendering.
String formatCoverTextForExport(String value, {required double fontSize}) {
  final normalized = value.trim().replaceAll(RegExp(r'\s+'), ' ');
  if (normalized.isEmpty) return '';

  final graphemes = normalized.characters.take(48).toList();
  final maxCharactersPerLine =
      (936 / (fontSize.clamp(24, 96) * 0.78)).floor().clamp(12, 32);
  final lines = <String>[];
  var remaining = graphemes;

  while (remaining.isNotEmpty && lines.length < 4) {
    var splitAt = remaining.length.clamp(0, maxCharactersPerLine);
    if (splitAt < remaining.length) {
      final minimumWordBreak = (maxCharactersPerLine * 0.55).floor();
      for (var index = splitAt - 1; index >= minimumWordBreak; index -= 1) {
        if (remaining[index] == ' ') {
          splitAt = index;
          break;
        }
      }
    }

    final line = remaining.take(splitAt).join().trim();
    if (line.isNotEmpty) lines.add(line);
    remaining = remaining.skip(splitAt).toList();
    while (remaining.isNotEmpty && remaining.first == ' ') {
      remaining = remaining.skip(1).toList();
    }
  }

  return lines.join('\n');
}

List<String> buildCoverImageArguments({
  required String inputPath,
  required String outputPath,
  required String fontPath,
  required CoverDesign design,
  String? textFilePath,
  int? durationMs,
  int jpegQuality = 3,
  CoverSourceKind sourceKind = CoverSourceKind.videoFrame,
}) {
  final filters = <String>[
    'scale=1080:1920:force_original_aspect_ratio=increase',
    'crop=1080:1920',
  ];
  final text = design.text.trim();

  if (text.isNotEmpty) {
    if (textFilePath == null || textFilePath.trim().isEmpty) {
      throw ArgumentError.value(
        textFilePath,
        'textFilePath',
        'is required when cover text is not empty',
      );
    }
    final escapedFont = _escapeFilterPath(fontPath);
    final escapedTextFile = _escapeFilterPath(textFilePath);
    final textColor = _ffmpegColor(design.textColor);
    final backgroundColor = _ffmpegColor(design.backgroundColor);
    final boxEnabled = design.backgroundColor.a > 0;
    final dx = design.dx.clamp(0.08, 0.92).toStringAsFixed(3);
    final dy = design.dy.clamp(0.08, 0.92).toStringAsFixed(3);
    final fontSize = design.fontSize.round().clamp(24, 96);

    filters.add(
      "drawtext=fontfile='$escapedFont':textfile='$escapedTextFile':"
      'reload=0:expansion=none:'
      'fontcolor=$textColor:fontsize=$fontSize:'
      'borderw=2:bordercolor=0x000000@0.45:'
      'box=${boxEnabled ? 1 : 0}:boxcolor=$backgroundColor:boxborderw=22:'
      'text_align=center:line_spacing=10:fix_bounds=1:'
      'x=(w*$dx-text_w/2):y=(h*$dy-text_h/2)',
    );
  }

  return [
    '-y',
    '-i',
    inputPath,
    if (sourceKind == CoverSourceKind.videoFrame) ...[
      // Output-side seek is slower than input-side seek, but selects the frame
      // accurately instead of landing only on the nearest keyframe.
      '-ss',
      ((durationMs == null
                  ? design.coverFrameTimeMs.clamp(0, 86400000)
                  : clampCoverFrameTimeMs(
                      design.coverFrameTimeMs,
                      durationMs: durationMs,
                    )) /
              1000)
          .toStringAsFixed(3),
    ],
    '-frames:v',
    '1',
    '-vf',
    filters.join(','),
    '-an',
    '-q:v',
    jpegQuality.clamp(2, 10).toString(),
    outputPath,
  ];
}

String _escapeFilterPath(String value) => value
    .replaceAll('\\', '\\\\')
    .replaceAll(':', '\\:')
    .replaceAll("'", "\\'");

String _ffmpegColor(Color color) {
  final value = color.toARGB32();
  final rgb = (value & 0x00FFFFFF).toRadixString(16).padLeft(6, '0');
  final alpha = ((value >> 24) & 0xFF) / 255;
  return '0x$rgb@${alpha.toStringAsFixed(3)}';
}

class FfmpegCoverImageProcessor {
  FfmpegCoverImageProcessor({
    AssetBundle? assetBundle,
    CoverCommandRunner? runCommand,
    CoverWorkingDirectoryCreator? createWorkingDirectory,
    CoverWorkingDirectoryDeleter? deleteWorkingDirectory,
  })  : _assetBundle = assetBundle ?? rootBundle,
        _runCommand = runCommand ?? _runFfmpegCommand,
        _createWorkingDirectory = createWorkingDirectory ??
            (() => Directory.systemTemp.createTemp('postdee-cover-')),
        _deleteWorkingDirectory =
            deleteWorkingDirectory ?? _deleteDirectoryBestEffort;

  final AssetBundle _assetBundle;
  final CoverCommandRunner _runCommand;
  final CoverWorkingDirectoryCreator _createWorkingDirectory;
  final CoverWorkingDirectoryDeleter _deleteWorkingDirectory;

  static const maxCoverImageBytes = 2 * 1024 * 1024;

  Future<CoverEditorResult> call(CoverImageRequest request) async {
    if (!await request.videoFile.exists()) {
      throw const CoverImageException('ไม่พบไฟล์วิดีโอสำหรับสร้างหน้าปก');
    }

    final sourceImageFile = request.sourceImageFile;
    if (request.sourceKind == CoverSourceKind.galleryImage &&
        (sourceImageFile == null ||
            !await sourceImageFile.exists() ||
            await sourceImageFile.length() < 1)) {
      throw const CoverImageException('ไม่พบรูปหน้าปก กรุณาเลือกรูปใหม่');
    }

    final workingDirectory = await _createWorkingDirectory();
    try {
      if (!await workingDirectory.exists()) {
        await workingDirectory.create(recursive: true);
      }
      final durationMs = request.durationMs;
      final design = durationMs == null
          ? request.design
          : request.design.copyWith(
              coverFrameTimeMs: clampCoverFrameTimeMs(
                request.design.coverFrameTimeMs,
                durationMs: durationMs,
              ),
            );
      final separator = Platform.pathSeparator;
      var renderInputFile = request.videoFile;
      String? ownedSourceImagePath;
      String? sourceImageName;
      if (request.sourceKind == CoverSourceKind.galleryImage) {
        final sourceFileName = _fileName(sourceImageFile!.path);
        final requestedSourceName = request.sourceImageName?.trim() ?? '';
        sourceImageName = requestedSourceName.isEmpty
            ? sourceFileName
            : _fileName(requestedSourceName);
        if (sourceImageName.isEmpty) {
          sourceImageName = sourceFileName;
        }
        final ownedSourceImage = File(
          '${workingDirectory.path}${separator}postdee_cover_source'
          '${_fileExtension(sourceFileName)}',
        );
        await sourceImageFile.copy(ownedSourceImage.path);
        renderInputFile = ownedSourceImage;
        ownedSourceImagePath = ownedSourceImage.path;
      }
      final assetPath = coverFontAssetPath(
        design.fontFamily,
        design.fontWeight,
      );
      final fontData = await _assetBundle.load(assetPath);
      final fontFile = File(
        '${workingDirectory.path}$separator${_fileName(assetPath)}',
      );
      await fontFile.writeAsBytes(fontData.buffer.asUint8List());
      String? textFilePath;
      if (design.text.trim().isNotEmpty) {
        final textFile = File(
          '${workingDirectory.path}${separator}cover_text.txt',
        );
        await textFile.writeAsString(
          formatCoverTextForExport(
            design.text,
            fontSize: design.fontSize,
          ),
          flush: true,
        );
        textFilePath = textFile.path;
      }
      final outputFile = File(
        '${workingDirectory.path}${separator}postdee_cover.jpg',
      );
      var succeeded = await _runCommand(
        buildCoverImageArguments(
          inputPath: renderInputFile.path,
          outputPath: outputFile.path,
          fontPath: fontFile.path,
          design: design,
          textFilePath: textFilePath,
          durationMs: durationMs,
          sourceKind: request.sourceKind,
        ),
      );

      if (succeeded &&
          await outputFile.exists() &&
          await outputFile.length() > maxCoverImageBytes) {
        succeeded = await _runCommand(
          buildCoverImageArguments(
            inputPath: renderInputFile.path,
            outputPath: outputFile.path,
            fontPath: fontFile.path,
            design: design,
            textFilePath: textFilePath,
            durationMs: durationMs,
            jpegQuality: 6,
            sourceKind: request.sourceKind,
          ),
        );
      }

      if (!succeeded ||
          !await outputFile.exists() ||
          await outputFile.length() < 1 ||
          await outputFile.length() > maxCoverImageBytes) {
        throw const CoverImageException(
          'สร้างภาพหน้าปกไม่สำเร็จ กรุณาลองเลือกเฟรมหรือรูปใหม่',
        );
      }

      final imageBytes = await outputFile.readAsBytes();
      return CoverEditorResult._temporary(
        localImagePath: outputFile.path,
        sizeBytes: imageBytes.length,
        design: design,
        durationMs: durationMs,
        imageBytes: imageBytes,
        temporaryDirectory: workingDirectory,
        deleteWorkingDirectory: _deleteWorkingDirectory,
        sourceKind: request.sourceKind,
        sourceImagePath: ownedSourceImagePath,
        sourceImageName: sourceImageName,
      );
    } catch (_) {
      await _deleteWorkingDirectory(workingDirectory);
      rethrow;
    }
  }

  String _fileName(String assetPath) => assetPath.split(RegExp(r'[\\/]')).last;

  String _fileExtension(String fileName) {
    final dotIndex = fileName.lastIndexOf('.');
    if (dotIndex < 0 || dotIndex == fileName.length - 1) return '';
    final extension = fileName.substring(dotIndex).toLowerCase();
    return RegExp(r'^\.[a-z0-9]{1,10}$').hasMatch(extension) ? extension : '';
  }

  static Future<bool> _runFfmpegCommand(List<String> arguments) async {
    final session = await FFmpegKit.executeWithArguments(arguments);
    return ReturnCode.isSuccess(await session.getReturnCode());
  }
}

Future<void> _deleteDirectoryBestEffort(Directory directory) async {
  const attempts = 8;
  for (var attempt = 0; attempt < attempts; attempt += 1) {
    try {
      if (!await directory.exists()) return;
      await directory.delete(recursive: true);
      return;
    } on FileSystemException {
      if (attempt == attempts - 1) return;
      // Windows image decoders can retain a just-evicted file handle briefly.
      // Keep retries bounded so cleanup never delays publishing indefinitely.
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
  }
}
