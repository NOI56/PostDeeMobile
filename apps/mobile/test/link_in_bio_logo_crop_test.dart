import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postdee_mobile/features/link_in_bio/link_in_bio_logo_crop.dart';

Future<Uint8List> _stripedLogo() async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  for (var stripe = 0; stripe < 3; stripe++) {
    canvas.drawRect(Rect.fromLTWH(stripe * 100, 0, 100, 100),
        Paint()..color = [Colors.red, Colors.green, Colors.blue][stripe]);
  }
  final picture = recorder.endRecording();
  final image = await picture.toImage(300, 100);
  try {
    final data = (await image.toByteData(format: ui.ImageByteFormat.png))!;
    return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
  } finally {
    image.dispose();
    picture.dispose();
  }
}

Future<Color> _centerPixel(Uint8List bytes) async {
  final codec = await ui.instantiateImageCodec(bytes);
  final image = (await codec.getNextFrame()).image;
  try {
    final data = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
    final offset = ((image.height ~/ 2) * image.width + image.width ~/ 2) * 4;
    final rgba = data.buffer.asUint8List(offset, 4);
    return Color.fromARGB(rgba[3], rgba[0], rgba[1], rgba[2]);
  } finally {
    image.dispose();
    codec.dispose();
  }
}

Future<void> _decodeReady(WidgetTester tester) async {
  for (var attempt = 0; attempt < 8; attempt++) {
    await tester.pump();
    await tester
        .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
  }
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('wide and tall logos can reach each edge without empty space', () {
    for (final size in [const Size(300, 100), const Size(100, 300)]) {
      for (final center in [const Offset(-500, -500), const Offset(500, 500)]) {
        for (final zoom in [1.0, 2.0, 4.0]) {
          final crop = linkInBioLogoCropRect(size, zoom: zoom, center: center);
          expect(crop.width, crop.height);
          expect(crop.left, greaterThanOrEqualTo(0));
          expect(crop.top, greaterThanOrEqualTo(0));
          expect(crop.right, lessThanOrEqualTo(size.width));
          expect(crop.bottom, lessThanOrEqualTo(size.height));
          expect(crop.width, size.shortestSide / zoom);
        }
      }
    }
  });

  test('square images can move in both directions after zooming', () {
    expect(
        linkInBioLogoCropRect(const Size(200, 200),
            zoom: 2, center: const Offset(0, 200)),
        const Rect.fromLTWH(0, 100, 100, 100));
    expect(linkInBioLogoCropRect(const Size(200, 200)),
        const Rect.fromLTWH(0, 0, 200, 200));
  });

  test('export contains the selected pixels and stays a bounded square PNG',
      () async {
    final pixels = Uint8List(300 * 100 * 4);
    for (var y = 0; y < 100; y++) {
      for (var x = 0; x < 300; x++) {
        final index = (y * 300 + x) * 4;
        pixels[index + x ~/ 100] = 255;
        pixels[index + 3] = 255;
      }
    }
    final pending = Completer<ui.Image>();
    ui.decodeImageFromPixels(
        pixels, 300, 100, ui.PixelFormat.rgba8888, pending.complete);
    final image = await pending.future;
    try {
      final bytes = await cropLinkInBioLogo(
          image,
          linkInBioLogoCropRect(const Size(300, 100),
              center: const Offset(250, 50)));
      expect(bytes.length, lessThanOrEqualTo(512 * 1024));
      expect(bytes.take(8), [137, 80, 78, 71, 13, 10, 26, 10]);
      final codec = await ui.instantiateImageCodec(bytes);
      final output = (await codec.getNextFrame()).image;
      try {
        expect(output.width, output.height);
        final data =
            (await output.toByteData(format: ui.ImageByteFormat.rawRgba))!;
        for (final pixel in [
          0,
          (output.width * output.height) ~/ 2,
          output.width * output.height - 1
        ]) {
          final rgba = data.buffer.asUint8List(pixel * 4, 4);
          expect(rgba[0], 0);
          // Filtering can blend a few adjacent pixels along the crop edge.
          expect(rgba[1], lessThanOrEqualTo(20));
          expect(rgba[2], greaterThanOrEqualTo(235));
          expect(rgba[3], 255);
        }
      } finally {
        output.dispose();
        codec.dispose();
      }
    } finally {
      image.dispose();
    }
  });

  for (final reset in [false, true]) {
    testWidgets(
        'dragging selects pixels${reset ? ' and reset restores center' : ''}',
        (tester) async {
      final source = (await tester.runAsync(_stripedLogo))!;
      Uint8List? saved;
      await tester.pumpWidget(MaterialApp(
          home: Builder(
              builder: (context) => Scaffold(
                  body: TextButton(
                      onPressed: () async {
                        saved = await showDialog<Uint8List>(
                            context: context,
                            builder: (_) =>
                                LinkInBioLogoCropDialog(bytes: source));
                      },
                      child: const Text('open'))))));
      await tester.tap(find.text('open'));
      await _decodeReady(tester);
      await tester.timedDrag(
          find.byKey(const ValueKey('link-in-bio-logo-crop-preview')),
          const Offset(-300, 0),
          const Duration(milliseconds: 600));
      await tester.pumpAndSettle();
      if (reset) {
        await tester
            .tap(find.byKey(const ValueKey('link-in-bio-logo-crop-zoom')));
        await tester.pumpAndSettle();
        expect(
            tester.widget<Slider>(find.byType(Slider)).value, greaterThan(1));
        await tester.ensureVisible(
            find.byKey(const ValueKey('link-in-bio-logo-crop-reset')));
        await tester.pumpAndSettle();
        await tester
            .tap(find.byKey(const ValueKey('link-in-bio-logo-crop-reset')));
        await tester.pumpAndSettle();
        expect(tester.widget<Slider>(find.byType(Slider)).value, 1);
      }
      await tester
          .tap(find.byKey(const ValueKey('link-in-bio-logo-crop-confirm')));
      await _decodeReady(tester);
      expect(saved, isNotNull);
      final color = await tester.runAsync(() => _centerPixel(saved!));
      expect(
          color!.toARGB32(), (reset ? Colors.green : Colors.blue).toARGB32());
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('closing crop during export keeps the appearance editor open',
      (tester) async {
    final source = (await tester.runAsync(_stripedLogo))!;
    final pending = Completer<Uint8List>();
    Uint8List? saved;
    var editorClosed = false;
    BuildContext? cropContext;
    await tester.pumpWidget(MaterialApp(
        home: Builder(
            builder: (context) => Scaffold(
                body: TextButton(
                    onPressed: () async {
                      await showModalBottomSheet<void>(
                          context: context,
                          builder: (context) =>
                              Column(mainAxisSize: MainAxisSize.min, children: [
                                const Text('appearance editor'),
                                TextButton(
                                    onPressed: () async {
                                      saved = await showDialog<Uint8List>(
                                          context: context,
                                          builder: (context) {
                                            cropContext = context;
                                            return LinkInBioLogoCropDialog(
                                                bytes: source,
                                                exportImage: (image, crop) =>
                                                    pending.future);
                                          });
                                    },
                                    child: const Text('crop')),
                              ]));
                      editorClosed = true;
                    },
                    child: const Text('decorate'))))));
    await tester.tap(find.text('decorate'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('crop'));
    await _decodeReady(tester);
    await tester
        .tap(find.byKey(const ValueKey('link-in-bio-logo-crop-confirm')));
    await tester.binding.handlePopRoute();
    // Finish encoding while the dismissed route is still mounted.
    await tester.pump();
    expect(cropContext!.mounted, isTrue);
    expect(ModalRoute.of(cropContext!)!.isCurrent, isFalse);
    pending.complete(source);
    await tester.pumpAndSettle();
    expect(saved, isNull);
    expect(editorClosed, isFalse);
    expect(find.text('appearance editor'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('crop remains usable on a small screen with large text',
      (tester) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final source = (await tester.runAsync(_stripedLogo))!;
    await tester.pumpWidget(MaterialApp(
        builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(2)),
            child: child!),
        home: LinkInBioLogoCropDialog(bytes: source)));
    await _decodeReady(tester);
    expect(
        find
            .byKey(const ValueKey('link-in-bio-logo-crop-confirm'))
            .hitTestable(),
        findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('an unreadable image leaves confirmation disabled',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
        home: LinkInBioLogoCropDialog(bytes: Uint8List.fromList([1, 2, 3]))));
    await _decodeReady(tester);
    expect(find.text('เปิดรูปนี้ไม่ได้ กรุณาเลือกรูปอื่น'), findsOneWidget);
    expect(
        tester
            .widget<FilledButton>(
                find.byKey(const ValueKey('link-in-bio-logo-crop-confirm')))
            .onPressed,
        isNull);
    expect(tester.takeException(), isNull);
  });
}
