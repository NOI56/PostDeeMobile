import 'dart:io';

import 'package:ffmpeg_kit_flutter_new_video/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new_video/ffprobe_kit.dart';
import 'package:ffmpeg_kit_flutter_new_video/return_code.dart';
import 'package:ffmpeg_kit_flutter_new_video/session_state.dart';
import 'package:flutter/services.dart';

class SubtitleSegment {
  const SubtitleSegment({
    required this.text,
    required this.start,
    required this.end,
  });

  final String text;
  final double start;
  final double end;
}

class SilenceCutRange {
  const SilenceCutRange({required this.start, required this.end});

  final double start;
  final double end;
}

enum VideoRenderPurpose { preview, export }

class VideoPreviewProfile {
  const VideoPreviewProfile({
    required this.maxVideoDimension,
    required this.videoBitrate,
    required this.maxVideoFrameRate,
  });

  final int maxVideoDimension;
  final String videoBitrate;
  final int maxVideoFrameRate;
}

/// Keeps short previews reasonably sharp while making longer source videos
/// cheaper to process on-device. Full exports do not use this profile.
VideoPreviewProfile videoPreviewProfileForSourceDuration(double seconds) {
  if (seconds > 60) {
    return const VideoPreviewProfile(
      maxVideoDimension: 540,
      videoBitrate: '1M',
      maxVideoFrameRate: 20,
    );
  }

  return const VideoPreviewProfile(
    maxVideoDimension: 720,
    videoBitrate: '2M',
    maxVideoFrameRate: 24,
  );
}

class RenderCancellationToken {
  bool _isCancelled = false;
  Future<void> Function()? _attachedCancel;

  bool get isCancelled => _isCancelled;

  Future<void> attach(Future<void> Function() cancel) async {
    _attachedCancel = cancel;
    if (_isCancelled) {
      await cancel();
    }
  }

  void detach(Future<void> Function() cancel) {
    if (identical(_attachedCancel, cancel)) {
      _attachedCancel = null;
    }
  }

  Future<void> cancel() async {
    if (_isCancelled) {
      return;
    }
    _isCancelled = true;
    await _attachedCancel?.call();
  }
}

class BurnSubtitleRequest {
  const BurnSubtitleRequest({
    required this.inputFile,
    required this.fileName,
    required this.segments,
    this.speed = 1.0,
    this.volume = 1.0,
    this.trimStartSec,
    this.trimEndSec,
    this.silenceRanges = const [],
    this.filterIndex = 0,
    this.brightness = 0,
    this.contrast = 0,
    this.textOverlays = const [],
    this.stickerImagePaths = const [],
    this.stickerPositions = const [],
    this.subtitleFontSize = 18,
    this.subtitleAtBottom = true,
    this.preserveTempDirectoryPaths = const {},
    this.outputDurationSeconds,
    this.onProgress,
    this.renderPurpose = VideoRenderPurpose.export,
    this.maxVideoDimension,
    this.videoBitrate,
    this.maxVideoFrameRate,
    this.cancellationToken,
  });

  final File inputFile;
  final String fileName;
  final List<SubtitleSegment> segments;
  final double speed;
  final double volume;
  final double? trimStartSec;
  final double? trimEndSec;
  final List<SilenceCutRange> silenceRanges;
  final int filterIndex;
  final double brightness;
  final double contrast;
  final List<TextOverlaySpec> textOverlays;

  /// PNG files (already rendered with full-color emoji) to composite onto the
  /// video at [stickerPositions] (parallel list of normalized centers).
  final List<String> stickerImagePaths;
  final List<(double dx, double dy)> stickerPositions;

  /// Burned subtitle font size and whether it sits at the bottom (vs top).
  final double subtitleFontSize;
  final bool subtitleAtBottom;

  /// Render-result directories that must remain available until this render
  /// succeeds. This lets review flows keep the last accepted video on failure.
  final Set<String> preserveTempDirectoryPaths;

  /// Expected length of the rendered output (after cuts/speed), used to turn
  /// FFmpeg's processed-time statistics into a 0..1 progress fraction.
  final double? outputDurationSeconds;

  /// Optional render progress reporter (0..1).
  final RenderProgressCallback? onProgress;

  /// Preview renders are intentionally smaller and are never uploaded as the
  /// final social video. Export renders keep the source dimensions.
  final VideoRenderPurpose renderPurpose;
  final int? maxVideoDimension;
  final String? videoBitrate;
  final int? maxVideoFrameRate;
  final RenderCancellationToken? cancellationToken;
}

/// Reports render progress (0..1).
typedef RenderProgressCallback = void Function(double fraction);

class BurnedSubtitleResult {
  const BurnedSubtitleResult({
    required this.file,
    required this.fileName,
    required this.sizeBytes,
    this.colorFilterSkipped = false,
  });

  final File file;
  final String fileName;
  final int sizeBytes;
  final bool colorFilterSkipped;
}

typedef SubtitleBurnVideoProcessor = Future<BurnedSubtitleResult> Function(
    BurnSubtitleRequest request);

class SubtitleBurnException implements Exception {
  const SubtitleBurnException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Formats a time in seconds as an SRT timestamp: `HH:MM:SS,mmm`.
String formatSrtTimestamp(double seconds) {
  final totalMs = (seconds * 1000).round().clamp(0, 359999999);
  final hours = totalMs ~/ 3600000;
  final minutes = (totalMs % 3600000) ~/ 60000;
  final secs = (totalMs % 60000) ~/ 1000;
  final millis = totalMs % 1000;

  String pad(int value, int width) => value.toString().padLeft(width, '0');

  return '${pad(hours, 2)}:${pad(minutes, 2)}:${pad(secs, 2)},${pad(millis, 3)}';
}

/// Reads the latest processed media time written by FFmpeg's `-progress`
/// output. Despite its legacy name, `out_time_ms` is also expressed in
/// microseconds by FFmpeg, just like `out_time_us`.
double? parseFfmpegProgressSeconds(String content) {
  final values = <String, String>{};
  for (final line in content.split(RegExp(r'\r?\n'))) {
    final separator = line.indexOf('=');
    if (separator <= 0) {
      continue;
    }
    values[line.substring(0, separator)] = line.substring(separator + 1);
  }

  final microseconds =
      int.tryParse(values['out_time_us'] ?? values['out_time_ms'] ?? '');
  if (microseconds != null) {
    return microseconds / Duration.microsecondsPerSecond;
  }

  final timestamp = values['out_time'];
  if (timestamp == null) {
    return null;
  }
  final parts = timestamp.split(':');
  if (parts.length != 3) {
    return null;
  }
  final hours = int.tryParse(parts[0]);
  final minutes = int.tryParse(parts[1]);
  final seconds = double.tryParse(parts[2]);
  if (hours == null || minutes == null || seconds == null) {
    return null;
  }
  return hours * 3600 + minutes * 60 + seconds;
}

/// Builds an SRT subtitle file body from transcript segments. Pure + testable.
String buildSrtContent(List<SubtitleSegment> segments) {
  final buffer = StringBuffer();

  for (var index = 0; index < segments.length; index += 1) {
    final segment = segments[index];
    final text = segment.text.trim();

    if (text.isEmpty) {
      continue;
    }

    buffer.writeln('${index + 1}');
    buffer.writeln(
        '${formatSrtTimestamp(segment.start)} --> ${formatSrtTimestamp(segment.end)}');
    buffer.writeln(text);
    buffer.writeln();
  }

  return buffer.toString();
}

/// Builds the libass `force_style` for burned subtitles. [atBottom] uses
/// Alignment=2 (bottom-center) or 8 (top-center). Pure + testable.
String buildSubtitleForceStyle({
  double fontSize = 18,
  bool atBottom = true,
  String fontName = 'Prompt',
}) {
  final size = fontSize.round();
  final alignment = atBottom ? 2 : 8;
  final safeFontName = fontName.replaceAll(RegExp(r"[',:]"), '').trim();

  return 'FontName=${safeFontName.isEmpty ? 'Prompt' : safeFontName},'
      'Fontsize=$size,PrimaryColour=&H00FFFFFF,OutlineColour=&H00000000,'
      'BorderStyle=1,Outline=2,Alignment=$alignment';
}

/// A video encoder choice for the render: the FFmpeg codec name plus its
/// encoder flags and whether dimensions must be padded to even numbers (the
/// platform H.264 hardware encoders require it).
class VideoEncoderOption {
  const VideoEncoderOption({
    required this.codec,
    required this.encoderArgs,
    required this.scaleEvenDimensions,
  });

  final String codec;
  final List<String> encoderArgs;
  final bool scaleEvenDimensions;
}

/// Universal, license-safe fallback. MPEG-4 Part 2 always works in the LGPL
/// ffmpeg-kit build but yields larger, less compatible files than H.264.
const VideoEncoderOption fallbackMpeg4Encoder = VideoEncoderOption(
  codec: 'mpeg4',
  encoderArgs: ['-q:v', '4'],
  scaleEvenDimensions: false,
);

/// Picks the platform hardware H.264 encoder (no GPL/libx264 needed) so exports
/// are H.264 — the format the social platforms expect — with MPEG-4 as the
/// universal fallback. Pure + testable.
VideoEncoderOption hardwareH264Encoder({
  required bool isAndroid,
  required bool isIOS,
  String videoBitrate = '6M',
}) {
  final encoderArgs = ['-b:v', videoBitrate, '-pix_fmt', 'yuv420p'];

  if (isAndroid) {
    return VideoEncoderOption(
      codec: 'h264_mediacodec',
      encoderArgs: encoderArgs,
      scaleEvenDimensions: true,
    );
  }
  if (isIOS) {
    return VideoEncoderOption(
      codec: 'h264_videotoolbox',
      encoderArgs: encoderArgs,
      scaleEvenDimensions: true,
    );
  }

  return fallbackMpeg4Encoder;
}

/// Clips subtitle segments to the trim window and shifts them so 0 = trim start
/// (so subtitles stay in sync with the trimmed output). Pure + testable.
List<SubtitleSegment> clipSegmentsToTrim(
  List<SubtitleSegment> segments, {
  double? trimStartSec,
  double? trimEndSec,
}) {
  final start = trimStartSec ?? 0;

  return [
    for (final segment in segments)
      if (segment.end > start &&
          (trimEndSec == null || segment.start < trimEndSec))
        SubtitleSegment(
          text: segment.text,
          start: (segment.start - start).clamp(0, double.infinity).toDouble(),
          end: ((trimEndSec != null && segment.end > trimEndSec
                      ? trimEndSec
                      : segment.end) -
                  start)
              .clamp(0, double.infinity)
              .toDouble(),
        ),
  ];
}

/// Finds silent gaps between consecutive transcript segments longer than
/// [minGapSec]. Whisper word timing gives finer gaps; segment gaps are the
/// conservative first pass. Pure + testable.
List<SilenceCutRange> detectSilenceRanges(
  List<SubtitleSegment> segments, {
  double minGapSec = 0.8,
}) {
  final sorted = [...segments]..sort((a, b) => a.start.compareTo(b.start));
  final ranges = <SilenceCutRange>[];

  for (var i = 0; i < sorted.length - 1; i += 1) {
    final gapStart = sorted[i].end;
    final gapEnd = sorted[i + 1].start;

    if (gapEnd - gapStart >= minGapSec) {
      ranges.add(SilenceCutRange(start: gapStart, end: gapEnd));
    }
  }

  return ranges;
}

/// Shifts silence ranges into the trimmed timeline (0 = trim start) and clips
/// them to the trim window. Pure + testable.
List<SilenceCutRange> clipSilenceToTrim(
  List<SilenceCutRange> ranges, {
  double? trimStartSec,
  double? trimEndSec,
}) {
  final start = trimStartSec ?? 0;

  return [
    for (final range in ranges)
      if (range.end > start && (trimEndSec == null || range.start < trimEndSec))
        SilenceCutRange(
          start: (range.start - start).clamp(0, double.infinity).toDouble(),
          end: ((trimEndSec != null && range.end > trimEndSec
                      ? trimEndSec
                      : range.end) -
                  start)
              .clamp(0, double.infinity)
              .toDouble(),
        ),
  ];
}

/// Builds the color-grade video filter for a preset look plus brightness /
/// contrast adjustments (editor values are -1..1). Returns '' for "normal".
/// Pure + testable.
String buildColorFilter({
  required int filterIndex,
  double brightness = 0,
  double contrast = 0,
}) {
  final filters = <String>[];

  if (brightness != 0 || contrast != 0) {
    // The mobile "video" FFmpeg build does not include `eq`, but it does
    // include `lutrgb`. Apply the same brightness offset and contrast around
    // the mid point to each RGB channel so these controls work on-device.
    final lutContrast = (1 + contrast).toStringAsFixed(3);
    final brightnessOffset = brightness * 0.5 * 255;
    final signedOffset = brightnessOffset >= 0
        ? '+${brightnessOffset.toStringAsFixed(3)}'
        : brightnessOffset.toStringAsFixed(3);
    final expression = "'clip((val-128)*$lutContrast+128$signedOffset,0,255)'";
    filters.add('lutrgb=r=$expression:g=$expression:b=$expression');
  }

  switch (filterIndex) {
    case 1: // สดใส (vivid)
      filters.add('hue=s=1.400');
      break;
    case 2: // วินเทจ (vintage)
      filters.add('hue=s=0.700');
      filters.add('colorbalance=rs=0.10:gs=0.05:bs=-0.10');
      break;
    case 3: // ขาวดำ (B&W)
      filters.add('hue=s=0');
      break;
    case 4: // อบอุ่น (warm)
      filters.add('colorbalance=rs=0.15:bs=-0.12');
      break;
    case 5: // เย็น (cool)
      filters.add('colorbalance=rs=-0.10:bs=0.15');
      break;
  }

  return filters.join(',');
}

/// Tries the requested grade first, then preserves the source colors when a
/// device FFmpeg build or encoder cannot render the requested filter chain.
List<String> buildColorFilterFallbacks(String requestedColorFilter) =>
    requestedColorFilter.isEmpty ? const [''] : [requestedColorFilter, ''];

String _sanitizeDrawText(String text) => text
    .replaceAll('\\', ' ')
    .replaceAll("'", '’')
    .replaceAll(':', ' ')
    .replaceAll('%', ' ')
    .trim();

/// A text overlay with a normalized position ([dx] = horizontal centre,
/// [dy] = top), both 0..1 of the frame.
class TextOverlaySpec {
  const TextOverlaySpec(this.text, {this.dx = 0.5, this.dy = 0.18});

  final String text;
  final double dx;
  final double dy;
}

/// Builds `drawtext` filters placing each overlay at its normalized position.
/// Pure + testable. (Needs a bundled TTF font path on device.)
List<String> buildDrawTextFilters(
  List<TextOverlaySpec> overlays, {
  required String fontPath,
}) {
  final escapedFont = fontPath.replaceAll('\\', '\\\\').replaceAll(':', '\\:');
  final filters = <String>[];

  for (final overlay in overlays) {
    final text = _sanitizeDrawText(overlay.text);

    if (text.isEmpty) {
      continue;
    }

    filters.add(
      "drawtext=fontfile='$escapedFont':text='$text':expansion=none:"
      'fontcolor=white:fontsize=28:borderw=3:bordercolor=black:'
      'x=(w*${overlay.dx.toStringAsFixed(3)}-text_w/2):'
      'y=h*${overlay.dy.toStringAsFixed(3)}',
    );
  }

  return filters;
}

/// Builds a `-filter_complex` graph that runs the single-stream [videoFilters]
/// on the main input, then composites [stickerCount] PNG overlay inputs (image
/// inputs 1..n) stacked down from the top-right corner. The final output is
/// labelled `[vout]`. `eof_action=repeat` keeps each single-frame sticker
/// visible for the whole clip. Pure + testable.
String buildStickerFilterComplex({
  required List<String> videoFilters,
  required int stickerCount,
  List<(double dx, double dy)> positions = const [],
  int marginPx = 12,
  int stepPx = 104,
}) {
  final segments = <String>[];
  var label = '0:v';

  if (videoFilters.isNotEmpty) {
    segments.add('[0:v]${videoFilters.join(',')}[vbase]');
    label = 'vbase';
  }

  for (var i = 0; i < stickerCount; i += 1) {
    final outLabel = i == stickerCount - 1 ? 'vout' : 'v$i';
    // Use an explicit drag position when given; otherwise stack from top-right.
    final overlayXy = i < positions.length
        ? 'main_w*${positions[i].$1.toStringAsFixed(3)}-overlay_w/2:'
            'main_h*${positions[i].$2.toStringAsFixed(3)}-overlay_h/2'
        : 'main_w-overlay_w-$marginPx:${marginPx + i * stepPx}';
    segments.add(
      '[$label][${i + 1}:v]'
      'overlay=$overlayXy:eof_action=repeat[$outLabel]',
    );
    label = outLabel;
  }

  return segments.join(';');
}

List<SilenceCutRange> _normalizeSilenceRanges(
  List<SilenceCutRange> ranges,
) {
  final sorted = [
    for (final range in ranges)
      if (range.start.isFinite && range.end.isFinite && range.end > range.start)
        SilenceCutRange(
          start: range.start < 0 ? 0 : range.start,
          end: range.end,
        ),
  ]..sort((left, right) => left.start.compareTo(right.start));
  final merged = <SilenceCutRange>[];

  for (final range in sorted) {
    if (merged.isEmpty || range.start > merged.last.end) {
      merged.add(range);
      continue;
    }
    final previous = merged.removeLast();
    merged.add(
      SilenceCutRange(
        start: previous.start,
        end: range.end > previous.end ? range.end : previous.end,
      ),
    );
  }

  return merged;
}

String _buildAudioSilenceConcatFilter(
  List<SilenceCutRange> silenceRanges, {
  List<String> trailingFilters = const [],
}) {
  final keepRanges = <(double, double?)>[];
  var cursor = 0.0;

  for (final range in silenceRanges) {
    if (range.start > cursor) {
      keepRanges.add((cursor, range.start));
    }
    if (range.end > cursor) {
      cursor = range.end;
    }
  }
  keepRanges.add((cursor, null));

  if (keepRanges.length == 1) {
    final keep = keepRanges.single;
    final filters = <String>[
      'atrim=start=${keep.$1.toStringAsFixed(3)}',
      'asetpts=PTS-STARTPTS',
      ...trailingFilters,
    ];
    return '[0:a]${filters.join(',')}[aout]';
  }

  final segments = <String>[];
  final labels = <String>[];
  for (var index = 0; index < keepRanges.length; index += 1) {
    final keep = keepRanges[index];
    final end = keep.$2 == null ? '' : ':end=${keep.$2!.toStringAsFixed(3)}';
    final label = 'akeep$index';
    segments.add(
      '[0:a]atrim=start=${keep.$1.toStringAsFixed(3)}$end,'
      'asetpts=PTS-STARTPTS[$label]',
    );
    labels.add('[$label]');
  }

  final trailing =
      trailingFilters.isEmpty ? '' : ',${trailingFilters.join(',')}';
  segments.add(
    '${labels.join()}concat=n=${labels.length}:v=0:a=1$trailing[aout]',
  );
  return segments.join(';');
}

/// Builds the FFmpeg argument list for an edit render: color grade, trim
/// (`-ss`/`-to`), burned subtitles, text overlays, sticker overlays, silence
/// removal (video `select` + compact audio `concat`), speed and volume.
/// Subtitles are burned BEFORE the silence cut so the burned-in pixels travel
/// with their frames — no subtitle re-timing needed. Pure + testable.
List<String> buildEditFfmpegArguments({
  required String inputPath,
  required String outputPath,
  String? subtitlePath,
  String? subtitleFontsDirectory,
  String subtitleFontName = 'Prompt',
  String colorFilter = '',
  List<String> drawTextFilters = const [],
  double speed = 1.0,
  double volume = 1.0,
  double? trimStartSec,
  double? trimEndSec,
  List<SilenceCutRange> silenceRanges = const [],
  List<String> stickerImagePaths = const [],
  List<(double dx, double dy)> stickerPositions = const [],
  double subtitleFontSize = 18,
  bool subtitleAtBottom = true,
  String videoCodec = 'mpeg4',
  List<String> videoEncoderArgs = const ['-q:v', '4'],
  bool scaleEvenDimensions = false,
  int? maxVideoDimension,
  int? maxVideoFrameRate,
  String? progressPath,
}) {
  final args = <String>['-y'];
  if (progressPath != null && progressPath.trim().isNotEmpty) {
    args.addAll([
      '-stats_period',
      '0.5',
      '-progress',
      progressPath,
      '-nostats',
    ]);
  }
  args.addAll(['-i', inputPath]);

  // Sticker overlays arrive as extra image inputs (indices 1..n).
  for (final stickerPath in stickerImagePaths) {
    args.addAll(['-i', stickerPath]);
  }

  if (trimStartSec != null && trimStartSec > 0) {
    args.addAll(['-ss', trimStartSec.toStringAsFixed(3)]);
  }
  if (trimEndSec != null) {
    args.addAll(['-to', trimEndSec.toStringAsFixed(3)]);
  }

  final normalizedSilenceRanges = _normalizeSilenceRanges(silenceRanges);
  final hasSilence = normalizedSilenceRanges.isNotEmpty;
  // Single-quoted so the commas inside between(t,..) survive filtergraph parsing.
  final keepExpr = normalizedSilenceRanges
      .map((range) =>
          'between(t,${range.start.toStringAsFixed(3)},${range.end.toStringAsFixed(3)})')
      .join('+');

  final videoFilters = <String>[];
  if (maxVideoDimension != null && maxVideoDimension > 0) {
    videoFilters.add(
      "scale=w='min($maxVideoDimension,iw)':"
      "h='min($maxVideoDimension,ih)':"
      'force_original_aspect_ratio=decrease:force_divisible_by=2',
    );
  } else if (scaleEvenDimensions) {
    // Hardware H.264 encoders reject odd width/height; round both down.
    videoFilters.add('scale=trunc(iw/2)*2:trunc(ih/2)*2');
  }
  if (maxVideoFrameRate != null && maxVideoFrameRate > 0) {
    videoFilters.add('fps=$maxVideoFrameRate');
  }
  if (colorFilter.isNotEmpty) {
    videoFilters.add(colorFilter);
  }
  if (subtitlePath != null) {
    final escaped =
        subtitlePath.replaceAll('\\', '\\\\').replaceAll(':', '\\:');
    final escapedFontsDirectory =
        subtitleFontsDirectory?.replaceAll('\\', '\\\\').replaceAll(':', '\\:');
    final forceStyle = buildSubtitleForceStyle(
      fontSize: subtitleFontSize,
      atBottom: subtitleAtBottom,
      fontName: subtitleFontName,
    );
    final fontsDirectoryOption = escapedFontsDirectory == null
        ? ''
        : ":fontsdir='$escapedFontsDirectory'";
    videoFilters.add(
      "subtitles='$escaped'$fontsDirectoryOption:force_style='$forceStyle'",
    );
  }
  videoFilters.addAll(drawTextFilters);
  if (hasSilence) {
    videoFilters.add("select='not($keepExpr)'");
    videoFilters.add('setpts=N/FRAME_RATE/TB');
  }
  if (speed != 1.0) {
    videoFilters.add('setpts=${(1 / speed).toStringAsFixed(4)}*PTS');
  }

  final audioFilters = <String>[];
  if (speed != 1.0) {
    audioFilters.add('atempo=${speed.toStringAsFixed(3)}');
  }
  if (volume != 1.0) {
    audioFilters.add('volume=${volume.toStringAsFixed(3)}');
  }

  final complexFilters = <String>[];
  if (stickerImagePaths.isNotEmpty) {
    complexFilters.add(
      buildStickerFilterComplex(
        videoFilters: videoFilters,
        stickerCount: stickerImagePaths.length,
        positions: stickerPositions,
      ),
    );
  }
  if (hasSilence) {
    complexFilters.add(
      _buildAudioSilenceConcatFilter(
        normalizedSilenceRanges,
        trailingFilters: audioFilters,
      ),
    );
  }

  // Silence removal needs audio segments concatenated so both streams become
  // shorter together. `aselect` alone leaves the original audio timestamps.
  if (complexFilters.isNotEmpty) {
    args.addAll([
      '-filter_complex',
      complexFilters.join(';'),
    ]);
    if (stickerImagePaths.isNotEmpty) {
      args.addAll(['-map', '[vout]']);
    } else {
      if (videoFilters.isNotEmpty) {
        args.addAll(['-vf', videoFilters.join(',')]);
      }
      args.addAll(['-map', '0:v:0?']);
    }
    args.addAll(['-map', hasSilence ? '[aout]' : '0:a?']);
  } else if (videoFilters.isNotEmpty) {
    args.addAll(['-vf', videoFilters.join(',')]);
  }

  if (!hasSilence && audioFilters.isNotEmpty) {
    args.addAll(['-af', audioFilters.join(',')]);
  }

  args.addAll(['-c:v', videoCodec, ...videoEncoderArgs]);
  args.addAll(hasSilence || audioFilters.isNotEmpty
      ? ['-c:a', 'aac']
      : ['-c:a', 'copy']);
  args.addAll(['-movflags', '+faststart', outputPath]);

  return args;
}

const _renderTempPrefixes = ['postdee-edit-', 'postdee-sticker-'];

/// Deletes leftover PostDee render temp dirs under [base] (outputs/stickers from
/// previous exports that are no longer needed), keeping [keepPaths] — the
/// current render's dirs. Best-effort; returns how many dirs were removed.
/// Pure-ish + testable (pass a fake [base]).
Future<int> purgeEditTempDirs(
  Directory base, {
  Set<String> keepPaths = const {},
}) async {
  if (!await base.exists()) {
    return 0;
  }

  var removed = 0;
  await for (final entity in base.list(followLinks: false)) {
    if (entity is! Directory) {
      continue;
    }

    final name =
        entity.path.split(RegExp(r'[\\/]')).where((s) => s.isNotEmpty).last;
    final isOurs = _renderTempPrefixes.any(name.startsWith);

    if (isOurs && !keepPaths.contains(entity.path)) {
      try {
        await entity.delete(recursive: true);
        removed += 1;
      } catch (_) {
        // Ignore dirs we can't delete (in use / permissions).
      }
    }
  }

  return removed;
}

/// Probes a rendered file and returns its stream types (e.g. `['video',
/// 'audio']`), or null when the file can't be read.
typedef RenderedStreamTypesProbe = Future<List<String?>?> Function(String path);

/// Whether a rendered output actually contains a video stream. Hardware
/// encoders can exit 0 while writing an audio-only file (seen with
/// h264_mediacodec on the Android emulator), so a successful FFmpeg return
/// code alone doesn't prove the render worked. Pure + testable.
bool renderedOutputHasVideo(Iterable<String?>? streamTypes) =>
    streamTypes != null && streamTypes.contains('video');

/// Default [RenderedStreamTypesProbe]: FFprobe on the rendered file.
Future<List<String?>?> ffprobeStreamTypes(String path) async {
  final session = await FFprobeKit.getMediaInformation(path);
  final information = session.getMediaInformation();
  if (information == null) return null;
  return [
    for (final stream in information.getStreams()) stream.getType(),
  ];
}

/// Renders an edited clip on-device with FFmpeg (trim + subtitles + speed +
/// volume). Produces a new MP4 ready for the existing upload/post flow.
class FfmpegSubtitleBurnVideoProcessor {
  const FfmpegSubtitleBurnVideoProcessor({
    this.assetBundle,
    this.fontAssetPath = 'assets/fonts/prompt/Prompt-Bold.ttf',
    this.probeStreamTypes = ffprobeStreamTypes,
    this.renderTempDirectory,
  });

  final AssetBundle? assetBundle;
  final String fontAssetPath;

  /// Injectable so tests can fake the post-render stream check.
  final RenderedStreamTypesProbe probeStreamTypes;

  /// Overrides the render temp root in tests. Production uses the platform
  /// system temp directory.
  final Directory? renderTempDirectory;

  Future<BurnedSubtitleResult> call(BurnSubtitleRequest request) async {
    if (!await request.inputFile.exists()) {
      throw const SubtitleBurnException('ไม่พบไฟล์วิดีโอสำหรับใส่ซับ');
    }

    // Reclaim earlier exports while keeping this input and its sticker dirs.
    await purgeEditTempDirs(
      renderTempDirectory ?? Directory.systemTemp,
      keepPaths: {
        ...request.preserveTempDirectoryPaths,
        request.inputFile.parent.path,
        for (final path in request.stickerImagePaths) File(path).parent.path,
      },
    );

    final trimmedSegments = clipSegmentsToTrim(
      request.segments,
      trimStartSec: request.trimStartSec,
      trimEndSec: request.trimEndSec,
    );
    final trimmedSilence = clipSilenceToTrim(
      request.silenceRanges,
      trimStartSec: request.trimStartSec,
      trimEndSec: request.trimEndSec,
    );
    final colorFilter = buildColorFilter(
      filterIndex: request.filterIndex,
      brightness: request.brightness,
      contrast: request.contrast,
    );
    final hasText =
        request.textOverlays.any((overlay) => overlay.text.trim().isNotEmpty);
    final srtBody = buildSrtContent(trimmedSegments);
    final hasSubtitles = srtBody.trim().isNotEmpty;
    final hasEdits = hasSubtitles ||
        trimmedSilence.isNotEmpty ||
        colorFilter.isNotEmpty ||
        hasText ||
        request.stickerImagePaths.isNotEmpty ||
        request.speed != 1.0 ||
        request.volume != 1.0 ||
        (request.trimStartSec != null && request.trimStartSec! > 0) ||
        request.trimEndSec != null;

    if (!hasEdits) {
      throw const SubtitleBurnException('ยังไม่มีการแก้ไขให้เรนเดอร์');
    }

    final workingDirectory =
        await Directory.systemTemp.createTemp('postdee-edit-');
    final separator = Platform.pathSeparator;

    String? renderFontPath;
    if (hasSubtitles || hasText) {
      final bundle = assetBundle ?? rootBundle;
      final fontData = await bundle.load(fontAssetPath);
      final fontFile =
          File('${workingDirectory.path}${separator}Prompt-Bold.ttf');
      await fontFile.writeAsBytes(fontData.buffer.asUint8List());
      renderFontPath = fontFile.path;
    }

    String? subtitlePath;
    if (hasSubtitles) {
      final srtFile = File('${workingDirectory.path}${separator}captions.srt');
      await srtFile.writeAsString(srtBody);
      subtitlePath = srtFile.path;
    }

    var drawTextFilters = const <String>[];
    if (hasText) {
      drawTextFilters = buildDrawTextFilters(
        request.textOverlays,
        fontPath: renderFontPath!,
      );
    }

    final outputFile = File(
      '${workingDirectory.path}$separator${_subtitledFileName(request.fileName)}',
    );
    final progressFile = File(
      '${workingDirectory.path}${separator}render-progress.txt',
    );

    // Prefer the platform hardware H.264 encoder for quality/compatibility,
    // then fall back to the universal MPEG-4 path if it fails on a device.
    final primary = hardwareH264Encoder(
      isAndroid: Platform.isAndroid,
      isIOS: Platform.isIOS,
      videoBitrate: request.videoBitrate ?? '6M',
    );
    final encoders = <VideoEncoderOption>[
      primary,
      if (primary.codec != fallbackMpeg4Encoder.codec) fallbackMpeg4Encoder,
    ];

    // Try the full render (with stickers) first; if the overlay step fails on a
    // device, retry without stickers so the rest of the edit still exports.
    final stickerVariants = request.stickerImagePaths.isEmpty
        ? <List<String>>[const []]
        : <List<String>>[request.stickerImagePaths, const []];

    // Poll FFmpeg's progress file, with native statistics as a fallback,
    // instead of depending on the package's Android async callback event sink.
    // That event sink can be unavailable even while FFmpeg runs normally.
    final outDuration = request.outputDurationSeconds;
    final onProgress = request.onProgress;

    var renderedOk = false;
    var colorFilterSkipped = false;
    String? failureLogs;
    render:
    for (final attemptedColorFilter in buildColorFilterFallbacks(colorFilter)) {
      for (final stickerPaths in stickerVariants) {
        for (final encoder in encoders) {
          if (request.cancellationToken?.isCancelled ?? false) {
            throw const SubtitleBurnException('ยกเลิกการเรนเดอร์แล้ว');
          }

          if (await progressFile.exists()) {
            await progressFile.delete();
          }

          final session = await FFmpegKit.executeWithArgumentsAsync(
            buildEditFfmpegArguments(
              inputPath: request.inputFile.path,
              outputPath: outputFile.path,
              subtitlePath: subtitlePath,
              subtitleFontsDirectory:
                  hasSubtitles ? workingDirectory.path : null,
              subtitleFontName: 'Prompt',
              colorFilter: attemptedColorFilter,
              drawTextFilters: drawTextFilters,
              speed: request.speed,
              volume: request.volume,
              trimStartSec: request.trimStartSec,
              trimEndSec: request.trimEndSec,
              silenceRanges: trimmedSilence,
              stickerImagePaths: stickerPaths,
              stickerPositions:
                  stickerPaths.isEmpty ? const [] : request.stickerPositions,
              subtitleFontSize: request.subtitleFontSize,
              subtitleAtBottom: request.subtitleAtBottom,
              videoCodec: encoder.codec,
              videoEncoderArgs: encoder.encoderArgs,
              scaleEvenDimensions: encoder.scaleEvenDimensions,
              maxVideoDimension: request.maxVideoDimension,
              maxVideoFrameRate: request.maxVideoFrameRate,
              progressPath: progressFile.path,
            ),
          );
          Future<void> cancelSession() => session.cancel();
          await request.cancellationToken?.attach(cancelSession);
          try {
            while (true) {
              if (onProgress != null &&
                  outDuration != null &&
                  outDuration > 0) {
                double? processedSeconds;
                try {
                  if (await progressFile.exists()) {
                    processedSeconds = parseFfmpegProgressSeconds(
                      await progressFile.readAsString(),
                    );
                  }
                } on FileSystemException {
                  // FFmpeg may be replacing the progress file while it is read.
                }
                if (processedSeconds == null) {
                  final statistics = await session.getLastReceivedStatistics();
                  if (statistics != null) {
                    processedSeconds = statistics.getTime() / 1000;
                  }
                }
                if (processedSeconds != null) {
                  onProgress(
                    (processedSeconds / outDuration).clamp(0.0, 0.99),
                  );
                }
              }

              final state = await session.getState();
              if (state == SessionState.completed ||
                  state == SessionState.failed) {
                break;
              }
              await Future<void>.delayed(
                const Duration(milliseconds: 250),
              );
            }
          } finally {
            request.cancellationToken?.detach(cancelSession);
          }
          final returnCode = await session.getReturnCode();

          if (ReturnCode.isSuccess(returnCode)) {
            // Trust but verify: some hardware encoders exit 0 while writing an
            // audio-only file. Only accept output with a real video stream.
            if (renderedOutputHasVideo(
                await probeStreamTypes(outputFile.path))) {
              renderedOk = true;
              colorFilterSkipped =
                  colorFilter.isNotEmpty && attemptedColorFilter.isEmpty;
              failureLogs = null;
              break render;
            }
            failureLogs =
                'encoder ${encoder.codec} exited 0 but wrote no video stream';
            continue;
          }

          // A cancel aborts the whole export — don't fall back to other paths.
          if (ReturnCode.isCancel(returnCode)) {
            throw const SubtitleBurnException('ยกเลิกการเรนเดอร์แล้ว');
          }

          final logs = await session.getAllLogsAsString();
          failureLogs = logs == null || logs.trim().isEmpty
              ? 'FFmpeg return code: $returnCode'
              : logs.trim();
        }
      }
    }

    if (!renderedOk) {
      throw SubtitleBurnException('เรนเดอร์วิดีโอไม่สำเร็จ: $failureLogs');
    }

    if (!await outputFile.exists()) {
      throw const SubtitleBurnException('เรนเดอร์แล้วแต่ไม่พบไฟล์ผลลัพธ์');
    }

    return BurnedSubtitleResult(
      file: outputFile,
      fileName: outputFile.uri.pathSegments.last,
      sizeBytes: await outputFile.length(),
      colorFilterSkipped: colorFilterSkipped,
    );
  }

  String _subtitledFileName(String fileName) {
    final trimmed = fileName.trim();
    final dotIndex = trimmed.lastIndexOf('.');

    if (dotIndex <= 0) {
      return '${trimmed}_subtitled.mp4';
    }

    return '${trimmed.substring(0, dotIndex)}_subtitled.mp4';
  }
}
