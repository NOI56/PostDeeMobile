import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postdee_mobile/core/models/link_in_bio_appearance.dart';
import 'package:postdee_mobile/core/theme/app_theme.dart';
import 'package:postdee_mobile/features/link_in_bio/link_in_bio_appearance_editor.dart';
import 'package:postdee_mobile/features/link_in_bio/link_in_bio_draft_store.dart';

const _imageKey =
    'uploads/seller-a/12345678-1234-1234-1234-123456789abc/profile-logo.png';
const _coverKey =
    'uploads/seller-a/12345678-1234-1234-1234-123456789abc/profile-cover.png';
const _backgroundKey =
    'uploads/seller-a/12345678-1234-1234-1234-123456789abc/profile-background.png';
const _links = [
  LinkInBioCustomLink(
      id: 'shop', title: 'ร้านค้า', url: 'https://example.com/shop'),
];
const _customAppearance = LinkInBioAppearance(
    description: 'ร้านเดิมของเรา',
    logoKey: _imageKey,
    coverKey: _coverKey,
    background: LinkInBioBackground(
        mode: 'image', imageKey: _backgroundKey, overlay: 57),
    surfaceColor: '#abcdef',
    buttonColor: '#123456',
    buttonRadius: 'square',
    nameStyle: LinkInBioTextStyle(color: '#234567', font: 'prompt'),
    descriptionStyle: LinkInBioTextStyle(color: '#345678', font: 'system'),
    categoryStyle: LinkInBioTextStyle(color: '#456789', font: 'prompt'),
    buttonStyle: LinkInBioTextStyle(color: '#567890', font: 'system'),
    brandStyle: LinkInBioTextStyle(color: '#678901', font: 'prompt'),
    featuredLinkId: 'shop',
    featuredLabel: 'โปรของร้าน');

Future<void> _openEditor(WidgetTester tester,
    {LinkInBioAppearance appearance = const LinkInBioAppearance(),
    bool showThemePicker = true,
    Map<String, Uint8List>? images,
    ValueNotifier<int>? imageRevision,
    Future<String?> Function(String)? uploadImage,
    ValueChanged<LinkInBioAppearance?>? onResult,
    double keyboardInset = 0}) async {
  await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light,
      builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(viewInsets: EdgeInsets.only(bottom: keyboardInset)),
          child: child!),
      home: Scaffold(
          body: Builder(
              builder: (context) => FilledButton(
                  onPressed: () async {
                    final result =
                        await showModalBottomSheet<LinkInBioAppearance>(
                            context: context,
                            isScrollControlled: true,
                            builder: (_) => LinkInBioAppearanceEditor(
                                appearance: appearance,
                                storeName: 'ร้านทดสอบ',
                                slug: 'test-shop',
                                links: _links,
                                images: images ?? {},
                                uploadImage: uploadImage ?? (_) async => null,
                                imageRevision: imageRevision,
                                showThemePicker: showThemePicker));
                    onResult?.call(result);
                  },
                  child: const Text('เปิดตัวแก้ไข'))))));
  await tester.tap(find.text('เปิดตัวแก้ไข'));
  await tester.pumpAndSettle();
}

Future<void> _tap(WidgetTester tester, String key) async {
  final finder = find.byKey(ValueKey(key));
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<void> _openGroup(WidgetTester tester, String group,
    {bool advancedMode = false}) async {
  if (!advancedMode) {
    await _tap(tester, 'link-in-bio-decoration-advanced');
  }
  await _tap(tester, 'link-in-bio-decoration-$group');
}

void main() {
  testWidgets(
      'starts with a bounded preview and themes while details are closed',
      (tester) async {
    await _openEditor(tester);
    expect(find.byType(ChoiceChip), findsNWidgets(4));
    expect(find.text('ตกแต่งเพิ่มเติม'), findsOneWidget);
    expect(find.byKey(const ValueKey('link-in-bio-background-color')),
        findsNothing);
    expect(find.byKey(const ValueKey('link-in-bio-name-color')), findsNothing);
    expect(find.byKey(const ValueKey('link-in-bio-description')), findsNothing);
    expect(
        tester
            .getSize(
                find.byKey(const ValueKey('link-in-bio-decoration-preview')))
            .height,
        200);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'advanced mode shows grouped details without repeating the themes',
      (tester) async {
    await _openEditor(tester, showThemePicker: false);
    expect(find.byType(ChoiceChip), findsNothing);
    expect(find.byKey(const ValueKey('link-in-bio-decoration-advanced')),
        findsNothing);
    for (final group in ['images', 'buttons', 'styles', 'featured']) {
      expect(find.byKey(ValueKey('link-in-bio-decoration-$group')),
          findsOneWidget);
    }
    expect(find.byKey(const ValueKey('link-in-bio-background-color')),
        findsNothing);
    expect(
        tester
            .getSize(
                find.byKey(const ValueKey('link-in-bio-decoration-preview')))
            .height,
        120);
    await _openGroup(tester, 'styles', advancedMode: true);
    expect(find.byKey(const ValueKey('link-in-bio-name-color')), findsNothing);
    await _tap(tester, 'link-in-bio-style-name');
    expect(
        find.byKey(const ValueKey('link-in-bio-name-color')), findsOneWidget);
  });

  testWidgets('applying untouched hidden details preserves the complete design',
      (tester) async {
    LinkInBioAppearance? result;
    await _openEditor(tester,
        appearance: _customAppearance, onResult: (value) => result = value);
    await _tap(tester, 'link-in-bio-decoration-done');
    expect(result!.toJson(), _customAppearance.toJson());
  });

  testWidgets('section edits survive collapsing and reopening their group',
      (tester) async {
    LinkInBioAppearance? result;
    await _openEditor(tester, onResult: (value) => result = value);
    await _openGroup(tester, 'styles');
    await _tap(tester, 'link-in-bio-style-name');
    final color = find.byKey(const ValueKey('link-in-bio-name-color'));
    await tester.enterText(color, '#112233');
    await _tap(tester, 'link-in-bio-style-name');
    expect(color, findsNothing);
    await _tap(tester, 'link-in-bio-style-name');
    expect(find.descendant(of: color, matching: find.text('#112233')),
        findsOneWidget);
    await _tap(tester, 'link-in-bio-decoration-done');
    expect(result!.nameStyle.color, '#112233');
  });

  testWidgets(
      'invalid color hidden by a collapsed section prevents applying and reopens it',
      (tester) async {
    LinkInBioAppearance? result;
    await _openEditor(tester, onResult: (value) => result = value);
    await _openGroup(tester, 'styles');
    await _tap(tester, 'link-in-bio-style-name');
    await tester.enterText(
        find.byKey(const ValueKey('link-in-bio-name-color')), 'oops');
    await _tap(tester, 'link-in-bio-style-name');
    await _tap(tester, 'link-in-bio-decoration-styles');
    await _tap(tester, 'link-in-bio-decoration-advanced');
    await _tap(tester, 'link-in-bio-decoration-done');
    expect(result, isNull);
    expect(
        find.byKey(const ValueKey('link-in-bio-name-color')), findsOneWidget);
    expect(find.text('กรอกสีแบบ #RRGGBB'), findsOneWidget);
  });

  testWidgets('theme changes retain description media and featured promotion',
      (tester) async {
    LinkInBioAppearance? result;
    await _openEditor(tester,
        appearance: _customAppearance, onResult: (value) => result = value);
    await _tap(tester, 'link-in-bio-theme-pastel');
    await _tap(tester, 'link-in-bio-decoration-done');
    expect(result!.themeId, 'pastel');
    expect(result!.buttonColor,
        LinkInBioAppearance.forTheme('pastel').buttonColor);
    expect(result!.description, _customAppearance.description);
    expect(result!.logoKey, _customAppearance.logoKey);
    expect(result!.coverKey, _customAppearance.coverKey);
    expect(result!.background.imageKey, _customAppearance.background.imageKey);
    expect(result!.featuredLinkId, _customAppearance.featuredLinkId);
    expect(result!.featuredLabel, _customAppearance.featuredLabel);
  });

  testWidgets(
      'pending upload blocks apply and an upload error preserves the old image',
      (tester) async {
    final pending = Completer<String?>();
    LinkInBioAppearance? result;
    await _openEditor(tester,
        appearance: _customAppearance,
        showThemePicker: false,
        uploadImage: (_) => pending.future,
        onResult: (value) => result = value);
    await _openGroup(tester, 'images', advancedMode: true);
    await tester
        .ensureVisible(find.byKey(const ValueKey('link-in-bio-image-cover')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('link-in-bio-image-cover')));
    await tester.pump();
    expect(
        tester
            .widget<FilledButton>(
                find.byKey(const ValueKey('link-in-bio-decoration-done')))
            .onPressed,
        isNull);
    pending.completeError(Exception('failed'));
    await tester.pumpAndSettle();
    expect(find.text('อัปโหลดรูปไม่สำเร็จ กรุณาลองใหม่ รูปเดิมยังอยู่'),
        findsOneWidget);
    await _tap(tester, 'link-in-bio-decoration-done');
    expect(result!.coverKey, _coverKey);
  });

  testWidgets('preview updates when an existing draft image finishes loading',
      (tester) async {
    final images = <String, Uint8List>{};
    final revision = ValueNotifier(0);
    addTearDown(revision.dispose);
    await _openEditor(tester,
        appearance: const LinkInBioAppearance(logoKey: _imageKey),
        images: images,
        imageRevision: revision);
    expect(find.byType(Image), findsNothing);
    images[_imageKey] = base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVQIHWP4z8DwHwAFgAI/ScLbtAAAAABJRU5ErkJggg==');
    revision.value++;
    await tester.pumpAndSettle();
    expect(find.byType(Image), findsOneWidget);
  });

  testWidgets('apply stays reachable above the keyboard on a narrow screen',
      (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await _openEditor(tester, keyboardInset: 260);
    final button = find.byKey(const ValueKey('link-in-bio-decoration-done'));
    expect(tester.getBottomRight(button).dy, lessThanOrEqualTo(380));
    await _tap(tester, 'link-in-bio-decoration-done');
    expect(find.byType(LinkInBioAppearanceEditor), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
