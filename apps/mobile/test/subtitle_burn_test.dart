import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:postdee_mobile/features/ai_editing/subtitle_burn_video_processor.dart';

void main() {
  test('formats SRT timestamps as HH:MM:SS,mmm', () {
    expect(formatSrtTimestamp(0), '00:00:00,000');
    expect(formatSrtTimestamp(3.2), '00:00:03,200');
    expect(formatSrtTimestamp(65.5), '00:01:05,500');
    expect(formatSrtTimestamp(3661.001), '01:01:01,001');
  });

  test('builds a valid SRT body from transcript segments', () {
    final srt = buildSrtContent(const [
      SubtitleSegment(text: 'สวัสดีค่ะ', start: 0, end: 3.2),
      SubtitleSegment(text: ' ขายดีมาก ', start: 3.2, end: 6),
    ]);

    expect(srt, contains('1\n00:00:00,000 --> 00:00:03,200\nสวัสดีค่ะ'));
    expect(srt, contains('2\n00:00:03,200 --> 00:00:06,000\nขายดีมาก'));
  });

  test('skips empty subtitle segments', () {
    final srt = buildSrtContent(const [
      SubtitleSegment(text: '   ', start: 0, end: 1),
    ]);

    expect(srt.trim(), isEmpty);
  });

  test('clips and shifts segments to the trim window', () {
    final clipped = clipSegmentsToTrim(
      const [
        SubtitleSegment(text: 'a', start: 0, end: 3),
        SubtitleSegment(text: 'b', start: 5, end: 9),
        SubtitleSegment(text: 'c', start: 20, end: 22),
      ],
      trimStartSec: 4,
      trimEndSec: 10,
    );

    // 'a' (0-3) is before the window → dropped. 'c' (20-22) is after → dropped.
    expect(clipped.length, 1);
    expect(clipped.first.text, 'b');
    expect(clipped.first.start, 1); // 5 - 4
    expect(clipped.first.end, 5); // 9 - 4
  });

  test('builds ffmpeg args for trim, speed, volume and subtitles', () {
    final args = buildEditFfmpegArguments(
      inputPath: '/in.mp4',
      outputPath: '/out.mp4',
      subtitlePath: '/captions.srt',
      speed: 2.0,
      volume: 1.5,
      trimStartSec: 4,
      trimEndSec: 10,
    );
    final joined = args.join(' ');

    expect(joined, contains('-ss 4.000'));
    expect(joined, contains('-to 10.000'));
    expect(joined, contains('subtitles='));
    expect(joined, contains('setpts=0.5000*PTS'));
    expect(joined, contains('atempo=2.000'));
    expect(joined, contains('volume=1.500'));
    expect(joined, contains('-c:a aac')); // re-encode because of audio filters
  });

  test('copies audio when there are no audio edits', () {
    final args = buildEditFfmpegArguments(
      inputPath: '/in.mp4',
      outputPath: '/out.mp4',
      subtitlePath: '/captions.srt',
    );
    final joined = args.join(' ');

    expect(joined, contains('-c:a copy'));
    expect(joined, isNot(contains('atempo')));
  });

  test('detects silent gaps between transcript segments', () {
    final ranges = detectSilenceRanges(
      const [
        SubtitleSegment(text: 'a', start: 0, end: 3),
        SubtitleSegment(text: 'b', start: 5, end: 8), // 2s gap before
        SubtitleSegment(text: 'c', start: 8.3, end: 10), // 0.3s gap → ignored
      ],
      minGapSec: 0.8,
    );

    expect(ranges.length, 1);
    expect(ranges.first.start, 3);
    expect(ranges.first.end, 5);
  });

  test('builds select/aselect filters that remove silence ranges', () {
    final args = buildEditFfmpegArguments(
      inputPath: '/in.mp4',
      outputPath: '/out.mp4',
      silenceRanges: const [
        SilenceCutRange(start: 3, end: 5),
        SilenceCutRange(start: 12, end: 14),
      ],
    );
    final joined = args.join(' ');

    expect(joined, contains("select='not(between(t,3.000,5.000)+"
        "between(t,12.000,14.000))'"));
    expect(joined, contains('aselect='));
    expect(joined, contains('-c:a aac'));
  });

  test('builds color filter for presets and adjustments', () {
    expect(buildColorFilter(filterIndex: 0), isEmpty);
    expect(buildColorFilter(filterIndex: 3), 'hue=s=0');
    expect(
      buildColorFilter(filterIndex: 0, brightness: 0.5, contrast: 0.4),
      'eq=brightness=0.250:contrast=1.400',
    );
    expect(buildColorFilter(filterIndex: 4), contains('colorbalance'));
  });

  test('builds drawtext filters and sanitizes risky characters', () {
    final filters = buildDrawTextFilters(
      const [
        TextOverlaySpec('ลดราคา 50%'),
        TextOverlaySpec("it's: ok"),
        TextOverlaySpec('   '),
      ],
      fontPath: '/fonts/Prompt.ttf',
    );

    expect(filters.length, 2); // blank skipped
    expect(filters.first, contains("fontfile='/fonts/Prompt.ttf'"));
    expect(filters.first, contains('text='));
    expect(filters.first, isNot(contains('%')));
    expect(filters[1], isNot(contains("'s")));
  });

  test('drawtext + sticker overlays honor custom positions', () {
    final text = buildDrawTextFilters(
      const [TextOverlaySpec('hi', dx: 0.25, dy: 0.6)],
      fontPath: '/f.ttf',
    );
    expect(text.first, contains('x=(w*0.250-text_w/2)'));
    expect(text.first, contains('y=h*0.600'));

    final fc = buildStickerFilterComplex(
      videoFilters: const [],
      stickerCount: 1,
      positions: const [(0.3, 0.7)],
    );
    expect(fc, contains('overlay=main_w*0.300-overlay_w/2:'
        'main_h*0.700-overlay_h/2:eof_action=repeat'));
  });

  test('color grade comes before subtitles in the filter chain', () {
    final args = buildEditFfmpegArguments(
      inputPath: '/in.mp4',
      outputPath: '/out.mp4',
      colorFilter: 'hue=s=0',
      subtitlePath: '/captions.srt',
    );
    final vf = args[args.indexOf('-vf') + 1];

    expect(vf.indexOf('hue=s=0'), lessThan(vf.indexOf('subtitles=')));
  });

  test('picks platform hardware H.264 encoder with mpeg4 fallback', () {
    final android = hardwareH264Encoder(isAndroid: true, isIOS: false);
    expect(android.codec, 'h264_mediacodec');
    expect(android.scaleEvenDimensions, isTrue);
    expect(android.encoderArgs, contains('-pix_fmt'));

    final ios = hardwareH264Encoder(isAndroid: false, isIOS: true);
    expect(ios.codec, 'h264_videotoolbox');
    expect(ios.scaleEvenDimensions, isTrue);

    // Desktop/test hosts have no hardware encoder → universal MPEG-4 fallback.
    final other = hardwareH264Encoder(isAndroid: false, isIOS: false);
    expect(other.codec, fallbackMpeg4Encoder.codec);
  });

  test('applies the chosen video codec and even-dimension scaling', () {
    final args = buildEditFfmpegArguments(
      inputPath: '/in.mp4',
      outputPath: '/out.mp4',
      videoCodec: 'h264_mediacodec',
      videoEncoderArgs: const ['-b:v', '6M', '-pix_fmt', 'yuv420p'],
      scaleEvenDimensions: true,
    );
    final joined = args.join(' ');
    final vf = args[args.indexOf('-vf') + 1];

    expect(joined, contains('-c:v h264_mediacodec'));
    expect(joined, contains('-b:v 6M'));
    expect(joined, contains('-pix_fmt yuv420p'));
    expect(vf, contains('scale=trunc(iw/2)*2:trunc(ih/2)*2'));
  });

  test('defaults to the mpeg4 encoder when no codec is given', () {
    final args = buildEditFfmpegArguments(
      inputPath: '/in.mp4',
      outputPath: '/out.mp4',
      volume: 1.2,
    );
    final joined = args.join(' ');

    expect(joined, contains('-c:v mpeg4 -q:v 4'));
    expect(joined, isNot(contains('scale=trunc')));
  });

  test('builds a sticker overlay graph stacked from the top-right', () {
    final fc = buildStickerFilterComplex(
      videoFilters: const ['hue=s=0'],
      stickerCount: 2,
    );

    expect(fc, contains('[0:v]hue=s=0[vbase]'));
    expect(
      fc,
      contains('[vbase][1:v]overlay=main_w-overlay_w-12:12:'
          'eof_action=repeat[v0]'),
    );
    expect(
      fc,
      contains('[v0][2:v]overlay=main_w-overlay_w-12:116:'
          'eof_action=repeat[vout]'),
    );
  });

  test('sticker graph overlays directly on the raw input with no filters', () {
    final fc = buildStickerFilterComplex(
      videoFilters: const [],
      stickerCount: 1,
    );

    expect(
      fc,
      '[0:v][1:v]overlay=main_w-overlay_w-12:12:eof_action=repeat[vout]',
    );
  });

  test('adds sticker inputs and maps the overlay output', () {
    final args = buildEditFfmpegArguments(
      inputPath: '/in.mp4',
      outputPath: '/out.mp4',
      colorFilter: 'hue=s=0',
      stickerImagePaths: const ['/s0.png', '/s1.png'],
    );
    final joined = args.join(' ');

    expect(joined, contains('-i /s0.png'));
    expect(joined, contains('-i /s1.png'));
    expect(joined, contains('-filter_complex'));
    expect(joined, contains('-map [vout]'));
    expect(joined, contains('-map 0:a?'));
    expect(joined, isNot(contains('-vf'))); // overlay path replaces -vf
  });

  test('purges stale render temp dirs but keeps the current ones', () async {
    final base = Directory.systemTemp.createTempSync('postdee-purge-test-');
    addTearDown(() {
      if (base.existsSync()) base.deleteSync(recursive: true);
    });
    final sep = Platform.pathSeparator;
    final stale1 = Directory('${base.path}${sep}postdee-edit-old')..createSync();
    final stale2 = Directory('${base.path}${sep}postdee-sticker-old')
      ..createSync();
    final keep = Directory('${base.path}${sep}postdee-edit-keep')..createSync();
    final other = Directory('${base.path}${sep}unrelated')..createSync();

    final removed = await purgeEditTempDirs(base, keepPaths: {keep.path});

    expect(removed, 2);
    expect(stale1.existsSync(), isFalse);
    expect(stale2.existsSync(), isFalse);
    expect(keep.existsSync(), isTrue);
    expect(other.existsSync(), isTrue);
  });

  test('keeps the simple -vf path when there are no stickers', () {
    final args = buildEditFfmpegArguments(
      inputPath: '/in.mp4',
      outputPath: '/out.mp4',
      colorFilter: 'hue=s=0',
    );
    final joined = args.join(' ');

    expect(joined, contains('-vf hue=s=0'));
    expect(joined, isNot(contains('-filter_complex')));
    expect(joined, isNot(contains('-map')));
  });

  test('builds subtitle force style with size and position', () {
    final bottom = buildSubtitleForceStyle(fontSize: 24, atBottom: true);
    expect(bottom, contains('Fontsize=24'));
    expect(bottom, contains('Alignment=2'));

    final top = buildSubtitleForceStyle(fontSize: 14, atBottom: false);
    expect(top, contains('Fontsize=14'));
    expect(top, contains('Alignment=8'));
  });

  test('applies subtitle font size and top position to the args', () {
    final args = buildEditFfmpegArguments(
      inputPath: '/in.mp4',
      outputPath: '/out.mp4',
      subtitlePath: '/captions.srt',
      subtitleFontSize: 24,
      subtitleAtBottom: false,
    );
    final vf = args[args.indexOf('-vf') + 1];

    expect(vf, contains('Fontsize=24'));
    expect(vf, contains('Alignment=8'));
  });
}
