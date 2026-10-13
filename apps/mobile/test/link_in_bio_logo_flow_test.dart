import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postdee_mobile/core/auth/auth_session.dart';
import 'package:postdee_mobile/core/models/link_in_bio_appearance.dart';
import 'package:postdee_mobile/core/theme/app_theme.dart';
import 'package:postdee_mobile/features/link_in_bio/link_in_bio_draft_store.dart';
import 'package:postdee_mobile/features/link_in_bio/link_in_bio_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'link_in_bio_test_navigation.dart';

const _oldLogo =
    'uploads/seller-a/12345678-1234-1234-1234-123456789abc/profile-logo.png';
const _newLogo =
    'uploads/seller-a/22345678-1234-1234-1234-123456789abc/profile-logo.png';
const _draft = LinkInBioDraft(
    storeName: 'ร้านมินา',
    slug: 'mina-shop',
    autoUpdateFromScheduledPosts: false,
    enabledLinkIds: {},
    customLinks: [],
    appearance: LinkInBioAppearance(logoKey: _oldLogo));
const _store = SharedPreferencesLinkInBioDraftStore(ownerUserId: 'seller-a');

// A wide image with red, green, and blue vertical bands cannot be uploaded
// unchanged when the user confirms a square crop.
final _widePng = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAHgAAAA8CAYAAACtrX6oAAAAAXNSR0IArs4c6QAAAARnQU1BAACxjwv8YQUAAAAJcEhZcwAADsMAAA7DAcdvqGQAAAGwSURBVHhezdAxEQAwEMOwQC/zLwAT0KAlky+77WR7uCZbulhyqKbJli6WHKppsqWLJYdqmmzpYsmhmiZbulhyqKbJli6WHKppsqWLJYdqmmzpYsmhmiZbulhyqKbJli6WHKppsqWLJYdqmmzpYsmhmiZbulhyqKbJli6WHKppsqWLJYdqmmzpYsmhmiZbulhyqKbJli6WHKppsqWLJYdqmmzpYsmhmiZbulhyqKbJli6WHKppsqWLJYdqmmzpYsmhmiZbulhyqKbJli6WHKppsqWLJYdqmmzpYsmhmiZbulhyqKbJli6WHKppsqWLJYdqmmzpYsmhmiZbulhyqKbJli6WHKppsqWLJYdqmmzpYsmhmiZbulhyqKbJli6WHKppsqWLJYdqmmzpYsmhmiZbulhyqKbJli6WHKppsqWLJYdqmmzpYsmhmiZbulhyqKbJli6WHKppsqWLJYdqmmzpYsmhmiZbulhyqKbJli6WHKppsqWLJYdqmmzpYsmhmiZbulhyqKbJli6WHKppsqWLJYdqmmzpYsmhmiZbulhyqKbJli6WHKppsqWLJYdqmkz5fSRkHpVGAywAAAAASUVORK5CYII=');

Finder _key(String key) => find.byKey(ValueKey(key));

Widget _app({
  required LinkInBioImageUploader uploadImage,
  LinkInBioImagePicker? pickImage,
  LinkInBioImageLoader? loadImage,
}) =>
    MaterialApp(
        theme: AppTheme.light,
        home: LinkInBioScreen(
            loadProfile: () async => null,
            pickImage: pickImage ?? () async => Uint8List.fromList(_widePng),
            uploadImage: uploadImage,
            loadImage: loadImage ?? (_) async => _widePng,
            protectDraftImages: (
                {required draftId, required keys, required mode}) async {}));

Future<void> _waitForEngine(WidgetTester tester, bool Function() ready) async {
  for (var attempt = 0; attempt < 100 && (attempt < 8 || !ready()); attempt++) {
    await tester.pump(const Duration(milliseconds: 20));
    await tester
        .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
  }
  expect(ready(), isTrue,
      reason: 'The logo image operation must finish. Visible text: '
          '${tester.allWidgets.whereType<Text>().map((text) => text.data).toList()}');
  await tester.pump(const Duration(milliseconds: 300));
}

Future<void> _waitForCrop(WidgetTester tester) async {
  expect(find.text('ปรับตำแหน่งโลโก้'), findsOneWidget);
  await _waitForEngine(tester, () {
    final confirm = _key('link-in-bio-logo-crop-confirm');
    return confirm.evaluate().isNotEmpty &&
        tester.widget<ButtonStyleButton>(confirm).onPressed != null;
  });
}

Future<void> _openCrop(WidgetTester tester) async {
  final button = _key('link-in-bio-image-logo');
  await showBioControl(tester, button);
  await tester.tap(button);
  await tester.pump();
  await _waitForCrop(tester);
}

Future<void> _confirmCrop(WidgetTester tester) async {
  await tester.tap(_key('link-in-bio-logo-crop-confirm'));
  await tester.pump();
  await _waitForEngine(tester, () {
    final button = _key('link-in-bio-image-logo');
    return _key('link-in-bio-logo-crop-confirm').evaluate().isEmpty &&
        button.evaluate().isNotEmpty &&
        tester.widget<ButtonStyleButton>(button).onPressed != null;
  });
}

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    PostDeeAuthSessionStore.instance
        .signIn(const AuthSession(userId: 'seller-a', idToken: 'token-a'));
    await _store.saveDraft(_draft);
  });
  tearDown(PostDeeAuthSessionStore.instance.clear);

  testWidgets('choosing and positioning a logo waits for explicit confirmation',
      (tester) async {
    final uploads = <Uint8List>[];
    await tester
        .pumpWidget(_app(uploadImage: ({required slot, required bytes}) async {
      uploads.add(bytes);
      return _newLogo;
    }));
    await tester.pumpAndSettle();
    await showBioStep(tester, 'info');
    await _openCrop(tester);
    expect(uploads, isEmpty);
    expect(find.text('ใช้โลโก้นี้'), findsOneWidget);
    expect(find.text('ยกเลิก'), findsOneWidget);
    final preview = _key('link-in-bio-logo-crop-preview');
    expect(preview, findsOneWidget);
    await tester.timedDrag(
        preview, const Offset(45, 0), const Duration(milliseconds: 600));
    final zoom = _key('link-in-bio-logo-crop-zoom');
    final initialZoom = tester.widget<Slider>(zoom).value;
    await tester.drag(zoom, const Offset(55, 0));
    await tester.pump();
    expect(tester.widget<Slider>(zoom).value, greaterThan(initialZoom));
    await tester.ensureVisible(_key('link-in-bio-logo-crop-reset'));
    await tester.pumpAndSettle();
    await tester.tap(_key('link-in-bio-logo-crop-reset'));
    await tester.pump();
    expect(tester.widget<Slider>(zoom).value, initialZoom);
    expect(uploads, isEmpty);
    expect((await _store.loadDraft())!.appearance.logoKey, _oldLogo);
    await tester.tap(_key('link-in-bio-logo-crop-cancel'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('canceling a logo crop preserves the existing draft and logo',
      (tester) async {
    var uploads = 0;
    await tester
        .pumpWidget(_app(uploadImage: ({required slot, required bytes}) async {
      uploads++;
      return _newLogo;
    }));
    await tester.pumpAndSettle();
    await showBioStep(tester, 'info');
    await tester.enterText(_key('link-in-bio-store-name'), 'ชื่อร้านที่แก้ไว้');
    await tester.pumpAndSettle();
    final before = (await _store.loadDraft())!;
    await _openCrop(tester);
    await tester.timedDrag(_key('link-in-bio-logo-crop-preview'),
        const Offset(-55, 20), const Duration(milliseconds: 600));
    await tester.tap(_key('link-in-bio-logo-crop-cancel'));
    await tester.pumpAndSettle();
    final after = (await _store.loadDraft())!;
    expect(uploads, 0);
    expect(after.storeName, before.storeName);
    expect(after.slug, before.slug);
    expect(after.appearance.toJson(), before.appearance.toJson());
    expect(
        tester
            .widget<TextField>(_key('link-in-bio-store-name'))
            .controller!
            .text,
        before.storeName);
    expect(_key('link-in-bio-info-logo'), findsOneWidget);
    expect(find.text('ปรับตำแหน่งโลโก้'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'confirmed logo uploads a square PNG and reloads the saved result',
      (tester) async {
    final uploads = <(String, Uint8List)>[];
    await tester
        .pumpWidget(_app(uploadImage: ({required slot, required bytes}) async {
      uploads.add((slot, Uint8List.fromList(bytes)));
      return _newLogo;
    }));
    await tester.pumpAndSettle();
    await showBioStep(tester, 'info');
    await _openCrop(tester);
    await tester.timedDrag(_key('link-in-bio-logo-crop-preview'),
        const Offset(40, 0), const Duration(milliseconds: 600));
    await _confirmCrop(tester);
    expect(uploads, hasLength(1));
    expect(uploads.single.$1, 'logo');
    final cropped = uploads.single.$2;
    expect(cropped.take(8), [137, 80, 78, 71, 13, 10, 26, 10]);
    expect(cropped, isNot(_widePng));
    await tester.runAsync(() async {
      final codec = await ui.instantiateImageCodec(cropped);
      final image = (await codec.getNextFrame()).image;
      try {
        expect(image.width, image.height);
        expect(image.width, greaterThan(0));
      } finally {
        image.dispose();
        codec.dispose();
      }
    });
    expect((await _store.loadDraft())!.appearance.logoKey, _newLogo);
    expect(_key('link-in-bio-info-logo'), findsOneWidget);
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    await tester.pumpAndSettle();
    final loaded = <String>[];
    await tester
        .pumpWidget(_app(uploadImage: ({required slot, required bytes}) async {
      fail('Reloading an existing logo must not upload it again.');
    }, loadImage: (key) async {
      loaded.add(key);
      return cropped;
    }));
    await tester.pumpAndSettle();
    await showBioStep(tester, 'info');
    expect(loaded, [_newLogo]);
    expect(_key('link-in-bio-info-logo'), findsOneWidget);
    final logo = find.descendant(
        of: _key('link-in-bio-info-logo'), matching: find.byType(Image));
    expect((tester.widget<Image>(logo).image as MemoryImage).bytes, cropped);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'appearance editor can open a nested crop and apply the chosen logo',
      (tester) async {
    var uploads = 0;
    await tester
        .pumpWidget(_app(uploadImage: ({required slot, required bytes}) async {
      uploads++;
      return _newLogo;
    }));
    await tester.pumpAndSettle();
    await tapBioControl(tester, 'link-in-bio-decorate');
    await tapBioControl(tester, 'link-in-bio-disclosure-images');
    await _openCrop(tester);
    expect(uploads, 0);
    await _confirmCrop(tester);
    expect(uploads, 1);
    expect(_key('link-in-bio-decoration-done'), findsOneWidget);
    expect((await _store.loadDraft())!.appearance.logoKey, _oldLogo);
    await tapBioControl(tester, 'link-in-bio-decoration-done');
    expect((await _store.loadDraft())!.appearance.logoKey, _newLogo);
    expect(tester.takeException(), isNull);
  });

  testWidgets('changing account closes an open logo crop without uploading',
      (tester) async {
    var uploads = 0;
    await tester
        .pumpWidget(_app(uploadImage: ({required slot, required bytes}) async {
      uploads++;
      return _newLogo;
    }));
    await tester.pumpAndSettle();
    await showBioStep(tester, 'info');
    await _openCrop(tester);
    PostDeeAuthSessionStore.instance
        .signIn(const AuthSession(userId: 'seller-b', idToken: 'token-b'));
    await tester.pumpAndSettle();
    expect(find.text('ปรับตำแหน่งโลโก้'), findsNothing);
    expect(uploads, 0);
    expect((await _store.loadDraft())!.appearance.logoKey, _oldLogo);
    const otherStore =
        SharedPreferencesLinkInBioDraftStore(ownerUserId: 'seller-b');
    expect(await otherStore.loadDraft(), isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('rapid logo taps open only one picker and one crop editor',
      (tester) async {
    final picked = Completer<Uint8List?>();
    var picks = 0;
    var uploads = 0;
    await tester.pumpWidget(_app(pickImage: () {
      picks++;
      return picked.future;
    }, uploadImage: ({required slot, required bytes}) async {
      uploads++;
      return _newLogo;
    }));
    await tester.pumpAndSettle();
    await showBioStep(tester, 'info');
    final button = _key('link-in-bio-image-logo');
    await showBioControl(tester, button);
    await tester.tap(button);
    await tester.tap(button);
    await tester.pump();
    expect(picks, 1);
    picked.complete(_widePng);
    await tester.pump();
    await _waitForCrop(tester);
    expect(find.text('ปรับตำแหน่งโลโก้'), findsOneWidget);
    expect(uploads, 0);
    await tester.tap(_key('link-in-bio-logo-crop-cancel'));
    await tester.pumpAndSettle();
    expect((await _store.loadDraft())!.appearance.logoKey, _oldLogo);
    expect(tester.takeException(), isNull);
  });
}
