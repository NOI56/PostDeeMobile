import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postdee_mobile/core/models/link_in_bio_appearance.dart';
import 'package:postdee_mobile/core/models/profile_platform_catalog.generated.dart';
import 'package:postdee_mobile/core/theme/app_theme.dart';
import 'package:postdee_mobile/features/link_in_bio/link_in_bio_link_defaults.dart';
import 'package:postdee_mobile/features/link_in_bio/link_in_bio_platform_picker.dart';

void main() {
  test('100 brand destinations retain automatic names and safe boundaries', () {
    expect(profilePlatformCatalog, hasLength(100));
    expect(profilePlatformIds, hasLength(100));
    expect(linkInBioIcons, hasLength(105));
    for (final platform in profilePlatformCatalog) {
      expect(bioPlatformId(platform.sampleUrl), platform.id,
          reason: platform.sampleUrl);
      expect(suggestedBioLinkTitle(platform.sampleUrl), platform.name);
      for (final domain in platform.domains) {
        expect(bioPlatformId('https://$domain.evil.example/path'), 'website');
        expect(bioPlatformId('https://evil.example/?url=https://$domain'),
            'website');
        expect(bioPlatformId('https://user@$domain/'), 'link');
      }
      validateLinkInBioLinkOptions(icon: platform.id);
    }
  });

  test('shared hosts keep distinct brands and path boundaries', () {
    const cases = {
      'https://open.kakao.com/o/shop': 'kakao_talk',
      'https://music.163.com/artist?id=1': 'netease_music',
      'https://im.qq.com/': 'qq',
      'https://qzone.qq.com/': 'website',
      'https://qq.com/': 'website',
      'https://dianping.com/': 'website',
      'https://ctrip.com/': 'website',
      'https://music.apple.com/us/artist/shop': 'apple_music',
      'https://drive.google.com/file/d/example': 'google_drive',
      'https://www.google.com/maps/place/shop': 'google_maps',
      'https://www.google.com/mapsomething': 'website',
      'https://www.google.com/%6daps': 'website',
      'https://www.google.com/maps%2Fplace': 'website',
      'https://www.facebook.com/messages/t/shop': 'messenger',
      'https://www.facebook.com/messagesomething': 'facebook',
      'mailto:shop@example.com': 'email',
      'tel:+66812345678': 'phone',
    };
    for (final entry in cases.entries) {
      expect(bioPlatformId(entry.key), entry.value, reason: entry.key);
    }
  });

  Future<void> mountPicker(WidgetTester tester,
      {String selected = 'auto', ValueChanged<String>? onChanged}) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
            body: BioPlatformPicker(
                selected: selected, onSelected: onChanged ?? (_) {}))));
    await tester.pumpAndSettle();
  }

  testWidgets('picker searches an international name and returns the ID',
      (tester) async {
    String? selected;
    await mountPicker(tester, onChanged: (id) => selected = id);
    await tester.enterText(
        find.byKey(const ValueKey('bio-platform-search')), 'zalo');
    await tester.pumpAndSettle();
    expect(
        find.byKey(const ValueKey('bio-platform-option-zalo')), findsOneWidget);
    expect(find.byKey(const ValueKey('bio-platform-option-youtube')),
        findsNothing);
    await tester.tap(find.byKey(const ValueKey('bio-platform-option-zalo')));
    expect(selected, 'zalo');
    expect(tester.takeException(), isNull);
  });

  testWidgets('picker searches aliases and countries, clears empty results',
      (tester) async {
    await mountPicker(tester, selected: 'wechat');
    final search = find.byKey(const ValueKey('bio-platform-search'));
    await tester.enterText(search, '微信');
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('bio-platform-option-wechat')),
        findsOneWidget);
    await tester.enterText(search, 'เวียดนาม');
    await tester.pumpAndSettle();
    expect(
        find.byKey(const ValueKey('bio-platform-option-zalo')), findsOneWidget);
    await tester.enterText(search, 'no-such-platform-xyz');
    await tester.pumpAndSettle();
    expect(find.text('ไม่พบโลโก้ที่ตรงกับคำค้น'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('bio-platform-search-clear')));
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(search).controller!.text, isEmpty);
    expect(
        find.byKey(const ValueKey('bio-platform-option-auto')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('picker stays usable above a keyboard with large text',
      (tester) async {
    await mountPicker(tester);
    await tester.pumpWidget(MaterialApp(
        theme: AppTheme.light,
        builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
                textScaler: const TextScaler.linear(1.5),
                viewInsets: const EdgeInsets.only(bottom: 260)),
            child: child!),
        home: Scaffold(
            body: BioPlatformPicker(selected: 'auto', onSelected: (_) {}))));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const ValueKey('bio-platform-search')), 'buy me a coffee');
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('bio-platform-option-buy_me_a_coffee')),
        findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
