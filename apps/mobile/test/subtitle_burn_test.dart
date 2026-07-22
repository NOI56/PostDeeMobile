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

  test('builds video select and compact audio concat for silence ranges', () {
    final args = buildEditFfmpegArguments(
      inputPath: '/in.mp4',
      outputPath: '/out.mp4',
      silenceRanges: const [
        SilenceCutRange(start: 3, end: 5),
        SilenceCutRange(start: 12, end: 14),
      ],
    );
    final joined = args.join(' ');

    expect(
        joined,
        contains("select='not(between(t,3.000,5.000)+"
            "between(t,12.000,14.000))'"));
    expect(joined, contains('[0:a]atrim=start=0.000:end=3.000'));
    expect(joined, contains('[0:a]atrim=start=5.000:end=12.000'));
    expect(joined, contains('[0:a]atrim=start=14.000'));
    expect(joined, contains('concat=n=3:v=0:a=1[aout]'));
    expect(joined, contains('-map 0:v:0? -map [aout]'));
    expect(joined, isNot(contains('aselect=')));
    expect(joined, contains('-c:a aac'));
  });

  test('gives libass the bundled subtitle font directory and family', () {
    final args = buildEditFfmpegArguments(
      inputPath: '/in.mp4',
      outputPath: '/out.mp4',
      subtitlePath: '/work/captions.srt',
      subtitleFontsDirectory: '/work/fonts',
      subtitleFontName: 'Prompt',
    );
    final vf = args[args.indexOf('-vf') + 1];

    expect(vf, contains("fontsdir='/work/fonts'"));
    expect(vf, contains('FontName=Prompt'));
  });

  test('combines silence, sticker, speed and volume in one mapped graph', () {
    final args = buildEditFfmpegArguments(
      inputPath: '/in.mp4',
      outputPath: '/out.mp4',
      silenceRanges: const [SilenceCutRange(start: 3, end: 5)],
      stickerImagePaths: const ['/sticker.png'],
      speed: 1.5,
      volume: 0.8,
    );
    final joined = args.join(' ');

    expect(joined, contains('overlay='));
    expect(joined, contains('[0:a]atrim=start=0.000:end=3.000'));
    expect(joined, contains('[0:a]atrim=start=5.000'));
    expect(joined, contains('concat=n=2:v=0:a=1'));
    expect(joined, contains('atempo=1.500'));
    expect(joined, contains('volume=0.800'));
    expect(joined, contains('-map [vout] -map [aout]'));
    expect(joined, isNot(contains(' -af ')));
    expect(joined, isNot(contains('aselect=')));
  });

  test('sorts and merges overlapping silence ranges before rendering', () {
    final args = buildEditFfmpegArguments(
      inputPath: '/in.mp4',
      outputPath: '/out.mp4',
      silenceRanges: const [
        SilenceCutRange(start: 5, end: 8),
        SilenceCutRange(start: 3, end: 6),
      ],
    );
    final joined = args.join(' ');

    expect(joined, contains("select='not(between(t,3.000,8.000))'"));
    expect(joined, contains('[0:a]atrim=start=0.000:end=3.000'));
    expect(joined, contains('[0:a]atrim=start=8.000'));
    expect(joined, contains('concat=n=2:v=0:a=1'));
  });

  test('builds color filter for presets and adjustments', () {
    expect(buildColorFilter(filterIndex: 0), isEmpty);
    expect(buildColorFilter(filterIndex: 3), 'hue=s=0');
    expect(
      buildColorFilter(filterIndex: 0, brightness: 0.5, contrast: 0.4),
      "lutrgb=r='clip((val-128)*1.400+128+63.750,0,255)':"
      "g='clip((val-128)*1.400+128+63.750,0,255)':"
      "b='clip((val-128)*1.400+128+63.750,0,255)'",
    );
    expect(buildColorFilter(filterIndex: 1), 'hue=s=1.400');
    expect(buildColorFilter(filterIndex: 2), startsWith('hue=s=0.700'));
    expect(buildColorFilter(filterIndex: 1), isNot(contains('eq=')));
    expect(buildColorFilter(filterIndex: 4), contains('colorbalance'));
  });

  test('retries a requested color filter without color as a safe fallback', () {
    expect(
      buildColorFilterFallbacks('hue=s=1.400'),
      ['hue=s=1.400', ''],
    );
    expect(buildColorFilterFallbacks(''), ['']);
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
    expect(
        fc,
        contains('overlay=main_w*0.300-overlay_w/2:'
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

  test('caps preview dimensions and keeps the aspect ratio', () {
    final args = buildEditFfmpegArguments(
      inputPath: '/in.mp4',
      outputPath: '/out.mp4',
      videoCodec: 'h264_mediacodec',
      videoEncoderArgs: const ['-b:v', '2M', '-pix_fmt', 'yuv420p'],
      scaleEvenDimensions: true,
      maxVideoDimension: 720,
      maxVideoFrameRate: 24,
    );
    final joined = args.join(' ');
    final vf = args[args.indexOf('-vf') + 1];

    expect(joined, contains('-b:v 2M'));
    expect(
      vf,
      contains(
        "scale=w='min(720,iw)':h='min(720,ih)':"
        'force_original_aspect_ratio=decrease:force_divisible_by=2',
      ),
    );
    expect(vf, isNot(contains('scale=trunc(iw/2)*2')));
    expect(vf, contains('fps=24'));
  });

  test('uses a smaller preview profile for long source videos', () {
    final short = videoPreviewProfileForSourceDuration(45);
    final long = videoPreviewProfileForSourceDuration(150);

    expect(short.maxVideoDimension, 720);
    expect(short.videoBitrate, '2M');
    expect(short.maxVideoFrameRate, 24);
    expect(long.maxVideoDimension, 540);
    expect(long.videoBitrate, '1M');
    expect(long.maxVideoFrameRate, 20);
  });

  test('writes FFmpeg progress to a file that can be polled on Android', () {
    final args = buildEditFfmpegArguments(
      inputPath: '/in.mp4',
      outputPath: '/out.mp4',
      progressPath: '/tmp/render-progress.txt',
    );

    expect(
      args.join(' '),
      contains(
        '-stats_period 0.5 -progress /tmp/render-progress.txt -nostats',
      ),
    );
  });

  test('reads processed time from FFmpeg progress file content', () {
    expect(
      parseFfmpegProgressSeconds(
        'frame=120\nout_time_us=12345678\nprogress=continue\n',
      ),
      closeTo(12.345678, 0.000001),
    );
    expect(
      parseFfmpegProgressSeconds(
        'frame=120\nout_time_ms=7654321\nprogress=continue\n',
      ),
      closeTo(7.654321, 0.000001),
    );
    expect(parseFfmpegProgressSeconds('progress=continue\n'), isNull);
  });

  test('render cancellation token cancels an attached session once', () async {
    final token = RenderCancellationToken();
    var cancelCalls = 0;

    await token.attach(() async => cancelCalls += 1);
    await token.cancel();
    await token.cancel();

    expect(token.isCancelled, isTrue);
    expect(cancelCalls, 1);
  });

  test('render cancellation token cancels a session attached later', () async {
    final token = RenderCancellationToken();
    var cancelCalls = 0;

    await token.cancel();
    await token.attach(() async => cancelCalls += 1);

    expect(cancelCalls, 1);
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
    final stale1 = Directory('${base.path}${sep}postdee-edit-old')
      ..createSync();
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

  test('renderer keeps its input temp dir while removing other stale dirs',
      () async {
    final base =
        Directory.systemTemp.createTempSync('postdee-purge-call-test-');
    addTearDown(() {
      if (base.existsSync()) base.deleteSync(recursive: true);
    });
    final sep = Platform.pathSeparator;
    final inputDir = Directory('${base.path}${sep}postdee-edit-current')
      ..createSync();
    final inputFile = File('${inputDir.path}${sep}previous-render.mp4')
      ..writeAsBytesSync([0, 1, 2]);
    final acceptedResult = Directory('${base.path}${sep}postdee-edit-accepted')
      ..createSync();
    final acceptedFile = File('${acceptedResult.path}${sep}accepted.mp4')
      ..writeAsBytesSync([2, 1, 0]);
    final staleEdit = Directory('${base.path}${sep}postdee-edit-stale')
      ..createSync();
    final staleSticker = Directory('${base.path}${sep}postdee-sticker-stale')
      ..createSync();

    final processor = FfmpegSubtitleBurnVideoProcessor(
      renderTempDirectory: base,
    );

    await expectLater(
      processor(
        BurnSubtitleRequest(
          inputFile: inputFile,
          fileName: 'previous-render.mp4',
          segments: const [],
          preserveTempDirectoryPaths: {acceptedResult.path},
        ),
      ),
      throwsA(isA<SubtitleBurnException>()),
    );

    expect(inputDir.existsSync(), isTrue);
    expect(inputFile.existsSync(), isTrue);
    expect(acceptedResult.existsSync(), isTrue);
    expect(acceptedFile.existsSync(), isTrue);
    expect(staleEdit.existsSync(), isFalse);
    expect(staleSticker.existsSync(), isFalse);
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
    expect(bottom, contains('MarginL=24'));
    expect(bottom, contains('MarginR=24'));
    expect(bottom, contains('MarginV=28'));
    expect(bottom, contains('WrapStyle=0'));

    final top = buildSubtitleForceStyle(fontSize: 14, atBottom: false);
    expect(top, contains('Fontsize=14'));
    expect(top, contains('Alignment=8'));
  });

  test('builds the selected font, colors, outline, shadow, and middle position',
      () {
    final style = buildSubtitleForceStyle(
      fontSize: 28,
      alignment: BurnSubtitleAlignment.middle,
      fontName: 'Anuphan',
      textColor: '#12AB34',
      outlineColor: '#112233',
      outlineWidth: 3,
      shadowColor: '#445566',
      shadowDepth: 4,
    );

    expect(style, contains('FontName=Anuphan'));
    expect(style, contains('PrimaryColour=&H0034AB12'));
    expect(style, contains('OutlineColour=&H00332211'));
    expect(style, contains('BackColour=&H00665544'));
    expect(style, contains('Outline=3'));
    expect(style, contains('Shadow=4'));
    expect(style, contains('Alignment=5'));
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

  test('accepts a rendered output only when it has a video stream', () {
    // h264_mediacodec on some devices exits 0 while writing an audio-only
    // file; the render loop must reject that output and try the fallback.
    expect(renderedOutputHasVideo(['video', 'audio']), isTrue);
    expect(renderedOutputHasVideo(['audio']), isFalse);
    expect(renderedOutputHasVideo(['audio', null]), isFalse);
    expect(renderedOutputHasVideo([]), isFalse);
    expect(renderedOutputHasVideo(null), isFalse);
  });
}
